import Foundation
import OrbMotionKit
import ProjectionMotionKit
import Testing

struct HUDInteractionTests {
    @MainActor @Test func inspectionTemporarilyExcludesDesktopInputAndRestoresItsPriorPreference() {
        let controller = ProjectionAnimationController(orbParameters: OrbParameters())
        let desktop = ProjectionDesktopController(controller: controller)
        desktop.setInspectionActive(true)
        #expect(desktop.inspectionActive && !desktop.enabled)
        desktop.setEnabled(true)
        #expect(!desktop.enabled)
        desktop.setInspectionActive(false)
        #expect(!desktop.inspectionActive && desktop.enabled)
        desktop.setEnabled(false)
        desktop.setInspectionActive(true)
        desktop.setInspectionActive(false)
        #expect(!desktop.enabled)
    }

    @Test func crossingTheGapKeepsTheCurrentTargetAndLeavingTheHudDebounces() {
        var state = HUDInteractionState()
        #expect(state.update(region: .source, now: 0, progress: 0) == .open)
        #expect(state.update(region: .transit, now: 0.1, progress: 0.2) == nil)
        #expect(state.update(region: .transit, now: 0.9, progress: 0.6) == nil)
        #expect(state.update(region: .hud, now: 1.0, progress: 0.8) == nil)
        #expect(state.phase == .interacting)
        #expect(state.update(region: .outside, now: 1.1, progress: 1) == nil)
        #expect(state.update(region: .outside, now: 1.5, progress: 1) == nil)
        #expect(state.update(region: .outside, now: 1.7, progress: 1) == .close)
        #expect(state.phase == .closing && !state.needsDeadline)
        #expect(state.update(region: .source, now: 1.8, progress: 0.57) == .open)
        #expect(state.phase == .opening)
    }

    @Test func theTransitCorridorExpiresAndCannotHoldAnUnattendedHudOpen() {
        var state = HUDInteractionState()
        _ = state.update(region: .source, now: 0, progress: 0)
        #expect(state.update(region: .transit, now: 0.1, progress: 0.1) == nil)
        #expect(state.needsDeadline)
        #expect(state.update(region: .transit, now: 1.31, progress: 0.9) == .close)
        let bounds = CGRect(x: 550, y: 180, width: 500, height: 500)
        #expect(HUDInteractionState.isInTransit(CGPoint(x: 420, y: 420), source: CGPoint(x: 40, y: 420), hudBounds: bounds))
        #expect(!HUDInteractionState.isInTransit(CGPoint(x: 420, y: 20), source: CGPoint(x: 40, y: 420), hudBounds: bounds))
        #expect(!HUDInteractionState.isInTransit(CGPoint(x: 1350, y: 420), source: CGPoint(x: 40, y: 420), hudBounds: bounds))
    }

    @Test func manualCloseWinsUntilThePointerActuallyLeavesAndReenters() {
        var state = HUDInteractionState()
        _ = state.update(region: .source, now: 0, progress: 1)
        _ = state.update(region: .hud, now: 0.2, progress: 1)
        state.manualClose()
        #expect(state.update(region: .hud, now: 0.3, progress: 0.8) == nil)
        #expect(state.phase == .closing)
        #expect(state.update(region: .outside, now: 0.4, progress: 0.6) == nil)
        #expect(state.update(region: .hud, now: 0.5, progress: 0.5) == .open)
        #expect(state.phase == .interacting)
    }

    @Test func explicitPlaybackRetainsOwnershipAcrossStationaryPointerAndOutsideRegions() {
        var state = HUDInteractionState()
        state.manualOpen()
        #expect(state.update(region: .outside, now: 100, progress: 1) == nil)
        #expect(state.phase == .previewing && !state.needsDeadline)
        _ = state.update(region: .source, now: 101, progress: 1)
        state.manualPlayback(progress: 0.42)
        #expect(state.update(region: .source, now: 102, progress: 0.42) == nil)
        #expect(state.update(region: .outside, now: 103, progress: 0.42) == nil)
        #expect(!state.needsDeadline)
        #expect(state.update(region: .source, now: 104, progress: 0.42) == .open)
    }

    @Test func pausingDecorationKeepsTheGlobalProjectionFullyReversible() {
        var timeline = ProjectionTimeline()
        timeline.forward()
        timeline.advance(seconds: 0.7, config: ProjectionConfig(), decorationsPaused: true)
        #expect(timeline.progress == 0.5)
        #expect(timeline.ambientTime == 0 && timeline.flowTime == 0 && timeline.rotorTime == 0)
        timeline.reverse()
        timeline.advance(seconds: 0.125, config: ProjectionConfig(), decorationsPaused: true)
        #expect(abs(timeline.progress - 0.4) < 0.00001)
        timeline.forward()
        timeline.advance(seconds: 0.14, config: ProjectionConfig())
        #expect(abs(timeline.progress - 0.5) < 0.00001)
        #expect(timeline.ambientTime > 0 && timeline.rotorTime > 0)
    }

    @MainActor @Test func desktopPointerTargetsReverseWithoutResetAndRespectExplicitClose() {
        let controller = ProjectionAnimationController(orbParameters: OrbParameters())
        let desktop = ProjectionDesktopController(controller: controller)
        controller.scrub(to: 0.57)
        desktop.evaluatePointerRegion(.source, now: 0)
        #expect(controller.timeline.progress == 0.57 && controller.timeline.direction == .forward)
        desktop.evaluatePointerRegion(.hud, now: 0.2)
        controller.hud.select(.performance); controller.hud.expandSelection()
        controller.retract()
        desktop.evaluatePointerRegion(.hud, now: 0.3)
        #expect(controller.timeline.direction == .reverse && controller.timeline.progress == 0.57)
        desktop.evaluatePointerRegion(.outside, now: 0.4)
        desktop.evaluatePointerRegion(.source, now: 0.5)
        #expect(controller.timeline.direction == .forward && controller.timeline.progress == 0.57)
        controller.loop(true)
        for i in 0..<10 {
            desktop.evaluatePointerRegion(.source, now: Double(i + 1))
            desktop.evaluatePointerRegion(.outside, now: Double(i + 1) + 0.8)
        }
        #expect(controller.timeline.isLooping && controller.lastAction == "Loop enabled")
        #expect(desktop.projectionPanel.ignoresMouseEvents)
        #expect(desktop.interactivePanels.isEmpty)
    }

    @Test func croppedInputFramesStayOnTheChosenDisplayIncludingNegativeOrigins() {
        let screen = CGRect(x: -1600, y: 50, width: 1600, height: 900)
        let local = CGRect(x: 200, y: 150, width: 244, height: 142)
        let frame = ProjectionDesktopController.screenFrame(for: local, visibleFrame: screen)
        #expect(frame == CGRect(x: -1400, y: 658, width: 244, height: 142))
        #expect(screen.contains(frame))
        #expect(frame.width * frame.height < screen.width * screen.height * 0.03)
    }
}
