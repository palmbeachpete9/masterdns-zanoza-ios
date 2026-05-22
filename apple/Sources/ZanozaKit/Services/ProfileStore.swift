import Foundation

// Persists [ConnectionProfile] as JSON inside the app's Documents directory.
public final class ProfileStore {
    public static let shared = ProfileStore()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "io.zanoza.profilestore")

    private init() {
        let fm = FileManager.default
        let dir = (try? fm.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        fileURL = dir.appendingPathComponent("profiles.json")
    }

    public func load() -> [ConnectionProfile] {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return [] }
            do {
                return try JSONDecoder().decode([ConnectionProfile].self, from: data)
            } catch {
                return []
            }
        }
    }

    public func save(_ profiles: [ConnectionProfile]) {
        queue.async {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(profiles) else { return }
            try? data.write(to: self.fileURL, options: .atomic)
        }
    }
}
