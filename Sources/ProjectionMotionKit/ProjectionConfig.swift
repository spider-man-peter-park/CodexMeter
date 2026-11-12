import Foundation

public enum ProjectionEdge: String, CaseIterable, Codable, Sendable {
    case left, right
    public var title: String { rawValue.capitalized }
}

public struct ProjectionConfig: Equatable, Codable, Sendable {
    public var edge: ProjectionEdge = .left
    public var verticalPosition: Double = 0.5
    public var beamLength: Double = 1
    public var beamWidth: Double = 80
    public var divergence: Double = 7
    public var brightness: Double = 0.72
    public var edgeGlow: Double = 0.55
    public var particleCount: Int = 12
    public var particleSpeed: Double = 0.8
    public var scanVisibility: Double = 0.35
    public var beamLayers: Int = 3
    public var mainRadius: Double = 110
    public var ringCount: Int = 3
    public var tickCount: Int = 72
    public var scanSpeed: Double = 18
    public var rotationSpeed: Double = 5
    public var cardCount: Int = 4
    public var connectorLength: Double = 70
    public var haloIntensity: Double = 0.5
    public var hudScale: Double = 1
    public var openDuration: Double = 1.4
    public var closeDuration: Double = 1.25

    public init() {}

    public var sanitized: Self {
        var p = self
        func clamp(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        p.verticalPosition = clamp(verticalPosition, 0.1...0.9, 0.5)
        p.beamLength = clamp(beamLength, 0.4...1, 1)
        p.beamWidth = clamp(beamWidth, 20...180, 80)
        p.divergence = clamp(divergence, 0...16, 7)
        p.brightness = clamp(brightness, 0.1...1.2, 0.72)
        p.edgeGlow = clamp(edgeGlow, 0...1, 0.55)
        p.particleCount = min(24, max(0, particleCount))
        p.particleSpeed = clamp(particleSpeed, 0.1...2, 0.8)
        p.scanVisibility = clamp(scanVisibility, 0...1, 0.35)
        p.beamLayers = min(5, max(1, beamLayers))
        p.mainRadius = clamp(mainRadius, 70...160, 110)
        p.ringCount = min(4, max(0, ringCount))
        p.tickCount = min(120, max(24, tickCount))
        p.scanSpeed = clamp(scanSpeed, 0...60, 18)
        p.rotationSpeed = clamp(rotationSpeed, -16...16, 5)
        p.cardCount = min(4, max(0, cardCount))
        p.connectorLength = clamp(connectorLength, 24...120, 70)
        p.haloIntensity = clamp(haloIntensity, 0...1, 0.5)
        p.hudScale = clamp(hudScale, 0.6...1.4, 1)
        p.openDuration = clamp(openDuration, 0.8...3, 1.4)
        p.closeDuration = clamp(closeDuration, 0.8...3, 1.25)
        return p
    }
}

public struct ProjectionSample: Equatable, Sendable {
    public let progress: Double
    public var orbActivation: Double { stage(0, 0.15) }
    public var beamExtension: Double { stage(0.15, 0.35) }
    public var energyPoint: Double { stage(0.35, 0.45) }
    public var mainRing: Double { stage(0.45, 0.65) }
    public var peripheral: Double { stage(0.65, 0.85) }
    public var steady: Double { stage(0.85, 1) }
    public var phaseTitle: String {
        switch progress {
        case ..<0.15: return "A · Orb activation"
        case ..<0.35: return "B · Beam launch"
        case ..<0.45: return "C · Focal point"
        case ..<0.65: return "D · Core construction"
        case ..<0.85: return "E · Peripheral structures"
        default: return "F · Steady projection"
        }
    }
    public init(progress: Double) {
        self.progress = progress.isFinite ? min(1, max(0, progress)) : 0
    }
    public func stage(_ lower: Double, _ upper: Double) -> Double {
        let x = min(1, max(0, (progress - lower) / (upper - lower)))
        return x * x * x * (x * (x * 6 - 15) + 10)
    }
    public static func particlePosition(index: Int, progress: Double, flowTime: Double, speed: Double) -> Double {
        let phase = Double(index) * 0.61803398875 + progress * 2 + flowTime * speed
        return phase - floor(phase)
    }
}
