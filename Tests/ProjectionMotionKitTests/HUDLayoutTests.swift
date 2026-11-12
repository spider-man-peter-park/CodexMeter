import AppKit
import OrbMotionKit
import Testing
@testable import ProjectionMotionKit

struct HUDLayoutTests {
    @Test func layoutKeepsAllSixModulesLegibleAndSeparatedOnSupportedScreens() {
        for size in [CGSize(width: 1024, height: 640), CGSize(width: 1280, height: 720),
                     CGSize(width: 1512, height: 944), CGSize(width: 2560, height: 1440)] {
            for density in HUDDensity.allCases {
                var config = HUDConfiguration(); config.density = density
                let layout = HUDLayout(visibleSize: size, config: config)
                let bounds = CGRect(origin: .zero, size: size)
                #expect(bounds.contains(layout.coreFrame))
                #expect(layout.moduleFrames.count == 6)
                #expect(layout.coreFrame.width >= 240)
                let frames = Array(layout.moduleFrames.values)
                for (index, frame) in frames.enumerated() {
                    #expect(bounds.contains(frame))
                    #expect(frame.width >= 200)
                    #expect(!frame.intersects(layout.coreFrame))
                    for later in frames.dropFirst(index + 1) { #expect(!frame.intersects(later)) }
                }
            }
        }
    }

    @Test func hiddenModulesAndTransparentCornersHaveNoHitRegion() throws {
        var config = HUDConfiguration()
        config.enabledModules.remove(.ai)
        config.disabledModules.insert(.network)
        let layout = HUDLayout(visibleSize: CGSize(width: 1280, height: 800), config: config)
        #expect(layout.moduleFrames[.ai] == nil)
        let disabled = try #require(layout.moduleFrames[.network])
        #expect(layout.target(at: CGPoint(x: disabled.midX, y: disabled.midY)) == nil)
        #expect(layout.module(atCorePoint: CGPoint(x: disabled.midX, y: disabled.midY)) != .network)
        #expect(layout.target(at: CGPoint(x: 20, y: 20)) == nil)
        #expect(layout.target(at: layout.center) == .core)
        let frame = try #require(layout.moduleFrames[.performance])
        #expect(layout.target(at: CGPoint(x: frame.midX, y: frame.midY)) == .module(.performance))
        #expect(layout.target(at: CGPoint(x: frame.minX + 1, y: frame.minY + 1)) == nil)
        #expect(layout.target(at: CGPoint(x: frame.maxX - 1, y: frame.midY)) == nil)
    }

    @Test func everyModuleRetracesItsDrawingStagesAtTheSameGlobalProgress() {
        for index in 0..<6 {
            let start = HUDGeneration(progress: 0, moduleIndex: index)
            let end = HUDGeneration(progress: 1, moduleIndex: index)
            #expect(start == HUDGeneration(progress: 0, moduleIndex: index))
            #expect(start.core == 0 && start.connector == 0 && start.border == 0 && start.content == 0)
            #expect(end.core == 1 && end.rings == 1 && end.connector == 1 && end.border == 1 && end.content == 1)
            let forward = stride(from: 0.0, through: 1.0, by: 0.01).map { HUDGeneration(progress: $0, moduleIndex: index) }
            let backward = stride(from: 0.0, through: 1.0, by: 0.01).reversed().map { HUDGeneration(progress: $0, moduleIndex: index) }
            #expect(forward == backward.reversed())
            for (a, b) in zip(forward, forward.dropFirst()) {
                #expect(a.connector <= b.connector && a.border <= b.border && a.content <= b.content)
            }
            let borderOnly = HUDGeneration(progress: 0.77 + Double(index) * 0.016, moduleIndex: index)
            #expect(borderOnly.border > 0 && borderOnly.content == 0)
        }
    }

    @MainActor @Test func nativeActionsSelectExpandReturnAndPreserveTheProjectionPlayhead() throws {
        let controller = ProjectionAnimationController(orbParameters: OrbParameters())
        controller.scrub(to: 0.91)
        let timeline = controller.timeline
        let view = HUDDashboardView(controller: controller)
        let geometry = ProjectionGeometry(visibleFrame: CGRect(x: 0, y: 0, width: 1280, height: 800),
                                          config: controller.config, orb: controller.orbParameters)
        view.render(geometry: geometry, timeline: timeline, reducedMotion: true)
        let layout = try #require(view.dashboardLayout)
        let frame = try #require(layout.moduleFrames[.performance])
        let point = CGPoint(x: frame.midX, y: frame.midY)
        view.evaluatePointer(at: point)
        #expect(controller.hud.hovered == .performance)
        view.performAction(at: point)
        #expect(controller.hud.selected == .performance && controller.hud.expanded)
        view.performAction(at: CGPoint(x: layout.center.x, y: layout.center.y + layout.coreFrame.height * 0.3))
        #expect(controller.hud.selected == nil && !controller.hud.expanded)
        #expect(controller.timeline == timeline)
        view.drawsContent = false
        view.viewportOrigin = frame.origin
        view.renderedTarget = .module(.performance)
        view.render(geometry: geometry, timeline: timeline, reducedMotion: true)
        #expect(view.target(at: CGPoint(x: frame.width / 2, y: frame.height / 2)) == .module(.performance))
        #expect(view.target(at: CGPoint(x: 1, y: 1)) == nil)
        controller.scrub(to: 0.5)
        view.render(geometry: geometry, timeline: controller.timeline, reducedMotion: true)
        #expect(view.target(at: CGPoint(x: frame.width / 2, y: frame.height / 2)) == nil)
    }
}
