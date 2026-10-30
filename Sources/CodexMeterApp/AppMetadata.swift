import CodexMeterCore
import Foundation

enum AppMetadata {
    static let name = "CodexMeter"
    static let projectURL = URL(string: "https://github.com/spider-man-peter-park/CodexMeter")!
    static let issuesURL = URL(string: "https://github.com/spider-man-peter-park/CodexMeter/issues/new")!
    static let licenseURL = URL(string: "https://github.com/spider-man-peter-park/CodexMeter/blob/main/LICENSE")!
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }
    static var versionLabel: String { version == "Development" ? version : "v" + version }
}

enum SubscriptionPlanLabel {
    static func title(for raw: String?) -> String {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return L10n.text("Unavailable") }
        let normalized = raw.lowercased().filter { $0.isLetter || $0.isNumber }
        switch normalized {
        case "free": return "Free"
        case "go": return "Go"
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "prolite": return "Pro Lite"
        case "promax": return "Pro Max"
        case "team": return "Team"
        case "business", "selfservebusinessusagebased": return "Business"
        case "selfservebusinessprolite": return "Business · Pro Lite"
        case "enterprise", "ent26", "enterprisecbpautomation", "enterprisecbpusagebased": return "Enterprise"
        case "edu", "education": return "Education"
        case "eduplus": return "Education Plus"
        case "edupro": return "Education Pro"
        case "unknown": return L10n.text("Unknown")
        default:
            if normalized.hasPrefix("pro"), normalized.hasSuffix("x") {
                let multiplier = normalized.dropFirst(3).dropLast()
                if !multiplier.isEmpty, multiplier.allSatisfy(\.isNumber) { return "Pro \(multiplier)×" }
            }
            return String(raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(60)).capitalized
        }
    }
}
