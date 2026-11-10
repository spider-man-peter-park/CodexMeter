import CodexMeterCore
import Foundation

enum WorkspaceDestination: Hashable, Identifiable {
    case overview
    case detail(DetailSection)

    static let codexSections: [DetailSection] = [.quota, .today, .speed, .account]
    static let systemSections: [DetailSection] = [.cpu, .gpu, .ram, .network]

    var id: String {
        switch self {
        case .overview: "overview"
        case .detail(let section): section.rawValue
        }
    }

    var title: String {
        switch self {
        case .overview: L10n.text("Overview")
        case .detail(.speed): L10n.text("Responses")
        case .detail(let section): section.title
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .detail(let section): section.symbol.replacingOccurrences(of: ".fill", with: "")
        }
    }

    var subtitle: String {
        switch self {
        case .overview: L10n.text("Know your limits. Keep your focus.")
        case .detail(.quota): L10n.text("Reported plan windows, reset times and reset credits.")
        case .detail(.today): L10n.text("A local estimate for this Mac, kept separate from account totals.")
        case .detail(.speed): L10n.text("Recent completed responses with reliable timing.")
        case .detail(.account): L10n.text("Account-wide history, on the dates reported by Codex.")
        case .detail(.cpu), .detail(.gpu), .detail(.ram): L10n.text("Live readings and a two-minute history. Collected locally.")
        case .detail(.network): L10n.text("Live network rates and active processes. Collected locally.")
        case .detail(.settings): L10n.text("Make CodexMeter work the way you do.")
        }
    }
}
