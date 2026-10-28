import Foundation
import Testing
@testable import CodexMeterCore

struct QuotaTests {
    @Test func testWindowOrderAndPercentageClamping() throws {
        let raw: [String: Any] = ["rateLimits": [
            "primary": ["usedPercent": 130, "windowDurationMins": 10_080, "resetsAt": 2000],
            "secondary": ["usedPercent": -2, "windowDurationMins": 300, "resetsAt": 1000]
        ]]
        let snapshot = try #require(QuotaParser.parse(raw, at: Date(timeIntervalSince1970: 10)))
        #expect(snapshot.fiveHour?.remainingPercent == 100)
        #expect(snapshot.weekly?.remainingPercent == 0)
        #expect(snapshot.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1000))
        #expect(snapshot.updatedAt == Date(timeIntervalSince1970: 10))
    }

    @Test func testOnlyWeeklyDoesNotInventFiveHours() throws {
        let snapshot = try #require(QuotaParser.parse(["primary": [
            "usedPercent": 39.5, "windowDurationMins": 10_080
        ]]))
        #expect(snapshot.fiveHour == nil)
        #expect(snapshot.weekly?.remainingPercent == 60.5)
        #expect(snapshot.weekly?.resetsAt == nil)
    }

    @Test func testCodexBucketOverridesLegacyAndOtherBuckets() throws {
        let snapshot = try #require(QuotaParser.parse([
            "rateLimitsByLimitId": ["codex": ["primary": ["usedPercent": 20, "windowDurationMins": 300]],
                                    "codex_other": ["secondary": ["usedPercent": 2, "windowDurationMins": 10_080]]],
            "rateLimits": ["primary": ["usedPercent": 99, "windowDurationMins": 300]]
        ]))
        #expect(snapshot.fiveHour?.remainingPercent == 80)
        #expect(snapshot.weekly == nil)
        #expect(QuotaParser.parse(["rateLimitsByLimitId": ["other": ["primary": ["usedPercent": 20, "windowDurationMins": 300]]]]) == nil)
    }

    @Test func testSnakeCaseLogCacheAndMissingValues() throws {
        let snapshot = try #require(QuotaParser.parse(["rate_limits": ["primary": [
            "used_percent": 25, "window_minutes": 300, "resets_at": 1234
        ]]], at: Date(timeIntervalSince1970: 99), source: .logCache))
        #expect(snapshot.source == .logCache)
        #expect(snapshot.isStale)
        #expect(snapshot.fiveHour?.remainingPercent == 75)
        #expect(QuotaParser.parse([:]) == nil)
        #expect(QuotaParser.parse(["primary": ["windowDurationMins": 300]]) == nil)
        #expect(QuotaParser.parse(["primary": ["usedPercent": true, "windowDurationMins": 300]]) == nil)
        #expect(QuotaParser.parse(["primary": ["usedPercent": 30, "windowDurationMins": 60]]) == nil)
        #expect(QuotaParser.parse(["limitId": "other", "primary": ["usedPercent": 30, "windowDurationMins": 300]]) == nil)
    }

    @Test func resetCreditsKeepAuthoritativeCountAndDetails() throws {
        let snapshot = try #require(QuotaParser.parse(["result": [
            "rateLimits": ["primary": ["usedPercent": 40, "windowDurationMins": 10_080]],
            "rateLimitResetCredits": ["availableCount": 4, "credits": [[
                "id": "fixture-credit", "resetType": "codexRateLimits", "status": "available",
                "grantedAt": 1_700_000_000, "expiresAt": 1_700_086_400,
                "title": "Rate-limit reset", "description": "Reset an eligible quota window."
            ]]]
        ]]))
        let summary = try #require(snapshot.resetCredits)
        #expect(summary.availableCount == 4)
        #expect(summary.credits?.count == 1)
        let credit = try #require(summary.credits?.first)
        #expect(credit.id == "fixture-credit")
        #expect(credit.resetType == "codexRateLimits")
        #expect(credit.status == "available")
        #expect(credit.grantedAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(credit.expiresAt == Date(timeIntervalSince1970: 1_700_086_400))
        #expect(credit.title == "Rate-limit reset")
        #expect(credit.description == "Reset an eligible quota window.")
        #expect(snapshot.weekly?.remainingPercent == 60)
        let decoded = try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
    }

    @Test func resetCreditCountOnlyPreservesUnknownDetails() throws {
        for raw in [["availableCount": 2], ["availableCount": 2, "credits": NSNull()]] as [[String: Any]] {
            let snapshot = try #require(QuotaParser.parse(["rateLimitResetCredits": raw]))
            #expect(snapshot.resetCredits?.availableCount == 2)
            #expect(snapshot.resetCredits?.credits == nil)
            #expect(snapshot.fiveHour == nil)
            #expect(snapshot.weekly == nil)
        }
    }

    @Test func resetCreditZeroAndEmptyRowsAreKnownValues() throws {
        let snapshot = try #require(QuotaParser.parse(["rateLimitResetCredits": [
            "availableCount": 0, "credits": []
        ]]))
        #expect(snapshot.resetCredits?.availableCount == 0)
        #expect(snapshot.resetCredits?.credits == [])
        let truncated = try #require(QuotaParser.parse(["rateLimitResetCredits": [
            "availableCount": 3, "credits": []
        ]]))
        #expect(truncated.resetCredits?.availableCount == 3)
        #expect(truncated.resetCredits?.credits == [])
    }

    @Test func absentNullAndInvalidResetCountsStayUnavailable() throws {
        let window: [String: Any] = ["primary": ["usedPercent": 25, "windowDurationMins": 300]]
        let absent = try #require(QuotaParser.parse(window))
        #expect(absent.resetCredits == nil)
        let null = try #require(QuotaParser.parse(["rateLimits": window, "rateLimitResetCredits": NSNull()]))
        #expect(null.resetCredits == nil)
        for count in [-1, 1.5, Double.nan, Double.infinity, true, "1", NSNull()] as [Any] {
            let snapshot = try #require(QuotaParser.parse(["rateLimits": window,
                "rateLimitResetCredits": ["availableCount": count, "credits": []]]))
            #expect(snapshot.resetCredits == nil)
            #expect(snapshot.fiveHour?.remainingPercent == 75)
        }
        #expect(QuotaParser.parse(["rateLimitResetCredits": ["credits": []]]) == nil)
        #expect(QuotaParser.parse(["rateLimitResetCredits": NSNull()]) == nil)
    }

    @Test func resetCreditOptionalDatesAndLabelsMayBeNull() throws {
        let snapshot = try #require(QuotaParser.parse(["rateLimitResetCredits": [
            "availableCount": 1, "credits": [["id": "fixture-no-expiry", "resetType": "codexRateLimits",
                "status": "available", "grantedAt": NSNull(), "expiresAt": NSNull(),
                "title": NSNull(), "description": NSNull()]]
        ]]))
        let credit = try #require(snapshot.resetCredits?.credits?.first)
        #expect(credit.grantedAt == nil)
        #expect(credit.expiresAt == nil)
        #expect(credit.title == nil)
        #expect(credit.description == nil)
    }

    @Test func malformedResetDetailsPreserveOnlyVerifiedCount() throws {
        let snapshot = try #require(QuotaParser.parse(["rateLimitResetCredits": [
            "availableCount": 2, "credits": [["id": "fixture-incomplete"]]
        ]]))
        #expect(snapshot.resetCredits?.availableCount == 2)
        #expect(snapshot.resetCredits?.credits == nil)
    }

    @Test func creditsWithoutCodexWindowDoNotBorrowOtherBuckets() throws {
        let snapshot = try #require(QuotaParser.parse([
            "rateLimitsByLimitId": ["other": ["primary": ["usedPercent": 99, "windowDurationMins": 300]]],
            "rateLimitResetCredits": ["availableCount": 1, "credits": []]
        ]))
        #expect(snapshot.resetCredits?.availableCount == 1)
        #expect(snapshot.fiveHour == nil)
        #expect(snapshot.weekly == nil)
    }

    @Test func legacyQuotaCheckpointDecodesWithoutResetCredits() throws {
        let legacy = Data("""
        {"fiveHour":null,"weekly":null,"updatedAt":0,"source":"appServer","isStale":false}
        """.utf8)
        let snapshot = try JSONDecoder().decode(QuotaSnapshot.self, from: legacy)
        #expect(snapshot.resetCredits == nil)
        #expect(snapshot.updatedAt == Date(timeIntervalSinceReferenceDate: 0))
        #expect(snapshot.source == .appServer)
        #expect(!snapshot.isStale)
    }
}
