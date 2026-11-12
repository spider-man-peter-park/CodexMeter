import Foundation
import Testing
@testable import OrbMotionKit

struct MotionTimelineTests {
    private let parameters = OrbParameters()

    private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.000_000_1 }

    @Test func reversingAtFortyPercentPreservesTheVisibleSample() {
        var timeline = MotionTimeline()
        timeline.activate()
        timeline.advance(seconds: parameters.chargeDuration * 0.4, parameters: parameters)
        let before = MotionSample(progress: timeline.progress)
        timeline.retract()
        #expect(close(timeline.progress, 0.4))
        #expect(MotionSample(progress: timeline.progress) == before)
        timeline.advance(seconds: parameters.releaseDuration * 0.1, parameters: parameters)
        #expect(close(timeline.progress, 0.3))
        timeline.advance(seconds: parameters.releaseDuration * 0.3, parameters: parameters)
        #expect(close(timeline.progress, 0))
    }

    @Test func reenteringAtThirtyPercentContinuesFromThePresentationValue() {
        var timeline = MotionTimeline()
        timeline.scrub(to: 0.8)
        timeline.retract()
        timeline.advance(seconds: parameters.releaseDuration * 0.5, parameters: parameters)
        timeline.setHovered(true)
        #expect(close(timeline.progress, 0.3))
        timeline.advance(seconds: parameters.chargeDuration * 0.2, parameters: parameters)
        #expect(close(timeline.progress, 0.5))
        #expect(timeline.direction == .forward)
    }

    @Test func rapidHoverChangesNeverResetOrExceedProgressBounds() {
        var timeline = MotionTimeline()
        timeline.scrub(to: 0.5)
        for index in 0..<500 {
            let visibleProgress = timeline.progress
            timeline.setHovered(index.isMultiple(of: 2))
            #expect(timeline.progress == visibleProgress)
            timeline.advance(seconds: 0.003, parameters: parameters)
            #expect((0...1).contains(timeline.progress))
        }
    }

    @Test func scrubbingIsDeterministicAndPausesEveryAnimatedClock() {
        var timeline = MotionTimeline()
        timeline.activate()
        timeline.advance(seconds: 0.21, parameters: parameters)
        timeline.scrub(to: 0.42)
        let sample = MotionSample(progress: timeline.progress)
        let snapshot = timeline
        timeline.advance(seconds: 10, parameters: parameters)
        #expect(timeline == snapshot)
        timeline.scrub(to: 0.9)
        timeline.scrub(to: 0.42)
        #expect(MotionSample(progress: timeline.progress) == sample)
        timeline.retract()
        #expect(timeline.progress == 0.42)
        #expect(timeline.isPlaying)
    }

    @Test func pauseAndResumePreserveDirectionAndAmbientPhase() {
        var timeline = MotionTimeline()
        timeline.activate()
        timeline.advance(seconds: 0.12, parameters: parameters)
        timeline.pause()
        let paused = timeline
        timeline.advance(seconds: 1, parameters: parameters)
        #expect(timeline == paused)
        timeline.play()
        timeline.advance(seconds: 0.12, parameters: parameters)
        #expect(close(timeline.progress, 0.4))
        #expect(close(timeline.ambientTime, 0.24))
    }

    @Test func playbackRateScalesChargeAndAmbientTimeTogether() {
        for rate in OrbParameters.playbackRates {
            var timeline = MotionTimeline()
            timeline.playbackRate = rate
            timeline.activate()
            timeline.advance(seconds: 0.1, parameters: parameters)
            #expect(close(timeline.progress, 0.1 * rate / parameters.chargeDuration))
            #expect(close(timeline.ambientTime, 0.1 * rate))
        }
    }

    @Test func loopingConsumesEndpointRemaindersAndIsIndependentOfFramePartition() {
        var oneFrame = MotionTimeline()
        oneFrame.isLooping = true
        oneFrame.activate()
        var manyFrames = oneFrame
        oneFrame.advance(seconds: 4.79, parameters: parameters)
        for _ in 0..<479 { manyFrames.advance(seconds: 0.01, parameters: parameters) }
        #expect(close(oneFrame.progress, manyFrames.progress))
        #expect(oneFrame.direction == manyFrames.direction)
        #expect(close(oneFrame.ambientTime, manyFrames.ambientTime))
        #expect(close(oneFrame.rotorTime, manyFrames.rotorTime))
    }

    @Test func loopingFromAPartialReverseRetainsPhaseAcrossWholeCycles() {
        var timeline = MotionTimeline()
        timeline.scrub(to: 0.37)
        timeline.retract()
        timeline.isLooping = true
        timeline.advance(seconds: (parameters.chargeDuration + parameters.releaseDuration) * 100,
                         parameters: parameters)
        #expect(close(timeline.progress, 0.37))
        #expect(timeline.direction == .reverse)
    }

    @Test func invalidTimeAndProgressInputsCannotPoisonTheTimeline() {
        var timeline = MotionTimeline()
        timeline.activate()
        let snapshot = timeline
        for delta in [Double.nan, .infinity, -.infinity, -1, 0] {
            timeline.advance(seconds: delta, parameters: parameters)
            #expect(timeline == snapshot)
        }
        timeline.scrub(to: .nan)
        #expect(timeline == snapshot)
        timeline.scrub(to: 10)
        #expect(timeline.progress == 1)
        timeline.scrub(to: -10)
        #expect(timeline.progress == 0)
    }

    @Test func reduceMotionFreezesAmbientAndSubstitutesAShortChargeFadeWithoutLooping() {
        var timeline = MotionTimeline()
        timeline.isLooping = true
        timeline.activate()
        timeline.advance(seconds: 0.06, parameters: parameters, reduceMotion: true)
        #expect(close(timeline.progress, 0.5))
        #expect(timeline.ambientTime == 0)
        #expect(timeline.rotorTime == 0)
        timeline.advance(seconds: 2, parameters: parameters, reduceMotion: true)
        #expect(timeline.progress == 1)
        #expect(timeline.direction == .idle)
        #expect(timeline.ambientTime == 0)
        #expect(timeline.rotorTime == 0)
    }

    @Test func resetReturnsToAnExactPausedBaseline() {
        var timeline = MotionTimeline()
        timeline.playbackRate = 0.5
        timeline.isLooping = true
        timeline.activate()
        timeline.advance(seconds: 0.4, parameters: parameters)
        timeline.reset()
        #expect(timeline.progress == 0)
        #expect(timeline.ambientTime == 0)
        #expect(timeline.rotorTime == 0)
        #expect(timeline.elapsedTime == 0)
        #expect(!timeline.isPlaying)
        #expect(!timeline.isLooping)
        #expect(timeline.playbackRate == 0.5)
    }

    @Test func stageSamplesAreBoundedMonotonicAndReverseExactly() {
        for curve in MotionCurve.allCases {
            let forward = (0...100).map { MotionSample(progress: Double($0) / 100, curve: curve) }
            let reverse = (0...100).reversed().map { MotionSample(progress: Double($0) / 100, curve: curve) }
            #expect(forward == Array(reverse.reversed()))
            for (a, b) in zip(forward, forward.dropFirst()) {
                #expect(b.coreCharge >= a.coreCharge)
                #expect(b.ringCharge >= a.ringCharge)
                #expect(b.tickSweep >= a.tickSweep)
                #expect(b.convergence >= a.convergence)
            }
            #expect(forward.first?.coreCharge == 0)
            #expect(forward.last?.convergence == 1)
        }
    }

    @Test func fullyChargedRotorsStayFasterAndRetractionGraduallyReturnsToStandbySpeed() {
        var timeline = MotionTimeline()
        timeline.activate()
        timeline.advance(seconds: parameters.chargeDuration, parameters: parameters)
        let chargedPhase = timeline.rotorTime
        timeline.advance(seconds: 0.1, parameters: parameters)
        #expect(close(timeline.rotorTime - chargedPhase, 0.28))
        timeline.retract()
        timeline.advance(seconds: parameters.releaseDuration, parameters: parameters)
        let standbyPhase = timeline.rotorTime
        timeline.advance(seconds: 0.1, parameters: parameters)
        #expect(close(timeline.rotorTime - standbyPhase, 0.1))
    }

    @Test func rotorVelocityContinuesThroughAnInterruptedDirectionChange() {
        var timeline = MotionTimeline()
        timeline.scrub(to: 0.4)
        timeline.activate()
        let initialPhase = timeline.rotorTime
        timeline.advance(seconds: 0.000_001, parameters: parameters)
        let forwardVelocity = (timeline.rotorTime - initialPhase) / 0.000_001
        let visiblePhase = timeline.rotorTime
        timeline.retract()
        #expect(timeline.rotorTime == visiblePhase)
        timeline.advance(seconds: 0.000_001, parameters: parameters)
        let reverseVelocity = (timeline.rotorTime - visiblePhase) / 0.000_001
        #expect(abs(forwardVelocity - reverseVelocity) < 0.000_01)
    }

    @Test func chargedRotorIntegrationIsFrameIndependentForEveryCurveAndReleaseTail() {
        for curve in MotionCurve.allCases {
            var settings = parameters
            settings.curve = curve
            var oneFrame = MotionTimeline()
            oneFrame.scrub(to: 0.72)
            oneFrame.retract()
            var manyFrames = oneFrame
            oneFrame.advance(seconds: 0.57, parameters: settings)
            for _ in 0..<57 { manyFrames.advance(seconds: 0.01, parameters: settings) }
            #expect(close(oneFrame.rotorTime, manyFrames.rotorTime))
            #expect(close(oneFrame.progress, manyFrames.progress))
        }
    }

    @Test func parameterValidationAndSerializationKeepAPortableConfiguration() throws {
        var settings = OrbParameters()
        settings.diameter = .nan
        settings.chargeDuration = 0
        settings.tickCount = Int.max
        settings.innerSpeed = -.infinity
        let normalized = settings.sanitized
        #expect(normalized.diameter == 60)
        #expect(normalized.chargeDuration == OrbParameters.durationRange.lowerBound)
        #expect(normalized.tickCount == OrbParameters.tickCountRange.upperBound)
        #expect(normalized.innerSpeed == OrbParameters().innerSpeed)
        #expect(try JSONDecoder().decode(OrbParameters.self, from: JSONEncoder().encode(normalized)) == normalized)
    }
}
