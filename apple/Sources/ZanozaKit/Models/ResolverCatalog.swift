import Foundation

public struct ResolverProvider: Identifiable, Hashable {
    public let id: String
    public let displayName: String
    let fileName: String

    var source: ResolverSource {
        ResolverSource(displayName: displayName, fileName: fileName)
    }
}

struct ResolverSource: Hashable {
    let displayName: String
    let fileName: String

    var url: URL {
        ResolverCatalog.url(for: fileName)
    }
}

public enum ResolverCatalog {
    private static let rawBaseURL = "https://hub.mos.ru/pete9/zanoza/-/raw/main/"

    public static let providers: [ResolverProvider] = [
        ResolverProvider(id: "mts", displayName: "МТС", fileName: "mts.txt"),
        ResolverProvider(id: "beeline", displayName: "Билайн", fileName: "beeline.txt"),
        ResolverProvider(id: "t2", displayName: "Т2", fileName: "t2.txt"),
        ResolverProvider(id: "sbermobile", displayName: "СберМобайл", fileName: "t2.txt"),
        ResolverProvider(id: "tmobile", displayName: "Т-Мобайл", fileName: "t2.txt"),
        ResolverProvider(id: "volna", displayName: "Волна мобайл", fileName: "volna.txt"),
        ResolverProvider(id: "megafon", displayName: "Мегафон", fileName: "megafon.txt"),
        ResolverProvider(id: "yota", displayName: "Yota", fileName: "megafon.txt"),
    ]

    static let yandexSource = ResolverSource(displayName: "Yandex", fileName: "yandex.txt")
    static let fastSource = ResolverSource(displayName: "Fast", fileName: "fast.txt")

    public static func provider(id: String) -> ResolverProvider? {
        providers.first { $0.id == id }
    }

    static func url(for fileName: String) -> URL {
        URL(string: rawBaseURL + fileName)!
    }
}
