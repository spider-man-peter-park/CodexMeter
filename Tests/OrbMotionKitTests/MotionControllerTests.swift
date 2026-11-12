import Foundation
import Testing
@testable import OrbMotionKit

struct MotionControllerTests {
    @Test @MainActor func suspendedAndStoppedControllersDoNotAdvanceHiddenFrames() async throws {
        let controller = MotionController()
        controller.activate()
        controller.setSuspended(true)
        controller.start()
        let suspendedFrame = controller.timeline
        try await Task.sleep(nanoseconds: 60_000_000)
        #expect(controller.timeline == suspendedFrame)
        controller.setSuspended(false)
        controller.stop()
        let stoppedFrame = controller.timeline
        try await Task.sleep(nanoseconds: 60_000_000)
        #expect(controller.timeline == stoppedFrame)
    }

    @Test @MainActor func lifecyclePauseDoesNotOverwriteThePlayheadOrPlaybackIntent() {
        let controller = MotionController()
        controller.scrub(to: 0.4)
        controller.retract()
        let visibleFrame = controller.timeline
        controller.setSuspended(true)
        #expect(controller.isSuspended)
        #expect(controller.timeline == visibleFrame)
        controller.setSuspended(false)
        #expect(!controller.isSuspended)
        #expect(controller.timeline.progress == 0.4)
        #expect(controller.timeline.direction == .reverse)
        #expect(controller.timeline.isPlaying)
        controller.stop()
    }

    @Test @MainActor func theDriverDoesNotRetainItsControllerAfterTheWindowReleasesIt() async throws {
        var controller: MotionController? = MotionController()
        weak var releasedController = controller
        controller?.start()
        try await Task.sleep(nanoseconds: 30_000_000)
        controller = nil
        #expect(releasedController == nil)
    }
}
