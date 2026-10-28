import Foundation

public enum MenuBarMetric: String, Codable, CaseIterable, Hashable, Sendable {
    case fiveHour, weekly, tps, fallback
}

public enum QuotaLabelStyle: String, Codable, CaseIterable, Sendable {
    case ai, window, none
}

public enum CountdownStyle: String, Codable, CaseIterable, Sendable {
    case compact, clock
}

public struct MenuBarItem: Equatable, Sendable, Identifiable {
    public let metric: MenuBarMetric
    public let title: String
    public let accessibilityLabel: String
    public var id: MenuBarMetric { metric }

    public init(metric: MenuBarMetric, title: String, accessibilityLabel: String) {
        self.metric = metric
        self.title = title
        self.accessibilityLabel = accessibilityLabel
    }
}

public struct DisplayOptions: Equatable, Codable, Sendable {
    // Retained for preference migration; countdown visibility is now independent.
    public var fullMode: Bool
    public var showFiveHour: Bool
    public var showWeekly: Bool
    public var showCountdown: Bool
    public var showTPS: Bool
    public var quotaLabelStyle: QuotaLabelStyle
    public var countdownStyle: CountdownStyle
    public var tpsDecimals: Int
    public var showTPSLabel: Bool

    public init(fullMode: Bool = false, showFiveHour: Bool = true, showWeekly: Bool = true,
                showCountdown: Bool = true, showTPS: Bool = true,
                quotaLabelStyle: QuotaLabelStyle = .ai, countdownStyle: CountdownStyle = .compact,
                tpsDecimals: Int = 0, showTPSLabel: Bool = true) {
        self.fullMode = fullMode
        self.showFiveHour = showFiveHour
        self.showWeekly = showWeekly
        self.showCountdown = showCountdown
        self.showTPS = showTPS
        self.quotaLabelStyle = quotaLabelStyle
        self.countdownStyle = countdownStyle
        self.tpsDecimals = tpsDecimals
        self.showTPSLabel = showTPSLabel
    }

    private enum CodingKeys: String, CodingKey {
        case fullMode, showFiveHour, showWeekly, showCountdown, showTPS
        case quotaLabelStyle, countdownStyle, tpsDecimals, showTPSLabel
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fullMode = try values.decodeIfPresent(Bool.self, forKey: .fullMode) ?? false
        showFiveHour = try values.decodeIfPresent(Bool.self, forKey: .showFiveHour) ?? true
        showWeekly = try values.decodeIfPresent(Bool.self, forKey: .showWeekly) ?? true
        showCountdown = try values.decodeIfPresent(Bool.self, forKey: .showCountdown) ?? true
        showTPS = try values.decodeIfPresent(Bool.self, forKey: .showTPS) ?? true
        quotaLabelStyle = try values.decodeIfPresent(QuotaLabelStyle.self, forKey: .quotaLabelStyle) ?? .ai
        countdownStyle = try values.decodeIfPresent(CountdownStyle.self, forKey: .countdownStyle) ?? .compact
        tpsDecimals = try values.decodeIfPresent(Int.self, forKey: .tpsDecimals) ?? 0
        showTPSLabel = try values.decodeIfPresent(Bool.self, forKey: .showTPSLabel) ?? true
    }
}

public enum MenuBarFormatter {
    public static func items(quota: QuotaSnapshot?, sample: TPSSample?, options: DisplayOptions,
                             now: Date = Date(), stale: Bool = false) -> [MenuBarItem] {
        var result: [MenuBarItem] = []
        let isCached = quota.map { stale || $0.source == .logCache || $0.isStale } ?? false
        func window(_ metric: MenuBarMetric, _ value: QuotaWindow?) -> MenuBarItem {
            let windowLabel = metric == .fiveHour ? "5h" : "7d"
            let accessibleWindow = metric == .fiveHour ? "5-hour quota" : "7-day quota"
            let label: String
            switch options.quotaLabelStyle {
            case .ai: label = "AI "
            case .window: label = windowLabel + " "
            case .none: label = ""
            }
            var title = label + (value.map { "\(Int($0.remainingPercent.rounded()))%" } ?? (quota == nil ? "—" : "N/A"))
            var accessibility = accessibleWindow
            if let value {
                accessibility += ", \(Int(value.remainingPercent.rounded())) percent remaining"
                if options.showCountdown {
                    let remaining = countdown(until: value.resetsAt, now: now, style: options.countdownStyle)
                    title += " " + remaining
                    accessibility += ", resets in " + remaining
                }
            } else {
                accessibility += quota == nil ? ", data unavailable" : ", window not reported by this account"
            }
            if isCached {
                title += " *"
                accessibility += ", cached data, may be outdated"
            }
            return MenuBarItem(metric: metric, title: title, accessibilityLabel: accessibility)
        }
        if options.showFiveHour { result.append(window(.fiveHour, quota?.fiveHour)) }
        if options.showWeekly { result.append(window(.weekly, quota?.weekly)) }
        if options.showTPS {
            let precision = options.tpsDecimals > 0 ? 1 : 0
            let value = sample.map { String(format: "%.*f", precision, $0.tokensPerSecond) } ?? "—"
            result.append(MenuBarItem(metric: .tps, title: value + (options.showTPSLabel ? " TPS" : ""),
                                      accessibilityLabel: sample == nil ? "Latest response speed unavailable" :
                                        "Latest completed response, \(value) effective tokens per second"))
        }
        return result.isEmpty ? [MenuBarItem(metric: .fallback, title: "AI", accessibilityLabel: "CodexMeter, open details")] : result
    }

    public static func title(quota: QuotaSnapshot?, sample: TPSSample?, options: DisplayOptions,
                             now: Date = Date(), stale: Bool = false) -> String {
        items(quota: quota, sample: sample, options: options, now: now, stale: stale).map(\.title).joined(separator: " | ")
    }

    public static func countdown(until reset: Date?, now: Date = Date(), style: CountdownStyle = .compact) -> String {
        guard let reset else { return "—" }
        let remaining = max(0, Int(ceil(reset.timeIntervalSince(now) / 60)))
        let days = remaining / 1440
        let hours = (remaining % 1440) / 60
        let minutes = remaining % 60
        if style == .clock {
            let time = String(format: "%02d:%02d", hours, minutes)
            return days > 0 ? "\(days)d" + time : time
        }
        if remaining == 0 { return "now" }
        if days > 0 { return "\(days)d\(hours)h" }
        if hours > 0 { return "\(hours)h\(minutes)m" }
        return "\(minutes)m"
    }
}
