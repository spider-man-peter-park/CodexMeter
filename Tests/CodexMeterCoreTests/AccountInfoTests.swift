import Foundation
import Testing
@testable import CodexMeterCore

struct AccountInfoTests {
    private var account: [String: Any] { ["account": ["type": "chatgpt", "planType": "pro"]] }

    @Test func parsesAccountWideSummaryAndExactServerDayLabels() throws {
        let timestamp = Date(timeIntervalSince1970: 1234)
        let snapshot = try #require(AccountInfoParser.parse(account: account, usage: [
            "summary": ["lifetimeTokens": 12_345_678_901, "peakDailyTokens": 222_222_222,
                "longestRunningTurnSec": 3_605, "currentStreakDays": 7, "longestStreakDays": 28],
            "dailyUsageBuckets": [["startDate": "2026-10-27", "tokens": 12_345_678],
                                  ["startDate": "2026-10-26", "tokens": 9_876_543]]
        ], at: timestamp))
        #expect(snapshot.planType == "pro")
        #expect(snapshot.summary?.lifetimeTokens == 12_345_678_901)
        #expect(snapshot.summary?.peakDailyTokens == 222_222_222)
        #expect(snapshot.summary?.longestRunningTurnSec == 3_605)
        #expect(snapshot.summary?.currentStreakDays == 7)
        #expect(snapshot.summary?.longestStreakDays == 28)
        #expect(snapshot.dailyUsageBuckets?.map(\.startDate) == ["2026-10-27", "2026-10-26"])
        #expect(snapshot.latestDailyUsage?.startDate == "2026-10-27")
        #expect(snapshot.latestDailyUsage?.tokens == 12_345_678)
        #expect(snapshot.dailyUsageBuckets?.contains { $0.startDate == "2026-10-28" } == false)
        #expect(snapshot.updatedAt == timestamp)
        #expect(!snapshot.isStale)
    }

    @Test func nullUnavailableAndKnownZeroRemainDistinct() throws {
        let snapshot = try #require(AccountInfoParser.parse(account: account, usage: [
            "summary": ["lifetimeTokens": NSNull(), "peakDailyTokens": 0,
                        "currentStreakDays": NSNull()], "dailyUsageBuckets": NSNull()
        ]))
        #expect(snapshot.summary?.lifetimeTokens == nil)
        #expect(snapshot.summary?.peakDailyTokens == 0)
        #expect(snapshot.summary?.currentStreakDays == nil)
        #expect(snapshot.summary?.longestStreakDays == nil)
        #expect(snapshot.dailyUsageBuckets == nil)
        let empty = try #require(AccountInfoParser.parse(account: account, usage: [
            "summary": NSNull(), "dailyUsageBuckets": []
        ]))
        #expect(empty.summary == nil)
        #expect(empty.dailyUsageBuckets == [])
        #expect(empty.latestDailyUsage == nil)
    }

    @Test func rejectsInvalidMetricNumbersWithoutInventingZero() throws {
        for value in [-1, true, 1.25, "123", Double.nan, Double.infinity, NSNumber(value: UInt64.max)] as [Any] {
            let snapshot = try #require(AccountInfoParser.parse(account: account, usage: [
                "summary": ["lifetimeTokens": value]
            ]))
            #expect(snapshot.summary?.lifetimeTokens == nil)
        }
        let maximum = try #require(AccountInfoParser.parse(account: account, usage: [
            "summary": ["lifetimeTokens": NSNumber(value: Int.max), "peakDailyTokens": 1000.0]
        ]))
        #expect(maximum.summary?.lifetimeTokens == Int.max)
        #expect(maximum.summary?.peakDailyTokens == 1000)
    }

    @Test func malformedDailyRowsAreUnknownRatherThanEmptyOrSummed() throws {
        for row in [["startDate": "2026-02-29", "tokens": 1],
                    ["startDate": "2026-13-01", "tokens": 1],
                    ["startDate": "2026-10-28T00:00:00Z", "tokens": 1],
                    ["startDate": "2026-10-28", "tokens": true],
                    ["startDate": "2026-10-28", "tokens": -1]] as [[String: Any]] {
            let snapshot = try #require(AccountInfoParser.parse(account: account, usage: [
                "summary": [:], "dailyUsageBuckets": [row]
            ]))
            #expect(snapshot.dailyUsageBuckets == nil)
        }
        let duplicate = try #require(AccountInfoParser.parse(account: account, usage: [
            "summary": [:], "dailyUsageBuckets": [["startDate": "2026-10-27", "tokens": 10],
                                                  ["startDate": "2026-10-27", "tokens": 10]]
        ]))
        #expect(duplicate.dailyUsageBuckets?.count == 1)
        #expect(duplicate.latestDailyUsage?.tokens == 10)
        let conflicting = try #require(AccountInfoParser.parse(account: account, usage: [
            "summary": [:], "dailyUsageBuckets": [["startDate": "2026-10-27", "tokens": 10],
                                                  ["startDate": "2026-10-27", "tokens": 20]]
        ]))
        #expect(conflicting.dailyUsageBuckets == nil)
    }

    @Test func calendarValidationKeepsLeapDayWithoutLocalTimeConversion() throws {
        let snapshot = try #require(AccountInfoParser.parse(account: account, usage: [
            "summary": [:], "dailyUsageBuckets": [["startDate": "2024-02-29", "tokens": 0]]
        ]))
        #expect(snapshot.latestDailyUsage?.startDate == "2024-02-29")
        #expect(snapshot.latestDailyUsage?.tokens == 0)
    }

    @Test func serializationStoresOnlyWhitelistedAccountMetrics() throws {
        let snapshot = try #require(AccountInfoParser.parse(account: ["account": [
            "type": "chatgpt", "planType": "pro", "email": "PRIVATE_EMAIL",
            "accountId": "PRIVATE_ACCOUNT", "avatar": "PRIVATE_AVATAR_URL"
        ], "workspaceRouting": ["chatgptAccountId": "PRIVATE_ROUTING"]], usage: [
            "summary": ["lifetimeTokens": 42, "secret": "PRIVATE_SUMMARY"],
            "dailyUsageBuckets": [["startDate": "2026-10-27", "tokens": 10]],
            "threadUsage": ["threadId": "PRIVATE_THREAD"], "prompt": "PRIVATE_PROMPT"
        ]))
        let bytes = try JSONEncoder().encode(snapshot)
        let text = try #require(String(data: bytes, encoding: .utf8))
        #expect(!text.contains("PRIVATE_"))
        #expect(!text.contains("email"))
        #expect(!text.contains("threadUsage"))
        #expect(try JSONDecoder().decode(AccountInfoSnapshot.self, from: bytes) == snapshot)
    }

    @Test func missingAccountOrUnsupportedResponseSchemaHasNoSnapshot() {
        #expect(AccountInfoParser.parse(account: ["account": NSNull()], usage: ["summary": [:]]) == nil)
        #expect(AccountInfoParser.parse(account: account, usage: ["unrecognized": 1]) == nil)
        #expect(AccountInfoParser.parse(account: account, usage: ["summary": "bad"]) == nil)
    }
}
