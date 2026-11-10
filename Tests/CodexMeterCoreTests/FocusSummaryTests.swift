import Foundation
import Testing
@testable import CodexMeterCore

struct FocusSummaryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func quota(fiveHour: Double? = nil, weekly: Double? = nil, age: TimeInterval = 0,
                       source: QuotaSource = .appServer, stale: Bool = false) -> QuotaSnapshot {
        QuotaSnapshot(fiveHour: fiveHour.map {
            QuotaWindow(usedPercent: 100 - $0, windowDurationMins: 300, resetsAt: now.addingTimeInterval(600))
        }, weekly: weekly.map {
            QuotaWindow(usedPercent: 100 - $0, windowDurationMins: 10_080, resetsAt: now.addingTimeInterval(86_400))
        }, updatedAt: now.addingTimeInterval(-age), source: source, isStale: stale)
    }

    private func summary(_ quota: QuotaSnapshot?, warning: String? = nil, automatic: Bool = true,
                         interval: TimeInterval = 180) -> FocusSummary {
        FocusSummary(quota: quota, warning: warning, automaticRefresh: automatic, now: now,
            refreshInterval: interval)
    }

    @Test func selectsTheReportedWindowWithLessRemainingQuota() {
        let fiveHour = summary(quota(fiveHour: 20, weekly: 80))
        let weekly = summary(quota(fiveHour: 80, weekly: 20))
        #expect(fiveHour.limitingMetric == .fiveHour)
        #expect(fiveHour.window?.remainingPercent == 20)
        #expect(weekly.limitingMetric == .weekly)
        #expect(weekly.window?.remainingPercent == 20)
    }

    @Test func tiesAlwaysPreferTheFiveHourWindow() {
        for remaining in [0.0, 10, 50, 100] {
            #expect(summary(quota(fiveHour: remaining, weekly: remaining)).limitingMetric == .fiveHour)
        }
    }

    @Test func weeklyOnlyAccountsNeverInventAFiveHourWindow() {
        let value = summary(quota(weekly: 61))
        #expect(value.limitingMetric == .weekly)
        #expect(value.window?.windowDurationMins == 10_080)
        #expect(value.updatedAt == now)
        #expect(value.state == .ready)
    }

    @Test func missingQuotaAndCreditsOnlyResponsesAreUnavailable() {
        #expect(summary(nil).state == .unavailable)
        let creditsOnly = QuotaSnapshot(fiveHour: nil, weekly: nil, updatedAt: now, source: .appServer,
            resetCredits: ResetCreditSummary(availableCount: 2))
        let value = summary(creditsOnly)
        #expect(value.state == .unavailable)
        #expect(value.window == nil)
        #expect(value.limitingMetric == nil)
        #expect(summary(nil, automatic: false).state == .unavailable)
    }

    @Test func thresholdAndExhaustionReflectOnlyReportedPercentages() {
        for (remaining, expected) in [(11.0, FocusSummary.State.ready), (10, .low), (0.1, .low), (0, .exhausted)] {
            #expect(summary(quota(weekly: remaining)).state == expected)
        }
        #expect(MenuBarFormatter.focusItem(quota: quota(weekly: 0.1), warning: nil,
            autoRefresh: true, now: now).title == "7d <1%")
    }

    @Test func logCacheStaleFlagAndReadFailuresRemainExplicitlyCached() {
        #expect(summary(quota(weekly: 70, source: .logCache)).state == .cached)
        #expect(summary(quota(weekly: 70, stale: true)).state == .cached)
        let failed = summary(quota(weekly: 0), warning: "Live read failed")
        #expect(failed.state == .cached)
        #expect(failed.window?.remainingPercent == 0)
    }

    @Test func ageBudgetIncludesTheBoundaryButRejectsOlderAndFutureReadings() {
        #expect(summary(quota(weekly: 70, age: 360)).state == .ready)
        #expect(summary(quota(weekly: 70, age: 360.1)).state == .cached)
        #expect(summary(quota(weekly: 70, age: -1)).state == .cached)
        #expect(summary(quota(weekly: 70, age: 1_800), interval: 900).state == .ready)
        #expect(summary(quota(weekly: 70, age: 1_801), interval: 900).state == .cached)
    }

    @Test func invalidRefreshIntervalsUseTheDefaultFreshnessBudget() {
        for interval in [0.0, -1, .nan, .infinity, -.infinity] {
            #expect(summary(quota(weekly: 70, age: 361), interval: interval).state == .cached)
        }
    }

    @Test func pausingRetainsTheLastWindowWithoutClaimingFreshness() {
        let value = summary(quota(weekly: 40, age: 10_000, source: .logCache),
            warning: "No connection", automatic: false)
        #expect(value.state == .paused)
        #expect(value.window?.remainingPercent == 40)
        #expect(value.symbolName == "pause.circle")
    }

    @Test func malformedWindowsAreNotDisplayedAsReportedQuota() {
        for used in [Double.nan, .infinity, -.infinity] {
            let value = QuotaSnapshot(fiveHour: QuotaWindow(usedPercent: used, windowDurationMins: 300, resetsAt: nil),
                weekly: nil, updatedAt: now, source: .appServer)
            #expect(summary(value).state == .unavailable)
        }
        let mismatched = QuotaSnapshot(fiveHour: QuotaWindow(usedPercent: 20, windowDurationMins: 10_080, resetsAt: nil),
            weekly: nil, updatedAt: now, source: .appServer)
        #expect(summary(mismatched).state == .unavailable)
    }

    @Test func finiteExtremeCountersAreClampedBeforeFormatting() {
        #expect(summary(quota(weekly: 500)).window?.remainingPercent == 100)
        #expect(summary(quota(weekly: -500)).window?.remainingPercent == 0)
        #expect(MenuBarFormatter.focusItem(quota: quota(weekly: .greatestFiniteMagnitude), warning: nil,
            autoRefresh: true, now: now).title == "7d 100%")
    }

    @Test func elapsedResetDoesNotInventAQuotaRecovery() {
        let exhausted = QuotaSnapshot(fiveHour: nil,
            weekly: QuotaWindow(usedPercent: 100, windowDurationMins: 10_080, resetsAt: now.addingTimeInterval(-1)),
            updatedAt: now, source: .appServer)
        #expect(summary(exhausted).state == .exhausted)
    }

    @Test func focusIdentityIsStableWhenTheLimitingPeriodChanges() {
        let inputs: [QuotaSnapshot?] = [nil, quota(fiveHour: 20, weekly: 80), quota(fiveHour: 80, weekly: 20),
            quota(weekly: 100), quota(weekly: 0), quota(weekly: 50, source: .logCache)]
        let items = inputs.map {
            MenuBarFormatter.focusItem(quota: $0, warning: nil, autoRefresh: true, now: now)
        }
        #expect(Set(items.map(\.metric)) == [.focus])
        #expect(Array(items.map(\.title).prefix(3)) == ["Codex —", "5h 20%", "7d 20%"])
    }

    @Test func accessibilityDescribesThePeriodAndTheActualDataState() {
        L10n.$languageOverride.withValue(.english) {
            let paused = MenuBarFormatter.focusItem(quota: quota(weekly: 61), warning: nil,
                autoRefresh: false, now: now)
            #expect(paused.accessibilityLabel.contains("7-day quota"))
            #expect(paused.accessibilityLabel.contains("61 percent remaining"))
            #expect(paused.accessibilityLabel.contains("Refresh paused"))
            let cached = MenuBarFormatter.focusItem(quota: quota(weekly: 61, age: 361), warning: nil,
                autoRefresh: true, now: now)
            #expect(cached.accessibilityLabel.contains("Saved reading"))
            #expect(cached.symbolName != paused.symbolName)
        }
    }
}
