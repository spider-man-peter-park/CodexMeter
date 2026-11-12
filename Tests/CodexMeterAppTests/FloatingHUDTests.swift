import AppKit
import Testing
@testable import CodexMeterApp

struct FloatingHUDTests {
    @Test func projectionCentersOnTheOrbScreenWithoutMovingTheOrb() throws {
        for screen in [NSRect(x: 0, y: 0, width: 1440, height: 900),
                       NSRect(x: -900, y: 40, width: 900, height: 700),
                       NSRect(x: 0, y: 0, width: 640, height: 400)] {
            for x in [screen.minX, screen.midX - 34, screen.maxX - 68] {
                for y in [screen.minY, screen.midY - 34, screen.maxY - 68] {
                    let orb = NSRect(x: x, y: y, width: 68, height: 68)
                    let layout = FloatingHUDGeometry.layout(orb: orb, on: screen, expanded: true)
                    let dashboard = try #require(layout.dashboardFrame)
                    #expect(screen.contains(layout.orbFrame))
                    #expect(screen.contains(dashboard))
                    #expect(layout.orbFrame == orb)
                    #expect(dashboard.midX == screen.midX && dashboard.midY == screen.midY)
                    #expect(layout.beamOrigin == NSPoint(x: orb.midX, y: orb.midY))
                    #expect(layout.beamTarget == NSPoint(x: screen.midX, y: screen.midY))
                }
            }
        }
    }

    @Test func edgeSnappingKeepsA24PointMarginOnEveryEdge() {
        for screen in [NSRect(x: 0, y: 0, width: 1440, height: 900),
                       NSRect(x: -1600, y: -200, width: 1600, height: 1000)] {
            let cases: [(NSRect, FloatingHUDEdge)] = [
                (NSRect(x: screen.minX + 4, y: screen.midY, width: 68, height: 68), .left),
                (NSRect(x: screen.maxX - 72, y: screen.midY, width: 68, height: 68), .right),
                (NSRect(x: screen.midX, y: screen.minY + 3, width: 68, height: 68), .bottom),
                (NSRect(x: screen.midX, y: screen.maxY - 73, width: 68, height: 68), .top)
            ]
            for (proposed, edge) in cases {
                let snapped = FloatingHUDGeometry.snappedOrb(proposed, on: screen)
                #expect(screen.contains(snapped))
                switch edge {
                case .left: #expect(snapped.minX == screen.minX + 24)
                case .right: #expect(snapped.maxX == screen.maxX - 24)
                case .bottom: #expect(snapped.minY == screen.minY + 24)
                case .top: #expect(snapped.maxY == screen.maxY - 24)
                }
            }
        }
    }

    @Test func beamCorridorRetainsHoverWithoutBecomingAnInteractiveSurface() throws {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let orb = NSRect(x: 1348, y: 416, width: 68, height: 68)
        let layout = FloatingHUDGeometry.layout(orb: orb, on: screen, expanded: true)
        let dashboard = try #require(layout.dashboardFrame)
        let between = NSPoint(x: (orb.minX + dashboard.maxX) / 2, y: screen.midY)
        #expect(layout.containsRetentionPoint(between))
        #expect(!layout.containsInteractivePoint(between))
        let outside = NSPoint(x: between.x, y: screen.maxY - 20)
        #expect(!layout.containsRetentionPoint(outside))
        let collapsed = FloatingHUDGeometry.layout(orb: orb, on: screen, expanded: false)
        #expect(!collapsed.containsRetentionPoint(between))
    }

    @Test func invalidOrOffscreenSavedPositionsReturnToTheVisibleScreen() {
        let screen = NSRect(x: 100, y: 50, width: 1280, height: 800)
        for proposed in [NSRect(x: -9000, y: 9000, width: 68, height: 68),
                         NSRect(x: CGFloat.nan, y: CGFloat.infinity, width: 68, height: 68)] {
            let orb = FloatingHUDGeometry.snappedOrb(proposed, on: screen)
            #expect(screen.contains(orb))
            #expect(orb.width == 68 && orb.height == 68)
        }
    }

    @Test func glassCompositionFitsNormalAndCompactScenesWithoutOverlappingCards() {
        for size in [NSSize(width: 1120, height: 680), NSSize(width: 676, height: 652),
                     NSSize(width: 416, height: 352)] {
            let composition = FloatingHUDComposition(size: size)
            let bounds = NSRect(origin: .zero, size: size)
            #expect(bounds.contains(composition.coreFrame))
            #expect(composition.cardFrames.count == 4)
            for (index, frame) in composition.cardFrames.enumerated() {
                #expect(bounds.contains(frame))
                #expect(!frame.intersects(composition.coreFrame))
                for other in composition.cardFrames.dropFirst(index + 1) {
                    #expect(!frame.intersects(other))
                }
            }
        }
    }

    @Test func transparentPanelGapsPassClicksWhileRetainingPointerTransfer() throws {
        let screen = NSRect(x: -1600, y: 40, width: 1600, height: 900)
        let layout = FloatingHUDGeometry.layout(orb: NSRect(x: -1576, y: 450, width: 68, height: 68),
            on: screen, expanded: true)
        let frame = try #require(layout.dashboardFrame)
        let composition = try #require(layout.composition)
        func global(_ local: NSPoint) -> NSPoint {
            NSPoint(x: frame.minX + local.x, y: frame.maxY - local.y)
        }
        let core = composition.coreFrame
        #expect(layout.containsDashboardPoint(global(NSPoint(x: core.midX, y: core.midY))))
        for card in composition.cardFrames {
            #expect(layout.containsDashboardPoint(global(NSPoint(x: card.midX, y: card.midY))))
            #expect(layout.containsDashboardPoint(global(NSPoint(x: card.minX + 5, y: card.minY + 5))))
            let clearCorner = global(NSPoint(x: card.minX + 1, y: card.minY + 1))
            #expect(!layout.containsInteractivePoint(clearCorner))
            #expect(layout.containsRetentionPoint(clearCorner))
        }
        let gap = global(NSPoint(x: (composition.cardFrames[0].maxX + core.minX) / 2, y: core.midY))
        #expect(!layout.containsInteractivePoint(gap))
        #expect(layout.containsRetentionPoint(gap))
        #expect(!layout.containsDashboardPoint(global(NSPoint(x: core.minX + 1, y: core.minY + 1))))
    }

    @Test func compactGlassHitRegionsConvertNegativeDisplayCoordinatesFromTheTop() throws {
        let screen = NSRect(x: -900, y: -100, width: 900, height: 700)
        let layout = FloatingHUDGeometry.layout(orb: NSRect(x: -876, y: 200, width: 68, height: 68),
            on: screen, expanded: true)
        let frame = try #require(layout.dashboardFrame)
        let composition = try #require(layout.composition)
        #expect(composition.isCompact)
        let core = composition.coreFrame
        let coreCenter = NSPoint(x: frame.minX + core.midX, y: frame.maxY - core.midY)
        #expect(layout.containsDashboardPoint(coreCenter))
        let reflected = NSPoint(x: coreCenter.x, y: frame.minY + core.midY)
        #expect(!layout.containsDashboardPoint(reflected))
    }

    @Test func savedOrbPositionsRestoreOnTheirConnectedDisplay() {
        let main = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let secondary = NSRect(x: -1600, y: 0, width: 1600, height: 1000)
        let saved = NSRect(x: -1576, y: 700, width: 68, height: 68)
        let connected = FloatingHUDGeometry.screen(for: saved, among: [main, secondary], fallback: main)
        #expect(connected == secondary)
        #expect(FloatingHUDGeometry.snappedOrb(saved, on: connected) == saved)
        let disconnected = FloatingHUDGeometry.screen(for: saved, among: [main], fallback: main)
        #expect(disconnected == main)
        #expect(main.contains(FloatingHUDGeometry.snappedOrb(saved, on: disconnected)))
    }

    @Test func returningFromTheOrbToThePanelCancelsAnOlderExit() throws {
        var interaction = FloatingHUDInteraction()
        interaction.pointerEntered()
        let firstTicket = interaction.pointerExited()
        let firstExit = try #require(firstTicket)
        interaction.pointerEntered()
        let oldExitCompleted = interaction.completeExit(firstExit, pointerInside: false)
        #expect(!oldExitCompleted)
        #expect(interaction.expanded)
        let secondTicket = interaction.pointerExited()
        let secondExit = try #require(secondTicket)
        let insideExitCompleted = interaction.completeExit(secondExit, pointerInside: true)
        #expect(!insideExitCompleted)
        #expect(interaction.expanded)
        let outsideExitCompleted = interaction.completeExit(secondExit, pointerInside: false)
        #expect(outsideExitCompleted)
        #expect(!interaction.expanded)
    }

    @Test func draggingSuppressesHoverExpansionAndInvalidatesPendingCollapse() throws {
        var interaction = FloatingHUDInteraction()
        interaction.pointerEntered()
        let ticket = interaction.pointerExited()
        let exit = try #require(ticket)
        interaction.beginDrag()
        interaction.pointerEntered()
        #expect(interaction.dragging && !interaction.expanded)
        let dragExit = interaction.pointerExited()
        #expect(dragExit == nil)
        let oldExitCompleted = interaction.completeExit(exit, pointerInside: false)
        #expect(!oldExitCompleted)
        interaction.endDrag()
        interaction.pointerEntered()
        #expect(!interaction.dragging && interaction.expanded)
    }
}
