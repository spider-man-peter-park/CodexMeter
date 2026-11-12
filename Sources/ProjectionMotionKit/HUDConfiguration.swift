import Foundation

public enum HUDModule: String, CaseIterable, Codable, Sendable, Identifiable {
    case system, performance, ai, network, activity, controls
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .ai: return "AI"
        default: return rawValue.capitalized
        }
    }
}

public enum HUDDensity: String, CaseIterable, Codable, Sendable, Identifiable {
    case compact, standard, expanded
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public struct HUDConfiguration: Equatable, Codable, Sendable {
    public var enabledModules = Set(HUDModule.allCases)
    public var disabledModules: Set<HUDModule> = []
    public var density: HUDDensity = .standard
    public var coreDiameter = 280.0
    public var moduleScale = 1.0
    public var spacing = 24.0
    public var layoutVariant = 0
    public var hue = 0.51
    public var glassOpacity = 0.65
    public var borderBrightness = 0.65
    public var glow = 0.4
    public var connectorIntensity = 0.5
    public var decorationDensity = 0.5
    public var textScale = 1.0
    public var clockwiseSpeed = 2.0
    public var counterclockwiseSpeed = -1.0
    public var scanSpeed = 18.0
    public var feedbackDuration = 0.32
    public var feedbackDamping = 1.0
    public var pulseAmplitude = 0.12
    public var exitDelay = 0.55
    public var transitGrace = 1.2
    public var decorativeMotion = true

    public init() {}

    public var sanitized: Self {
        var p = self
        func clamp(_ value: Double, _ bounds: ClosedRange<Double>, _ fallback: Double) -> Double {
            value.isFinite ? min(bounds.upperBound, max(bounds.lowerBound, value)) : fallback
        }
        p.coreDiameter = clamp(coreDiameter, 240...340, 280)
        p.moduleScale = clamp(moduleScale, 0.8...1.2, 1)
        p.spacing = clamp(spacing, 12...48, 24)
        p.layoutVariant = min(2, max(0, layoutVariant))
        p.hue = clamp(hue, 0...1, 0.51)
        p.glassOpacity = clamp(glassOpacity, 0.25...0.95, 0.65)
        p.borderBrightness = clamp(borderBrightness, 0.1...1, 0.65)
        p.glow = clamp(glow, 0...1, 0.4)
        p.connectorIntensity = clamp(connectorIntensity, 0...1, 0.5)
        p.decorationDensity = clamp(decorationDensity, 0...1, 0.5)
        p.textScale = clamp(textScale, 0.9...1.3, 1)
        p.clockwiseSpeed = clamp(clockwiseSpeed, 0...8, 2)
        p.counterclockwiseSpeed = clamp(counterclockwiseSpeed, -8...0, -1)
        p.scanSpeed = clamp(scanSpeed, 0...60, 18)
        p.feedbackDuration = clamp(feedbackDuration, 0.15...0.5, 0.32)
        p.feedbackDamping = clamp(feedbackDamping, 0.8...1.2, 1)
        p.pulseAmplitude = clamp(pulseAmplitude, 0...0.3, 0.12)
        p.exitDelay = clamp(exitDelay, 0.15...1.5, 0.55)
        p.transitGrace = clamp(transitGrace, 0.4...2.5, 1.2)
        return p
    }
}
