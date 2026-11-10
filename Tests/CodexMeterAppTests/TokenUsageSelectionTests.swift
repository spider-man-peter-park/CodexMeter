import CodexMeterCore
import Testing
@testable import CodexMeterApp

@MainActor struct TokenUsageSelectionTests {
    private func series(endingAt day: String, tokens: Int = 100) throws -> TokenUsageSeries {
        try #require(TokenUsageSeries(buckets: [.init(startDate: day, tokens: tokens)]))
    }

    @Test func selectionFollowsTheDateWhenTheSevenDayWindowMoves() throws {
        let original = try series(endingAt: "2026-11-07")
        let selection = TokenUsageSelection()
        selection.position(in: original).wrappedValue = 4
        #expect(selection.selectedDay(in: original)?.day == "2026-11-05")

        let forward = try series(endingAt: "2026-11-08")
        #expect(selection.selectedDay(in: forward)?.day == "2026-11-05")
        #expect(selection.position(in: forward).wrappedValue == 3)
        let backward = try series(endingAt: "2026-11-06")
        #expect(selection.selectedDay(in: backward)?.day == "2026-11-05")
        #expect(selection.position(in: backward).wrappedValue == 5)
    }

    @Test func sameDateUsesTheRefreshedCounterAndStillDistinguishesMissingUsage() throws {
        let original = try series(endingAt: "2026-11-07")
        let selection = TokenUsageSelection()
        selection.position(in: original).wrappedValue = 6
        let refreshed = try series(endingAt: "2026-11-07", tokens: 250)
        #expect(selection.selectedDay(in: refreshed)?.day == "2026-11-07")
        #expect(selection.selectedDay(in: refreshed)?.tokens == 250)
        selection.position(in: refreshed).wrappedValue = 5
        #expect(selection.selectedDay(in: refreshed)?.day == "2026-11-06")
        #expect(selection.selectedDay(in: refreshed)?.tokens == nil)
    }

    @Test func removedDatesDoNotSelectAnotherDayInEitherDirection() throws {
        let original = try series(endingAt: "2026-11-07")
        let selection = TokenUsageSelection()
        selection.position(in: original).wrappedValue = 0
        let forward = try series(endingAt: "2026-11-08")
        #expect(selection.selectedDay(in: forward) == nil)
        #expect(selection.position(in: forward).wrappedValue == nil)
        selection.reconcile(with: forward)
        #expect(selection.selectedDay(in: original) == nil)
        #expect(selection.dayID == nil)

        selection.position(in: original).wrappedValue = 6
        let backward = try series(endingAt: "2026-11-06")
        #expect(selection.selectedDay(in: backward) == nil)
        #expect(selection.position(in: backward).wrappedValue == nil)
        selection.reconcile(with: backward)
        #expect(selection.selectedDay(in: original) == nil)
        #expect(selection.dayID == nil)
    }

    @Test func nilAndNonFiniteCoordinatesClearSelection() throws {
        let series = try series(endingAt: "2026-11-07")
        let selection = TokenUsageSelection()
        let binding = selection.position(in: series)
        for invalid in [Double.nan, .infinity, -.infinity] {
            binding.wrappedValue = 2
            binding.wrappedValue = invalid
            #expect(selection.selectedDay(in: series) == nil)
            #expect(binding.wrappedValue == nil)
        }
        binding.wrappedValue = 2
        binding.wrappedValue = nil
        #expect(selection.selectedDay(in: series) == nil)
    }

    @Test func finiteCoordinatesAreRoundedAndClampedBeforeIntegerConversion() throws {
        let series = try series(endingAt: "2026-11-07")
        let selection = TokenUsageSelection()
        let binding = selection.position(in: series)
        binding.wrappedValue = 2.6
        #expect(selection.selectedDay(in: series)?.index == 3)
        binding.wrappedValue = .greatestFiniteMagnitude
        #expect(selection.selectedDay(in: series)?.index == 6)
        binding.wrappedValue = -.greatestFiniteMagnitude
        #expect(selection.selectedDay(in: series)?.index == 0)
    }
}
