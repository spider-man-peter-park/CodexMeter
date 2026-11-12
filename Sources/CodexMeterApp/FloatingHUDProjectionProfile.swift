import Foundation
import ProjectionMotionKit

struct FloatingHUDProjectionProfile: Codable, Equatable {
    var projection = ProjectionConfig()
    var hud = HUDConfiguration()
    var backdrop = ProjectionBackdropConfiguration()

    static func loadBundled() -> Self? {
        let bundle: Bundle
        if let url = Bundle.main.url(forResource: "CodexMeter_CodexMeterApp", withExtension: "bundle"),
           let packaged = Bundle(url: url) {
            bundle = packaged
        } else {
            #if SWIFT_PACKAGE
            bundle = .module
            #else
            bundle = .main
            #endif
        }
        guard let url = bundle.url(forResource: "ProjectionProfile", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let profile = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        return Self(projection: profile.projection.sanitized, hud: profile.hud.sanitized,
                    backdrop: profile.backdrop.sanitized)
    }
}
