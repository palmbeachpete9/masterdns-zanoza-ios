import Foundation

private final class AppLocalizationBundleToken {}

public enum AppLocalization {
    public static var locale: Locale {
        Locale(identifier: localeIdentifier)
    }

    public static var localeIdentifier: String {
        localizationIdentifier(for: Locale.preferredLanguages.first)
    }

    static func localizationIdentifier(for preferredLanguage: String?) -> String {
        guard let preferredLanguage,
              Locale(identifier: preferredLanguage).language.languageCode?.identifier == "ru" else {
            return "en_US"
        }
        return "ru_RU"
    }

    public static func string(_ key: String) -> String {
        NSLocalizedString(key, bundle: localizationBundle, value: key, comment: "")
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }

    private static var localizationBundle: Bundle {
        let languageCode = localeIdentifier.hasPrefix("ru") ? "ru" : "en"
        guard let bundle = clientKitResourceBundle(),
              let path = bundle.path(forResource: languageCode, ofType: "lproj"),
              let resourceBundle = Bundle(path: path) else {
            return .main
        }
        return resourceBundle
    }

    private static func clientKitResourceBundle() -> Bundle? {
        let bundleName = "ZanozaApple_ZanozaKit.bundle"
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle(for: AppLocalizationBundleToken.self).resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
        ]
        return candidates.lazy.compactMap { url in url.flatMap(Bundle.init(url:)) }.first
    }
}
