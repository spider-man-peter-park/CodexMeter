import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
for (points, scale) in sizes {
    let pixels = points * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let background = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 190, yRadius: 190)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor(white: 0, alpha: 0.2).cgColor)
    NSColor(srgbRed: 0.02, green: 0.50, blue: 0.87, alpha: 1).setFill()
    background.fill()
    context.restoreGState()
    NSGradient(starting: NSColor(srgbRed: 0.01, green: 0.75, blue: 0.75, alpha: 1),
               ending: NSColor(srgbRed: 0.05, green: 0.35, blue: 0.86, alpha: 1))!
        .draw(in: background, angle: -55)
    let center = NSPoint(x: 512, y: 472)
    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: 270, startAngle: 210, endAngle: -30, clockwise: true)
    arc.lineWidth = 30
    arc.lineCapStyle = .round
    NSColor.white.setStroke()
    arc.stroke()
    for angle in stride(from: -30.0, through: 210.0, by: 40) {
        let radians = angle * .pi / 180
        let point = NSPoint(x: center.x + 213 * cos(radians), y: center.y + 213 * sin(radians))
        NSColor(white: 1, alpha: 0.85).setFill()
        NSBezierPath(ovalIn: NSRect(x: point.x - 11, y: point.y - 11, width: 22, height: 22)).fill()
    }
    let needle = NSBezierPath()
    needle.move(to: NSPoint(x: 488, y: 438))
    needle.line(to: NSPoint(x: 639, y: 664))
    needle.lineWidth = 32
    needle.lineCapStyle = .round
    NSColor.white.setStroke()
    needle.stroke()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: 488, y: 448, width: 48, height: 48)).fill()
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 2 ? "@2x" : ""
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
}
