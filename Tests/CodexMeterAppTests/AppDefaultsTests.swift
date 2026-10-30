import Foundation
import Testing
@testable import CodexMeterApp
@testable import CodexMeterCore

@MainActor struct AppDefaultsTests {
    private func preferences() throws -> (String, UserDefaults) {
        let suite = "io.github.codexmeter.defaults-tests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("/private/tmp/" + suite, forKey: "codexHome")
        return (suite, defaults)
    }

    @Test func freshInstallMatchesCapturedSettingsAcrossRepeatedInitialization() async throws {
        let (suite, defaults) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let capturedDisplay = Data(#"{"customQuotaLabel":"","countdownSeparator":"dot","countdownStyle":"compact","fontWeight":"medium","showWeekly":true,"showFiveHour":true,"fullMode":true,"showTPS":true,"showTPSLabel":true,"showCountdown":true,"fontDesign":"system","itemStyle":"activeCapsule","quotaLabelStyle":"gpt","spacing":"compact","colorStyle":"adaptive","showPercentSign":true,"tpsDecimals":0,"fontSize":12,"tpsLayout":"stacked"}"#.utf8)
        let capturedReminders = Data(#"{"creditLeadTime":"threeDays","creditExpiryEnabled":true,"weeklyEnabled":true,"fiveHourEnabled":true,"lowQuotaEnabled":true,"recoveryEnabled":true,"thresholds":"ten"}"#.utf8)
        let center = TestReminderCenter(.notDetermined)
        for initialization in 0..<2 {
            let model = AppModel(defaults: defaults, notificationCenter: center)
            #expect(model.initialLoginPreference == (initialization == 0 ? true : nil))
            #expect(model.options == (try JSONDecoder().decode(DisplayOptions.self, from: capturedDisplay)))
            #expect(model.refreshOptions == RefreshOptions(quotaSeconds: 180, logSeconds: 2, displaySeconds: 60, accountSeconds: 900))
            #expect(model.detailLayout.order == [.quota, .today, .speed, .account, .settings])
            #expect(model.detailLayout.visibleSections == [.quota, .today, .speed])
            #expect(model.reminders.options == (try JSONDecoder().decode(ReminderOptions.self, from: capturedReminders)))
            #expect(model.language == .system)
            #expect(model.autoRefresh)
            #expect(!AppUpdates(defaults: defaults).automaticallyChecks)
            model.reminders.start()
            try await Task.sleep(for: .milliseconds(80))
            #expect(await center.prompts == 0)
            model.reminders.stop()
        }
        #expect(defaults.data(forKey: "displayOptions") == nil)
        #expect(defaults.data(forKey: "reminderOptions") == nil)
    }

    @Test func savedPreferencesOverrideReleaseDefaultsIncludingDisabledReminders() throws {
        let (suite, defaults) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let display = DisplayOptions(showTPS: false, quotaLabelStyle: .custom, fontSize: 15, customQuotaLabel: "Mine")
        let layout = DetailLayout(order: [.settings, .account], hidden: [.today])
        let refresh = RefreshOptions(quotaSeconds: 600, logSeconds: 10, displaySeconds: 30, accountSeconds: 1800)
        defaults.set(try JSONEncoder().encode(display), forKey: "displayOptions")
        defaults.set(try JSONEncoder().encode(layout), forKey: "detailLayout")
        defaults.set(try JSONEncoder().encode(refresh), forKey: "refreshOptions")
        defaults.set(try JSONEncoder().encode(ReminderOptions()), forKey: "reminderOptions")
        defaults.set("en", forKey: "appLanguage")
        defaults.set(false, forKey: "autoRefresh")
        defaults.set(true, forKey: "automaticallyCheckForUpdates")
        let model = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        #expect(model.initialLoginPreference == nil)
        #expect(model.options == display)
        #expect(model.detailLayout == layout)
        #expect(model.refreshOptions == refresh)
        #expect(!model.reminders.options.anyEnabled)
        #expect(model.language == .english)
        #expect(!model.autoRefresh)
        #expect(AppUpdates(defaults: defaults).automaticallyChecks)
    }

    @Test func legacyDisplayMigrationStillRunsWithoutReplacingSavedVisibility() throws {
        let (suite, defaults) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "showTPS")
        defaults.set("window", forKey: "quotaLabelStyle")
        let migrated = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        #expect(migrated.initialLoginPreference == nil)
        #expect(!migrated.options.showTPS)
        #expect(migrated.options.quotaLabelStyle == .ai)
        #expect(defaults.integer(forKey: "displaySchemaVersion") == 2)
    }
}
