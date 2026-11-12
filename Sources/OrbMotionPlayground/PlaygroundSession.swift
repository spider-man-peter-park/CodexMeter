import Combine
import Foundation
import OrbMotionKit
import PlaygroundLocalization
import ProjectionMotionKit

enum PlaygroundMode: String, CaseIterable {
    case orb = "Orb"
    case projection = "Projection"
}

@MainActor
final class PlaygroundSession: ObservableObject {
    @Published var mode: PlaygroundMode
    @Published var language: PlaygroundLanguage {
        didSet {
            preferences?.set(language.rawValue, forKey: "playgroundLanguage")
            guard language != oldValue else { return }
            desktop.setLanguage(language)
        }
    }
    let orb = MotionController(parameters: ApprovedOrbParameters.value)
    let projection = ProjectionAnimationController(orbParameters: ApprovedOrbParameters.value)
    let desktop: ProjectionDesktopController
    private let preferences: UserDefaults?
    private var configurationSubscription: AnyCancellable?
    private var hudConfigurationSubscription: AnyCancellable?

    init(preferences: UserDefaults? = .standard, languageOverride: PlaygroundLanguage? = nil) {
        self.preferences = preferences
        mode = CommandLine.arguments.contains("--projection-playground") ? .projection : .orb
        language = languageOverride ?? PlaygroundLanguage.resolve(saved: preferences?.string(forKey: "playgroundLanguage"),
                                                                  preferredLanguages: Locale.preferredLanguages)
        if let data = preferences?.data(forKey: "playgroundProjectionConfig"),
           let saved = try? JSONDecoder().decode(ProjectionConfig.self, from: data) {
            projection.config = saved.sanitized
        } else {
            projection.config = Self.configurationBeforeLanguageUpgrade
        }
        if let data = preferences?.data(forKey: "playgroundHUDConfig"),
           let saved = try? JSONDecoder().decode(HUDConfiguration.self, from: data) {
            projection.hud.config = saved.sanitized
        }
        desktop = ProjectionDesktopController(controller: projection)
        desktop.setLanguage(language)
        configurationSubscription = projection.$config.removeDuplicates().sink { config in
            guard let data = try? JSONEncoder().encode(config.sanitized) else { return }
            preferences?.set(data, forKey: "playgroundProjectionConfig")
        }
        hudConfigurationSubscription = projection.hud.$config.removeDuplicates().sink { config in
            guard let data = try? JSONEncoder().encode(config.sanitized) else { return }
            preferences?.set(data, forKey: "playgroundHUDConfig")
        }
        if CommandLine.arguments.contains("--hud-demo") {
            projection.scrub(to: 1)
            projection.expand()
        }
    }

    private static var configurationBeforeLanguageUpgrade: ProjectionConfig {
        // Migrate the values read from the user's running preview before the language update.
        var p = ProjectionConfig()
        p.edge = .right
        p.verticalPosition = 0.1524739583333333
        p.beamWidth = 103
        p.divergence = 10
        p.brightness = 0.87
        p.edgeGlow = 1
        p.particleSpeed = 0.79
        p.scanVisibility = 0.6
        p.beamLayers = 1
        p.rotationSpeed = 0
        return p
    }
}
