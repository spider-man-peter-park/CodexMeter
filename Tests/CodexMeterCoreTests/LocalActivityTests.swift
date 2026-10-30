import Foundation
import Testing
@testable import CodexMeterCore

@Suite struct LocalActivityTests {
    private let time = Date(timeIntervalSince1970: 1_793_188_800)
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    @Test func displayedTotalRejectsOtherDaysTimeZonesAndUnreadableOrIncompleteEmptyLogs() {
        var usage = LocalDayUsage(dayStart: calendar.startOfDay(for: time), timeZoneIdentifier: calendar.timeZone.identifier,
            updatedAt: time, hasDesktopLogs: true)
        #expect(usage.displayTotal(at: time, calendar: calendar) == 0)
        #expect(usage.displayTotal(at: time.addingTimeInterval(86_400), calendar: calendar) == nil)
        var otherZone = calendar
        otherZone.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        #expect(usage.displayTotal(at: time, calendar: otherZone) == nil)
        usage.hasDesktopLogs = false
        #expect(usage.displayTotal(at: time, calendar: calendar) == nil)
        usage.hasDesktopLogs = true
        usage.isPartial = true
        #expect(usage.displayTotal(at: time, calendar: calendar) == nil)
        usage.isPartial = false
        usage.logsAvailable = false
        #expect(usage.displayTotal(at: time, calendar: calendar) == nil)
        usage.responses = 1
        usage.input = 1_000
        usage.output = 200
        usage.cachedInput = 800
        usage.reasoningOutput = 100
        #expect(usage.displayTotal(at: time, calendar: calendar) == 1_200)
    }
    private func row(_ type: String, _ payload: [String: Any], at time: Date? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["type": type, "timestamp": (time ?? self.time).ISO8601Format(), "payload": payload])
    }
    private func meta(_ id: String = "main", extra: [String: Any] = [:]) throws -> Data {
        var payload: [String: Any] = ["id": id, "originator": "Codex Desktop", "cwd": "/synthetic/private/project"]
        payload.merge(extra) { _, new in new }
        return try row("session_meta", payload)
    }
    private func usage(input: Int = 1000, output: Int = 100) -> [String: Any] {
        ["input_tokens": input, "output_tokens": output, "cached_input_tokens": min(400, input),
         "reasoning_output_tokens": min(40, output), "total_tokens": input + output]
    }
    private func modern(_ id: String = "response", session: String = "main", at: Date? = nil,
                        input: Int = 1000, output: Int = 100, totals: [String: Any]? = nil) throws -> Data {
        var payload: [String: Any] = ["response_id": id, "thread_id": session, "usage": usage(input: input, output: output)]
        if let totals { payload["thread_token_usage"] = totals }
        return try row("token_usage_record", payload, at: at)
    }
    private func legacy(totals: [String: Any], at: Date? = nil) throws -> Data {
        try row("event_msg", ["type": "token_count", "info": ["last_token_usage": usage(), "total_token_usage": totals]], at: at)
    }
    private func feed(_ lines: [Data], parser: inout LocalUsageParser, ledger: inout LocalActivityLedger) {
        for line in lines {
            if let event = parser.consume(line, observedAt: time) { ledger.consume(event, now: time) }
            ledger.register(parser.session, origin: parser.origin)
        }
    }

    @Test func usageDoesNotRequireValidTPSAndSubsetsAreNotAddedTwice() throws {
        var parser = LocalUsageParser(); var ledger = LocalActivityLedger()
        try feed([meta(), modern()], parser: &parser, ledger: &ledger)
        let result = ledger.summary(now: time, calendar: calendar, backfilling: false, partial: false)
        #expect(result.total == 1100)
        #expect(result.input == 1000 && result.output == 100)
        #expect(result.cachedInput == 400 && result.reasoningOutput == 40)
        #expect(result.responses == 1)
        var tps = SessionParser()
        let metadataSample = tps.consume(try meta())
        let usageSample = tps.consume(try modern())
        #expect(metadataSample == nil && usageSample == nil)
    }

    @Test func modernAndLegacyDuplicatesMergeInEitherOrderWithoutCumulativeSummation() throws {
        for reversed in [false, true] {
            var parser = LocalUsageParser(); var ledger = LocalActivityLedger()
            let cumulative = usage(input: 20_000, output: 9000)
            let pair = try [modern(totals: cumulative), legacy(totals: cumulative)]
            feed([try meta()] + (reversed ? Array(pair.reversed()) : pair), parser: &parser, ledger: &ledger)
            let result = ledger.summary(now: time, calendar: calendar, backfilling: false, partial: false)
            #expect(result.total == 1100)
            #expect(result.responses == 1)
            #expect(!result.isPartial)
        }
    }

    @Test func distinctModernResponsesSurviveIdenticalCumulativeCounters() throws {
        var parser = LocalUsageParser(); var ledger = LocalActivityLedger()
        let totals = usage()
        try feed([meta(), modern("first", totals: totals), modern("second", totals: totals)], parser: &parser, ledger: &ledger)
        let result = ledger.summary(now: time, calendar: calendar, backfilling: false, partial: false)
        #expect(result.responses == 2)
        #expect(result.total == 2200)
    }

    @Test func legacyOnlyCountersDeduplicateRepeatedUpdates() throws {
        var parser = LocalUsageParser(); var ledger = LocalActivityLedger()
        try feed([meta(), legacy(totals: usage(input: 20_000)), legacy(totals: usage(input: 20_000)),
                  legacy(totals: usage(input: 21_000))], parser: &parser, ledger: &ledger)
        #expect(ledger.summary(now: time, calendar: calendar, backfilling: false, partial: false).total == 2200)
    }

    @Test func desktopChildrenCountWhenParentIsIdentifiedButCLIAndGuardianDoNot() throws {
        var ledger = LocalActivityLedger(); var child = LocalUsageParser()
        let source: [String: Any] = ["subagent": ["thread_spawn": ["parent_thread_id": "main"]]]
        try feed([meta("child", extra: ["source": source]), modern("child-response", session: "child")], parser: &child, ledger: &ledger)
        let unresolved = ledger.summary(now: time, calendar: calendar, backfilling: false, partial: false)
        #expect(unresolved.total == 0 && unresolved.isPartial)
        var main = LocalUsageParser()
        feed([try meta()], parser: &main, ledger: &ledger)
        #expect(ledger.summary(now: time, calendar: calendar, backfilling: false, partial: false).total == 1100)
        var cli = LocalUsageParser(); var guardian = LocalUsageParser()
        try feed([meta("cli", extra: ["originator": "codex_cli_rs", "source": "cli"]), modern("cli-response", session: "cli")], parser: &cli, ledger: &ledger)
        try feed([meta("review", extra: ["thread_source": "guardian_review"]), modern("review-response", session: "review")], parser: &guardian, ledger: &ledger)
        #expect(ledger.summary(now: time, calendar: calendar, backfilling: false, partial: false).total == 1100)
    }

    @Test func forkReplayAndCopiedMetadataCannotBecomeNewUsage() throws {
        var parser = LocalUsageParser(); var ledger = LocalActivityLedger()
        try feed([meta("fork", extra: ["forked_from_id": "main"]), meta("main"),
            modern("parent-response", session: "main"), legacy(totals: usage()),
            modern("own-response", session: "fork")], parser: &parser, ledger: &ledger)
        #expect(ledger.summary(now: time, calendar: calendar, backfilling: false, partial: false).responses == 1)
    }

    @Test func modernTimestampWinsWhenLegacyCopyFallsOnDifferentLocalDay() throws {
        var localCalendar = calendar; localCalendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let midnight = localCalendar.startOfDay(for: time)
        let modernTime = midnight.addingTimeInterval(-1)
        var parser = LocalUsageParser(); var ledger = LocalActivityLedger()
        try feed([meta(), legacy(totals: usage(), at: midnight.addingTimeInterval(1)), modern(at: modernTime, totals: usage())], parser: &parser, ledger: &ledger)
        let today = ledger.summary(now: time, calendar: localCalendar, backfilling: false, partial: false)
        let yesterday = ledger.summary(now: modernTime, calendar: localCalendar, backfilling: false, partial: false)
        #expect(today.total == 0)
        #expect(yesterday.total == 1100)
    }

    @Test func localMidnightAndDSTUseCalendarDaysAndPersistedEventsRebin() throws {
        var localCalendar = calendar; localCalendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let midnight = localCalendar.startOfDay(for: time)
        var parser = LocalUsageParser(); var ledger = LocalActivityLedger()
        try feed([meta(), modern("yesterday", at: midnight.addingTimeInterval(-1)),
                  modern("today", at: midnight.addingTimeInterval(1))], parser: &parser, ledger: &ledger)
        let restored = LocalActivityLedger(state: try JSONDecoder().decode(LocalActivityState.self, from: JSONEncoder().encode(ledger.state)))
        let current = restored.summary(now: time, calendar: localCalendar, backfilling: false, partial: false)
        #expect(current.total == 1100 && current.matches(time, calendar: localCalendar))
        #expect(!current.matches(midnight.addingTimeInterval(86400), calendar: localCalendar))
        var dstCalendar = calendar; dstCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let dst = try #require(ISO8601DateFormatter().date(from: "2026-11-01T12:00:00Z"))
        let start = dstCalendar.startOfDay(for: dst)
        let end = try #require(dstCalendar.date(byAdding: .day, value: 1, to: start))
        #expect(end.timeIntervalSince(start) == 25 * 3600)
    }

    @Test func malformedUsageIsSkippedAndUnknownSubsetsRemainUnavailable() throws {
        var parser = LocalUsageParser(); var ledger = LocalActivityLedger()
        let invalid = try row("token_usage_record", ["response_id": "bad", "thread_id": "main",
            "usage": ["input_tokens": true, "output_tokens": 10]])
        let noDetails = try row("token_usage_record", ["response_id": "minimal", "thread_id": "main",
            "usage": ["input_tokens": 1000, "output_tokens": 100]])
        feed([try meta(), invalid, noDetails], parser: &parser, ledger: &ledger)
        let result = ledger.summary(now: time, calendar: calendar, backfilling: false, partial: parser.unsupportedAt != nil)
        #expect(result.total == 1100 && result.isPartial)
        #expect(result.cachedInput == nil && result.reasoningOutput == nil)
    }

    @Test func checkpointContainsOnlyWhitelistedCountersAndOpaqueIdentityHashes() throws {
        var parser = LocalUsageParser(); var ledger = LocalActivityLedger()
        let content = try row("response_item", ["type": "message", "role": "assistant", "content": "synthetic-private-reply"])
        try feed([meta(), content, modern()], parser: &parser, ledger: &ledger)
        let text = String(decoding: try JSONEncoder().encode(ledger.state), as: UTF8.self)
        #expect(!text.contains("synthetic-private") && !text.contains("/synthetic/private/project"))
        #expect(!text.contains("main") && !text.contains("response:"))
    }

    @Test func futureDatedRecordsWaitForClockAndMalformedUsageIsVisibleAsPartial() throws {
        var parser = LocalUsageParser(); var ledger = LocalActivityLedger()
        try feed([meta(), modern(at: time.addingTimeInterval(600))], parser: &parser, ledger: &ledger)
        let before = ledger.summary(now: time, calendar: calendar, backfilling: false, partial: false)
        #expect(before.total == 0 && before.isPartial)
        let later = ledger.summary(now: time.addingTimeInterval(600), calendar: calendar, backfilling: false, partial: false)
        #expect(later.total == 1100)
        _ = parser.consume(Data("{\"type\":\"token_usage_record\",broken}".utf8), observedAt: time)
        #expect(parser.unsupportedAt != nil)
    }

    @Test func quotaOnlyTokenCountUpdatesAreNotMissingUsage() throws {
        var parser = LocalUsageParser(); var ledger = LocalActivityLedger()
        let quota = try row("event_msg", ["type": "token_count", "info": NSNull(), "rate_limits": ["used_percent": 10]])
        feed([try meta(), quota], parser: &parser, ledger: &ledger)
        #expect(parser.unsupportedAt == nil)
        #expect(ledger.summary(now: time, calendar: calendar, backfilling: false, partial: false).total == 0)
    }

    @Test func thirtyResponseHistoryIsSortedDeduplicatedAndBreaksOnModelChange() {
        var samples = (0..<40).map { index in
            TPSSample(id: "\(index)", model: index < 20 ? "model-a" : "model-b", outputTokens: index + 1,
                      reasoningTokens: 0, elapsedSeconds: 1, completedAt: time.addingTimeInterval(Double(index)))
        }
        samples.append(samples[30])
        samples.append(TPSSample(id: "invalid", model: nil, outputTokens: 1, reasoningTokens: 0, elapsedSeconds: 0, completedAt: time))
        let points = TPSHistory.points(Array(samples.reversed()))
        #expect(points.count == 30)
        #expect(points.first?.id == "10" && points.last?.id == "39")
        #expect(points[9].segment != points[10].segment)
        #expect(Set(points.map(\.id)).count == 30)
    }
}
