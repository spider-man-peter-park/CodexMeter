import Foundation
import OrbMotionKit
import ProjectionMotionKit
import Testing

struct ProjectionLifecycleTests {
    @MainActor @Test func sleepingOrClosingThePlaygroundFreezesTheCurrentProjection() async throws {
        let controller = ProjectionAnimationController(orbParameters: OrbParameters())
        controller.scrub(to: 0.42); controller.expand(); controller.suspend(true); controller.start()
        let suspended = controller.timeline
        try await Task.sleep(nanoseconds: 40_000_000)
        #expect(controller.timeline == suspended)
        controller.suspend(false)
        try await Task.sleep(nanoseconds: 40_000_000)
        #expect(controller.timeline.progress > 0.42)
        controller.stop(); let stopped = controller.timeline
        try await Task.sleep(nanoseconds: 40_000_000)
        #expect(controller.timeline == stopped)
    }

    @MainActor @Test func cancellingTheDriverReleasesAClosedPlayground() async throws {
        var controller: ProjectionAnimationController? = ProjectionAnimationController(orbParameters: OrbParameters())
        weak var weakController = controller
        controller?.expand(); controller?.start(); controller = nil
        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(weakController == nil)
    }
}
