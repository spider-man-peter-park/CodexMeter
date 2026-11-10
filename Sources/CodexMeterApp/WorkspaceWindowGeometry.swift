import AppKit

enum WorkspaceWindowGeometry {
    static func restored(_ frame: NSRect, on screen: NSRect) -> NSRect {
        let width = frame.width.isFinite && frame.width >= 780 ? frame.width : 940
        let height = frame.height.isFinite && frame.height >= 540 ? frame.height : 700
        let size = NSSize(width: min(width, screen.width), height: min(height, screen.height))
        let x = frame.minX.isFinite ? frame.minX : screen.midX - size.width / 2
        let y = frame.minY.isFinite ? frame.minY : screen.midY - size.height / 2
        return NSRect(x: max(screen.minX, min(x, screen.maxX - size.width)),
            y: max(screen.minY, min(y, screen.maxY - size.height)), width: size.width, height: size.height)
    }
}
