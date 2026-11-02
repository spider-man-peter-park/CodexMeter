import AppKit
import Foundation
import Testing
@testable import CodexMeterApp

@MainActor struct AppAppearanceTests {
    private func preferences() throws -> (String, UserDefaults) {
        let suite = "io.github.codexmeter.appearance-tests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("/private/tmp/" + suite, forKey: "codexHome")
        return (suite, defaults)
    }

    @Test func missingAndUnknownAppearanceFollowSystemWithoutOverwritingPreferences() throws {
        let (suite, defaults) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(AppModel(defaults: defaults, notificationCenter: TestReminderCenter()).appearance == .system)
        #expect(defaults.object(forKey: "appAppearance") == nil)
        defaults.set("future-theme", forKey: "appAppearance")
        #expect(AppModel(defaults: defaults, notificationCenter: TestReminderCenter()).appearance == .system)
        #expect(defaults.string(forKey: "appAppearance") == "future-theme")
    }

    @Test func appearanceChangesPersistAndLeaveDisplayAndRefreshPreferencesIntact() throws {
        let (suite, defaults) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        let display = model.options, refresh = model.refreshOptions, layout = model.detailLayout
        var changes = 0
        model.appearanceChanged = { changes += 1 }
        for appearance in [AppAppearance.dark, .light, .system] {
            model.appearance = appearance
            let restarted = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
            #expect(restarted.appearance == appearance)
            #expect(restarted.options == display)
            #expect(restarted.refreshOptions == refresh)
            #expect(restarted.detailLayout == layout)
        }
        #expect(changes == 3)
    }

    @Test func nativeAppearanceAllowsSystemInheritanceAndExplicitLightAndDark() {
        #expect(AppAppearance.system.nativeAppearance == nil)
        #expect(AppAppearance.light.nativeAppearance?.name == .aqua)
        #expect(AppAppearance.dark.nativeAppearance?.name == .darkAqua)
    }
}
