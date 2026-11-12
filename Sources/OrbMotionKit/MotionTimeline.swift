import Foundation

public enum MotionDirection: String, Codable, Sendable {
    case idle
    case forward
    case reverse

    public var title: String {
        switch self {
        case .idle: return "Idle"
        case .forward: return "Forward"
        case .reverse: return "Reverse"
        }
    }
}

public struct MotionSample: Equatable, Sendable {
    public let progress: Double
    public let easedProgress: Double
    public let coreCharge: Double
    public let ringCharge: Double
    public let tickSweep: Double
    public let convergence: Double
    public let activationRotation: Double

    public init(progress: Double, curve: MotionCurve = .smooth) {
        let p = progress.isFinite ? min(1, max(0, progress)) : 0
        self.progress = p
        easedProgress = curve.map(p)
        func stage(_ start: Double, _ end: Double) -> Double {
            curve.map((p - start) / (end - start))
        }
        coreCharge = stage(0, 0.82)
        ringCharge = stage(0.12, 0.78)
        tickSweep = stage(0.22, 0.92)
        convergence = stage(0.36, 1)
        activationRotation = 95 * curve.map(p)
    }
}

public struct MotionTimeline: Equatable, Sendable {
    public private(set) var progress: Double = 0
    public private(set) var ambientTime: Double = 0
    public private(set) var rotorTime: Double = 0
    public private(set) var elapsedTime: Double = 0
    public private(set) var direction: MotionDirection = .idle
    public private(set) var isPlaying: Bool = true
    public var isLooping: Bool = false
    public var playbackRate: Double = 1
    private var lastDirection: MotionDirection = .forward
    private static let chargeSpeedBoost = 1.8

    public init() {}

    public var isTransitioning: Bool {
        isPlaying && direction != .idle
    }

    public var stateTitle: String {
        if !isPlaying { return "Paused" }
        switch direction {
        case .forward: return "Charging"
        case .reverse: return "Releasing"
        case .idle: return progress >= 1 ? "Activated" : "Standby"
        }
    }

    public mutating func activate() {
        lastDirection = .forward
        direction = progress < 1 ? .forward : .idle
        isPlaying = true
    }

    public mutating func retract() {
        lastDirection = .reverse
        direction = progress > 0 ? .reverse : .idle
        isPlaying = true
    }

    public mutating func setHovered(_ hovered: Bool) {
        isLooping = false
        if hovered { activate() } else { retract() }
    }

    public mutating func scrub(to value: Double) {
        guard value.isFinite else { return }
        progress = min(1, max(0, value))
        isPlaying = false
        direction = .idle
    }

    public mutating func play() {
        isPlaying = true
        if direction == .idle {
            if progress <= 0 { direction = .forward }
            else if progress >= 1 { direction = .reverse }
            else { direction = lastDirection }
        }
        lastDirection = direction
    }

    public mutating func pause() {
        isPlaying = false
    }

    public mutating func reset() {
        let rate = playbackRate
        self = Self()
        playbackRate = rate
        isPlaying = false
    }

    public mutating func advance(seconds: Double, parameters: OrbParameters, reduceMotion: Bool = false) {
        guard isPlaying, seconds.isFinite, seconds > 0, playbackRate.isFinite, playbackRate > 0 else { return }
        let delta = seconds * min(4, playbackRate)
        guard delta.isFinite else { return }
        elapsedTime += delta
        if !reduceMotion {
            ambientTime += delta
            rotorTime += delta
        }
        let settings = parameters.sanitized
        let chargeDuration = reduceMotion ? min(0.12, settings.chargeDuration) : settings.chargeDuration
        let releaseDuration = reduceMotion ? min(0.12, settings.releaseDuration) : settings.releaseDuration
        let looping = isLooping && !reduceMotion
        if direction == .idle {
            guard looping else {
                if !reduceMotion { rotorTime += Self.chargeSpeedBoost * delta * settings.curve.map(progress) }
                return
            }
            direction = progress >= 1 ? .reverse : .forward
        }

        var remaining = delta
        // Skip complete cycles without frame-count-dependent endpoint behavior.
        let cycleDuration = chargeDuration + releaseDuration
        if looping, remaining >= cycleDuration {
            let wholeCycles = floor(remaining / cycleDuration)
            let cycleTime = wholeCycles * cycleDuration
            rotorTime += Self.chargeSpeedBoost * cycleTime * settings.curve.integral(upTo: 1)
            remaining -= cycleTime
        }
        while remaining > 0, direction != .idle {
            let forward = direction == .forward
            let duration = forward ? chargeDuration : releaseDuration
            let distance = forward ? 1 - progress : progress
            let untilEndpoint = distance * duration
            let previousProgress = progress
            let segmentDuration = min(remaining, untilEndpoint)
            if remaining < untilEndpoint {
                progress += (forward ? 1 : -1) * remaining / duration
                remaining = 0
            } else {
                progress = forward ? 1 : 0
                remaining -= untilEndpoint
                if looping {
                    direction = forward ? .reverse : .forward
                    lastDirection = direction
                } else {
                    direction = .idle
                }
            }
            if !reduceMotion, segmentDuration > 0 {
                // Integrating the authored curve keeps rotor velocity tied to progress, not direction.
                let chargeArea = abs(settings.curve.integral(upTo: progress)
                                     - settings.curve.integral(upTo: previousProgress)) * duration
                rotorTime += Self.chargeSpeedBoost * chargeArea
            }
            if direction == .idle {
                if !reduceMotion { rotorTime += Self.chargeSpeedBoost * remaining * settings.curve.map(progress) }
                remaining = 0
            }
        }
        progress = min(1, max(0, progress))
    }
}
