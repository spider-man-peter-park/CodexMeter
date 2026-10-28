import Foundation

public struct DisplayOptions: Equatable, Codable, Sendable {
    public var fullMode: Bool
    public var showFiveHour: Bool
    public var showWeekly: Bool
    public var showCountdown: Bool
    public var showTPS: Bool

    public init(fullMode: Bool = false, showFiveHour: Bool = true, showWeekly: Bool = true,
                showCountdown: Bool = true, showTPS: Bool = true) {
        self.fullMode = fullMode
        self.showFiveHour = showFiveHour
        self.showWeekly = showWeekly
        self.showCountdown = showCountdown
        self.showTPS = showTPS
    }
}

public enum MenuBarFormatter {
    public static func title(quota: QuotaSnapshot?, sample: TPSSample?, options: DisplayOptions,
                             now: Date = Date(), stale: Bool = false) -> String {
        var components: [String] = []
        func window(_ label: String, _ value: QuotaWindow?) -> String {
            guard let value else { return "\(label) \(quota == nil ? "—" : "N/A")" }
            var text = "\(label) \(Int(value.remainingPercent.rounded()))%"
            if options.fullMode && options.showCountdown {
                text += " " + countdown(until: value.resetsAt, now: now)
            }
            return text
        }
        if options.showFiveHour { components.append(window("5h", quota?.fiveHour)) }
        if options.showWeekly { components.append(window("7d", quota?.weekly)) }
        if options.showTPS {
            components.append(sample.map { String(format: "%.0f TPS", $0.tokensPerSecond) } ?? "— TPS")
        }
        guard !components.isEmpty else { return "CodexMeter" }
        let isCached = quota.map { $0.source == .logCache || $0.isStale } ?? false
        return components.joined(separator: " | ") + ((stale || isCached) && (options.showFiveHour || options.showWeekly) ? " *" : "")
    }

    public static func countdown(until reset: Date?, now: Date = Date()) -> String {
        guard let reset else { return "—" }
        let remaining = max(0, Int(ceil(reset.timeIntervalSince(now) / 60)))
        if remaining == 0 { return "now" }
        let days = remaining / 1440
        let hours = (remaining % 1440) / 60
        let minutes = remaining % 60
        if days > 0 { return "\(days)d\(hours)h" }
        if hours > 0 { return "\(hours)h\(minutes)m" }
        return "\(minutes)m"
    }
}
