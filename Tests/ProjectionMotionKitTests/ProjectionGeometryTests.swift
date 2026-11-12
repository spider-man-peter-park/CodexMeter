import AppKit
import OrbMotionKit
import ProjectionMotionKit
import Testing

struct ProjectionGeometryTests {
    @Test func bothEdgesProjectFromTheExactOrbCenterToTheCurrentVisibleScreenCenter() {
        for screen in [CGRect(x: 0, y: 24, width: 1728, height: 1048),
                       CGRect(x: -1920, y: -100, width: 1920, height: 1060),
                       CGRect(x: 100, y: 50, width: 640, height: 430)] {
            for edge in ProjectionEdge.allCases {
                var p = ProjectionConfig(); p.edge = edge
                let g = ProjectionGeometry(visibleFrame: screen, config: p, orb: OrbParameters())
                #expect(g.center == CGPoint(x: screen.width / 2, y: screen.height / 2))
                #expect(g.source.x + screen.minX == g.orbFrame.midX)
                #expect(screen.maxY - g.source.y == g.orbFrame.midY)
                #expect(screen.contains(g.orbFrame))
                #expect(g.beamTip(at: 0) == g.source)
                #expect(g.beamTip(at: 0.35) == g.center)
                #expect(g.direction == (edge == .left ? 1 : -1))
                for frame in g.cardFrames {
                    #expect(CGRect(origin: .zero, size: screen.size).contains(frame))
                }
            }
        }
    }

    @Test func changingVolumeLengthDoesNotBreakTheSourceToHudConnection() {
        var config = ProjectionConfig(); config.beamLength = 0.4
        let short = ProjectionGeometry(visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), config: config, orb: OrbParameters())
        config.beamLength = 1
        let full = ProjectionGeometry(visibleFrame: short.visibleFrame, config: config, orb: OrbParameters())
        #expect(short.source == full.source && short.center == full.center)
        #expect(short.beamTip(at: 1) == full.beamTip(at: 1))
    }

    @Test func movingTheOrbUpdatesOnlyTheProjectionOrigin() {
        let screen = CGRect(x: -1600, y: 50, width: 1600, height: 900)
        let moved = CGRect(x: -1510, y: 200, width: 84, height: 84)
        let normal = ProjectionGeometry(visibleFrame: screen, config: ProjectionConfig(), orb: OrbParameters())
        let dragging = ProjectionGeometry(visibleFrame: screen, config: ProjectionConfig(), orb: OrbParameters(), orbFrame: moved)
        #expect(dragging.center == normal.center)
        #expect(dragging.source != normal.source)
        #expect(dragging.source.x == moved.midX - screen.minX)
        #expect(dragging.beamTip(at: 1) == normal.center)
    }

    @MainActor @Test func projectionWindowsRemainNonactivatingAndAllDecorationIsClickThrough() {
        let panel = ProjectionPanel(title: "Projection test", ignoresMouseEvents: true)
        #expect(panel.ignoresMouseEvents)
        #expect(!panel.canBecomeKey && !panel.canBecomeMain)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.isVisible)
        #expect(ProjectionSceneView().hitTest(CGPoint(x: 20, y: 20)) == nil)
    }

    @MainActor @Test func nativePointerTrackingUsesTheRealOrbHitRegionAndInterruptsBothWays() {
        let c = ProjectionAnimationController(orbParameters: OrbParameters())
        let view = ProjectionOrbInputView()
        view.frame = CGRect(x: 0, y: 0, width: 84, height: 84); view.diameter = 60
        view.onHover = { c.hover($0) }
        view.updateTrackingAreas()
        #expect(view.trackingAreas.contains { $0.options.contains(.activeAlways) && $0.options.contains(.enabledDuringMouseDrag) })
        view.evaluatePointer(at: CGPoint(x: 42, y: 42))
        #expect(c.pointerInside && c.timeline.direction == .forward)
        c.scrub(to: 0.42)
        view.evaluatePointer(at: .zero)
        #expect(!c.pointerInside && c.timeline.direction == .reverse && c.timeline.progress == 0.42)
        c.scrub(to: 0.31)
        view.evaluatePointer(at: CGPoint(x: 42, y: 42))
        #expect(c.pointerInside && c.timeline.direction == .forward && c.timeline.progress == 0.31)
    }

    @MainActor @Test func simulatedHoverDoesNotOverrideARealPointerStillOnTheOrb() {
        let c = ProjectionAnimationController(orbParameters: OrbParameters())
        c.hover(true); c.simulateHover(true); c.simulateHover(false)
        #expect(c.timeline.direction == .forward)
        c.hover(false); #expect(c.timeline.direction == .idle)
        c.scrub(to: 0.7); c.simulateHover(true); c.scrub(to: 0.42)
        #expect(!c.simulatedHover && !c.timeline.isPlaying && c.timeline.progress == 0.42)
    }

    @MainActor @Test func explicitLoopDemoKeepsOwnershipAcrossIncidentalPointerChanges() {
        let c = ProjectionAnimationController(orbParameters: OrbParameters())
        c.loop(true)
        for _ in 0..<50 { c.hover(true); c.hover(false) }
        #expect(c.timeline.isLooping && c.timeline.isPlaying)
        #expect(c.lastAction == "Loop enabled")
        c.expand(); #expect(!c.timeline.isLooping && c.lastAction == "Expand")
        c.loop(true); c.simulateHover(true)
        #expect(!c.timeline.isLooping && c.simulatedHover)
    }
}
