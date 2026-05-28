import Combine
import Foundation
import SwiftUI

@MainActor
public final class ClientViewModel: ObservableObject {
    @Published public private(set) var profiles: [ConnectionProfile] = []
    @Published public var selectedProfileID: UUID?
    @Published public var draft: ConnectionProfile = .empty
    @Published public var settings: AppSettings
    @Published public private(set) var status: ClientStatus = .stopped
    @Published public private(set) var logs: [String] = []
    @Published public private(set) var isImporting = false
    @Published public var importErrorMessage: String?
    @Published public private(set) var activeSocksPort: Int?
    @Published public private(set) var pingingProfileIDs: Set<UUID> = []
    @Published public private(set) var pingResults: [UUID: ProfilePingResult] = [:]

    private let engine = MasterDnsEngine()
    #if os(iOS)
    private let backgroundRuntimeKeeper = BackgroundRuntimeKeeper()
    #endif
    private let profileStore = ProfileStore.shared
    private let settingsStore = AppSettingsStore.shared
    private let pinger = ProfilePinger()
    public let physicalInterfaceMonitor = PhysicalInterfaceMonitor()
    private var cancellables = Set<AnyCancellable>()
    private var startTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var pingTasks: [UUID: Task<Void, Never>] = [:]
    private var lifecycleToken: UInt64 = 0

    public init() {
        settings = AppSettingsStore.shared.load()
        profiles = profileStore.load()
        selectedProfileID = profiles.first?.id
        if let selected = profiles.first { draft = selected }

        AppLogger.shared.$lines
            .receive(on: DispatchQueue.main)
            .sink { [weak self] lines in self?.logs = lines }
            .store(in: &cancellables)

        physicalInterfaceMonitor.start()
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
        if !AppSettings.socksPortRange.contains(settings.socksPort) {
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
        importErrorMessage = nil
        AppLogger.shared.append("Imported profile \(displayName) (\(trimmedDomain)).")
    }

    public func shareProfile(_ profile: ConnectionProfile) {
        do {
            let link = try ProfileShareCodec.encode(profile)
            ClipboardService.copy(link)
            importErrorMessage = nil
            AppLogger.shared.append("Copied profile \(profile.displayName) to clipboard.")
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    public func importSharedProfile(_ link: String) -> Bool {
        isImporting = true
        defer { isImporting = false }

        do {
            let profile = try ProfileShareCodec.decode(link)
            if let message = validationMessage(for: profile) {
                importErrorMessage = message
                return false
            }
            profiles.append(profile)
            selectedProfileID = profile.id
            draft = profile
            persistProfiles()
            importErrorMessage = nil
            AppLogger.shared.append("Imported shared profile \(profile.displayName) (\(profile.domain)).")
            return true
        } catch {
            importErrorMessage = error.localizedDescription
            return false
        }
    }

    public func clearImportError() {
        importErrorMessage = nil
    }

    public func saveDraft() {
        guard let index = profiles.firstIndex(where: { $0.id == draft.id }) else { return }
        var sanitized = draft
        sanitized.setupPacketDuplicationCount = max(sanitized.packetDuplicationCount, min(12, sanitized.setupPacketDuplicationCount))
        profiles[index] = sanitized
        draft = sanitized
        persistProfiles()
    }

    public func saveSettings() {
        settings.socksPort = AppSettings.clampedSocksPort(settings.socksPort)
        settings.resolverProviderID = AppSettings.normalizedResolverProviderID(settings.resolverProviderID)
        settingsStore.save(settings)
    }

    public func deleteProfiles(ids: [UUID]) {
        let set = Set(ids)
        profiles.removeAll { set.contains($0.id) }
        for id in ids {
            pingingProfileIDs.remove(id)
            pingResults.removeValue(forKey: id)
            pingTasks[id]?.cancel()
            pingTasks.removeValue(forKey: id)
        }
        if let current = selectedProfileID, set.contains(current) {
            selectedProfileID = profiles.first?.id
            if let next = profiles.first { draft = next } else { draft = .empty }
            if status.isRunning { stop() }
        }
        persistProfiles()
    }

    public func pingProfile(_ id: UUID) {
        guard !pingingProfileIDs.contains(id),
              let profile = profiles.first(where: { $0.id == id }) else { return }
        pingingProfileIDs.insert(id)
        pingTasks[id]?.cancel()
        pingTasks[id] = Task { [weak self, pinger] in
            let result = await pinger.ping(profile)
            await MainActor.run {
                guard let self else { return }
                self.pingingProfileIDs.remove(id)
                self.pingResults[id] = result
                self.pingTasks.removeValue(forKey: id)
            }
        }
    }

    public func start() {
        guard let id = selectedProfileID,
              let profile = profiles.first(where: { $0.id == id }) else { return }
        if let message = validationMessage(for: profile) {
            status = .failed(message)
            AppLogger.shared.append("Cannot start: \(message)")
            return
        }
        let settingsSnapshot = settings
        let boundInterface = physicalInterfaceMonitor.currentName
        let boundIPv4 = physicalInterfaceMonitor.currentIPv4
        let boundIPv6 = physicalInterfaceMonitor.currentIPv6
        lifecycleToken &+= 1
        let token = lifecycleToken
        status = .starting
        AppLogger.shared.append("Starting Zanoza tunnel for \(profile.domain)...")

        startTask?.cancel()
        startTask = Task { [weak self] in
            guard let self else { return }
            let runtimeDir = self.runtimeDirectory(for: profile)
            do {
                #if os(iOS)
                try self.backgroundRuntimeKeeper.start()
                #endif
                try await Task.detached(priority: .userInitiated) { [engine = self.engine] in
                    try engine.start(
                        EngineStartOptions(
                            profile: profile,
                            settings: settingsSnapshot,
                            runtimeDirectory: runtimeDir,
                            boundInterface: boundInterface,
                            boundIPv4: boundIPv4,
                            boundIPv6: boundIPv6
                        ),
                        log: { line in
                            Task { @MainActor in AppLogger.shared.append(line) }
                        }
                    )
                }.value

                let startAction = startCompletionAction(for: token)
                switch startAction {
                case .markReady:
                    break
                case .stopEngine:
                    await Task.detached(priority: .userInitiated) { [engine = self.engine] in
                        engine.stop()
                    }.value
                    #if os(iOS)
                    await MainActor.run { self.backgroundRuntimeKeeper.stop() }
                    #endif
                    return
                case .ignore:
                    return
                }

                await MainActor.run {
                    guard self.lifecycleToken == token else { return }
                    self.status = .ready
                    self.activeSocksPort = settingsSnapshot.socksPort
                    AppLogger.shared.append("Tunnel ready. SOCKS5 proxy at 127.0.0.1:\(settingsSnapshot.socksPort).")
                }
            } catch {
                await MainActor.run {
                    guard self.lifecycleToken == token else { return }
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
        lifecycleToken &+= 1
        let token = lifecycleToken
        startTask?.cancel()
        status = .stopping
        AppLogger.shared.append("Stopping tunnel...")

        stopTask?.cancel()
        stopTask = Task { [weak self] in
            guard let self else { return }
            await Task.detached(priority: .userInitiated) { [engine = self.engine] in
                engine.stop()
            }.value
            await MainActor.run {
                guard self.lifecycleToken == token else { return }
                #if os(iOS)
                self.backgroundRuntimeKeeper.stop()
                #endif
                self.status = .stopped
                self.activeSocksPort = nil
                AppLogger.shared.append("Tunnel stopped.")
            }
        }
    }

    private func startCompletionAction(for token: UInt64) -> StartCompletionAction {
        if lifecycleToken == token && status == .starting && !Task.isCancelled {
            return .markReady
        }
        switch status {
        case .stopped, .stopping, .failed:
            return .stopEngine
        case .starting, .ready:
            return .ignore
        }
    }

    public func clearLogs() {
        AppLogger.shared.clear()
    }

    public func shutdownForAppTermination() {
        if status.isRunning {
            engine.stop()
        }
        physicalInterfaceMonitor.stop()
        #if os(iOS)
        backgroundRuntimeKeeper.stop()
        #endif
    }

    private func persistProfiles() {
        profileStore.save(profiles)
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

private enum StartCompletionAction {
    case markReady
    case stopEngine
    case ignore
}
