import AppKit
import QuartzCore

@MainActor
public final class ProjectionBeamView {
    public let layer = CALayer()
    private var volumes: [CAGradientLayer] = []
    private var edges: [CAShapeLayer] = []
    private let spine = CAShapeLayer()
    private var particles: [CALayer] = []
    private var scans: [CAShapeLayer] = []
    private var color = NSColor.cyan

    public init() {
        for _ in 0..<5 {
            let gradient = CAGradientLayer()
            gradient.mask = CAShapeLayer()
            layer.addSublayer(gradient)
            volumes.append(gradient)
        }
        for _ in 0..<2 {
            let edge = CAShapeLayer(); layer.addSublayer(edge); edges.append(edge)
        }
        layer.addSublayer(spine)
        for _ in 0..<24 {
            let dot = CALayer(); dot.bounds = CGRect(x: 0, y: 0, width: 3, height: 3)
            dot.cornerRadius = 1.5; layer.addSublayer(dot); particles.append(dot)
        }
        for _ in 0..<9 {
            let scan = CAShapeLayer(); layer.addSublayer(scan); scans.append(scan)
        }
    }

    public func configure(size: CGSize, hue: Double, scale: Double) {
        layer.frame = CGRect(origin: .zero, size: size)
        color = NSColor(calibratedHue: hue, saturation: 0.62, brightness: 1, alpha: 1)
        for gradient in volumes {
            gradient.frame = layer.bounds
            gradient.mask?.frame = gradient.bounds
            gradient.colors = [color.withAlphaComponent(0.13).cgColor,
                               color.withAlphaComponent(0.045).cgColor,
                               color.withAlphaComponent(0.005).cgColor]
            gradient.locations = [0, 0.65, 1]
        }
        for shape in edges + scans + [spine] {
            shape.frame = layer.bounds; shape.fillColor = nil; shape.lineCap = .round
            shape.strokeColor = color.cgColor; shape.contentsScale = scale
        }
        spine.lineWidth = 0.85; spine.strokeColor = NSColor(calibratedRed: 0.76, green: 0.97, blue: 1, alpha: 1).cgColor
        edges.forEach { $0.lineWidth = 0.7 }
        scans.forEach { $0.lineWidth = 0.5 }
        particles.forEach { $0.backgroundColor = NSColor.white.cgColor; $0.contentsScale = scale }
    }

    public func render(geometry g: ProjectionGeometry, config p: ProjectionConfig,
                       timeline t: ProjectionTimeline, reducedMotion: Bool) {
        let s = t.sample
        layer.isHidden = s.beamExtension <= 0
        guard !layer.isHidden else { return }
        let tip = g.beamTip(at: t.progress)
        let dx = tip.x - g.source.x, dy = tip.y - g.source.y
        let distance = max(1, hypot(dx, dy))
        let normal = CGPoint(x: -dy / distance, y: dx / distance)
        let halfWidth = (p.beamWidth / 2 + tan(p.divergence * .pi / 180) * distance * 0.35) * s.beamExtension
        let brightness = p.brightness * s.beamExtension * (1 - s.steady * 0.38)
        func point(_ fraction: Double, _ spread: Double) -> CGPoint {
            CGPoint(x: g.source.x + dx * fraction + normal.x * halfWidth * fraction * spread,
                    y: g.source.y + dy * fraction + normal.y * halfWidth * fraction * spread)
        }
        for (index, gradient) in volumes.enumerated() {
            gradient.isHidden = index >= p.beamLayers
            let width = 1 - Double(index) * 0.16
            let length = p.beamLength
            let path = CGMutablePath()
            path.move(to: g.source)
            path.addQuadCurve(to: point(length, -width), control: point(length * 0.58, -width * 0.9))
            path.addLine(to: point(length, width))
            path.addQuadCurve(to: g.source, control: point(length * 0.58, width * 0.9))
            path.closeSubpath()
            (gradient.mask as? CAShapeLayer)?.path = path
            gradient.startPoint = CGPoint(x: g.source.x / g.visibleFrame.width, y: g.source.y / g.visibleFrame.height)
            gradient.endPoint = CGPoint(x: tip.x / g.visibleFrame.width, y: tip.y / g.visibleFrame.height)
            gradient.opacity = Float(brightness * 1.3 / Double(p.beamLayers).squareRoot())
        }
        for (index, edge) in edges.enumerated() {
            let side = index == 0 ? -1.0 : 1.0
            let path = CGMutablePath(); path.move(to: g.source)
            path.addQuadCurve(to: point(p.beamLength, side), control: point(p.beamLength * 0.6, side * 0.6))
            edge.path = path
            edge.opacity = Float(brightness * p.edgeGlow * 0.38)
        }
        let ray = CGMutablePath(); ray.move(to: g.source); ray.addLine(to: tip)
        spine.path = ray; spine.opacity = Float(brightness * 0.65)
        for (index, dot) in particles.enumerated() {
            dot.isHidden = reducedMotion || index >= p.particleCount
            let fraction = ProjectionSample.particlePosition(index: index, progress: t.progress,
                flowTime: t.flowTime, speed: p.particleSpeed)
            let spread = sin(Double(index) * 2.399) * 0.68
            dot.position = point(fraction, spread)
            dot.opacity = Float(sin(fraction * .pi) * brightness * 0.75)
        }
        for (index, scan) in scans.enumerated() {
            let fraction = Double(index + 1) / 10
            let path = CGMutablePath()
            path.move(to: point(fraction, -0.72)); path.addLine(to: point(fraction, 0.72))
            scan.path = path
            scan.opacity = Float(p.scanVisibility * brightness * 0.15 * sin(fraction * .pi))
        }
    }
}
