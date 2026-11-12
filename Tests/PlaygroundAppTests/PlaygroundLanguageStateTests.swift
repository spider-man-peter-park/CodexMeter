import Foundation
import PlaygroundLocalization
import ProjectionMotionKit
import Testing
@testable import OrbMotionPlayground

private final class MemoryPreferences: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]
    init() { super.init(suiteName: nil)! }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func object(forKey key: String) -> Any? { values[key] }
}

struct PlaygroundLanguageStateTests {
    @MainActor @Test func selectedLanguagePersistsWithoutChangingGlobalLanguagePreferences() {
        let preferences = MemoryPreferences()
        let first = PlaygroundSession(preferences: preferences, languageOverride: .english)
        first.language = .simplifiedChinese
        let reopened = PlaygroundSession(preferences: preferences)
        #expect(reopened.language == .simplifiedChinese)
        #expect(preferences.string(forKey: "playgroundLanguage") == "zh-Hans")
        #expect(preferences.object(forKey: "AppleLanguages") == nil)
    }

    @MainActor @Test func switchingLanguageKeepsParametersPlayheadAndControllerIdentity() {
        let session = PlaygroundSession(preferences: nil, languageOverride: .english)
        let orb = ObjectIdentifier(session.orb), projection = ObjectIdentifier(session.projection)
        session.projection.config.beamWidth = 137
        session.projection.config.edge = .right
        session.projection.scrub(to: 0.42)
        session.orb.scrub(to: 0.31)
        session.projection.hud.select(.performance)
        session.projection.hud.expandSelection()
        let config = session.projection.config
        let projected = session.projection.timeline, source = session.orb.timeline
        for language in [PlaygroundLanguage.simplifiedChinese, .english, .simplifiedChinese] {
            session.language = language
            #expect(ObjectIdentifier(session.orb) == orb && ObjectIdentifier(session.projection) == projection)
            #expect(session.projection.config == config && session.projection.timeline == projected)
            #expect(session.orb.timeline == source)
            #expect(session.projection.hud.selected == .performance && session.projection.hud.expanded)
            #expect(session.desktop.sourcePanel.title == language.text("Projection source orb"))
            #expect(session.desktop.projectionPanel.title == language.text("Holographic projection"))
        }
    }

    @MainActor @Test func hudSettingsPersistWithoutReplacingAcceptedProjectionTuning() {
        let preferences = MemoryPreferences()
        let first = PlaygroundSession(preferences: preferences)
        let accepted = first.projection.config
        first.projection.hud.config.density = .compact
        first.projection.hud.config.enabledModules.remove(.network)
        first.projection.hud.setDecorativeMotion(false)
        let reopened = PlaygroundSession(preferences: preferences)
        #expect(reopened.projection.hud.config == first.projection.hud.config)
        #expect(reopened.projection.config == accepted)
        #expect(preferences.object(forKey: "AppleLanguages") == nil)
    }

    @MainActor @Test func existingProjectionTuningMigratesAndLaterEditsAreRemembered() {
        let preferences = MemoryPreferences()
        let first = PlaygroundSession(preferences: preferences)
        #expect(first.projection.config.edge == .right && first.projection.config.beamWidth == 103)
        #expect(first.projection.config.verticalPosition == 0.1524739583333333)
        first.projection.config.mainRadius = 139
        first.language = .english
        let reopened = PlaygroundSession(preferences: preferences)
        #expect(reopened.projection.config == first.projection.config)
        #expect(reopened.language == .english)
    }
}
