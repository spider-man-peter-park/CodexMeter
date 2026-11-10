import AppKit
import Testing
@testable import CodexMeterApp

struct WorkspaceWindowGeometryTests {
    @Test func repairsCollapsedRestoredFramesToAReadableSize() {
        let screen = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let value = WorkspaceWindowGeometry.restored(NSRect(x: 0, y: 0, width: 1, height: 0), on: screen)
        #expect(value.width == 940 && value.height == 700)
        #expect(screen.contains(value))
    }

    @Test func invalidCoordinatesAndSizesUseAFiniteCenteredFrame() {
        let screen = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let frame = NSRect(x: CGFloat.nan, y: CGFloat.nan, width: CGFloat.nan, height: CGFloat.infinity)
        let value = WorkspaceWindowGeometry.restored(frame, on: screen)
        #expect(value.width == 940 && value.height == 700)
        #expect(value.minX == 250 && value.minY == 100)
        #expect(screen.contains(value))
    }

    @Test func framesFromRemovedDisplaysMoveIntoTheCurrentVisibleScreen() {
        let screen = NSRect(x: 100, y: 50, width: 1_280, height: 800)
        let value = WorkspaceWindowGeometry.restored(NSRect(x: -5_000, y: 5_000, width: 900, height: 600), on: screen)
        #expect(value.minX == 100 && value.minY == 250)
        #expect(value.width == 900 && value.height == 600 && screen.contains(value))
    }

    @Test func smallDisplaysBoundEvenPreviouslyLargeWindows() {
        let screen = NSRect(x: -800, y: 30, width: 640, height: 400)
        let value = WorkspaceWindowGeometry.restored(NSRect(x: 900, y: 900, width: 1_600, height: 1_000), on: screen)
        #expect(value == screen)
    }
}
