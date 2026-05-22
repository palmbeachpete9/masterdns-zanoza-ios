import Foundation
import Combine

// Bounded, thread-safe log buffer that the UI observes.
@MainActor
public final class AppLogger: ObservableObject {
    public static let shared = AppLogger()

    public static let maximumLines = 2_000

    @Published public private(set) var lines: [String] = []

    private init() {}

    public func append(_ line: String) {
        guard !line.isEmpty else { return }
        let timestamp = Self.timestampFormatter.string(from: Date())
        let prefixed = "[\(timestamp)] \(line)"
        lines.append(prefixed)
        if lines.count > Self.maximumLines {
            lines.removeFirst(lines.count - Self.maximumLines)
        }
    }

    public func clear() {
        lines.removeAll(keepingCapacity: false)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
