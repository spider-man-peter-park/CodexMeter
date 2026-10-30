import Foundation
import Testing
@testable import CodexMeterCore

struct DetailLayoutTests {
    @Test func defaultLayoutKeepsTheSettingsSectionReachable() {
        let layout = DetailLayout()
        #expect(layout.order == [.quota, .today, .speed, .account, .settings])
        #expect(layout.visibleSections == layout.order)
    }

    @Test func savedUnknownAndDuplicateIDsKeepKnownOrderAndAppendMissingSections() throws {
        let data = Data(#"{"order":["future","account","account","today"],"hidden":["future","quota","quota"]}"#.utf8)
        let layout = try JSONDecoder().decode(DetailLayout.self, from: data)
        #expect(layout.order == [.account, .today, .quota, .speed, .settings])
        #expect(layout.hidden == [.quota])
        #expect(layout.visibleSections == [.account, .today, .speed, .settings])
    }

    @Test func malformedFieldsFallBackIndependently() throws {
        let decoder = JSONDecoder()
        let brokenOrder = try decoder.decode(DetailLayout.self, from: Data(#"{"order":12,"hidden":["account"]}"#.utf8))
        #expect(brokenOrder.order == DetailSection.allCases)
        #expect(brokenOrder.hidden == [.account])
        let brokenHidden = try decoder.decode(DetailLayout.self, from: Data(#"{"order":["speed"],"hidden":false}"#.utf8))
        #expect(brokenHidden.order == [.speed, .quota, .today, .account, .settings])
        #expect(brokenHidden.hidden.isEmpty)
        #expect(try decoder.decode(DetailLayout.self, from: Data("{}".utf8)) == DetailLayout())
    }

    @Test func hiddenSectionsKeepTheirPositionsThroughReorderingAndRestoringVisibility() {
        var layout = DetailLayout()
        layout.setVisible(false, for: .today)
        layout.move(.account, by: -1)
        #expect(layout.order == [.quota, .today, .account, .speed, .settings])
        #expect(layout.visibleSections == [.quota, .account, .speed, .settings])
        layout.setVisible(true, for: .today)
        #expect(layout.visibleSections == [.quota, .today, .account, .speed, .settings])
    }

    @Test func movesAtBoundariesAndInvalidStepsNeverLoseOrDuplicateASection() {
        var layout = DetailLayout()
        for (section, step) in [(DetailSection.quota, -1), (.settings, 1), (.today, 0), (.today, Int.max)] {
            #expect(!layout.canMove(section, by: step))
            layout.move(section, by: step)
        }
        #expect(layout == DetailLayout())
        layout.move(.quota, by: 1)
        #expect(layout.order == [.today, .quota, .speed, .account, .settings])
        #expect(Set(layout.order).count == DetailSection.allCases.count)
    }

    @Test func fullyHiddenLayoutRoundTripsWithLanguageIndependentIDs() throws {
        var layout = DetailLayout(order: [.settings, .account])
        for section in DetailSection.allCases { layout.setVisible(false, for: section) }
        let data = try L10n.$languageOverride.withValue(.simplifiedChinese) { try JSONEncoder().encode(layout) }
        let restored = try L10n.$languageOverride.withValue(.english) { try JSONDecoder().decode(DetailLayout.self, from: data) }
        #expect(restored == layout)
        #expect(restored.visibleSections.isEmpty)
        let fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: [String]])
        #expect(fields["order"] == ["settings", "account", "quota", "today", "speed"])
        #expect(fields["hidden"]?.count == DetailSection.allCases.count)
    }
}
