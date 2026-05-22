import Foundation

// Builds the TOML configuration text consumed by the embedded MasterDnsVPN
// Go client out of a ConnectionProfile.
public enum ConfigBuilder {
    public static func buildTOML(for profile: ConnectionProfile) -> String {
        let domain = escape(profile.domain)
        let key = escape(profile.encryptionKey)
        let user = escape(profile.socksUser)
        let pass = escape(profile.socksPass)

        return """
        # Zanoza generated client_config.toml — do not edit manually.
        DOMAINS = ["\(domain)"]
        DATA_ENCRYPTION_METHOD = \(profile.encryptionMethod.rawValue)
        ENCRYPTION_KEY = "\(key)"

        PROTOCOL_TYPE = "SOCKS5"
        LISTEN_IP = "127.0.0.1"
        LISTEN_PORT = \(profile.socksPort)

        SOCKS5_AUTH = \(profile.socksAuthEnabled ? "true" : "false")
        SOCKS5_USER = "\(user)"
        SOCKS5_PASS = "\(pass)"

        LOCAL_DNS_ENABLED = false
        LOCAL_DNS_IP = "127.0.0.1"
        LOCAL_DNS_PORT = 53
        LOCAL_DNS_CACHE_MAX_RECORDS = 10000
        LOCAL_DNS_CACHE_TTL_SECONDS = 14400.0
        LOCAL_DNS_PENDING_TIMEOUT_SECONDS = 300.0
        DNS_RESPONSE_FRAGMENT_TIMEOUT_SECONDS = 60.0
        LOCAL_DNS_CACHE_PERSIST_TO_FILE = false
        LOCAL_DNS_CACHE_FLUSH_INTERVAL_SECONDS = 60.0

        RESOLVER_BALANCING_STRATEGY = \(profile.resolverBalancingStrategy.rawValue)
        PACKET_DUPLICATION_COUNT = \(profile.packetDuplicationCount)
        SETUP_PACKET_DUPLICATION_COUNT = \(profile.setupPacketDuplicationCount)
        STREAM_RESOLVER_FAILOVER_RESEND_THRESHOLD = 2
        STREAM_RESOLVER_FAILOVER_COOLDOWN = 2.5
        RECHECK_INACTIVE_SERVERS_ENABLED = true
        AUTO_DISABLE_TIMEOUT_SERVERS = true
        AUTO_DISABLE_TIMEOUT_WINDOW_SECONDS = 30.0
        BASE_ENCODE_DATA = false

        UPLOAD_COMPRESSION_TYPE = \(profile.uploadCompression.rawValue)
        DOWNLOAD_COMPRESSION_TYPE = \(profile.downloadCompression.rawValue)
        COMPRESSION_MIN_SIZE = 120

        MIN_UPLOAD_MTU = 38
        MIN_DOWNLOAD_MTU = 200
        MAX_UPLOAD_MTU = 150
        MAX_DOWNLOAD_MTU = 4000
        AUTO_REMOVE_LOW_MTU_SERVERS = true
        MTU_TEST_RETRIES = 2
        MTU_TEST_TIMEOUT = 2.0
        MTU_TEST_PARALLELISM = 32
        SAVE_MTU_SERVERS_TO_FILE = false

        RX_TX_WORKERS = 4
        TUNNEL_PROCESS_WORKERS = 6
        TUNNEL_PACKET_TIMEOUT_SECONDS = 10.0
        DISPATCHER_IDLE_POLL_INTERVAL_SECONDS = 0.020
        RX_CHANNEL_SIZE = 4096
        SOCKS_UDP_ASSOCIATE_READ_TIMEOUT_SECONDS = 30.0
        CLIENT_TERMINAL_STREAM_RETENTION_SECONDS = 45.0
        CLIENT_CANCELLED_SETUP_RETENTION_SECONDS = 120.0

        SESSION_INIT_RETRY_BASE_SECONDS = 1.0
        SESSION_INIT_RETRY_STEP_SECONDS = 1.0
        SESSION_INIT_RETRY_LINEAR_AFTER = 5
        SESSION_INIT_RETRY_MAX_SECONDS = 60.0
        SESSION_INIT_BUSY_RETRY_INTERVAL_SECONDS = 60.0
        SESSION_INIT_RACING_COUNT = 3

        PING_AGGRESSIVE_INTERVAL_SECONDS = 0.100
        PING_LAZY_INTERVAL_SECONDS = 0.750
        PING_COOLDOWN_INTERVAL_SECONDS = 2.0
        PING_COLD_INTERVAL_SECONDS = 15.0
        PING_WARM_THRESHOLD_SECONDS = 8.0
        PING_COOL_THRESHOLD_SECONDS = 20.0
        PING_COLD_THRESHOLD_SECONDS = 30.0

        MAX_PACKETS_PER_BATCH = 8
        ARQ_WINDOW_SIZE = 1000
        ARQ_INITIAL_RTO_SECONDS = 0.5
        ARQ_MAX_RTO_SECONDS = 3.0
        ARQ_CONTROL_INITIAL_RTO_SECONDS = 0.5
        ARQ_CONTROL_MAX_RTO_SECONDS = 2.0
        ARQ_MAX_CONTROL_RETRIES = 126
        ARQ_INACTIVITY_TIMEOUT_SECONDS = 1800.0
        ARQ_DATA_PACKET_TTL_SECONDS = 2400.0
        ARQ_CONTROL_PACKET_TTL_SECONDS = 1200.0
        ARQ_MAX_DATA_RETRIES = 126
        ARQ_DATA_NACK_MAX_GAP = 32
        ARQ_DATA_NACK_INITIAL_DELAY_SECONDS = 0.1
        ARQ_DATA_NACK_REPEAT_SECONDS = 0.8
        ARQ_TERMINAL_DRAIN_TIMEOUT_SECONDS = 120.0
        ARQ_TERMINAL_ACK_WAIT_TIMEOUT_SECONDS = 90.0

        LOG_LEVEL = "\(profile.logLevel.rawValue)"
        """
    }

    public static func resolversText(for profile: ConnectionProfile) -> String {
        let custom = profile.customResolvers.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        return DefaultResolvers.text
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
