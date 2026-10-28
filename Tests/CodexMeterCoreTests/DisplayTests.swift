import Foundation
import Testing
@testable import CodexMeterCore

@Suite struct DisplayTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func quota(source: QuotaSource = .appServer) -> QuotaSnapshot {
        QuotaSnapshot(fiveHour: QuotaWindow(usedPercent: 18, windowDurationMins: 300,
                                           resetsAt: now.addingTimeInterval(134 * 60)),
                      weekly: QuotaWindow(usedPercent: 39, windowDurationMins: 10_080,
                                         resetsAt: now.addingTimeInterval((4 * 24 + 8) * 3600)),
                      updatedAt: now, source: source)
    }

    @Test func testNoDataUsesDashesInsteadOfZero() {
        #expect(MenuBarFormatter.title(quota: nil, sample: nil, options: DisplayOptions(), now: now) == "5h — | 7d — | — TPS")
    }

    @Test func testCompactModeOmitsCountdown() {
        #expect(MenuBarFormatter.title(quota: quota(), sample: nil, options: DisplayOptions(), now: now) == "5h 82% | 7d 61% | — TPS")
    }

    @Test func testFullModeShowsLocalCountdowns() {
        #expect(MenuBarFormatter.title(quota: quota(), sample: nil,
                                              options: DisplayOptions(fullMode: true), now: now) == "5h 82% 2h14m | 7d 61% 4d8h | — TPS")
    }

    @Test func testWindowVisibilityAndCountdownAreIndependent() {
        let options = DisplayOptions(fullMode: true, showFiveHour: false, showCountdown: false, showTPS: false)
        #expect(MenuBarFormatter.title(quota: quota(), sample: nil, options: options, now: now) == "7d 61%")
    }

    @Test func testMissingWindowIsNAOnlyAfterValidSnapshot() {
        let weekly = QuotaSnapshot(fiveHour: nil, weekly: quota().weekly, updatedAt: now, source: .appServer)
        #expect(MenuBarFormatter.title(quota: weekly, sample: nil, options: DisplayOptions(), now: now) == "5h N/A | 7d 61% | — TPS")
    }

    @Test func testCacheAndFailedRefreshHaveVisibleMarker() {
        #expect(MenuBarFormatter.title(quota: quota(source: .logCache), sample: nil,
                                             options: DisplayOptions(), now: now).hasSuffix(" *"))
        #expect(MenuBarFormatter.title(quota: quota(), sample: nil,
                                             options: DisplayOptions(), now: now, stale: true).hasSuffix(" *"))
    }

    @Test func testCompletedTPSFormatsWithoutAddingReasoningTwice() {
        let sample = TPSSample(id: "response", model: "test-model", outputTokens: 734,
                               reasoningTokens: 300, elapsedSeconds: 10, completedAt: now)
        #expect(MenuBarFormatter.title(quota: nil, sample: sample,
                                              options: DisplayOptions(showFiveHour: false, showWeekly: false), now: now) == "73 TPS")
    }

    @Test func testAllHiddenKeepsClickableAppIdentity() {
        let options = DisplayOptions(showFiveHour: false, showWeekly: false, showTPS: false)
        #expect(MenuBarFormatter.title(quota: nil, sample: nil, options: options, now: now) == "CodexMeter")
    }

    @Test func testResetCountdownHandlesPastMissingAndMinuteRounding() {
        #expect(MenuBarFormatter.countdown(until: nil, now: now) == "—")
        #expect(MenuBarFormatter.countdown(until: now.addingTimeInterval(-300), now: now) == "now")
        #expect(MenuBarFormatter.countdown(until: now.addingTimeInterval(1), now: now) == "1m")
    }
}
