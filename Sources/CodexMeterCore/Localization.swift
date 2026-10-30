import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case system, english = "en", simplifiedChinese = "zh-Hans"

    public func resolvedCode(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        switch self {
        case .english: return "en"
        case .simplifiedChinese: return "zh-Hans"
        case .system: return preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? "zh-Hans" : "en"
        }
    }
}

public struct LocalizedMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation, Sendable {
    let key: String
    let arguments: [String]
    public init(stringLiteral value: String) { key = value; arguments = [] }
    public init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key; arguments = stringInterpolation.arguments
    }
    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        public init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity); arguments.reserveCapacity(interpolationCount)
        }
        public mutating func appendLiteral(_ literal: String) { key += literal }
        public mutating func appendInterpolation<Value>(_ value: Value) {
            key += "{\(arguments.count)}"; arguments.append(String(describing: value))
        }
    }
}

public enum L10n {
    @TaskLocal public static var languageOverride: AppLanguage?
    public static var language: AppLanguage {
        languageOverride ?? AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "system") ?? .system
    }
    public static var locale: Locale { Locale(identifier: language.resolvedCode()) }
    private static let english = localizedBundle("en")
    private static let chinese = localizedBundle("zh-Hans")
    private static let placeholder = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)

    static func localizedBundle(_ code: String) -> Bundle? {
        // SwiftPM can lowercase localization directories on case-sensitive volumes.
        for name in [code, code.lowercased()] {
            if let path = Bundle.module.path(forResource: name, ofType: "lproj"),
               let bundle = Bundle(path: path) { return bundle }
        }
        return nil
    }

    public static func lookup(_ key: String, language: AppLanguage? = nil) -> String {
        let selected = (language ?? self.language).resolvedCode() == "zh-Hans" ? chinese : english
        return selected?.localizedString(forKey: key, value: key, table: nil) ?? key
    }

    public static func text(_ message: LocalizedMessage, language: AppLanguage? = nil) -> String {
        var result = lookup(message.key, language: language)
        // Replace from the end so argument contents are never interpreted as placeholders.
        let matches = placeholder.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let indexRange = Range(match.range(at: 1), in: result),
                  let index = Int(result[indexRange]), message.arguments.indices.contains(index),
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: message.arguments[index])
        }
        return result
    }
}
