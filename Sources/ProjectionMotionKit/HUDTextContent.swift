public struct HUDTextContent: Equatable, Sendable {
    public var title: String
    public var value: String
    public var subtitle: String
    public var detail: String
    public var footnote: String
    public var badge: String
    public var warning: Bool

    public init(title: String, value: String, subtitle: String = "", detail: String = "",
                footnote: String = "", badge: String = "", warning: Bool = false) {
        self.title = title; self.value = value; self.subtitle = subtitle
        self.detail = detail; self.footnote = footnote; self.badge = badge; self.warning = warning
    }

    public var accessibilityText: String {
        [title, value, subtitle, detail, footnote, badge].filter { !$0.isEmpty }.joined(separator: ". ")
    }
}
