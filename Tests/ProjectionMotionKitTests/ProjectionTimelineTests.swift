import Foundation
import OrbMotionKit
import ProjectionMotionKit
import Testing

struct ProjectionTimelineTests {
    private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.000_000_1 }

    @Test func stagesBuildInOrderAndUnwindAsTheSameFunctions() {
        let idle = ProjectionSample(progress: 0)
        #expect(idle.orbActivation == 0 && idle.beamExtension == 0 && idle.mainRing == 0)
        let launch = ProjectionSample(progress: 0.31)
        #expect(launch.orbActivation == 1 && launch.beamExtension > 0 && launch.energyPoint == 0)
        let focal = ProjectionSample(progress: 0.42)
        #expect(focal.beamExtension == 1 && focal.energyPoint > 0 && focal.mainRing == 0)
        let rings = ProjectionSample(progress: 0.6)
        #expect(rings.mainRing > 0 && rings.peripheral == 0 && rings.steady == 0)
        let peripheral = ProjectionSample(progress: 0.8)
        #expect(peripheral.mainRing == 1 && peripheral.peripheral > 0 && peripheral.steady == 0)
        let values = (0...100).map { ProjectionSample(progress: Double($0) / 100) }
        for pair in zip(values, values.dropFirst()) {
            #expect(pair.0.orbActivation <= pair.1.orbActivation)
            #expect(pair.0.beamExtension <= pair.1.beamExtension)
            #expect(pair.0.energyPoint <= pair.1.energyPoint)
            #expect(pair.0.mainRing <= pair.1.mainRing)
            #expect(pair.0.peripheral <= pair.1.peripheral)
            #expect(pair.0.steady <= pair.1.steady)
        }
    }

    @Test func exitAtFortyTwoPercentReversesWithoutResettingAnyVisibleValue() {
        let config = ProjectionConfig()
        var t = ProjectionTimeline()
        t.forward(); t.advance(seconds: config.openDuration * 0.42, config: config)
        let sample = t.sample, flow = t.flowTime, rotor = t.rotorTime
        t.hover(false)
        #expect(t.sample == sample && t.flowTime == flow && t.rotorTime == rotor)
        t.advance(seconds: config.closeDuration * 0.1, config: config)
        #expect(close(t.progress, 0.32))
        #expect(t.sample.energyPoint == 0 && t.sample.beamExtension > 0)
    }

    @Test func reentryAtThirtyOnePercentContinuesForwardFromTheSameFrame() {
        var t = ProjectionTimeline()
        t.scrub(to: 0.31); t.reverse()
        let snapshot = t.sample
        t.hover(true)
        #expect(t.sample == snapshot)
        t.advance(seconds: ProjectionConfig().openDuration * 0.1, config: ProjectionConfig())
        #expect(close(t.progress, 0.41))
    }

    @Test func rapidHoverChangesDoNotRestartOrEscapeProgressBounds() {
        var t = ProjectionTimeline()
        let p = ProjectionConfig()
        t.scrub(to: 0.42)
        for index in 0..<500 {
            let visible = t.sample
            t.hover(index.isMultiple(of: 2))
            #expect(t.sample == visible)
            t.advance(seconds: 0.002, config: p)
            #expect((0...1).contains(t.progress))
        }
    }

    @Test func scrubbingAndPauseFreezeEveryClockAndResumeInTheChosenDirection() {
        let p = ProjectionConfig()
        var t = ProjectionTimeline()
        t.forward(); t.advance(seconds: 0.8, config: p)
        t.scrub(to: 0.73)
        let frozen = t
        t.advance(seconds: 2, config: p)
        #expect(t == frozen)
        t.reverse(); t.advance(seconds: 0.1, config: p)
        #expect(t.progress < 0.73)
        t.pause(); let paused = t
        t.advance(seconds: 1, config: p)
        #expect(t == paused)
        t.play(); #expect(t.direction == .reverse)
    }

    @Test func loopingIsFrameIndependentEvenAcrossAsymmetricDurations() {
        let p = ProjectionConfig()
        var one = ProjectionTimeline(); one.scrub(to: 0.63); one.reverse(); one.isLooping = true
        var many = one
        one.advance(seconds: 12.432, config: p)
        for _ in 0..<12432 { many.advance(seconds: 0.001, config: p) }
        #expect(close(one.progress, many.progress))
        #expect(close(one.flowTime, many.flowTime))
        #expect(close(one.rotorTime, many.rotorTime))
        #expect(close(one.ambientTime, many.ambientTime))
        #expect(one.direction == many.direction)
    }

    @Test func beamParticlesReverseContinuouslyAndIdleFlowReturnsTowardsTheOrb() {
        let p = ProjectionConfig()
        var t = ProjectionTimeline()
        t.forward(); t.advance(seconds: 1.6, config: p)
        let first = ProjectionSample.particlePosition(index: 3, progress: t.progress, flowTime: t.flowTime, speed: 0.8)
        t.reverse()
        let same = ProjectionSample.particlePosition(index: 3, progress: t.progress, flowTime: t.flowTime, speed: 0.8)
        #expect(first == same)
        let flow = t.flowTime
        t.advance(seconds: 0.01, config: p)
        #expect(t.flowTime < flow)
        let backwards = ProjectionSample.particlePosition(index: 3, progress: t.progress, flowTime: t.flowTime, speed: 0.8)
        #expect(backwards < same)
    }

    @Test func playbackRatesScaleTheWholeProjectionTogether() {
        let p = ProjectionConfig()
        for rate in [0.25, 0.5, 1.0, 2.0] {
            var t = ProjectionTimeline(); t.forward(); t.playbackRate = rate
            t.advance(seconds: 0.2, config: p)
            #expect(close(t.progress, 0.2 * rate / p.openDuration))
            #expect(close(t.ambientTime, 0.2 * rate))
        }
    }

    @Test func reduceMotionStopsAmbientFlowAndAutomaticLooping() {
        var t = ProjectionTimeline(); t.forward(); t.isLooping = true
        t.advance(seconds: 3, config: ProjectionConfig(), reducedMotion: true)
        #expect(t.progress == 1 && t.direction == .idle)
        #expect(t.ambientTime == 0 && t.flowTime == 0 && t.rotorTime == 0)
        t.advance(seconds: 3, config: ProjectionConfig(), reducedMotion: true)
        #expect(t.progress == 1)
    }

    @Test func exactProjectionEndpointsRemoveTheBackdropAfterFrameSizedRetraction() {
        for (duration, interval) in [(0.8, 0.023), (1.1, 0.019), (2.3, 1.0 / 60)] {
            var config = ProjectionConfig()
            config.closeDuration = duration
            var timeline = ProjectionTimeline()
            timeline.scrub(to: 1)
            timeline.reverse()
            for _ in 0...Int(ceil(duration / interval)) {
                timeline.advance(seconds: interval, config: config)
            }
            #expect(timeline.direction == .idle)
            #expect(timeline.progress == 0)
            #expect(timeline.sample.orbActivation == 0)

            timeline.forward()
            for _ in 0...Int(ceil(config.openDuration / interval)) {
                timeline.advance(seconds: interval, config: config)
            }
            #expect(timeline.direction == .idle && timeline.progress == 1)
        }
    }

    @Test func invalidInputAndResetCannotLeaveResidualProjection() throws {
        var t = ProjectionTimeline(); let baseline = t
        for value in [Double.nan, .infinity, -1, 0] { t.advance(seconds: value, config: ProjectionConfig()) }
        #expect(t == baseline)
        t.scrub(to: .nan); #expect(t == baseline)
        t.forward(); t.advance(seconds: 2, config: ProjectionConfig()); t.reset()
        #expect(t.progress == 0 && !t.isPlaying && t.flowTime == 0 && t.ambientTime == 0 && t.rotorTime == 0)
        var config = ProjectionConfig(); config.beamWidth = .nan; config.mainRadius = -999
        config.particleCount = 999; config.ringCount = 999
        let safe = config.sanitized
        #expect(safe.beamWidth == 80 && safe.mainRadius == 70 && safe.particleCount == 24 && safe.ringCount == 4)
        #expect(try JSONDecoder().decode(ProjectionConfig.self, from: JSONEncoder().encode(safe)) == safe)
    }
}
