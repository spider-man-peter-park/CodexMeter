import Foundation

public enum MenuBarMode: String, CaseIterable, Codable, Sendable {
    case focus, individual
}

/// Summarizes reported quota without treating a reset countdown as a fresh reading.
public struct FocusSummary: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case ready, low, exhausted, cached, paused, unavailable
    }

    public let state: State
    public let limitingMetric: MenuBarMetric?
    public let window: QuotaWindow?
    public let updatedAt: Date?

    public init(quota: QuotaSnapshot?, warning: String?, automaticRefresh: Bool,
                now: Date, refreshInterval: TimeInterval) {
        updatedAt = quota?.updatedAt
        let candidates: [(MenuBarMetric, QuotaWindow?)] = [(.fiveHour, quota?.fiveHour), (.weekly, quota?.weekly)]
        let reported = candidates.compactMap { metric, value -> (MenuBarMetric, QuotaWindow)? in
            guard let value, value.usedPercent.isFinite,
                  value.windowDurationMins == (metric == .fiveHour ? 300 : 10_080) else { return nil }
            return (metric, value)
        }
        // Keep the first window on ties so the limiting-period label does not oscillate.
        let limiting = reported.reduce(nil as (MenuBarMetric, QuotaWindow)?) { previous, candidate in
            guard let previous else { return candidate }
            return candidate.1.remainingPercent < previous.1.remainingPercent ? candidate : previous
        }
        limitingMetric = limiting?.0
        window = limiting?.1
        guard let window, let quota else { state = .unavailable; return }
        guard automaticRefresh else { state = .paused; return }
        let interval = refreshInterval.isFinite && refreshInterval > 0 ? refreshInterval : 180
        let age = now.timeIntervalSince(quota.updatedAt)
        if warning != nil || quota.isStale || quota.source == .logCache
            || !age.isFinite || age < 0 || age > max(360, interval * 2) {
            state = .cached
        } else if window.remainingPercent <= 0 {
            state = .exhausted
        } else if window.remainingPercent <= 10 {
            state = .low
        } else {
            state = .ready
        }
    }

    public var title: String {
        switch state {
        case .ready: L10n.text("Quota available")
        case .low: L10n.text("Low quota")
        case .exhausted: L10n.text("Quota exhausted")
        case .cached: L10n.text("Saved reading")
        case .paused: L10n.text("Refresh paused")
        case .unavailable: L10n.text("Waiting for Codex")
        }
    }

    public var message: String {
        switch state {
        case .ready: L10n.text("Your latest reported quota is available. Stay in your flow.")
        case .low: L10n.text("One quota window is running low. Check its reset time before your next session.")
        case .exhausted: L10n.text("A reported quota window is exhausted. A fresh reading will confirm recovery.")
        case .cached: L10n.text("This is the last known quota. Refresh to confirm the current limits.")
        case .paused: L10n.text("Automatic refresh is paused. These values are from the last successful reading.")
        case .unavailable: L10n.text("Open Codex and sign in, then refresh to load your quota.")
        }
    }

    public var symbolName: String {
        switch state {
        case .ready: "checkmark.circle"
        case .low: "exclamationmark.triangle"
        case .exhausted: "xmark.circle"
        case .cached: "clock"
        case .paused: "pause.circle"
        case .unavailable: "questionmark.circle"
        }
    }
}

public extension MenuBarFormatter {
    static func focusItem(quota: QuotaSnapshot?, warning: String?, autoRefresh: Bool,
                          now: Date = Date(), refreshInterval: TimeInterval = 180) -> MenuBarItem {
        let summary = FocusSummary(quota: quota, warning: warning, automaticRefresh: autoRefresh,
            now: now, refreshInterval: refreshInterval)
        var accessibility = L10n.text("CodexMeter Focus") + ". " + summary.title
        let title: String
        if let window = summary.window, let metric = summary.limitingMetric {
            let remaining = Int(window.remainingPercent.rounded())
            let belowOne = window.remainingPercent > 0 && remaining == 0
            title = (metric == .fiveHour ? "5h " : "7d ") + (belowOne ? "<1%" : "\(remaining)%")
            accessibility += ". " + (metric == .fiveHour ? L10n.text("5-hour quota") : L10n.text("7-day quota"))
            accessibility += belowOne ? L10n.text(", less than 1 percent remaining")
                : L10n.text(", \(remaining) percent remaining")
        } else {
            title = "Codex —"
        }
        accessibility += ". " + summary.message
        return MenuBarItem(metric: .focus, title: title, accessibilityLabel: accessibility,
            symbolName: summary.symbolName)
    }
}
