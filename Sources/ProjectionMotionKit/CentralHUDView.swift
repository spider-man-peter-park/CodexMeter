import AppKit
import QuartzCore
import PlaygroundLocalization

@MainActor
public final class CentralHUDView {
    public let layer = CALayer()
    private let halo = CAGradientLayer()
    private let focal = CAGradientLayer()
    private var rings: [CAShapeLayer] = []
    private var ticks: [CAShapeLayer] = []
    private let sweep = CAShapeLayer()
    private let reticle = CAShapeLayer()
    private let highlight = CAShapeLayer()
    private var connectors: [CAShapeLayer] = []
    private var cards: [CALayer] = []
    private var cardBorders: [CAShapeLayer] = []
    private var cardDetails: [[CAShapeLayer]] = []
    private var cardLabels: [CATextLayer] = []
    private var dots: [CALayer] = []
    private var geometry: ProjectionGeometry?

    public init() {
        layer.addSublayer(halo)
        for _ in 0..<5 { let ring = CAShapeLayer(); layer.addSublayer(ring); rings.append(ring) }
        for _ in 0..<120 { let tick = CAShapeLayer(); layer.addSublayer(tick); ticks.append(tick) }
        for item in [sweep, highlight, reticle, focal] { layer.addSublayer(item) }
        for _ in 0..<4 {
            let link = CAShapeLayer(); layer.addSublayer(link); connectors.append(link)
            let card = CALayer(); layer.addSublayer(card); cards.append(card)
            let border = CAShapeLayer(); card.addSublayer(border); cardBorders.append(border)
            let label = CATextLayer(); card.addSublayer(label); cardLabels.append(label)
            var details: [CAShapeLayer] = []
            for _ in 0..<12 { let bar = CAShapeLayer(); card.addSublayer(bar); details.append(bar) }
            cardDetails.append(details)
        }
        for _ in 0..<3 {
            let dot = CALayer(); layer.addSublayer(dot); dots.append(dot)
        }
    }

    public func configure(geometry g: ProjectionGeometry, config p: ProjectionConfig, hue: Double, contentsScale: Double,
                          language: PlaygroundLanguage = .english) {
        geometry = g
        layer.transform = CATransform3DIdentity
        layer.frame = CGRect(origin: .zero, size: g.visibleFrame.size)
        let energy = NSColor(calibratedHue: hue, saturation: 0.58, brightness: 1, alpha: 1)
        let white = NSColor(calibratedRed: 0.8, green: 0.97, blue: 1, alpha: 1)
        func circle(_ radius: Double) -> CGPath {
            CGPath(ellipseIn: CGRect(x: g.center.x - radius, y: g.center.y - radius,
                                    width: radius * 2, height: radius * 2), transform: nil)
        }
        func configureShape(_ shape: CAShapeLayer, path: CGPath, color: NSColor, width: Double) {
            shape.transform = CATransform3DIdentity
            shape.frame = layer.bounds; shape.path = path; shape.fillColor = nil
            shape.strokeColor = color.cgColor; shape.lineWidth = width; shape.lineCap = .round
            shape.contentsScale = contentsScale
        }
        func radial(_ gradient: CAGradientLayer, radius: Double, colors: [CGColor]) {
            gradient.frame = CGRect(x: g.center.x - radius, y: g.center.y - radius,
                                    width: radius * 2, height: radius * 2)
            gradient.type = .radial; gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 1); gradient.colors = colors
            gradient.cornerRadius = radius; gradient.masksToBounds = true
        }
        radial(halo, radius: g.radius * 1.8, colors: [energy.withAlphaComponent(0.1).cgColor,
               NSColor(calibratedWhite: 0.02, alpha: 0.72).cgColor, NSColor.clear.cgColor])
        halo.locations = [0, 0.5, 1]
        radial(focal, radius: 11 * g.scale, colors: [white.cgColor, energy.withAlphaComponent(0.55).cgColor, NSColor.clear.cgColor])
        for (index, ring) in rings.enumerated() {
            let radius = g.radius * [1.0, 0.72, 1.16, 1.3, 1.44][index]
            configureShape(ring, path: circle(radius), color: index == 0 ? white : energy,
                           width: index == 0 ? 1.6 : 0.65)
        }
        for (index, tick) in ticks.enumerated() {
            let angle = Double(index) / Double(p.tickCount) * .pi * 2 - .pi / 2
            let radius = g.radius * 1.13
            let length = index.isMultiple(of: 6) ? 8.0 : 3.5
            let path = CGMutablePath()
            path.move(to: CGPoint(x: g.center.x + cos(angle) * radius, y: g.center.y + sin(angle) * radius))
            path.addLine(to: CGPoint(x: g.center.x + cos(angle) * (radius + length * g.scale),
                                    y: g.center.y + sin(angle) * (radius + length * g.scale)))
            configureShape(tick, path: path, color: energy, width: 0.8)
        }
        let brightArc = CGMutablePath()
        brightArc.addArc(center: g.center, radius: g.radius * 1.39, startAngle: -.pi / 2, endAngle: -.pi / 7, clockwise: false)
        configureShape(highlight, path: brightArc, color: energy, width: 2)
        let radar = CGMutablePath(); radar.move(to: g.center)
        radar.addArc(center: g.center, radius: g.radius * 0.86, startAngle: -0.18, endAngle: 0, clockwise: false)
        radar.closeSubpath()
        sweep.frame = layer.bounds; sweep.path = radar; sweep.fillColor = energy.withAlphaComponent(0.13).cgColor
        sweep.strokeColor = energy.withAlphaComponent(0.3).cgColor; sweep.lineWidth = 0.5
        let cross = CGMutablePath()
        for axis in 0..<4 {
            let a = Double(axis) * .pi / 2
            cross.move(to: CGPoint(x: g.center.x + cos(a) * g.radius * 0.12, y: g.center.y + sin(a) * g.radius * 0.12))
            cross.addLine(to: CGPoint(x: g.center.x + cos(a) * g.radius * 0.35, y: g.center.y + sin(a) * g.radius * 0.35))
        }
        configureShape(reticle, path: cross, color: white.withAlphaComponent(0.45), width: 0.6)
        for index in 0..<4 {
            guard index < g.cardFrames.count else { cards[index].isHidden = true; connectors[index].isHidden = true; continue }
            let frame = g.cardFrames[index]
            let card = cards[index]
            card.transform = CATransform3DIdentity
            card.isHidden = false; connectors[index].isHidden = false
            card.frame = frame; card.cornerRadius = 7 * g.scale
            card.backgroundColor = NSColor(calibratedRed: 0.025, green: 0.065, blue: 0.085, alpha: 0.78).cgColor
            let border = cardBorders[index]
            border.frame = card.bounds
            border.path = CGPath(roundedRect: card.bounds, cornerWidth: 7 * g.scale, cornerHeight: 7 * g.scale, transform: nil)
            border.fillColor = nil; border.strokeColor = energy.withAlphaComponent(0.65).cgColor
            border.lineWidth = 0.7; border.contentsScale = contentsScale
            let label = cardLabels[index]
            label.string = language.text(["SIGNAL TRACE", "SPECTRUM", "PHASE STUDY", "LINK STRUCTURE"][index])
            label.font = NSFont.monospacedSystemFont(ofSize: 8 * g.scale, weight: .medium)
            label.fontSize = 8 * g.scale; label.foregroundColor = white.withAlphaComponent(0.8).cgColor
            label.frame = CGRect(x: 11 * g.scale, y: 10 * g.scale, width: frame.width - 22 * g.scale, height: 12 * g.scale)
            label.contentsScale = contentsScale
            let targetX = frame.midX < g.center.x ? frame.maxX : frame.minX
            let angle = atan2(frame.midY - g.center.y, targetX - g.center.x)
            let connection = CGMutablePath()
            connection.move(to: CGPoint(x: g.center.x + cos(angle) * g.radius * 1.28, y: g.center.y + sin(angle) * g.radius * 1.28))
            connection.addLine(to: CGPoint(x: targetX - (frame.midX < g.center.x ? -15 : 15) * g.scale, y: frame.midY))
            connection.addLine(to: CGPoint(x: targetX, y: frame.midY))
            configureShape(connectors[index], path: connection, color: energy.withAlphaComponent(0.48), width: 0.65)
            for (barIndex, bar) in cardDetails[index].enumerated() {
                bar.frame = card.bounds; bar.fillColor = nil
                bar.strokeColor = (index == 2 ? NSColor(calibratedHue: 0.68, saturation: 0.35, brightness: 1, alpha: 0.7) : energy).cgColor
                bar.lineWidth = 2 * g.scale; bar.lineCap = .round; bar.contentsScale = contentsScale
                let x = (12 + Double(barIndex) * 9.5) * g.scale
                let height = (7 + 17 * abs(sin(Double(barIndex) * 1.13 + Double(index)))) * g.scale
                let path = CGMutablePath(); path.move(to: CGPoint(x: x, y: 52 * g.scale))
                path.addLine(to: CGPoint(x: x, y: 52 * g.scale - height)); bar.path = path
            }
        }
        for dot in dots {
            dot.bounds = CGRect(x: 0, y: 0, width: 3, height: 3); dot.cornerRadius = 1.5
            dot.backgroundColor = white.cgColor; dot.contentsScale = contentsScale
        }
    }

    public func render(config p: ProjectionConfig, timeline t: ProjectionTimeline, reducedMotion: Bool) {
        guard let g = geometry else { return }
        let s = t.sample
        layer.isHidden = s.energyPoint <= 0
        guard !layer.isHidden else { return }
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / 1800
        layer.transform = CATransform3DRotate(perspective, reducedMotion ? 0 : g.direction * 0.035 * s.mainRing, 0, 1, 0)
        halo.opacity = Float(s.mainRing * p.haloIntensity)
        focal.opacity = Float(s.energyPoint * (1 - s.mainRing * 0.35))
        for (index, ring) in rings.enumerated() {
            ring.isHidden = index > p.ringCount
            let build = s.stage(0.45 + Double(index) * 0.026, 0.65 + Double(index) * 0.026)
            ring.strokeEnd = build
            ring.opacity = Float(index == 0 ? 0.9 : 0.38)
            let phase = reducedMotion ? 0 : t.flowTime * p.rotationSpeed * (index.isMultiple(of: 2) ? 1 : -0.7)
            let transform = CGAffineTransform(rotationAngle: phase * .pi / 180)
                .scaledBy(x: reducedMotion ? 1 : 0.32 + build * 0.68, y: reducedMotion ? 1 : 0.32 + build * 0.68)
            ring.setAffineTransform(transform)
        }
        let tickSweep = s.stage(0.54, 0.74)
        for (index, tick) in ticks.enumerated() {
            tick.isHidden = index >= p.tickCount
            tick.opacity = Float(max(0, min(0.65, (tickSweep * Double(p.tickCount + 2) - Double(index)) / 2)))
        }
        highlight.strokeEnd = s.stage(0.68, 0.85)
        highlight.opacity = 0.7
        reticle.strokeEnd = s.stage(0.48, 0.64)
        sweep.opacity = Float(reducedMotion ? 0 : s.steady)
        sweep.setAffineTransform(CGAffineTransform(rotationAngle: t.flowTime * p.scanSpeed * .pi / 180))
        for index in 0..<p.cardCount {
            let build = s.stage(0.65 + Double(index) * 0.035, 0.74 + Double(index) * 0.035)
            let detail = s.stage(0.72 + Double(index) * 0.035, 0.81 + Double(index) * 0.035)
            connectors[index].strokeEnd = build
            cardBorders[index].strokeEnd = build
            cards[index].opacity = Float(build)
            var transform = CATransform3DIdentity
            transform.m41 = reducedMotion ? 0 : (g.center.x - cards[index].position.x) * (1 - build)
            transform.m42 = reducedMotion ? 0 : (g.center.y - cards[index].position.y) * (1 - build)
            cards[index].transform = transform
            cardLabels[index].opacity = Float(detail)
            for (barIndex, bar) in cardDetails[index].enumerated() {
                bar.strokeEnd = max(0, min(1, detail * 1.4 - Double(barIndex) / 30))
                bar.opacity = Float(0.38 + (reducedMotion ? 0 : s.steady * 0.2 * sin(t.flowTime * 1.6 + Double(barIndex))))
            }
        }
        for (index, dot) in dots.enumerated() {
            let angle = (t.flowTime * p.scanSpeed + Double(index) * 120) * .pi / 180
            dot.position = CGPoint(x: g.center.x + cos(angle) * g.radius * 0.91, y: g.center.y + sin(angle) * g.radius * 0.91)
            dot.opacity = Float(reducedMotion ? 0 : s.steady * 0.7)
        }
    }

}
