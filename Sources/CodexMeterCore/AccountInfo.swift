import CoreFoundation
import Foundation

public struct AccountUsageSummary: Codable, Sendable, Equatable {
    public let lifetimeTokens: Int?
    public let peakDailyTokens: Int?
    public let longestRunningTurnSec: Int?
    public let currentStreakDays: Int?
    public let longestStreakDays: Int?

    public init(lifetimeTokens: Int? = nil, peakDailyTokens: Int? = nil,
                longestRunningTurnSec: Int? = nil, currentStreakDays: Int? = nil,
                longestStreakDays: Int? = nil) {
        self.lifetimeTokens = lifetimeTokens
        self.peakDailyTokens = peakDailyTokens
        self.longestRunningTurnSec = longestRunningTurnSec
        self.currentStreakDays = currentStreakDays
        self.longestStreakDays = longestStreakDays
    }
}

public struct AccountDailyUsageBucket: Codable, Sendable, Equatable, Identifiable {
    public let startDate: String
    public let tokens: Int
    public var id: String { startDate }

    public init(startDate: String, tokens: Int) {
        self.startDate = startDate
        self.tokens = tokens
    }
}

public struct AccountInfoSnapshot: Codable, Sendable, Equatable {
    public let planType: String?
    public let summary: AccountUsageSummary?
    public let dailyUsageBuckets: [AccountDailyUsageBucket]?
    public let updatedAt: Date
    public var isStale: Bool
    public var latestDailyUsage: AccountDailyUsageBucket? {
        dailyUsageBuckets?.max { $0.startDate < $1.startDate }
    }

    public init(planType: String? = nil, summary: AccountUsageSummary? = nil,
                dailyUsageBuckets: [AccountDailyUsageBucket]? = nil,
                updatedAt: Date = Date(), isStale: Bool = false) {
        self.planType = planType
        self.summary = summary
        self.dailyUsageBuckets = dailyUsageBuckets
        self.updatedAt = updatedAt
        self.isStale = isStale
    }
}

public enum AccountInfoParser {
    public static func parse(account: [String: Any], usage: [String: Any],
                             at date: Date = Date()) -> AccountInfoSnapshot? {
        let accountResult = account["result"] as? [String: Any] ?? account
        let usageResult = usage["result"] as? [String: Any] ?? usage
        guard let accountFields = accountResult["account"] as? [String: Any] else { return nil }
        let summaryFields = usageResult["summary"] as? [String: Any]
        guard summaryFields != nil || usageResult["summary"] is NSNull
                || usageResult["dailyUsageBuckets"] is [Any]
                || usageResult["dailyUsageBuckets"] is NSNull else { return nil }
        let summary = summaryFields.map {
            AccountUsageSummary(lifetimeTokens: nonnegativeInteger($0["lifetimeTokens"]),
                peakDailyTokens: nonnegativeInteger($0["peakDailyTokens"]),
                longestRunningTurnSec: nonnegativeInteger($0["longestRunningTurnSec"]),
                currentStreakDays: nonnegativeInteger($0["currentStreakDays"]),
                longestStreakDays: nonnegativeInteger($0["longestStreakDays"]))
        }
        let plan = (accountFields["planType"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return AccountInfoSnapshot(planType: plan, summary: summary,
            dailyUsageBuckets: parseDailyBuckets(usageResult["dailyUsageBuckets"]),
            updatedAt: date)
    }

    private static func parseDailyBuckets(_ value: Any?) -> [AccountDailyUsageBucket]? {
        guard let rows = value as? [Any] else { return nil }
        var buckets: [AccountDailyUsageBucket] = []
        var seen: [String: Int] = [:]
        for row in rows {
            guard let fields = row as? [String: Any],
                  let startDate = fields["startDate"] as? String, validDay(startDate),
                  let tokens = nonnegativeInteger(fields["tokens"]) else { return nil }
            if let previous = seen[startDate] {
                guard previous == tokens else { return nil }
                continue
            }
            seen[startDate] = tokens
            buckets.append(AccountDailyUsageBucket(startDate: startDate, tokens: tokens))
        }
        // Keep the server's date labels and order; do not invent missing days or a time zone.
        return buckets
    }

    static func validDay(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) }),
              let year = Int(text.prefix(4)), year > 0,
              let month = Int(text.dropFirst(5).prefix(2)), (1...12).contains(month),
              let day = Int(text.suffix(2)) else { return false }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return (1...days[month - 1]).contains(day)
    }

    private static func nonnegativeInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let type = String(cString: number.objCType)
        if ["c", "s", "i", "l", "q", "C", "S", "I", "L", "Q"].contains(type) {
            guard let integer = Int(number.stringValue), integer >= 0 else { return nil }
            return integer
        }
        let value = number.doubleValue
        guard value.isFinite, value >= 0 else { return nil }
        return Int(exactly: value)
    }
}
