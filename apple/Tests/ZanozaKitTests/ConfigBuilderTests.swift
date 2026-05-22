import XCTest
@testable import ZanozaKit

final class ConfigBuilderTests: XCTestCase {
    func testBuildsTOMLWithDomainAndPort() {
        let profile = ConnectionProfile(
            name: "Test",
            domain: "v.example.com",
            encryptionKey: "abc123",
            socksPort: 41080
        )
        let toml = ConfigBuilder.buildTOML(for: profile)
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
        let toml = ConfigBuilder.buildTOML(for: profile)
        XCTAssertTrue(toml.contains("ENCRYPTION_KEY = \"ab\\\"cd\""))
    }

    func testFallsBackToBundledResolversWhenCustomIsEmpty() {
        let profile = ConnectionProfile(name: "T", domain: "v.example.com", encryptionKey: "k")
        let text = ConfigBuilder.resolversText(for: profile)
        XCTAssertTrue(text.contains("1.1.1.1"))
        XCTAssertTrue(text.contains("8.8.8.8"))
    }
}

final class ConnectionProfileTests: XCTestCase {
    func testDefaultSocksPortIs41080() {
        let profile = ConnectionProfile()
        XCTAssertEqual(profile.socksPort, 41080)
    }

    func testNormalizedSocksPortFallsBackForOutOfRange() {
        XCTAssertEqual(ConnectionProfile.normalizedSocksPort(0), 41080)
        XCTAssertEqual(ConnectionProfile.normalizedSocksPort(100_000), 41080)
        XCTAssertEqual(ConnectionProfile.normalizedSocksPort(5050), 5050)
    }

    func testRoundTripsThroughJSON() throws {
        let profile = ConnectionProfile(
            name: "Round trip",
            domain: "v.example.com",
            encryptionKey: "shared-secret",
            encryptionMethod: .aes256gcm,
            socksPort: 18000,
            socksAuthEnabled: true,
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
}
