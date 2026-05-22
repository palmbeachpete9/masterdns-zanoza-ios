import Foundation

// Default list of public recursive resolvers used when a profile does not
// override them. One per line, comments allowed.
public enum DefaultResolvers {
    public static let text: String = """
    # Cloudflare
    1.1.1.1
    1.0.0.1
    # Google
    8.8.8.8
    8.8.4.4
    # Quad9
    9.9.9.9
    149.112.112.112
    # OpenDNS
    208.67.222.222
    208.67.220.220
    # AdGuard
    94.140.14.14
    94.140.15.15
    # Yandex
    77.88.8.8
    77.88.8.1
    # DNS.SB
    185.222.222.222
    45.11.45.11
    # ControlD
    76.76.2.0
    76.76.10.0
    """
}
