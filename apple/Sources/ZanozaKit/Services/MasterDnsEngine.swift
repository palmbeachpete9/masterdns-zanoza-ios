import Foundation

#if canImport(Mobile)
import Mobile
#endif

public enum MasterDnsEngineError: LocalizedError {
    case frameworkMissing
    case invalidProfile(String)
    case startFailed(String)

    public var errorDescription: String? {
        switch self {
        case .frameworkMissing:
            return AppLocalization.string("MasterDns Mobile.xcframework not embedded in the build.")
        case .invalidProfile(let message):
            return message
        case .startFailed(let message):
            return message
        }
    }
}

public struct EngineStartOptions {
    public let profile: ConnectionProfile
    public let runtimeDirectory: URL

    public init(profile: ConnectionProfile, runtimeDirectory: URL) {
        self.profile = profile
        self.runtimeDirectory = runtimeDirectory
    }
}

// Wraps the gomobile-built Mobile.xcframework. The Mobile package exposes:
//   MobileStart(configTOML, resolversText, runtimeDir) error
//   MobileStop()
//   MobileIsRunning() bool
//   MobileSetLogWriter(MobileLogWriterProtocol?)
public final class MasterDnsEngine {
    private let lock = NSLock()
    private var currentSocksPort: Int?
    #if canImport(Mobile)
    private var logRelay: MobileLogRelay?
    #endif

    public init() {}

    deinit {
        #if canImport(Mobile)
        MobileStop()
        MobileSetLogWriter(nil)
        #endif
    }

    public var isRunning: Bool {
        #if canImport(Mobile)
        return MobileIsRunning()
        #else
        return false
        #endif
    }

    public var activeSocksPort: Int? {
        lock.lock(); defer { lock.unlock() }
        return currentSocksPort
    }

    public func start(_ options: EngineStartOptions, log: @escaping (String) -> Void) throws {
        try validate(options.profile)

        let configTOML = ConfigBuilder.buildTOML(for: options.profile)
        let resolvers = ConfigBuilder.resolversText(for: options.profile)

        let fm = FileManager.default
        try fm.createDirectory(at: options.runtimeDirectory, withIntermediateDirectories: true)

        #if canImport(Mobile)
        let relay = MobileLogRelay { line in log(line) }
        lock.lock(); logRelay = relay; lock.unlock()
        MobileSetLogWriter(relay)

        var startError: NSError?
        let didStart = MobileStart(configTOML, resolvers, options.runtimeDirectory.path, &startError)
        if !didStart {
            MobileStop()
            MobileSetLogWriter(nil)
            lock.lock(); logRelay = nil; lock.unlock()
            let message = startError?.localizedDescription
                ?? AppLocalization.string("Failed to start MasterDnsVPN client.")
            throw MasterDnsEngineError.startFailed(message)
        }
        lock.lock(); currentSocksPort = options.profile.socksPort; lock.unlock()
        #else
        _ = configTOML
        _ = resolvers
        log("Mobile framework missing; cannot start tunnel.")
        throw MasterDnsEngineError.frameworkMissing
        #endif
    }

    public func stop() {
        #if canImport(Mobile)
        MobileStop()
        MobileSetLogWriter(nil)
        #endif
        lock.lock()
        currentSocksPort = nil
        #if canImport(Mobile)
        logRelay = nil
        #endif
        lock.unlock()
    }

    private func validate(_ profile: ConnectionProfile) throws {
        let trimmedDomain = profile.domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDomain.isEmpty else {
            throw MasterDnsEngineError.invalidProfile(AppLocalization.string("Domain is required."))
        }
        guard trimmedDomain.contains(".") else {
            throw MasterDnsEngineError.invalidProfile(AppLocalization.string("Domain must be a delegated subdomain (e.g. v.example.com)."))
        }
        guard !profile.encryptionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MasterDnsEngineError.invalidProfile(AppLocalization.string("Encryption key is required."))
        }
        guard ConnectionProfile.socksPortRange.contains(profile.socksPort) else {
            throw MasterDnsEngineError.invalidProfile(AppLocalization.string("SOCKS port must be between 1024 and 65535."))
        }
    }
}

#if canImport(Mobile)
private final class MobileLogRelay: NSObject, MobileLogWriterProtocol {
    private let onLog: (String) -> Void

    init(onLog: @escaping (String) -> Void) {
        self.onLog = onLog
    }

    func writeLog(_ line: String?) {
        guard let line, !line.isEmpty else { return }
        onLog(line)
    }
}
#endif
