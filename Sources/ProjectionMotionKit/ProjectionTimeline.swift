import Foundation
import OrbMotionKit

public struct ProjectionTimeline: Equatable, Sendable {
    public private(set) var progress: Double = 0
    public private(set) var ambientTime: Double = 0
    public private(set) var flowTime: Double = 0
    public private(set) var rotorTime: Double = 0
    public private(set) var direction: MotionDirection = .idle
    public private(set) var isPlaying = true
    public var isLooping = false
    public var playbackRate: Double = 1
    private var lastDirection: MotionDirection = .forward

    public init() {}
    public var sample: ProjectionSample { ProjectionSample(progress: progress) }
    public var isTransitioning: Bool { isPlaying && direction != .idle }
    public var stateTitle: String {
        if !isPlaying { return "Paused" }
        if direction == .forward { return "Expanding" }
        if direction == .reverse { return "Retracting" }
        return progress == 0 ? "Standby" : "Projected"
    }
    public mutating func forward() {
        lastDirection = .forward
        direction = progress < 1 ? .forward : .idle
        isPlaying = true
    }
    public mutating func reverse() {
        lastDirection = .reverse
        direction = progress > 0 ? .reverse : .idle
        isPlaying = true
    }
    public mutating func hover(_ inside: Bool) {
        guard !isLooping else { return }
        if inside { forward() } else { reverse() }
    }
    public mutating func scrub(to value: Double) {
        guard value.isFinite else { return }
        progress = min(1, max(0, value))
        direction = .idle
        isPlaying = false
    }
    public mutating func pause() { isPlaying = false }
    public mutating func play() {
        if direction == .idle {
            direction = progress <= 0 ? .forward : progress >= 1 ? .reverse : lastDirection
        }
        lastDirection = direction
        isPlaying = true
    }
    public mutating func reset() {
        let rate = playbackRate
        self = Self()
        playbackRate = rate
        isPlaying = false
    }
    public mutating func advance(seconds: Double, config: ProjectionConfig, reducedMotion: Bool = false,
                                 decorationsPaused: Bool = false) {
        guard isPlaying, seconds.isFinite, seconds > 0,
              [0.25, 0.5, 1, 2].contains(playbackRate) else { return }
        let p = config.sanitized
        let delta = seconds * playbackRate
        guard delta.isFinite else { return }
        let ambientEnabled = !reducedMotion && !decorationsPaused
        if ambientEnabled { ambientTime += delta; rotorTime += delta }
        let opening = reducedMotion ? 0.15 : p.openDuration
        let closing = reducedMotion ? 0.15 : p.closeDuration
        let looping = isLooping && !reducedMotion
        if direction == .idle {
            if looping { direction = progress >= 1 ? .reverse : .forward }
            else {
                if ambientEnabled {
                    flowTime += delta * sample.steady
                    rotorTime += 1.8 * delta * sample.orbActivation
                }
                return
            }
        }
        var remaining = delta
        // Integrate complete cycles before consuming their endpoint remainders.
        if looping, remaining >= opening + closing {
            let cycles = floor(remaining / (opening + closing))
            if ambientEnabled {
                flowTime += cycles * (opening - closing) * Self.stageIntegral(1, 0.85, 1)
                rotorTime += 1.8 * cycles * (opening + closing) * Self.stageIntegral(1, 0, 0.15)
            }
            remaining.formTruncatingRemainder(dividingBy: opening + closing)
        }
        while remaining > 0, direction != .idle {
            let forward = direction == .forward
            let duration = forward ? opening : closing
            let untilEnd = (forward ? 1 - progress : progress) * duration
            let interval = min(remaining, untilEnd)
            let previous = progress
            progress = min(1, max(0, progress + (forward ? 1 : -1) * interval / duration))
            if ambientEnabled {
                flowTime += duration * (Self.stageIntegral(progress, 0.85, 1) - Self.stageIntegral(previous, 0.85, 1))
                rotorTime += 1.8 * duration * abs(Self.stageIntegral(progress, 0, 0.15) - Self.stageIntegral(previous, 0, 0.15))
            }
            remaining -= interval
            if interval >= untilEnd {
                if looping {
                    direction = forward ? .reverse : .forward
                    lastDirection = direction
                } else {
                    direction = .idle
                    if ambientEnabled {
                        flowTime += remaining * sample.steady
                        rotorTime += 1.8 * remaining * sample.orbActivation
                    }
                    remaining = 0
                }
            }
        }
    }
    private static func stageIntegral(_ progress: Double, _ lower: Double, _ upper: Double) -> Double {
        let width = upper - lower
        let x = min(1, max(0, (progress - lower) / width))
        return width * (pow(x, 6) - 3 * pow(x, 5) + 2.5 * pow(x, 4)) + max(0, progress - upper)
    }
}
