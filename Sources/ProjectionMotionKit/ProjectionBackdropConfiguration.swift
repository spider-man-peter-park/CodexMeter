import Foundation

public struct ProjectionBackdropConfiguration: Equatable, Codable, Sendable {
    public var isEnabled = true
    public var opacity = 1.0
    public var tintOpacity = 0.48
    public var blurIntensity = 1.0

    public init() {}

    public var sanitized: Self {
        var value = self
        func clamp(_ number: Double, fallback: Double) -> Double {
            number.isFinite ? min(1, max(0, number)) : fallback
        }
        value.opacity = clamp(opacity, fallback: 1)
        value.tintOpacity = clamp(tintOpacity, fallback: 0.48)
        value.blurIntensity = clamp(blurIntensity, fallback: 1)
        return value
    }

    public func opacity(at progress: Double) -> Double {
        let value = sanitized
        return value.isEnabled ? value.opacity * ProjectionSample(progress: progress).orbActivation : 0
    }
}
