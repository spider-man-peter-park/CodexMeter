import AppKit
import Combine
import QuartzCore
import SwiftUI
import PlaygroundLocalization

/// Retains the drawing layers and observes playback without invalidating a SwiftUI view each frame.
@MainActor
public struct AnimatedEnergyOrb: NSViewRepresentable {
    public let controller: MotionController
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.playgroundLanguage) private var language

    public init(controller: MotionController) { self.controller = controller }
    public func makeCoordinator() -> Coordinator { Coordinator() }
    public func makeNSView(context: Context) -> OrbLayerView {
        let view = OrbLayerView()
        context.coordinator.bind(controller, view: view, systemReducedMotion: systemReducedMotion, language: language)
        return view
    }
    public func updateNSView(_ view: OrbLayerView, context: Context) {
        context.coordinator.bind(controller, view: view, systemReducedMotion: systemReducedMotion, language: language)
    }
    public static func dismantleNSView(_ view: OrbLayerView, coordinator: Coordinator) {
        coordinator.subscriptions.removeAll()
    }

    @MainActor
    public final class Coordinator {
        fileprivate var subscriptions: Set<AnyCancellable> = []
        private weak var controller: MotionController?
        private weak var view: OrbLayerView?
        private var parameters = OrbParameters()
        private var timeline = MotionTimeline()
        private var reducedMotion = false
        private var systemReducedMotion = false

        fileprivate func bind(_ controller: MotionController, view: OrbLayerView, systemReducedMotion: Bool, language: PlaygroundLanguage) {
            self.view = view
            view.language = language
            self.systemReducedMotion = systemReducedMotion
            guard self.controller !== controller else { render(); return }
            self.controller = controller
            subscriptions.removeAll()
            controller.$parameters.sink { [weak self] in self?.parameters = $0; self?.render() }.store(in: &subscriptions)
            controller.$reduceMotion.sink { [weak self] in self?.reducedMotion = $0; self?.render() }.store(in: &subscriptions)
            controller.$timeline.sink { [weak self] in self?.timeline = $0; self?.render() }.store(in: &subscriptions)
        }

        private func render() {
            view?.update(parameters: parameters, progress: timeline.progress, ambientTime: timeline.ambientTime,
                         rotorTime: timeline.rotorTime, reducedMotion: reducedMotion || systemReducedMotion)
        }
    }
}

@MainActor
struct OrbLayerSurface: NSViewRepresentable {
    var parameters: OrbParameters
    var progress: Double
    var ambientTime: Double
    var rotorTime: Double?
    var reducedMotion: Bool
    var language: PlaygroundLanguage

    func makeNSView(context: Context) -> OrbLayerView { OrbLayerView() }
    func updateNSView(_ view: OrbLayerView, context: Context) {
        view.language = language
        view.update(parameters: parameters, progress: progress, ambientTime: ambientTime,
                    rotorTime: rotorTime ?? ambientTime, reducedMotion: reducedMotion)
    }
}

@MainActor
public final class OrbLayerView: NSView {
    public var language: PlaygroundLanguage = .english {
        didSet {
            if language != oldValue { setAccessibilityLabel(language.text("Energy orb")) }
        }
    }
    private let halo = CAGradientLayer()
    private let body = CAGradientLayer()
    private let outline = CAShapeLayer()
    private let highlight = CAShapeLayer()
    private let outerTrack = CAShapeLayer()
    private let innerTrack = CAShapeLayer()
    private let outerRotor = CALayer()
    private let innerRotor = CALayer()
    private let returnRotor = CALayer()
    private let coreGlow = CAGradientLayer()
    private let core = CAGradientLayer()
    private let coreLight = CAGradientLayer()
    private let coreOutline = CAShapeLayer()
    private var ticks: [CAShapeLayer] = []
    private var arcs: [CAShapeLayer] = []
    private var returns: [CAShapeLayer] = []
    private var dots: [CALayer] = []
    private var glints: [CAShapeLayer] = []
    private var parameters: OrbParameters?
    private var lastSize = CGSize.zero
    private var frameState: (Double, Double, Double, Bool) = (0, 0, 0, false)

    public override var isFlipped: Bool { true }
    public override var intrinsicContentSize: NSSize {
        let p = parameters ?? OrbParameters()
        return NSSize(width: p.diameter + p.haloRadius * 2, height: p.diameter + p.haloRadius * 2)
    }

    public init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        for item in [halo, body, outline, highlight, outerTrack, outerRotor, innerRotor,
                     returnRotor, innerTrack, coreGlow, core, coreLight, coreOutline] {
            layer?.addSublayer(item)
        }
        for _ in 0..<4 {
            let arc = CAShapeLayer(); innerRotor.addSublayer(arc); arcs.append(arc)
            let path = CAShapeLayer(); returnRotor.addSublayer(path); returns.append(path)
        }
        for _ in 0..<3 { let dot = CALayer(); layer?.addSublayer(dot); dots.append(dot) }
        for _ in 0..<6 { let glint = CAShapeLayer(); layer?.addSublayer(glint); glints.append(glint) }
        setAccessibilityElement(true)
        setAccessibilityLabel(language.text("Energy orb"))
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let layer { updateScale(layer) }
    }

    public override func layout() {
        super.layout()
        guard let parameters, bounds.size != lastSize else { return }
        update(parameters: parameters, progress: frameState.0, ambientTime: frameState.1,
               rotorTime: frameState.2, reducedMotion: frameState.3)
    }

    public func update(parameters raw: OrbParameters, progress: Double, ambientTime: Double,
                       rotorTime: Double, reducedMotion: Bool) {
        let p = raw.sanitized
        frameState = (progress, ambientTime, rotorTime, reducedMotion)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if parameters != p || lastSize != bounds.size {
            let previousSize = intrinsicContentSize
            parameters = p
            rebuild(p)
            if intrinsicContentSize != previousSize { invalidateIntrinsicContentSize() }
        }
        let sample = MotionSample(progress: progress, curve: p.curve)
        let time = reducedMotion ? 0 : ambientTime
        let rotationTime = reducedMotion ? 0 : rotorTime
        let pulse = reducedMotion ? 0 : sin(time * .pi * 2 / p.breathPeriod) * p.breathAmplitude
        outerRotor.setAffineTransform(CGAffineTransform(rotationAngle: rotationTime * p.outerSpeed * .pi / 180))
        innerRotor.setAffineTransform(CGAffineTransform(rotationAngle: rotationTime * p.innerSpeed * .pi / 180))
        returnRotor.setAffineTransform(CGAffineTransform(rotationAngle: -rotationTime * p.innerSpeed * .pi / 180))
        halo.opacity = Float((0.16 + sample.coreCharge * 0.4) * p.glowIntensity)
        outerTrack.opacity = Float(0.17 + sample.ringCharge * 0.2)
        innerTrack.opacity = Float(0.2 + sample.coreCharge * 0.25)
        for (index, tick) in ticks.enumerated() {
            let fraction = Double(index) / Double(ticks.count)
            let sweep = reducedMotion ? sample.tickSweep : max(0, min(1,
                (sample.tickSweep * (1 + 2 / Double(ticks.count)) - fraction) * Double(ticks.count) / 2))
            let scan = reducedMotion ? 0 : pow(max(0, cos((fraction * 360 - time * p.scanSpeed) * .pi / 180)), 18)
            tick.opacity = Float(min(1, 0.23 + sweep * 0.62 + scan * 0.15))
        }
        for arc in arcs { arc.opacity = Float(0.45 + sample.ringCharge * 0.5) }
        for (index, dot) in dots.enumerated() {
            let angle = reducedMotion ? Double(index) * 120 :
                time * p.scanSpeed * (index == 1 ? -0.7 : 1) + Double(index) * 120
            dot.position = point(p.diameter * (0.277 + Double(index % 2) * 0.047), angle)
            dot.opacity = Float(0.5 + sample.ringCharge * 0.4)
        }
        for (index, glint) in glints.enumerated() {
            glint.isHidden = reducedMotion
            let travel = sample.convergence
            let angle = Double(index) * 60 - 30 + sample.activationRotation * 0.3
            let radius = p.diameter * (0.315 - travel * 0.16)
            glint.path = line(point(radius + p.diameter * 0.035, angle), point(radius, angle))
            glint.opacity = Float(sin(travel * .pi) * (0.3 + sample.coreCharge * 0.6))
        }
        coreGlow.opacity = Float(min(1, (0.26 + sample.coreCharge * 0.44 + pulse) * p.glowIntensity))
        core.opacity = Float(0.82 + sample.coreCharge * 0.18 + pulse * 0.2)
        coreLight.opacity = Float(0.1 + sample.coreCharge * 0.45)
        coreOutline.opacity = Float(0.18 + sample.coreCharge * 0.32)
        CATransaction.commit()
        setAccessibilityValue(language.format("%d percent activated", Int(sample.progress * 100)))
    }

    private var center: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }
    private func point(_ radius: Double, _ degrees: Double) -> CGPoint {
        let angle = degrees * .pi / 180
        return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }
    private func circle(_ radius: Double) -> CGPath {
        CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                width: radius * 2, height: radius * 2), transform: nil)
    }
    private func line(_ from: CGPoint, _ to: CGPoint) -> CGPath {
        let path = CGMutablePath(); path.move(to: from); path.addLine(to: to); return path
    }
    private func arc(_ radius: Double, _ start: Double, _ length: Double) -> CGPath {
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius, startAngle: start * .pi / 180,
                    endAngle: (start + length) * .pi / 180, clockwise: false)
        return path
    }

    private func rebuild(_ p: OrbParameters) {
        lastSize = bounds.size
        let d = p.diameter
        let energy = NSColor(calibratedHue: p.hue, saturation: 0.64, brightness: 1, alpha: 1)
        let violet = NSColor(calibratedHue: 0.68, saturation: 0.52, brightness: 1, alpha: 0.65)
        func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
            NSColor(calibratedRed: r, green: g, blue: b, alpha: a).cgColor
        }
        func radial(_ gradient: CAGradientLayer, radius: Double, colors: [CGColor], locations: [NSNumber]) {
            gradient.frame = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            gradient.type = .radial; gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
            // Radial endpoints define both ellipse radii; equal Y coordinates collapse its height.
            gradient.endPoint = CGPoint(x: 1, y: 1); gradient.colors = colors; gradient.locations = locations
            gradient.cornerRadius = radius; gradient.masksToBounds = true
        }
        func stroke(_ shape: CAShapeLayer, path: CGPath, color: CGColor, width: Double) {
            shape.path = path; shape.fillColor = nil; shape.strokeColor = color
            shape.lineWidth = width; shape.lineCap = .round
        }
        radial(halo, radius: d / 2 + p.haloRadius,
               colors: [energy.withAlphaComponent(0.7).cgColor, energy.withAlphaComponent(0.12).cgColor, color(0, 0, 0, 0)],
               locations: [0.2, 0.64, 1])
        body.frame = CGRect(x: center.x - d * 0.49, y: center.y - d * 0.49, width: d * 0.98, height: d * 0.98)
        body.colors = [color(0.17, 0.24, 0.29, p.glassOpacity), color(0.025, 0.065, 0.09, p.glassOpacity),
                       color(0.08, 0.12, 0.18, p.glassOpacity)]
        body.startPoint = CGPoint(x: 0.2, y: 0); body.endPoint = CGPoint(x: 0.7, y: 1)
        body.cornerRadius = d * 0.49; body.masksToBounds = true
        stroke(outline, path: circle(d * 0.49), color: color(1, 1, 1, 0.18), width: 0.65)
        stroke(highlight, path: arc(d * 0.482, 205, 104), color: color(1, 1, 1, 0.38), width: 0.7)
        stroke(outerTrack, path: circle(d * 0.365), color: energy.cgColor, width: 0.5)
        stroke(innerTrack, path: circle(d * 0.232), color: energy.cgColor, width: 0.5)
        for rotor in [outerRotor, innerRotor, returnRotor] {
            rotor.transform = CATransform3DIdentity; rotor.frame = bounds
        }
        if ticks.count != p.tickCount {
            ticks.forEach { $0.removeFromSuperlayer() }; ticks.removeAll()
            for _ in 0..<p.tickCount { let tick = CAShapeLayer(); outerRotor.addSublayer(tick); ticks.append(tick) }
        }
        for (index, tick) in ticks.enumerated() {
            let major = index.isMultiple(of: 4), angle = Double(index) / Double(ticks.count) * 360 - 90
            stroke(tick, path: line(point(d * (major ? 0.405 : 0.425), angle), point(d * 0.455, angle)),
                   color: energy.cgColor, width: major ? 1 : 0.65)
        }
        for index in 0..<4 {
            stroke(arcs[index], path: arc(d * 0.323, Double(index) * 90, 58), color: energy.cgColor, width: p.ringWidth)
            stroke(returns[index], path: arc(d * 0.278, -Double(index) * 90 + 18, 38),
                   color: index == 2 ? violet.cgColor : energy.withAlphaComponent(0.28).cgColor, width: 0.65)
        }
        for dot in dots { dot.bounds = CGRect(x: 0, y: 0, width: 1.7, height: 1.7); dot.cornerRadius = 0.85; dot.backgroundColor = NSColor.white.cgColor }
        for glint in glints { glint.fillColor = nil; glint.strokeColor = energy.cgColor; glint.lineWidth = 0.8; glint.lineCap = .round }
        let radius = d * p.coreRatio / 2
        radial(coreGlow, radius: radius * 1.85, colors: [energy.cgColor, color(0, 0, 0, 0)], locations: [0, 1])
        radial(core, radius: radius, colors: [NSColor.white.cgColor, color(0.81, 0.97, 1), energy.withAlphaComponent(0.73).cgColor,
                                            energy.withAlphaComponent(0.25).cgColor], locations: [0, 0.4, 0.78, 1])
        radial(coreLight, radius: radius, colors: [NSColor.white.cgColor, color(1, 1, 1, 0)], locations: [0, 1])
        stroke(coreOutline, path: circle(radius + 1.5), color: NSColor.white.cgColor, width: 0.5)
        if let layer { updateScale(layer) }
    }

    private func updateScale(_ item: CALayer) {
        item.contentsScale = window?.backingScaleFactor ?? 2
        item.sublayers?.forEach(updateScale)
    }
}
