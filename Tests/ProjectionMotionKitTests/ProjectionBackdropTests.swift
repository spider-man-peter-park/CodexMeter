import Foundation
import ProjectionMotionKit
import Testing

struct ProjectionBackdropTests {
    @Test func disablingOrMakingTheBackdropTransparentRemovesItAtEveryPlayhead() {
        var configuration = ProjectionBackdropConfiguration()
        configuration.opacity = 0.4
        #expect(configuration.opacity(at: 0) == 0)
        #expect(configuration.opacity(at: 1) == 0.4)
        #expect(configuration.opacity(at: 0.075) > 0 && configuration.opacity(at: 0.075) < 0.4)
        configuration.opacity = 0
        for progress in [0, 0.075, 0.42, 1.0] { #expect(configuration.opacity(at: progress) == 0) }
        configuration.opacity = 0.4
        configuration.isEnabled = false
        for progress in [0, 0.075, 0.42, 1.0] { #expect(configuration.opacity(at: progress) == 0) }
    }

    @Test func invalidStoredValuesRemainFiniteAndWithinTheControlRanges() throws {
        var configuration = ProjectionBackdropConfiguration()
        configuration.opacity = .nan
        configuration.tintOpacity = -2
        configuration.blurIntensity = .infinity
        let safe = configuration.sanitized
        #expect(safe.opacity == 1 && safe.tintOpacity == 0 && safe.blurIntensity == 1)
        let restored = try JSONDecoder().decode(ProjectionBackdropConfiguration.self,
            from: JSONEncoder().encode(safe))
        #expect(restored == safe)
    }
}
