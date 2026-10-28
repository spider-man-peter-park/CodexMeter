import Testing
@testable import CodexMeterCore

@Suite struct TokenCountFormatterTests {
    @Test(arguments: [
        (0, "0"), (999, "999"), (1_000, "1K"), (1_250, "1.3K"),
        (22_000_000, "22M"), (1_300_000_000, "1.3B"), (1_250_000_000_000, "1.3T"),
        (999_949, "999.9K"), (999_950, "1M"),
        (999_950_000, "1B"), (999_950_000_000, "1T"), (Int.max, "9223372T")
    ])
    func abbreviatesWithDecimalUnitsAndPromotesRoundedBoundaries(_ example: (Int, String)) {
        #expect(TokenCountFormatter.compact(example.0) == example.1)
    }

    @Test func unavailableCountsStayDistinctFromKnownZero() {
        #expect(TokenCountFormatter.compact(nil) == "—")
        #expect(TokenCountFormatter.compact(-1) == "—")
        #expect(TokenCountFormatter.compact(0) == "0")
    }
}
