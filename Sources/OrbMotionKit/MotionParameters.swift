import Foundation

public enum MotionCurve: String, CaseIterable, Codable, Sendable {
    case smooth
    case linear
    case easeOut

    public var title: String {
        switch self {
        case .smooth: return "Smooth"
        case .linear: return "Linear"
        case .easeOut: return "Ease out"
        }
    }

    public func map(_ value: Double) -> Double {
        let t = value.isFinite ? min(1, max(0, value)) : 0
        switch self {
        case .smooth: return t * t * t * (t * (t * 6 - 15) + 10)
        case .linear: return t
        case .easeOut: return 1 - pow(1 - t, 3)
        }
    }

    func integral(upTo value: Double) -> Double {
        let t = min(1, max(0, value))
        switch self {
        case .smooth: return pow(t, 4) * (2.5 - 3 * t + t * t)
        case .linear: return t * t / 2
        case .easeOut: return 1.5 * t * t - pow(t, 3) + pow(t, 4) / 4
        }
    }
}

public struct OrbParameters: Equatable, Codable, Sendable {
    public var diameter: Double = 60
    public var coreRatio: Double = 0.31
    public var ringWidth: Double = 1.1
    public var tickCount: Int = 48
    public var hue: Double = 0.53
    public var glowIntensity: Double = 0.65
    public var haloRadius: Double = 12
    public var glassOpacity: Double = 0.78
    public var outerSpeed: Double = 7
    public var innerSpeed: Double = -12
    public var breathPeriod: Double = 4.8
    public var breathAmplitude: Double = 0.09
    public var chargeDuration: Double = 0.6
    public var releaseDuration: Double = 0.5
    public var curve: MotionCurve = .smooth
    public var scanSpeed: Double = 22

    public init() {}

    public static let diameterRange: ClosedRange<Double> = 40...80
    public static let coreRatioRange: ClosedRange<Double> = 0.20...0.44
    public static let ringWidthRange: ClosedRange<Double> = 0.5...2.5
    public static let tickCountRange: ClosedRange<Int> = 24...72
    public static let hueRange: ClosedRange<Double> = 0.45...0.72
    public static let glowIntensityRange: ClosedRange<Double> = 0...1.5
    public static let haloRadiusRange: ClosedRange<Double> = 0...24
    public static let glassOpacityRange: ClosedRange<Double> = 0.2...1
    public static let rotationSpeedRange: ClosedRange<Double> = -40...40
    public static let breathPeriodRange: ClosedRange<Double> = 2...10
    public static let breathAmplitudeRange: ClosedRange<Double> = 0...0.2
    public static let durationRange: ClosedRange<Double> = 0.2...1.5
    public static let scanSpeedRange: ClosedRange<Double> = 0...90
    public static let playbackRates: [Double] = [0.25, 0.5, 1, 2]

    public var sanitized: OrbParameters {
        var result = self
        let defaults = Self()
        func bounded(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        result.diameter = bounded(diameter, Self.diameterRange, defaults.diameter)
        result.coreRatio = bounded(coreRatio, Self.coreRatioRange, defaults.coreRatio)
        result.ringWidth = bounded(ringWidth, Self.ringWidthRange, defaults.ringWidth)
        result.tickCount = min(Self.tickCountRange.upperBound, max(Self.tickCountRange.lowerBound, tickCount))
        result.hue = bounded(hue, Self.hueRange, defaults.hue)
        result.glowIntensity = bounded(glowIntensity, Self.glowIntensityRange, defaults.glowIntensity)
        result.haloRadius = bounded(haloRadius, Self.haloRadiusRange, defaults.haloRadius)
        result.glassOpacity = bounded(glassOpacity, Self.glassOpacityRange, defaults.glassOpacity)
        result.outerSpeed = bounded(outerSpeed, Self.rotationSpeedRange, defaults.outerSpeed)
        result.innerSpeed = bounded(innerSpeed, Self.rotationSpeedRange, defaults.innerSpeed)
        result.breathPeriod = bounded(breathPeriod, Self.breathPeriodRange, defaults.breathPeriod)
        result.breathAmplitude = bounded(breathAmplitude, Self.breathAmplitudeRange, defaults.breathAmplitude)
        result.chargeDuration = bounded(chargeDuration, Self.durationRange, defaults.chargeDuration)
        result.releaseDuration = bounded(releaseDuration, Self.durationRange, defaults.releaseDuration)
        result.scanSpeed = bounded(scanSpeed, Self.scanSpeedRange, defaults.scanSpeed)
        return result
    }
}
