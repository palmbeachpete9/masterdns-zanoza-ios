import Combine
import Foundation
import SwiftUI

@MainActor
public final class ClientViewModel: ObservableObject {
    @Published public private(set) var profiles: [ConnectionProfile] = []
    @Published public var selectedProfileID: UUID?
    @Published public var draft: ConnectionProfile = .empty
    @Published public private(set) var status: ClientStatus = .stopped
    @Published public private(set) var logs: [String] = []
    @Published public private(set) var isImporting = false
    @Published public var importErrorMessage: String?
    @Published public private(set) var activeSocksPort: Int?

    private let engine = MasterDnsEngine()
    #if os(iOS)
    private let backgroundRuntimeKeeper = BackgroundRuntimeKeeper()
    #endif
    private let store = ProfileStore.shared
    private var cancellables = Set<AnyCancellable>()
    private var startTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?

    public init() {
        profiles = store.load()
        selectedProfileID = profiles.first?.id
        if let selected = profiles.first { draft = selected }

        AppLogger.shared.$lines
            .receive(on: DispatchQueue.main)
            .sink { [weak self] lines in self?.logs = lines }
            .store(in: &cancellables)
    }

    public var selectedProfileName: String {
        profiles.first(where: { $0.id == selectedProfileID })?.displayName ?? AppLocalization.string("No profile")
    }

    public var canStart: Bool {
        guard !status.isRunning, selectedProfileID != nil else { return false }
        return validationMessage == nil
    }

    public var validationMessage: String? {
        validationMessage(for: draft)
    }

    public func validationMessage(for profile: ConnectionProfile) -> String? {
        let domain = profile.domain.trimmingCharacters(in: .whitespacesAndNewlines)
        if domain.isEmpty { return AppLocalization.string("Domain is required.") }
        if !domain.contains(".") {
            return AppLocalization.string("Domain must be a delegated subdomain (e.g. v.example.com).")
        }
        if profile.encryptionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppLocalization.string("Encryption key is required.")
        }
        if !ConnectionProfile.socksPortRange.contains(profile.socksPort) {
            return AppLocalization.string("SOCKS port must be between 1024 and 65535.")
        }
        return nil
    }

    public func selectProfile(_ id: UUID) {
        selectedProfileID = id
        if let profile = profiles.first(where: { $0.id == id }) { draft = profile }
    }

    public func importProfile(domain: String, encryptionKey: String, name: String?) {
        let trimmedDomain = domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let trimmedKey = encryptionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDomain.isEmpty else {
            importErrorMessage = AppLocalization.string("Domain is required.")
            return
        }
        guard trimmedDomain.contains(".") else {
            importErrorMessage = AppLocalization.string("Domain must be a delegated subdomain (e.g. v.example.com).")
            return
        }
        guard !trimmedKey.isEmpty else {
            importErrorMessage = AppLocalization.string("Encryption key is required.")
            return
        }
        isImporting = true
        defer { isImporting = false }

        let displayName = (name?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? trimmedDomain
        let profile = ConnectionProfile(
            name: displayName,
            domain: trimmedDomain,
            encryptionKey: trimmedKey
        )
        profiles.append(profile)
        selectedProfileID = profile.id
        draft = profile
        persistProfiles()
        AppLogger.shared.append("Imported profile \(displayName) (\(trimmedDomain)).")
    }

    public func clearImportError() {
        importErrorMessage = nil
    }

    public func saveDraft() {
        guard let index = profiles.firstIndex(where: { $0.id == draft.id }) else { return }
        var sanitized = draft
        sanitized.socksPort = ConnectionProfile.clampedSocksPort(sanitized.socksPort)
        sanitized.setupPacketDuplicationCount = max(sanitized.packetDuplicationCount, min(12, sanitized.setupPacketDuplicationCount))
        profiles[index] = sanitized
        draft = sanitized
        persistProfiles()
    }

    public func deleteProfiles(ids: [UUID]) {
        let set = Set(ids)
        profiles.removeAll { set.contains($0.id) }
        if let current = selectedProfileID, set.contains(current) {
            selectedProfileID = profiles.first?.id
            if let next = profiles.first { draft = next } else { draft = .empty }
            if status.isRunning { stop() }
        }
        persistProfiles()
    }

    public func start() {
        guard let id = selectedProfileID,
              let profile = profiles.first(where: { $0.id == id }) else { return }
        if let message = validationMessage(for: profile) {
            status = .failed(message)
            AppLogger.shared.append("Cannot start: \(message)")
            return
        }
        status = .starting
        AppLogger.shared.append("Starting Zanoza tunnel for \(profile.domain)...")

        startTask?.cancel()
        startTask = Task { [weak self] in
            guard let self else { return }
            let runtimeDir = self.runtimeDirectory(for: profile)
            do {
                #if os(iOS)
                try await MainActor.run {
                    try self.backgroundRuntimeKeeper.start()
                }
                #endif
                try await Task.detached(priority: .userInitiated) { [engine = self.engine] in
                    try engine.start(
                        EngineStartOptions(profile: profile, runtimeDirectory: runtimeDir),
                        log: { line in
                            Task { @MainActor in AppLogger.shared.append(line) }
                        }
                    )
                }.value

                await MainActor.run {
                    self.status = .ready
                    self.activeSocksPort = profile.socksPort
                    AppLogger.shared.append("Tunnel ready. SOCKS5 proxy at 127.0.0.1:\(profile.socksPort).")
                }
            } catch {
                await MainActor.run {
                    self.status = .failed(error.localizedDescription)
                    AppLogger.shared.append("Tunnel failed to start: \(error.localizedDescription)")
                    #if os(iOS)
                    self.backgroundRuntimeKeeper.stop()
                    #endif
                }
            }
        }
    }

    public func stop() {
        guard status.isRunning else { return }
        status = .stopping
        AppLogger.shared.append("Stopping tunnel...")

        stopTask?.cancel()
        stopTask = Task { [weak self] in
            guard let self else { return }
            await Task.detached(priority: .userInitiated) { [engine = self.engine] in
                engine.stop()
            }.value
            await MainActor.run {
                #if os(iOS)
                self.backgroundRuntimeKeeper.stop()
                #endif
                self.status = .stopped
                self.activeSocksPort = nil
                AppLogger.shared.append("Tunnel stopped.")
            }
        }
    }

    public func clearLogs() {
        AppLogger.shared.clear()
    }

    public func shutdownForAppTermination() {
        if status.isRunning {
            engine.stop()
        }
        #if os(iOS)
        backgroundRuntimeKeeper.stop()
        #endif
    }

    private func persistProfiles() {
        store.save(profiles)
    }

    private func runtimeDirectory(for profile: ConnectionProfile) -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("Zanoza", isDirectory: true)
            .appendingPathComponent(profile.id.uuidString, isDirectory: true)
    }
}
