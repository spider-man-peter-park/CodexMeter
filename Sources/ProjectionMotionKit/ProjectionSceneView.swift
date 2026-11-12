import AppKit
import Combine
import OrbMotionKit
import SwiftUI
import PlaygroundLocalization

@MainActor
public final class ProjectionSceneView: NSView {
    private let beam = ProjectionBeamView()
    private let fallbackHUD = CentralHUDView()
    private let drawsSkeleton: Bool
    public let dashboardView: HUDDashboardView?
    private var previousGeometry: ProjectionGeometry?
    private var previousConfig: ProjectionConfig?
    private var previousHue: Double?
    private var previousLanguage: PlaygroundLanguage?

    public override var isFlipped: Bool { true }
    public override var isOpaque: Bool { false }
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }
    public init(controller: ProjectionAnimationController? = nil, drawsSkeleton: Bool = true) {
        self.drawsSkeleton = drawsSkeleton
        dashboardView = controller.map { HUDDashboardView(controller: $0) }
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        layer?.addSublayer(beam.layer)
        if let dashboardView { addSubview(dashboardView) }
        else if drawsSkeleton { layer?.addSublayer(fallbackHUD.layer) }
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Decorative holographic projection")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    public func render(geometry: ProjectionGeometry, config: ProjectionConfig, orb: OrbParameters,
                       timeline: ProjectionTimeline, reducedMotion: Bool, language: PlaygroundLanguage = .english) {
        let p = config.sanitized
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if previousGeometry != geometry || previousConfig != p || previousHue != orb.hue || previousLanguage != language {
            let scale = window?.backingScaleFactor ?? 2
            beam.configure(size: geometry.visibleFrame.size, hue: orb.hue, scale: scale)
            if dashboardView == nil, drawsSkeleton {
                fallbackHUD.configure(geometry: geometry, config: p, hue: orb.hue, contentsScale: scale, language: language)
            }
            setAccessibilityLabel(language.text("Decorative holographic projection"))
            previousGeometry = geometry; previousConfig = p; previousHue = orb.hue
            previousLanguage = language
        }
        beam.render(geometry: geometry, config: p, timeline: timeline, reducedMotion: reducedMotion)
        if let dashboardView {
            dashboardView.language = language
            dashboardView.frame = CGRect(origin: .zero, size: geometry.visibleFrame.size)
            dashboardView.render(geometry: geometry, timeline: timeline, reducedMotion: reducedMotion)
        } else if drawsSkeleton { fallbackHUD.render(config: p, timeline: timeline, reducedMotion: reducedMotion) }
        CATransaction.commit()
    }
    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        previousGeometry = nil
    }
}

@MainActor
public final class ProjectionOrbInputView: NSView {
    public var language: PlaygroundLanguage = .english {
        didSet {
            guard language != oldValue else { return }
            orbView.language = language
            setAccessibilityLabel(language.text("Projection source orb"))
            setAccessibilityHelp(language.text("Hover to project. Move away to retract. Drag to either screen edge."))
        }
    }
    public let orbView = OrbLayerView()
    public var onHover: ((Bool) -> Void)?
    public var onDrag: ((CGPoint, Bool) -> Void)?
    public var diameter = 70.0
    private var pointerInside = false
    private var pointerTracking: NSTrackingArea?
    private var dragStart: CGPoint?
    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { false }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    public init() {
        super.init(frame: .zero)
        addSubview(orbView)
        setAccessibilityElement(true); setAccessibilityRole(.image)
        setAccessibilityLabel("Projection source orb")
        setAccessibilityHelp("Hover to project. Move away to retract. Drag to either screen edge.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    public override func layout() { super.layout(); orbView.frame = bounds }
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return ProjectionGeometry.containsOrb(local, in: bounds, diameter: diameter) ? self : nil
    }
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTracking { removeTrackingArea(pointerTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways,
            .mouseEnteredAndExited, .mouseMoved, .enabledDuringMouseDrag], owner: self)
        addTrackingArea(area); pointerTracking = area
    }
    public func evaluatePointer(at point: CGPoint) {
        let inside = ProjectionGeometry.containsOrb(point, in: bounds, diameter: diameter)
        guard inside != pointerInside else { return }
        pointerInside = inside; onHover?(inside)
    }
    public func clearPointerTracking() { pointerInside = false; dragStart = nil }
    public override func mouseEntered(with event: NSEvent) { evaluatePointer(at: convert(event.locationInWindow, from: nil)) }
    public override func mouseMoved(with event: NSEvent) { evaluatePointer(at: convert(event.locationInWindow, from: nil)) }
    public override func mouseExited(with event: NSEvent) {
        if dragStart == nil, pointerInside { pointerInside = false; onHover?(false) }
    }
    public override func mouseDown(with event: NSEvent) { dragStart = NSEvent.mouseLocation }
    public override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let point = NSEvent.mouseLocation
        onDrag?(CGPoint(x: point.x - dragStart.x, y: point.y - dragStart.y), false)
    }
    public override func mouseUp(with event: NSEvent) {
        guard let dragStart else { return }
        let point = NSEvent.mouseLocation
        onDrag?(CGPoint(x: point.x - dragStart.x, y: point.y - dragStart.y), true)
        self.dragStart = nil
        if let window { evaluatePointer(at: convert(window.convertPoint(fromScreen: point), from: nil)) }
    }
}

@MainActor
public struct ProjectionStage: NSViewRepresentable {
    @Environment(\.playgroundLanguage) private var language
    public let controller: ProjectionAnimationController
    public init(controller: ProjectionAnimationController) { self.controller = controller }
    public func makeCoordinator() -> Coordinator { Coordinator(controller) }
    public func makeNSView(context: Context) -> StageView {
        let view = StageView(controller: controller)
        context.coordinator.view = view
        return view
    }
    public func updateNSView(_ view: StageView, context: Context) { view.language = language; view.render() }
    public static func dismantleNSView(_ view: StageView, coordinator: Coordinator) {
        coordinator.subscriptions.removeAll(); view.stopInteraction(); coordinator.controller.clearPointer()
    }
    @MainActor
    public final class Coordinator {
        fileprivate let controller: ProjectionAnimationController
        fileprivate weak var view: StageView?
        fileprivate var subscriptions: Set<AnyCancellable> = []
        init(_ controller: ProjectionAnimationController) {
            self.controller = controller
            // Deliver after Published's willSet so the view can read the matching complete snapshot.
            controller.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.view?.render() }
                .store(in: &subscriptions)
        }
    }
    @MainActor
    public final class StageView: NSView {
        fileprivate var language: PlaygroundLanguage = .english
        private let controller: ProjectionAnimationController
        private let scene = ProjectionSceneView(drawsSkeleton: false)
        private let dashboard: HUDDashboardView
        private let source = ProjectionOrbInputView()
        private var geometry: ProjectionGeometry?
        private var interaction = HUDInteractionState()
        private var pointerTimer: Timer?
        private var pointerTracking: NSTrackingArea?
        private var transportSubscription: AnyCancellable?
        private var applyingPointerIntent = false
        public override var isFlipped: Bool { true }
        init(controller: ProjectionAnimationController) {
            self.controller = controller
            dashboard = HUDDashboardView(controller: controller)
            super.init(frame: .zero)
            addSubview(scene); addSubview(dashboard); addSubview(source)
            source.diameter = controller.orbParameters.diameter
            source.onHover = { [weak self] inside in
                self?.controller.trackSourcePointer(inside)
                self?.evaluatePointer()
            }
            dashboard.onHoverRegion = { [weak self] _ in self?.evaluatePointer() }
            dashboard.onAction = { [weak self] in
                guard let self else { return }
                self.interaction.engageHUD(); self.apply(.open)
            }
            transportSubscription = controller.$lastAction.sink { [weak self] action in
                guard let self, !self.applyingPointerIntent else { return }
                if action == "Retract" || action == "Reset" { self.interaction.manualClose() }
                else if action == "Expand" { self.interaction.manualOpen() }
                else if ["Scrubbed", "Pause", "Play", "Loop enabled", "Loop disabled", "Simulated entry", "Simulated exit"].contains(action) {
                    self.interaction.manualPlayback(progress: controller.timeline.progress)
                }
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        public override func layout() { super.layout(); scene.frame = bounds; dashboard.frame = bounds; render() }
        fileprivate func render() {
            guard bounds.width > 0, bounds.height > 0 else { return }
            let orb = controller.orbParameters
            let t = controller.timeline
            let g = ProjectionGeometry(visibleFrame: bounds, config: controller.config, orb: orb)
            geometry = g
            source.language = language
            source.frame = CGRect(x: g.orbFrame.minX, y: bounds.height - g.orbFrame.maxY,
                                  width: g.orbFrame.width, height: g.orbFrame.height)
            source.orbView.update(parameters: orb, progress: t.sample.orbActivation,
                                 ambientTime: t.ambientTime, rotorTime: t.rotorTime, reducedMotion: controller.reduceMotion)
            scene.render(geometry: g, config: controller.config, orb: orb, timeline: t, reducedMotion: controller.reduceMotion, language: language)
            dashboard.language = language
            dashboard.render(geometry: g, timeline: t, reducedMotion: controller.reduceMotion)
        }
        public override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let pointerTracking { removeTrackingArea(pointerTracking) }
            let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways,
                .mouseEnteredAndExited, .mouseMoved, .enabledDuringMouseDrag], owner: self)
            addTrackingArea(area); pointerTracking = area
        }
        public override func mouseEntered(with event: NSEvent) { evaluatePointer() }
        public override func mouseMoved(with event: NSEvent) { evaluatePointer() }
        public override func mouseExited(with event: NSEvent) { evaluatePointer() }

        fileprivate func stopInteraction() {
            pointerTimer?.invalidate(); pointerTimer = nil
            transportSubscription?.cancel(); transportSubscription = nil
        }

        private func evaluatePointer() {
            guard let window, let geometry else { return }
            let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            let layout = HUDLayout(visibleSize: bounds.size, config: controller.hud.config.sanitized)
            let sourceInside = ProjectionGeometry.containsOrb(point, in: source.frame, diameter: controller.orbParameters.diameter)
            let hudInside = dashboard.target(at: point) != nil
            var hudBounds = layout.coreFrame
            for frame in layout.moduleFrames.values { hudBounds = hudBounds.union(frame) }
            let region: HUDPointerRegion = sourceInside ? .source : hudInside ? .hud :
                HUDInteractionState.isInTransit(point, source: geometry.source, hudBounds: hudBounds) ? .transit : .outside
            controller.trackSourcePointer(sourceInside)
            let config = controller.hud.config.sanitized
            interaction.exitDelay = config.exitDelay; interaction.transitGrace = config.transitGrace
            if let intent = interaction.update(region: region, now: ProcessInfo.processInfo.systemUptime,
                                               progress: controller.timeline.progress), !controller.timeline.isLooping {
                apply(intent)
            }
            pointerTimer?.invalidate(); pointerTimer = nil
            if interaction.needsDeadline {
                let timer = Timer(timeInterval: 0.05, repeats: false) { [weak self] _ in self?.evaluatePointer() }
                pointerTimer = timer; RunLoop.main.add(timer, forMode: .common)
            }
        }

        private func apply(_ intent: HUDProjectionIntent) {
            applyingPointerIntent = true
            if intent == .open { controller.expand() } else { controller.retract() }
            applyingPointerIntent = false
        }
    }
}

struct ProjectionStage_Previews: PreviewProvider {
    @MainActor static var previews: some View {
        let controller = ProjectionAnimationController(orbParameters: OrbParameters())
        controller.scrub(to: 0.78)
        return ProjectionStage(controller: controller).frame(width: 900, height: 500)
            .background(Color(red: 0.02, green: 0.04, blue: 0.06))
    }
}
