import XCTest
@testable import ZanozaKit

final class ConfigBuilderTests: XCTestCase {
    func testBuildsTOMLWithDomainAndPort() {
        let profile = ConnectionProfile(
            name: "Test",
            domain: "v.example.com",
            encryptionKey: "abc123"
        )
        let settings = AppSettings(socksPort: 41080)
        let toml = ConfigBuilder.buildTOML(for: profile, settings: settings)
        XCTAssertTrue(toml.contains("DOMAINS = [\"v.example.com\"]"))
        XCTAssertTrue(toml.contains("LISTEN_PORT = 41080"))
        XCTAssertTrue(toml.contains("ENCRYPTION_KEY = \"abc123\""))
        XCTAssertTrue(toml.contains("LISTEN_IP = \"127.0.0.1\""))
    }

    func testEscapesQuotesInKey() {
        let profile = ConnectionProfile(
            name: "Test",
            domain: "v.example.com",
            encryptionKey: "ab\"cd"
        )
        let toml = ConfigBuilder.buildTOML(for: profile, settings: AppSettings())
        XCTAssertTrue(toml.contains("ENCRYPTION_KEY = \"ab\\\"cd\""))
    }

    func testFallsBackToBundledResolversWhenCustomIsEmpty() {
        let text = ConfigBuilder.resolversText(settings: AppSettings())
        // Bundled list is curated to the high-MTU Yandex set.
        XCTAssertTrue(text.contains("77.88.8.8"))
        XCTAssertTrue(text.contains("77.88.8.88"))
    }

    func testGlobalResolverOverrideAppliesToEveryProfile() {
        let custom = "10.0.0.1\n10.0.0.2"
        let settings = AppSettings(customResolvers: custom)
        XCTAssertEqual(ConfigBuilder.resolversText(settings: settings), custom)
    }

    func testSettingsSocksPortAuthFlowsIntoTOML() {
        let profile = ConnectionProfile(name: "T", domain: "v.example.com", encryptionKey: "k")
        let settings = AppSettings(
            socksPort: 9999,
            socksUser: "alice",
            socksPass: "p@ss",
            socksAuthEnabled: true
        )
        let toml = ConfigBuilder.buildTOML(for: profile, settings: settings)
        XCTAssertTrue(toml.contains("LISTEN_PORT = 9999"))
        XCTAssertTrue(toml.contains("SOCKS5_AUTH = true"))
        XCTAssertTrue(toml.contains("SOCKS5_USER = \"alice\""))
        XCTAssertTrue(toml.contains("SOCKS5_PASS = \"p@ss\""))
    }
}

final class ConnectionProfileTests: XCTestCase {
    func testDefaultSettingsSocksPortIs41080() {
        XCTAssertEqual(AppSettings().socksPort, 41080)
    }

    func testSettingsNormalizesOutOfRangePort() {
        XCTAssertEqual(AppSettings.normalizedSocksPort(0), 41080)
        XCTAssertEqual(AppSettings.normalizedSocksPort(100_000), 41080)
        XCTAssertEqual(AppSettings.normalizedSocksPort(5050), 5050)
    }

    func testProfileRoundTripsThroughJSON() throws {
        let profile = ConnectionProfile(
            name: "Round trip",
            domain: "v.example.com",
            encryptionKey: "shared-secret",
            encryptionMethod: .aes256gcm,
            uploadCompression: .zstd,
            downloadCompression: .lz4,
            packetDuplicationCount: 5,
            setupPacketDuplicationCount: 6,
            resolverBalancingStrategy: .hybridScore,
            logLevel: .debug
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ConnectionProfile.self, from: data)
        XCTAssertEqual(decoded, profile)
    }

    func testSettingsRoundTripsThroughJSON() throws {
        let settings = AppSettings(
            socksPort: 18000,
            socksUser: "u",
            socksPass: "p",
            socksAuthEnabled: true,
            customResolvers: "1.1.1.1\n8.8.8.8"
        )
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }
}

final class ProfilePingerTests: XCTestCase {
    func testDnsQueryPacketShape() {
        let data = ProfilePinger.makeDnsQuery(for: "v.example.com")
        // 12-byte header + (1 + 1 + 1 + 7 + 1 + 3 + 1) labels + 4-byte trailer
        XCTAssertEqual(data.count, 12 + 1 + 1 + 1 + 7 + 1 + 3 + 1 + 4)
        XCTAssertEqual(data[2], 0x01) // RD flag high byte
        XCTAssertEqual(data[5], 0x01) // QDCOUNT low byte
        XCTAssertEqual(data[data.count - 4], 0x00) // QTYPE high
        XCTAssertEqual(data[data.count - 3], 0x01) // QTYPE=A
        XCTAssertEqual(data[data.count - 1], 0x01) // QCLASS=IN
    }
}
