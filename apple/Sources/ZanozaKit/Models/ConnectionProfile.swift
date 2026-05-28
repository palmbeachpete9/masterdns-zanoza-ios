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
    public var id: UUID
    public var name: String
    public var domain: String
    public var encryptionKey: String
    public var encryptionMethod: EncryptionMethod
    public var uploadCompression: CompressionType
    public var downloadCompression: CompressionType
    public var packetDuplicationCount: Int
    public var setupPacketDuplicationCount: Int
    public var resolverBalancingStrategy: BalancingStrategy
    public var logLevel: LogLevel

    public init(
        id: UUID = UUID(),
        name: String = "",
        domain: String = "",
        encryptionKey: String = "",
        encryptionMethod: EncryptionMethod = .xor,
        uploadCompression: CompressionType = .zlib,
        downloadCompression: CompressionType = .zlib,
        packetDuplicationCount: Int = 5,
        setupPacketDuplicationCount: Int = 6,
        resolverBalancingStrategy: BalancingStrategy = .hybridScore,
        logLevel: LogLevel = .info
    ) {
        self.id = id
        self.name = name
        self.domain = domain
        self.encryptionKey = encryptionKey
        self.encryptionMethod = encryptionMethod
        self.uploadCompression = uploadCompression
        self.downloadCompression = downloadCompression
        let clampedPacketDuplicationCount = max(1, min(10, packetDuplicationCount))
        self.packetDuplicationCount = clampedPacketDuplicationCount
        self.setupPacketDuplicationCount = max(clampedPacketDuplicationCount, min(12, setupPacketDuplicationCount))
        self.resolverBalancingStrategy = resolverBalancingStrategy
        self.logLevel = logLevel
    }

    enum CodingKeys: String, CodingKey {
        case id, name, domain, encryptionKey, encryptionMethod
        case uploadCompression, downloadCompression
        case packetDuplicationCount, setupPacketDuplicationCount
        case resolverBalancingStrategy, logLevel
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
            domain: try c.decodeIfPresent(String.self, forKey: .domain) ?? "",
            encryptionKey: try c.decodeIfPresent(String.self, forKey: .encryptionKey) ?? "",
            encryptionMethod: try c.decodeIfPresent(EncryptionMethod.self, forKey: .encryptionMethod) ?? .xor,
            uploadCompression: try c.decodeIfPresent(CompressionType.self, forKey: .uploadCompression) ?? .zlib,
            downloadCompression: try c.decodeIfPresent(CompressionType.self, forKey: .downloadCompression) ?? .zlib,
            packetDuplicationCount: try c.decodeIfPresent(Int.self, forKey: .packetDuplicationCount) ?? 5,
            setupPacketDuplicationCount: try c.decodeIfPresent(Int.self, forKey: .setupPacketDuplicationCount) ?? 6,
            resolverBalancingStrategy: try c.decodeIfPresent(BalancingStrategy.self, forKey: .resolverBalancingStrategy) ?? .hybridScore,
            logLevel: try c.decodeIfPresent(LogLevel.self, forKey: .logLevel) ?? .info
        )
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
        parts.append(encryptionMethod.title)
        return parts.joined(separator: " · ")
    }
}
