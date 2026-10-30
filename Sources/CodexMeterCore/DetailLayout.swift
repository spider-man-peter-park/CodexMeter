import Foundation

public enum DetailSection: String, CaseIterable, Identifiable, Sendable {
    case quota, today, speed, account, settings
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .quota: L10n.text("Plan limits")
        case .today: L10n.text("Today · this Mac")
        case .speed: L10n.text("Latest response")
        case .account: L10n.text("Account usage")
        case .settings: L10n.text("Settings")
        }
    }

    public var symbol: String {
        switch self {
        case .quota: "chart.bar.fill"
        case .today: "sun.max"
        case .speed: "bolt.fill"
        case .account: "number.circle.fill"
        case .settings: "gearshape"
        }
    }
}

public struct DetailLayout: Codable, Equatable, Sendable {
    public private(set) var order: [DetailSection]
    public private(set) var hidden: Set<DetailSection>
    public var visibleSections: [DetailSection] { order.filter { !hidden.contains($0) } }

    public init(order: [DetailSection] = DetailSection.allCases, hidden: Set<DetailSection> = []) {
        var seen: Set<DetailSection> = []
        self.order = (order + DetailSection.allCases).filter { seen.insert($0).inserted }
        self.hidden = hidden
    }

    public mutating func setVisible(_ visible: Bool, for section: DetailSection) {
        if visible { hidden.remove(section) } else { hidden.insert(section) }
    }

    public func canMove(_ section: DetailSection, by step: Int) -> Bool {
        guard step == -1 || step == 1, let index = order.firstIndex(of: section) else { return false }
        return order.indices.contains(index + step)
    }

    public mutating func move(_ section: DetailSection, by step: Int) {
        guard canMove(section, by: step), let index = order.firstIndex(of: section) else { return }
        order.swapAt(index, index + step)
    }

    private enum CodingKeys: String, CodingKey { case order, hidden }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Stable IDs survive language changes; unknown IDs cannot remove access to new sections.
        let order = (try? container.decode([String].self, forKey: .order)) ?? []
        let hidden = (try? container.decode([String].self, forKey: .hidden)) ?? []
        self.init(order: order.compactMap(DetailSection.init(rawValue:)),
                  hidden: Set(hidden.compactMap(DetailSection.init(rawValue:))))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(order.map(\.rawValue), forKey: .order)
        try container.encode(order.filter { hidden.contains($0) }.map(\.rawValue), forKey: .hidden)
    }
}
