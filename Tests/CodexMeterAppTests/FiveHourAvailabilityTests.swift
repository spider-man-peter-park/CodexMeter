import Foundation
import Testing
@testable import CodexMeterApp
@testable import CodexMeterCore

@MainActor struct FiveHourAvailabilityTests {
    private func preferences() throws -> (String, UserDefaults) {
        let suite = "io.github.codexmeter.five-hour-tests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("/private/tmp/" + suite, forKey: "codexHome")
        return (suite, defaults)
    }

    private func quota(fiveHour: Bool = false, source: QuotaSource = .appServer,
                       stale: Bool = false) -> QuotaSnapshot {
        QuotaSnapshot(fiveHour: fiveHour ? QuotaWindow(usedPercent: 50, windowDurationMins: 300, resetsAt: nil) : nil,
            weekly: QuotaWindow(usedPercent: 25, windowDurationMins: 10080, resetsAt: nil),
            updatedAt: Date(), source: source, isStale: stale)
    }

    @Test func weeklyOnlyQuotaHidesTheMenuItemDisablesBothOptionsAndPersistsAcrossRestart() async throws {
        let (suite, defaults) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = TestReminderCenter(.notDetermined)
        let model = AppModel(defaults: defaults, notificationCenter: center)
        var changed = 0
        model.changed = { changed += 1 }
        model.quota = quota()
        #expect(model.fiveHourAvailable == false)
        #expect(!model.options.showFiveHour)
        #expect(!model.reminders.options.fiveHourEnabled)
        #expect(model.options.showWeekly && model.options.showTPS)
        #expect(model.reminders.options.weeklyEnabled && model.reminders.options.lowQuotaEnabled)
        #expect(model.reminders.options.recoveryEnabled && model.reminders.options.creditExpiryEnabled)
        #expect(changed > 0)
        let items = MenuBarFormatter.items(quota: model.quota, sample: nil, options: model.options)
        #expect(items.map(\.metric) == [.weekly, .tps, .todayTokens])
        #expect(await center.prompts == 0)
        model.options.showFiveHour = true
        var attempted = model.reminders.options
        attempted.fiveHourEnabled = true
        model.reminders.setOptions(attempted)
        #expect(!model.options.showFiveHour)
        #expect(!model.reminders.options.fiveHourEnabled)
        let restarted = AppModel(defaults: defaults, notificationCenter: center)
        #expect(restarted.fiveHourAvailable == false)
        #expect(!restarted.options.showFiveHour)
        #expect(!restarted.reminders.options.fiveHourEnabled)
    }

    @Test func unknownFailedStaleAndLogReadsDoNotDisableSupportedOrUnknownOptions() throws {
        let (suite, defaults) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        let incomplete = QuotaSnapshot(fiveHour: nil, weekly: nil, updatedAt: Date(), source: .appServer,
                                      resetCredits: ResetCreditSummary(availableCount: 0))
        for snapshot in [nil, quota(source: .logCache), quota(stale: true), incomplete] {
            model.quota = snapshot
            #expect(model.fiveHourAvailable == nil)
            #expect(model.options.showFiveHour && model.reminders.options.fiveHourEnabled)
        }
        model.quota = quota(fiveHour: true)
        for snapshot in [nil, quota(source: .logCache), quota(stale: true), incomplete] {
            model.quota = snapshot
            #expect(model.fiveHourAvailable == true)
            #expect(model.options.showFiveHour && model.reminders.options.fiveHourEnabled)
        }
    }

    @Test func aNewFiveHourWindowRestoresControlsWithoutReenablingTheOptions() throws {
        let (suite, defaults) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        model.quota = quota()
        model.quota = quota(fiveHour: true, source: .logCache)
        #expect(model.fiveHourAvailable == false)
        model.quota = quota(fiveHour: true)
        #expect(model.fiveHourAvailable == true)
        #expect(!model.options.showFiveHour && !model.reminders.options.fiveHourEnabled)
        model.options.showFiveHour = true
        var enabled = model.reminders.options
        enabled.fiveHourEnabled = true
        model.reminders.setOptions(enabled)
        #expect(model.options.showFiveHour && model.reminders.options.fiveHourEnabled)
    }

    @Test func preexistingCachedServerWindowsDisableOldEnabledPreferencesBeforeTheFirstRefresh() throws {
        let (suite, defaults) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        first.quota = quota()
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("fiveHourAvailable.") {
            defaults.removeObject(forKey: key)
        }
        defaults.set(try JSONEncoder().encode(AppDefaults.display), forKey: "displayOptions")
        defaults.set(try JSONEncoder().encode(AppDefaults.reminders), forKey: "reminderOptions")
        let upgraded = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        #expect(upgraded.quota?.isStale == true)
        #expect(upgraded.fiveHourAvailable == false)
        #expect(!upgraded.options.showFiveHour && !upgraded.reminders.options.fiveHourEnabled)
    }

    @Test func confirmedAvailabilitySurvivesLogCacheReplacementAndIsScopedToCodexHome() throws {
        let (suite, defaults) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        first.quota = quota()
        first.quota = quota(fiveHour: true, source: .logCache)
        let restarted = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        #expect(restarted.fiveHourAvailable == false)
        defaults.set("/private/tmp/another-" + suite, forKey: "codexHome")
        let differentHome = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        #expect(differentHome.fiveHourAvailable == nil)
    }

    @Test func successfulLiveRefreshAppliesAvailabilityAndFailuresPreserveIt() async throws {
        let (suite, defaults) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let weekly = quota()
        let model = AppModel(defaults: defaults, notificationCenter: TestReminderCenter(),
            readQuota: { _ in weekly }, readAccount: { _ in AccountInfoSnapshot() })
        model.refresh()
        for _ in 0..<100 where model.refreshing { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.fiveHourAvailable == false)
        #expect(!model.options.showFiveHour && !model.reminders.options.fiveHourEnabled)
        model.stop()
        let failing = AppModel(defaults: defaults, notificationCenter: TestReminderCenter(),
            readQuota: { _ in throw AppServerError.timeout }, readAccount: { _ in AccountInfoSnapshot() })
        failing.refresh()
        for _ in 0..<100 where failing.refreshing { try await Task.sleep(for: .milliseconds(10)) }
        #expect(failing.quotaWarning != nil)
        #expect(failing.fiveHourAvailable == false)
        #expect(!failing.options.showFiveHour && !failing.reminders.options.fiveHourEnabled)
        failing.stop()
    }
}
