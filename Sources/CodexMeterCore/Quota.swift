import Foundation

public enum QuotaSource: String, Codable, Sendable {
    case appServer
    case logCache
}

public struct QuotaWindow: Codable, Sendable, Equatable {
    public let usedPercent: Double
    public let windowDurationMins: Int
    public let resetsAt: Date?
    public var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }

    public init(usedPercent: Double, windowDurationMins: Int, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }
}

public struct QuotaSnapshot: Codable, Sendable, Equatable {
    public let fiveHour: QuotaWindow?
    public let weekly: QuotaWindow?
    public let updatedAt: Date
    public let source: QuotaSource
    public var isStale: Bool

    public init(fiveHour: QuotaWindow?, weekly: QuotaWindow?, updatedAt: Date,
                source: QuotaSource, isStale: Bool = false) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.updatedAt = updatedAt
        self.source = source
        self.isStale = isStale
    }
}

public enum QuotaParser {
    public static func parse(_ object: [String: Any], at date: Date = Date(),
                             source: QuotaSource = .appServer) -> QuotaSnapshot? {
        let result = object["result"] as? [String: Any] ?? object
        let buckets = result["rateLimitsByLimitId"] as? [String: Any]
            ?? result["rate_limits_by_limit_id"] as? [String: Any]
        let bucket: [String: Any]
        if let buckets {
            // Never combine unrelated model buckets into the Codex plan quota.
            guard let codex = buckets["codex"] as? [String: Any] else { return nil }
            bucket = codex
        } else if let legacy = result["rateLimits"] as? [String: Any]
                    ?? result["rate_limits"] as? [String: Any] {
            bucket = legacy
        } else {
            bucket = result
        }
        if let identifier = bucket["limitId"] as? String ?? bucket["limit_id"] as? String,
           identifier != "codex" { return nil }
        var fiveHour: QuotaWindow?
        var weekly: QuotaWindow?
        for key in ["primary", "secondary"] {
            guard let raw = bucket[key] as? [String: Any],
                  let used = number(raw["usedPercent"] ?? raw["used_percent"]),
                  let duration = number(raw["windowDurationMins"] ?? raw["window_minutes"]),
                  duration == 300 || duration == 10_080 else { continue }
            let resetSeconds = number(raw["resetsAt"] ?? raw["resets_at"])
            let reset = resetSeconds.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
            let window = QuotaWindow(usedPercent: used, windowDurationMins: Int(duration), resetsAt: reset)
            if duration == 300 { fiveHour = window } else { weekly = window }
        }
        guard fiveHour != nil || weekly != nil else { return nil }
        return QuotaSnapshot(fiveHour: fiveHour, weekly: weekly, updatedAt: date,
                             source: source, isStale: source == .logCache)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        return value.isFinite ? value : nil
    }
}

import CoreFoundation
