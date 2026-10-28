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

public struct ResetCredit: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let resetType: String
    public let status: String
    public let grantedAt: Date?
    public let expiresAt: Date?
    public let title: String?
    public let description: String?

    public init(id: String, resetType: String, status: String, grantedAt: Date? = nil,
                expiresAt: Date? = nil, title: String? = nil, description: String? = nil) {
        self.id = id
        self.resetType = resetType
        self.status = status
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
        self.title = title
        self.description = description
    }
}

public struct ResetCreditSummary: Codable, Sendable, Equatable {
    public let availableCount: Int
    public let credits: [ResetCredit]?

    public init(availableCount: Int, credits: [ResetCredit]? = nil) {
        self.availableCount = availableCount
        self.credits = credits
    }
}

public struct QuotaSnapshot: Codable, Sendable, Equatable {
    public let fiveHour: QuotaWindow?
    public let weekly: QuotaWindow?
    public let updatedAt: Date
    public let source: QuotaSource
    public var isStale: Bool
    public let resetCredits: ResetCreditSummary?

    public init(fiveHour: QuotaWindow?, weekly: QuotaWindow?, updatedAt: Date,
                source: QuotaSource, isStale: Bool = false, resetCredits: ResetCreditSummary? = nil) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.updatedAt = updatedAt
        self.source = source
        self.isStale = isStale
        self.resetCredits = resetCredits
    }
}

public enum QuotaParser {
    public static func parse(_ object: [String: Any], at date: Date = Date(),
                             source: QuotaSource = .appServer) -> QuotaSnapshot? {
        let result = object["result"] as? [String: Any] ?? object
        let resetCredits = parseResetCredits(result["rateLimitResetCredits"])
        let buckets = result["rateLimitsByLimitId"] as? [String: Any]
            ?? result["rate_limits_by_limit_id"] as? [String: Any]
        let bucket: [String: Any]
        if let buckets {
            // Never combine unrelated model buckets into the Codex plan quota.
            bucket = buckets["codex"] as? [String: Any] ?? [:]
        } else if let legacy = result["rateLimits"] as? [String: Any]
                    ?? result["rate_limits"] as? [String: Any] {
            bucket = legacy
        } else {
            bucket = result
        }
        if let identifier = bucket["limitId"] as? String ?? bucket["limit_id"] as? String,
           identifier != "codex" {
            guard let resetCredits else { return nil }
            return QuotaSnapshot(fiveHour: nil, weekly: nil, updatedAt: date, source: source,
                                 isStale: source == .logCache, resetCredits: resetCredits)
        }
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
        guard fiveHour != nil || weekly != nil || resetCredits != nil else { return nil }
        return QuotaSnapshot(fiveHour: fiveHour, weekly: weekly, updatedAt: date,
                             source: source, isStale: source == .logCache, resetCredits: resetCredits)
    }

    private static func parseResetCredits(_ value: Any?) -> ResetCreditSummary? {
        guard let raw = value as? [String: Any],
              let count = number(raw["availableCount"]), count >= 0,
              count.rounded() == count, count < Double(Int.max) else { return nil }
        let availableCount = Int(count)
        guard let rows = raw["credits"] as? [Any] else {
            return ResetCreditSummary(availableCount: availableCount)
        }
        var credits: [ResetCredit] = []
        for row in rows {
            guard let credit = row as? [String: Any],
                  let id = credit["id"] as? String, !id.isEmpty,
                  let resetType = credit["resetType"] as? String, !resetType.isEmpty,
                  let status = credit["status"] as? String, !status.isEmpty else {
                // Preserve the authoritative count when detail rows use an unsupported schema.
                return ResetCreditSummary(availableCount: availableCount)
            }
            credits.append(ResetCredit(id: id, resetType: resetType, status: status,
                grantedAt: number(credit["grantedAt"]).map { Date(timeIntervalSince1970: $0) },
                expiresAt: number(credit["expiresAt"]).map { Date(timeIntervalSince1970: $0) },
                title: credit["title"] as? String, description: credit["description"] as? String))
        }
        // Detail rows can be capped by the service; their count is never an available-count substitute.
        return ResetCreditSummary(availableCount: availableCount, credits: credits)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        return value.isFinite ? value : nil
    }
}

import CoreFoundation
