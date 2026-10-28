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
}
