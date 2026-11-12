import CodexMeterCore
import Foundation

enum WorkspaceDestination: Hashable, Identifiable {
    case overview
    case usage
    case settings(SettingsPane)
    case detail(DetailSection)

    static let codexDestinations: [WorkspaceDestination] = [.detail(.quota), .usage, .detail(.speed)]
    static let systemSections: [DetailSection] = [.cpu, .gpu, .ram, .network]

    var canonical: WorkspaceDestination {
        switch self {
        case .detail(.today), .detail(.account): .usage
        case .detail(.settings): .settings(.general)
        default: self
        }
    }

    var id: String {
        switch self {
        case .overview: "overview"
        case .usage: "usage"
        case .settings(let pane): "settings." + pane.rawValue
        case .detail(let section): section.rawValue
        }
    }

    var title: String {
        switch self {
        case .overview: L10n.text("Overview")
        case .usage: L10n.text("Token usage")
        case .settings(let pane): pane.title
        case .detail(.speed): L10n.text("Responses")
        case .detail(let section): section.title
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .usage: "square.stack.3d.up"
        case .settings(let pane): pane.symbol
        case .detail(let section): section.symbol.replacingOccurrences(of: ".fill", with: "")
        }
    }

    var subtitle: String {
        switch self {
        case .overview: L10n.text("Know your limits. Keep your focus.")
        case .usage: L10n.text("Today's local estimate and account history, with separate dates and totals.")
        case .settings: L10n.text("Make CodexMeter work the way you do.")
        case .detail(.quota): L10n.text("Reported plan windows, reset times and reset credits.")
        case .detail(.today): L10n.text("A local estimate for this Mac, kept separate from account totals.")
        case .detail(.speed): L10n.text("Recent completed responses with reliable timing.")
        case .detail(.account): L10n.text("Account-wide history, on the dates reported by Codex.")
        case .detail(.cpu), .detail(.gpu), .detail(.ram): L10n.text("Live readings and a two-minute history. Collected locally.")
        case .detail(.network): L10n.text("Live network rates and active processes. Collected locally.")
        case .detail(.settings): L10n.text("Make CodexMeter work the way you do.")
        }
    }

    var isSettings: Bool {
        if case .settings = canonical { return true }
        return false
    }

    var detailSection: DetailSection {
        switch canonical {
        case .overview: .quota
        case .usage: .account
        case .settings: .settings
        case .detail(let section): section
        }
    }
}
