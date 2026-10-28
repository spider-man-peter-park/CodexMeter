import Testing
@testable import CodexMeterCore

@Suite struct TokenUsageSeriesTests {
    @Test func selectsSevenCalendarDaysEndingAtLatestReportedDate() throws {
        let series = try #require(TokenUsageSeries(buckets: [
            .init(startDate: "2026-10-27", tokens: 22_000_000),
            .init(startDate: "2026-10-20", tokens: 1_300_000_000),
            .init(startDate: "2026-10-21", tokens: 100)
        ]))
        #expect(series.days.count == 7)
        #expect(series.startDay == "2026-10-21")
        #expect(series.endDay == "2026-10-27")
        #expect(series.days.map(\.index) == Array(0...6))
        #expect(series.days.first?.tokens == 100)
        #expect(series.days.last?.tokens == 22_000_000)
        #expect(series.maximumTokens == 22_000_000)
        #expect(series.days.last?.shortLabel == "10/27")
    }

    @Test func keepsMissingDaysSeparateFromZeroAndBreaksTheLine() throws {
        let series = try #require(TokenUsageSeries(buckets: [
            .init(startDate: "2025-12-31", tokens: 0),
            .init(startDate: "2026-01-02", tokens: 1_200),
            .init(startDate: "2026-01-03", tokens: 22_000_000)
        ]))
        #expect(series.startDay == "2025-12-28")
        #expect(series.days[3].tokens == 0)
        #expect(series.days[4].day == "2026-01-01")
        #expect(series.days[4].tokens == nil)
        #expect(series.days[3].segment != series.days[5].segment)
        #expect(series.days[5].segment == series.days[6].segment)
        #expect(series.hasMissingDays)
    }

    @Test func includesLeapDayWithoutRelabelingServerDates() throws {
        let series = try #require(TokenUsageSeries(buckets: [.init(startDate: "2024-03-02", tokens: 7)]))
        #expect(series.days.map(\.day) == ["2024-02-25", "2024-02-26", "2024-02-27", "2024-02-28",
                                           "2024-02-29", "2024-03-01", "2024-03-02"])
    }

    @Test func rejectsConflictingCountersWithoutSummingOrInventingUsage() throws {
        let series = try #require(TokenUsageSeries(buckets: [
            .init(startDate: "2026-10-25", tokens: 10), .init(startDate: "2026-10-25", tokens: 10),
            .init(startDate: "2026-10-26", tokens: 10), .init(startDate: "2026-10-26", tokens: 20),
            .init(startDate: "2026-10-27", tokens: -1)
        ]))
        #expect(series.days[4].tokens == 10)
        #expect(series.days[5].tokens == nil)
        #expect(series.days[6].tokens == nil)
        #expect(TokenUsageSeries(buckets: []) == nil)
        #expect(TokenUsageSeries(buckets: [.init(startDate: "2026-02-29", tokens: 1)]) == nil)
    }

    @Test func supportsAllZeroDataAndLargeCountersWithoutAggregationOverflow() throws {
        let zero = try #require(TokenUsageSeries(buckets: (21...27).map {
            .init(startDate: "2026-10-\($0)", tokens: 0)
        }))
        #expect(!zero.hasMissingDays)
        #expect(zero.maximumTokens == 0)
        let large = try #require(TokenUsageSeries(buckets: [.init(startDate: "2026-10-27", tokens: Int.max)]))
        #expect(large.maximumTokens == Int.max)
    }
}
