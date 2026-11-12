import OrbMotionKit

enum ApprovedOrbParameters {
    static var value: OrbParameters {
        // Preserve the user's accepted live tuning when either playground is relaunched.
        var p = OrbParameters()
        p.diameter = 70
        p.coreRatio = 0.37
        p.ringWidth = 1.79
        p.tickCount = 48
        p.hue = 0.51
        p.glowIntensity = 0.98
        p.haloRadius = 13
        p.glassOpacity = 0.25
        p.outerSpeed = -40
        p.innerSpeed = 40
        p.breathPeriod = 4.8
        p.breathAmplitude = 0.09
        p.scanSpeed = 42
        p.chargeDuration = 0.72
        p.releaseDuration = 0.67
        p.curve = .smooth
        return p
    }
}
