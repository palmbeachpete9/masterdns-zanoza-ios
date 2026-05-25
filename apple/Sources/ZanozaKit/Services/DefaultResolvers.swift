import Foundation

// Default list of recursive resolvers used when AppSettings.customResolvers
// is empty. Curated to Yandex DNS only — these consistently return the
// highest download MTU (3604 in our measurements), pinning the per-tunnel
// "Synced Download MTU" floor several × higher than mixed lists do, which
// directly raises throughput. Users can override per-profile via Settings →
// Resolvers.
public enum DefaultResolvers {
    public static let text: String = """
    # Yandex
    77.88.8.8
    77.88.8.7
    77.88.8.1
    77.88.8.2
    77.88.8.3
    77.88.8.88
    """
}
