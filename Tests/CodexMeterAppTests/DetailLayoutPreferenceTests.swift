import Foundation
import Testing
@testable import CodexMeterApp
@testable import CodexMeterCore

@MainActor struct DetailLayoutPreferenceTests {
    @Test func layoutChangesPersistWithoutChangingMenuBarOrRefreshPreferences() throws {
        let suite = "io.github.codexmeter.layout-tests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("/private/tmp/" + suite, forKey: "codexHome")
        let model = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        let menuBar = model.options, refresh = model.refreshOptions
        model.detailLayout.move(.account, by: -1)
        model.detailLayout.move(.account, by: -1)
        model.detailLayout.setVisible(false, for: .quota)
        model.detailLayout.setVisible(false, for: .settings)
        let restarted = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        #expect(restarted.detailLayout.order == [.quota, .account, .today, .speed, .settings])
        #expect(restarted.detailLayout.visibleSections == [.today, .speed])
        #expect(restarted.options == menuBar)
        #expect(restarted.refreshOptions == refresh)
        restarted.detailLayout = AppDefaults.detailLayout
        let reset = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        #expect(reset.detailLayout == AppDefaults.detailLayout)
        #expect(reset.options == menuBar)
        #expect(reset.refreshOptions == refresh)
    }

    @Test func invalidStoredJSONUsesTheReleaseDefaultLayout() throws {
        let suite = "io.github.codexmeter.layout-tests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("/private/tmp/" + suite, forKey: "codexHome")
        defaults.set(Data("invalid JSON".utf8), forKey: "detailLayout")
        let model = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        #expect(model.detailLayout == AppDefaults.detailLayout)
        #expect(model.detailLayout.visibleSections == [.quota, .today, .speed])
    }
}
