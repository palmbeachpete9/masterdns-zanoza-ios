import Foundation

public enum ProfileShareCodec {
    public static func encode(_ profile: ConnectionProfile) throws -> String {
        let payload = SharedProfilePayload(profile: profile)
        let data = try JSONEncoder().encode(payload)
        return "zanoza://profile?data=\(base64URLEncode(data))"
    }

    public static func decode(_ input: String) throws -> ConnectionProfile {
        let encodedPayload = try payloadString(from: input)
        let data = try base64URLDecode(encodedPayload)
        let payload: SharedProfilePayload
        do {
            payload = try JSONDecoder().decode(SharedProfilePayload.self, from: data)
        } catch {
            throw ProfileShareCodecError.invalidPayload
        }
        guard payload.version == 1 else { throw ProfileShareCodecError.unsupportedVersion }
        return payload.profile()
    }

    private static func payloadString(from input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProfileShareCodecError.invalidLink }

        if let components = URLComponents(string: trimmed),
           components.scheme?.lowercased() == "zanoza" {
            guard components.host == "profile",
                  let payload = components.queryItems?.first(where: { $0.name == "data" })?.value,
                  !payload.isEmpty else {
                throw ProfileShareCodecError.invalidLink
            }
            return payload
        }

        if trimmed.contains("://") {
            throw ProfileShareCodecError.invalidLink
        }
        return trimmed
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    private static func base64URLDecode(_ value: String) throws -> Data {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder == 1 { throw ProfileShareCodecError.invalidPayload }
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: base64) else {
            throw ProfileShareCodecError.invalidPayload
        }
        return data
    }
}

public enum ProfileShareCodecError: LocalizedError {
    case invalidLink
    case invalidPayload
    case unsupportedVersion

    public var errorDescription: String? {
        switch self {
        case .invalidLink:
            AppLocalization.string("Invalid profile sharing link.")
        case .invalidPayload, .unsupportedVersion:
            AppLocalization.string("Profile sharing link is not supported.")
        }
    }
}

private struct SharedProfilePayload: Codable {
    let version: Int
    let name: String
    let domain: String
    let encryptionKey: String
    let encryptionMethod: EncryptionMethod
    let uploadCompression: CompressionType
    let downloadCompression: CompressionType
    let packetDuplicationCount: Int
    let setupPacketDuplicationCount: Int
    let resolverBalancingStrategy: BalancingStrategy
    let logLevel: LogLevel

    init(profile: ConnectionProfile) {
        version = 1
        name = profile.name
        domain = profile.domain
        encryptionKey = profile.encryptionKey
        encryptionMethod = profile.encryptionMethod
        uploadCompression = profile.uploadCompression
        downloadCompression = profile.downloadCompression
        packetDuplicationCount = profile.packetDuplicationCount
        setupPacketDuplicationCount = profile.setupPacketDuplicationCount
        resolverBalancingStrategy = profile.resolverBalancingStrategy
        logLevel = profile.logLevel
    }

    func profile() -> ConnectionProfile {
        ConnectionProfile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            domain: domain
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: ".")),
            encryptionKey: encryptionKey,
            encryptionMethod: encryptionMethod,
            uploadCompression: uploadCompression,
            downloadCompression: downloadCompression,
            packetDuplicationCount: packetDuplicationCount,
            setupPacketDuplicationCount: setupPacketDuplicationCount,
            resolverBalancingStrategy: resolverBalancingStrategy,
            logLevel: logLevel
        )
    }
}
