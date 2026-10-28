import Foundation
import Testing
@testable import CodexMeterCore

struct RefreshOptionsTests {
    @Test func defaultsRetainLowFrequencyNetworkReads() {
        let options = RefreshOptions()
        #expect(options.quotaInterval == 180)
        #expect(options.logInterval == 2)
        #expect(options.displayInterval == 60)
        #expect(options.accountInterval == 900)
    }

    @Test func chosenIntervalsAreIndependent() {
        let options = RefreshOptions(quotaSeconds: 600, logSeconds: 5, displaySeconds: 15, accountSeconds: 1800)
        #expect(options.quotaInterval == 600)
        #expect(options.logInterval == 5)
        #expect(options.displayInterval == 15)
        #expect(options.accountInterval == 1800)
    }

    @Test func corruptedPreferencesCannotCauseHighFrequencyNetworkPolling() {
        let options = RefreshOptions(quotaSeconds: -1, logSeconds: .nan, displaySeconds: 0, accountSeconds: 1)
        #expect(options.quotaInterval == 60)
        #expect(options.accountInterval == 300)
        #expect(options.logInterval == 2)
        #expect(options.displayInterval == 5)
        #expect(RefreshOptions(logSeconds: .infinity).logInterval == 2)
        #expect(RefreshOptions(quotaSeconds: Int.max, logSeconds: 100, displaySeconds: Int.max, accountSeconds: Int.max).quotaInterval == 3600)
    }

    @Test func intervalPreferencesRoundTripAndMissingFieldsUseDefaults() throws {
        let options = RefreshOptions(quotaSeconds: 300, logSeconds: 10, displaySeconds: 30, accountSeconds: 3600)
        #expect(try JSONDecoder().decode(RefreshOptions.self, from: JSONEncoder().encode(options)) == options)
        let legacy = try JSONDecoder().decode(RefreshOptions.self, from: Data("{}".utf8))
        #expect(legacy == RefreshOptions())
    }
}
