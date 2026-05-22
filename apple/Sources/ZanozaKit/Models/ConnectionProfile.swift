import Foundation

public enum EncryptionMethod: Int, CaseIterable, Codable, Identifiable {
    case none = 0
    case xor = 1
    case chacha20 = 2
    case aes128gcm = 3
    case aes192gcm = 4
    case aes256gcm = 5

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .none: "None"
        case .xor: "XOR"
        case .chacha20: "ChaCha20"
        case .aes128gcm: "AES-128-GCM"
        case .aes192gcm: "AES-192-GCM"
        case .aes256gcm: "AES-256-GCM"
        }
    }
}

public enum CompressionType: Int, CaseIterable, Codable, Identifiable {
    case off = 0
    case zstd = 1
    case lz4 = 2
    case zlib = 3

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .off: "Off"
        case .zstd: "Zstd"
        case .lz4: "LZ4"
        case .zlib: "Zlib"
        }
    }
}

public enum BalancingStrategy: Int, CaseIterable, Codable, Identifiable {
    case random = 1
    case roundRobin = 2
    case leastLoss = 3
    case lowestLatency = 4
    case hybridScore = 5
    case lossThenLatency = 6
    case leastLossTopRandom = 7
    case leastLossTopRoundRobin = 8

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .random: "Random"
        case .roundRobin: "Round Robin"
        case .leastLoss: "Least Loss"
        case .lowestLatency: "Lowest Latency"
        case .hybridScore: "Hybrid Score"
        case .lossThenLatency: "Loss → Latency"
        case .leastLossTopRandom: "Least Loss Top (Random)"
        case .leastLossTopRoundRobin: "Least Loss Top (Round Robin)"
        }
    }
}

public enum LogLevel: String, CaseIterable, Codable, Identifiable {
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public struct ConnectionProfile: Codable, Equatable, Identifiable {
    public static let defaultSocksPort = 41080
    public static let minimumSocksPort = 1024
    public static let maximumSocksPort = 65535
    public static var socksPortRange: ClosedRange<Int> { minimumSocksPort...maximumSocksPort }

    public var id: UUID
    public var name: String
    public var domain: String
    public var encryptionKey: String
    public var encryptionMethod: EncryptionMethod
    public var socksPort: Int
    public var socksUser: String
    public var socksPass: String
    public var socksAuthEnabled: Bool
    public var uploadCompression: CompressionType
    public var downloadCompression: CompressionType
    public var packetDuplicationCount: Int
    public var setupPacketDuplicationCount: Int
    public var resolverBalancingStrategy: BalancingStrategy
    public var logLevel: LogLevel
    public var customResolvers: String

    public init(
        id: UUID = UUID(),
        name: String = "",
        domain: String = "",
        encryptionKey: String = "",
        encryptionMethod: EncryptionMethod = .xor,
        socksPort: Int = Self.defaultSocksPort,
        socksUser: String = "zanoza",
        socksPass: String = "zanoza",
        socksAuthEnabled: Bool = false,
        uploadCompression: CompressionType = .off,
        downloadCompression: CompressionType = .off,
        packetDuplicationCount: Int = 3,
        setupPacketDuplicationCount: Int = 4,
        resolverBalancingStrategy: BalancingStrategy = .leastLoss,
        logLevel: LogLevel = .info,
        customResolvers: String = ""
    ) {
        self.id = id
        self.name = name
        self.domain = domain
        self.encryptionKey = encryptionKey
        self.encryptionMethod = encryptionMethod
        self.socksPort = Self.normalizedSocksPort(socksPort)
        self.socksUser = socksUser
        self.socksPass = socksPass
        self.socksAuthEnabled = socksAuthEnabled
        self.uploadCompression = uploadCompression
        self.downloadCompression = downloadCompression
        self.packetDuplicationCount = max(1, min(10, packetDuplicationCount))
        self.setupPacketDuplicationCount = max(packetDuplicationCount, min(12, setupPacketDuplicationCount))
        self.resolverBalancingStrategy = resolverBalancingStrategy
        self.logLevel = logLevel
        self.customResolvers = customResolvers
    }

    public static var empty: ConnectionProfile {
        ConnectionProfile(name: AppLocalization.string("New profile"))
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        if !domain.isEmpty { return domain }
        return AppLocalization.string("Untitled")
    }

    public var listDetail: String {
        var parts: [String] = []
        if !domain.isEmpty { parts.append(domain) }
        parts.append("SOCKS \(socksPort)")
        parts.append(encryptionMethod.title)
        return parts.joined(separator: " · ")
    }

    public static func normalizedSocksPort(_ port: Int) -> Int {
        socksPortRange.contains(port) ? port : defaultSocksPort
    }

    public static func clampedSocksPort(_ port: Int) -> Int {
        min(max(port, minimumSocksPort), maximumSocksPort)
    }
}
