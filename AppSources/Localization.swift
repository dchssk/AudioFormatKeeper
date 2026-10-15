import Foundation

enum L10n {
    static func string(_ key: String, language: String? = nil) -> String {
        localizedBundle(language: language).localizedString(
            forKey: key,
            value: key,
            table: nil
        )
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: string(key),
            locale: Locale.current,
            arguments: arguments
        )
    }

    static func format(_ key: String, language: String, _ arguments: CVarArg...) -> String {
        String(
            format: string(key, language: language),
            locale: Locale(identifier: language),
            arguments: arguments
        )
    }

    private static var baseBundle: Bundle {
        if Bundle.main.path(forResource: "en", ofType: "lproj") != nil {
            return .main
        }
        return .module
    }

    private static func localizedBundle(language: String?) -> Bundle {
        guard let language,
              let path = baseBundle.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return baseBundle
        }
        return bundle
    }
}
