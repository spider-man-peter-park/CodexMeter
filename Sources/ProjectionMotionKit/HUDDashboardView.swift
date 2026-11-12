import AppKit
import Combine
import QuartzCore
import PlaygroundLocalization

@MainActor
public final class HUDDashboardView: NSView {
    public var language: PlaygroundLanguage = .english { didSet { if oldValue != language { invalidateGeometry() } } }
    public var viewportOrigin: CGPoint = .zero { didSet { sceneRoot.frame.origin = CGPoint(x: -viewportOrigin.x, y: -viewportOrigin.y) } }
    public var renderedTarget: HUDTarget?
    public var drawsContent = true { didSet { sceneRoot.isHidden = !drawsContent } }
    public var onHoverRegion: ((Bool) -> Void)?
    public var onAction: (() -> Void)?
    public private(set) var dashboardLayout: HUDLayout?
    public let dashboard: HUDDashboardController
    private let sceneRoot = CALayer()
    private let core = CALayer()
    private let coreGlass = CAShapeLayer()
    private let coreHalo = CAShapeLayer()
    private let focal = CAGradientLayer()
    private let outer = CAShapeLayer()
    private let ticks = CAShapeLayer()
    private let rotor = CAShapeLayer()
    private let counterRotor = CAShapeLayer()
    private let dataRing = CAShapeLayer()
    private let memoryRing = CAShapeLayer()
    private let inner = CAShapeLayer()
    private let directional = CAShapeLayer()
    private let reticle = CAShapeLayer()
    private let dataPulse = CAShapeLayer()
    private let coreTitle = CATextLayer()
    private let coreValue = CATextLayer()
    private let coreSubtitle = CATextLayer()
    private let coreDetail = CATextLayer()
    private let coreAction = CATextLayer()
    private let fixtureLabel = CATextLayer()
    private var panels: [HUDModule: ModuleLayers] = [:]
    private var links: [HUDModule: CAShapeLayer] = [:]
    private var tracking: NSTrackingArea?
    private var subscription: AnyCancellable?
    private var geometry: ProjectionGeometry?
    private var lastTimeline: ProjectionTimeline?
    private var lastReducedMotion = false
    private var configured: HUDConfiguration?
    private var configuredLanguage: PlaygroundLanguage?
    private var displayedSnapshot: HUDDataSnapshot?
    private var dataBucket = -1
    private var stateStamp = ""
    private var decorativeTime = 0.0
    private var lastFlowTime: Double?

    public override var isFlipped: Bool { true }
    public override var isOpaque: Bool { false }
    public override var acceptsFirstResponder: Bool { true }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public init(dashboard: HUDDashboardController) {
        self.dashboard = dashboard
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = true
        layer?.addSublayer(sceneRoot)
        sceneRoot.addSublayer(coreHalo)
        for module in HUDModule.allCases {
            let link = CAShapeLayer()
            sceneRoot.addSublayer(link); links[module] = link
        }
        sceneRoot.addSublayer(core)
        for item in [coreGlass, outer, rotor, counterRotor, ticks, dataRing, memoryRing, inner, directional, reticle, dataPulse] { core.addSublayer(item) }
        core.addSublayer(focal)
        for item in [coreTitle, coreValue, coreSubtitle, coreDetail, coreAction] { core.addSublayer(item) }
        for module in HUDModule.allCases {
            let panel = ModuleLayers()
            panels[module] = panel
            sceneRoot.addSublayer(panel.root)
        }
        sceneRoot.addSublayer(fixtureLabel)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Interactive holographic dashboard")
        subscription = dashboard.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
            guard let self, let geometry = self.geometry, let timeline = self.lastTimeline else { return }
            self.render(geometry: geometry, timeline: timeline, reducedMotion: self.lastReducedMotion)
        }
    }

    public convenience init(controller: ProjectionAnimationController) { self.init(dashboard: controller.hud) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    public func target(at localPoint: CGPoint) -> HUDTarget? {
        guard let layout = dashboardLayout, let timeline = lastTimeline, timeline.progress >= 0.65 else { return nil }
        let point = CGPoint(x: localPoint.x + viewportOrigin.x, y: localPoint.y + viewportOrigin.y)
        guard let target = layout.target(at: point), renderedTarget == nil || target == renderedTarget else { return nil }
        if case .module(let module) = target {
            let index = HUDModule.allCases.firstIndex(of: module) ?? 0
            guard HUDGeneration(progress: timeline.progress, moduleIndex: index).border > 0.08 else { return nil }
        }
        return target
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return target(at: local) == nil ? nil : self
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let value = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved], owner: self)
        addTrackingArea(value); tracking = value
    }

    public func evaluatePointer(at point: CGPoint) {
        let target = target(at: point)
        onHoverRegion?(target != nil)
        guard let target, let layout = dashboardLayout else { dashboard.hover(nil); return }
        switch target {
        case .module(let module): dashboard.hover(module)
        case .core: dashboard.hover(layout.module(atCorePoint: CGPoint(x: point.x + viewportOrigin.x, y: point.y + viewportOrigin.y)))
        }
    }

    public override func mouseEntered(with event: NSEvent) { evaluatePointer(at: convert(event.locationInWindow, from: nil)) }
    public override func mouseMoved(with event: NSEvent) { evaluatePointer(at: convert(event.locationInWindow, from: nil)) }
    public override func mouseExited(with event: NSEvent) { dashboard.hover(nil); onHoverRegion?(false) }
    public override func mouseDown(with event: NSEvent) { performAction(at: convert(event.locationInWindow, from: nil)) }

    public func performAction(at point: CGPoint) {
        guard let target = target(at: point), let layout = dashboardLayout else { return }
        let global = CGPoint(x: point.x + viewportOrigin.x, y: point.y + viewportOrigin.y)
        switch target {
        case .core:
            if dashboard.expanded, global.y > layout.center.y + layout.coreFrame.height * 0.18 {
                dashboard.overview()
            } else if let module = layout.module(atCorePoint: global) {
                dashboard.select(module); dashboard.expandSelection()
            }
        case .module(.controls):
            guard let frame = layout.moduleFrames[.controls] else { return }
            let relative = (global.x - frame.minX) / frame.width
            if relative < 0.36 { dashboard.setDecorativeMotion(!dashboard.config.decorativeMotion) }
            else if relative < 0.7 {
                let values = HUDDensity.allCases
                let index = values.firstIndex(of: dashboard.config.density) ?? 0
                dashboard.config.density = values[(index + 1) % values.count]
            } else if dashboard.expanded { dashboard.overview() }
            else { dashboard.select(dashboard.selected ?? .performance); dashboard.expandSelection() }
        case .module(let module):
            dashboard.select(module); dashboard.expandSelection()
        }
        onAction?()
    }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { dashboard.overview(); onAction?() }
        else if event.charactersIgnoringModifiers == " " { dashboard.setDecorativeMotion(!dashboard.config.decorativeMotion); onAction?() }
        else { super.keyDown(with: event) }
    }

    public override func accessibilityPerformPress() -> Bool {
        guard let frame = renderedTarget.flatMap({ dashboardLayout?.frame(for: $0) }) ?? dashboardLayout?.coreFrame else { return false }
        performAction(at: CGPoint(x: frame.midX - viewportOrigin.x, y: frame.midY - viewportOrigin.y))
        return true
    }

    public func render(geometry: ProjectionGeometry, timeline: ProjectionTimeline, reducedMotion: Bool) {
        self.geometry = geometry; lastTimeline = timeline; lastReducedMotion = reducedMotion
        let configuration = dashboard.config.sanitized
        let layout = HUDLayout(visibleSize: geometry.visibleFrame.size, config: configuration)
        if !drawsContent {
            dashboardLayout = layout
            sceneRoot.isHidden = true
            if case .module(let module) = renderedTarget {
                setAccessibilityRole(.button); setAccessibilityLabel(title(module))
            }
            return
        }
        let changed = configured != configuration || configuredLanguage != language || dashboardLayout != layout
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if changed {
            dashboardLayout = layout; configured = configuration; configuredLanguage = language
            configure(layout: layout, configuration: configuration)
            displayedSnapshot = nil; dataBucket = -1
        }
        sceneRoot.isHidden = !drawsContent || timeline.progress <= 0.35
        let generation = HUDGeneration(progress: timeline.progress)
        let delta = lastFlowTime.map { max(0, timeline.flowTime - $0) } ?? 0
        lastFlowTime = timeline.flowTime
        if configuration.decorativeMotion && !reducedMotion && timeline.progress > 0.85 { decorativeTime += delta }
        core.opacity = Float(generation.core)
        coreGlass.opacity = Float(0.75 * generation.core)
        coreHalo.opacity = Float(generation.rings * configuration.glow * 0.62)
        focal.opacity = Float(generation.core * (dashboard.expanded ? 0.1 : 0.6))
        outer.strokeEnd = generation.rings
        inner.strokeEnd = generation.rings
        ticks.opacity = Float(generation.rings * configuration.decorationDensity)
        rotor.strokeEnd = generation.rings
        counterRotor.strokeEnd = generation.rings
        rotor.setAffineTransform(CGAffineTransform(rotationAngle: decorativeTime * configuration.clockwiseSpeed * .pi / 180))
        counterRotor.setAffineTransform(CGAffineTransform(rotationAngle: decorativeTime * configuration.counterclockwiseSpeed * .pi / 180))
        dataRing.strokeEnd = generation.rings * (dashboard.snapshot.cpuUsage ?? 0)
        if let used = dashboard.snapshot.memoryUsedBytes, let total = dashboard.snapshot.memoryTotalBytes, total > 0 {
            memoryRing.strokeEnd = generation.rings * min(1, Double(used) / Double(total))
        } else { memoryRing.strokeEnd = 0 }
        reticle.opacity = Float(generation.rings * (dashboard.expanded ? 0.08 : 0.55))
        let coreContent = timeline.sample.stage(0.54, 0.69)
        for text in [coreTitle, coreValue, coreSubtitle, coreDetail, coreAction] { text.opacity = Float(coreContent) }
        for (index, module) in HUDModule.allCases.enumerated() {
            guard let panel = panels[module], layout.moduleFrames[module] != nil else { continue }
            let build = HUDGeneration(progress: timeline.progress, moduleIndex: index)
            let disabled = configuration.disabledModules.contains(module)
            let subdued = dashboard.selected != nil && dashboard.selected != module && dashboard.expanded
            panel.root.opacity = Float(build.border * (disabled ? 0.34 : subdued ? 0.42 : 1))
            panel.border.strokeEnd = build.border
            panel.accent.strokeEnd = build.border
            panel.content.opacity = Float(build.content)
            panel.chart.strokeEnd = build.content
            panel.secondaryChart.strokeEnd = build.content
            links[module]?.strokeEnd = build.connector
            links[module]?.opacity = Float(build.connector * (subdued ? 0.2 : 0.65) * configuration.connectorIntensity)
            if !reducedMotion {
                let resting = layout.moduleFrames[module]!
                panel.root.setAffineTransform(CGAffineTransform(translationX: (layout.center.x - resting.midX) * (1 - build.border) * 0.08,
                                                                y: (layout.center.y - resting.midY) * (1 - build.border) * 0.06))
            } else { panel.root.setAffineTransform(.identity) }
        }
        fixtureLabel.opacity = Float(generation.rings)
        let stamp = "\(dashboard.hovered?.rawValue ?? "")/\(dashboard.selected?.rawValue ?? "")/\(dashboard.expanded)"
        let stateChanged = stamp != stateStamp
        if stateChanged { stateStamp = stamp; configureSelection(layout: layout, reducedMotion: reducedMotion) }
        if let displayedSnapshot, displayedSnapshot != dashboard.snapshot, timeline.progress >= 0.99,
           configuration.decorativeMotion, !reducedMotion {
            let pulse = CAKeyframeAnimation(keyPath: "opacity")
            pulse.values = [0, configuration.pulseAmplitude, 0]
            pulse.keyTimes = [0, 0.28, 1]
            pulse.duration = configuration.feedbackDuration
            dataPulse.add(pulse, forKey: "data-change")
        }
        let bucket = Int(timeline.progress * 100)
        if displayedSnapshot != dashboard.snapshot || dataBucket != bucket || stateChanged || changed {
            updateText(layout: layout, progress: timeline.progress)
            displayedSnapshot = dashboard.snapshot; dataBucket = bucket
        }
        CATransaction.commit()
    }

    private func invalidateGeometry() {
        configured = nil
        if let geometry, let lastTimeline { render(geometry: geometry, timeline: lastTimeline, reducedMotion: lastReducedMotion) }
    }

    private var cyan: NSColor { HUDDesignTokens.primaryCyan(hue: dashboard.config.hue) }
    private var white: NSColor { HUDDesignTokens.textPrimary }
    private var violet: NSColor { HUDDesignTokens.secondaryViolet }
    private var muted: NSColor { HUDDesignTokens.textSecondary }
    private var amber: NSColor { HUDDesignTokens.mockAmber }
    private var scale: Double { Double(window?.backingScaleFactor ?? 2) }

    private func configure(layout: HUDLayout, configuration: HUDConfiguration) {
        sceneRoot.frame = CGRect(x: -viewportOrigin.x, y: -viewportOrigin.y, width: layout.visibleSize.width, height: layout.visibleSize.height)
        core.frame = layout.coreFrame
        let center = CGPoint(x: core.bounds.midX, y: core.bounds.midY)
        let radius = core.bounds.width / 2
        coreHalo.frame = layout.coreFrame.insetBy(dx: -10, dy: -10)
        coreHalo.path = CGPath(ellipseIn: coreHalo.bounds.insetBy(dx: 8, dy: 8), transform: nil)
        coreHalo.fillColor = nil
        coreHalo.strokeColor = cyan.withAlphaComponent(0.18).cgColor
        coreHalo.lineWidth = 1
        coreHalo.shadowColor = cyan.cgColor
        coreHalo.shadowOpacity = 0
        coreHalo.shadowRadius = 0
        coreHalo.shadowOffset = .zero
        coreHalo.shadowPath = coreHalo.path
        let disk = CGPath(ellipseIn: core.bounds.insetBy(dx: 14, dy: 14), transform: nil)
        shape(coreGlass, frame: core.bounds, path: disk, color: cyan.withAlphaComponent(0.18), width: 0.5)
        coreGlass.fillColor = NSColor(calibratedRed: 0.018, green: 0.052, blue: 0.073, alpha: min(0.98, 0.52 + configuration.glassOpacity * 0.45)).cgColor
        shape(outer, frame: core.bounds, path: circle(center, radius * 0.99), color: cyan.withAlphaComponent(0.38), width: 0.7)
        shape(inner, frame: core.bounds, path: circle(center, radius * 0.73), color: cyan.withAlphaComponent(0.28), width: 0.65)
        let tickPath = CGMutablePath()
        for index in 0..<96 {
            let angle = Double(index) * .pi / 48
            let length = index.isMultiple(of: 8) ? 9.0 : index.isMultiple(of: 2) ? 4 : 2
            let r = radius * 0.91
            tickPath.move(to: CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r))
            tickPath.addLine(to: CGPoint(x: center.x + cos(angle) * (r - length), y: center.y + sin(angle) * (r - length)))
        }
        shape(ticks, frame: core.bounds, path: tickPath, color: cyan.withAlphaComponent(0.78), width: 0.8)
        let segments = CGMutablePath()
        for index in 0..<6 {
            let angle = Double(index) * .pi / 3
            segments.move(to: CGPoint(x: center.x + cos(angle + 0.02) * radius * 0.965,
                                      y: center.y + sin(angle + 0.02) * radius * 0.965))
            segments.addArc(center: center, radius: radius * 0.965, startAngle: angle + 0.02, endAngle: angle + 0.43, clockwise: false)
        }
        shape(rotor, frame: core.bounds, path: segments, color: cyan.withAlphaComponent(0.76), width: 2.2)
        let counter = CGMutablePath()
        for index in 0..<3 {
            let angle = Double(index) * .pi * 2 / 3
            counter.move(to: CGPoint(x: center.x + cos(angle) * radius * 0.76,
                                     y: center.y + sin(angle) * radius * 0.76))
            counter.addArc(center: center, radius: radius * 0.76, startAngle: angle, endAngle: angle + 0.62, clockwise: false)
        }
        shape(counterRotor, frame: core.bounds, path: counter, color: violet.withAlphaComponent(0.5), width: 1.1)
        let arc = CGMutablePath(); arc.addArc(center: center, radius: radius * 0.83, startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: false)
        shape(dataRing, frame: core.bounds, path: arc, color: white.withAlphaComponent(0.9), width: 2.4)
        let memory = CGMutablePath(); memory.addArc(center: center, radius: radius * 0.805, startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: false)
        shape(memoryRing, frame: core.bounds, path: memory, color: cyan.withAlphaComponent(0.32), width: 1.5)
        let cross = CGMutablePath()
        for index in 0..<4 {
            let angle = Double(index) * .pi / 2
            cross.move(to: CGPoint(x: center.x + cos(angle) * radius * 0.1, y: center.y + sin(angle) * radius * 0.1))
            cross.addLine(to: CGPoint(x: center.x + cos(angle) * radius * 0.23, y: center.y + sin(angle) * radius * 0.23))
        }
        shape(reticle, frame: core.bounds, path: cross, color: cyan.withAlphaComponent(0.6), width: 0.8)
        shape(dataPulse, frame: core.bounds, path: circle(center, radius * 0.82), color: white, width: 4)
        dataPulse.opacity = 0
        focal.frame = CGRect(x: center.x - 18, y: center.y - 18, width: 36, height: 36)
        radial(focal, colors: [white.withAlphaComponent(0.8), cyan.withAlphaComponent(0.22), .clear])
        for module in HUDModule.allCases {
            guard let panel = panels[module] else { continue }
            guard let frame = layout.moduleFrames[module] else { panel.root.isHidden = true; links[module]?.isHidden = true; continue }
            panel.root.isHidden = false; links[module]?.isHidden = false
            panel.root.transform = CATransform3DIdentity
            panel.root.frame = frame
            panel.content.frame = panel.root.bounds
            let linear = module == .activity || module == .controls
            let path = modulePath(panel.root.bounds, curved: module == .performance || module == .network,
                                  facesRight: frame.midX < layout.center.x)
            shape(panel.glass, frame: panel.root.bounds, path: path, color: .clear, width: 0)
            panel.glass.fillColor = NSColor(calibratedRed: 0.018, green: 0.043, blue: 0.062,
                                           alpha: linear ? 0.2 + configuration.glassOpacity * 0.25 : 0.6 + configuration.glassOpacity * 0.3).cgColor
            shape(panel.border, frame: panel.root.bounds, path: linear ? bracketPath(panel.root.bounds) : path,
                  color: cyan.withAlphaComponent(configuration.borderBrightness * (linear ? 0.52 : 0.72)), width: 0.7)
            shape(panel.feedback, frame: panel.root.bounds, path: path, color: module == .ai ? violet : cyan, width: 1.1)
            panel.feedback.opacity = 0
            let accent = CGMutablePath()
            accent.move(to: CGPoint(x: 15, y: 0)); accent.addLine(to: CGPoint(x: min(70, frame.width * 0.3), y: 0))
            shape(panel.accent, frame: panel.root.bounds, path: accent, color: module == .ai ? violet : cyan, width: 2)
            for text in panel.labels { text.contentsScale = scale }
            let target = CGPoint(x: frame.midX < layout.center.x ? frame.maxX : frame.minX, y: frame.midY)
            let angle = atan2(target.y - layout.center.y, target.x - layout.center.x)
            let link = CGMutablePath()
            link.move(to: CGPoint(x: layout.center.x + cos(angle) * radius, y: layout.center.y + sin(angle) * radius))
            link.addLine(to: CGPoint(x: target.x + (target.x < layout.center.x ? 16 : -16), y: target.y))
            link.addLine(to: target)
            if let line = links[module] { shape(line, frame: CGRect(origin: .zero, size: layout.visibleSize), path: link, color: cyan.withAlphaComponent(0.58), width: 0.7) }
        }
        fixtureLabel.contentsScale = scale
        fixtureLabel.frame = CGRect(x: layout.center.x - 200, y: 24, width: 400, height: 18)
        text(fixtureLabel, value: dashboard.snapshot.isFixture ? tr("FIXTURE · ALL METRICS SIMULATED", "演示快照 · 全部指标均为模拟") : "", size: 11, color: amber, alignment: .center)
        if case .module(let module) = renderedTarget {
            setAccessibilityRole(.button)
            setAccessibilityLabel(title(module))
        } else {
            setAccessibilityRole(renderedTarget == .core ? .button : .group)
            setAccessibilityLabel(tr("Interactive holographic dashboard", "可交互全息仪表盘"))
        }
        stateStamp = "invalid"
    }

    private func configureSelection(layout: HUDLayout, reducedMotion: Bool) {
        let selected = dashboard.selected, hovered = dashboard.hovered
        for module in HUDModule.allCases {
            guard let panel = panels[module] else { continue }
            let highlighted = hovered == module || selected == module
            let opacity: Float = highlighted ? (selected == module ? 0.9 : 0.55) : 0
            let from = panel.feedback.presentation()?.opacity ?? panel.feedback.opacity
            panel.feedback.opacity = opacity
            let animation = CASpringAnimation(keyPath: "opacity")
            animation.fromValue = from; animation.toValue = opacity
            animation.duration = reducedMotion ? 0.1 : hovered == module ? HUDDesignTokens.hoverDuration : dashboard.config.feedbackDuration
            animation.mass = 1
            animation.stiffness = pow(8 / max(0.1, animation.duration), 2)
            animation.damping = 2 * sqrt(animation.stiffness) * dashboard.config.feedbackDamping
            animation.initialVelocity = 0
            panel.feedback.add(animation, forKey: "interaction")
            links[module]?.lineWidth = highlighted ? 1.5 : 0.7
            links[module]?.strokeColor = (module == .ai && highlighted ? violet : cyan.withAlphaComponent(highlighted ? 0.95 : 0.58)).cgColor
        }
        let module = hovered ?? selected
        if let module, let frame = layout.moduleFrames[module] {
            let center = CGPoint(x: core.bounds.midX, y: core.bounds.midY)
            let angle = atan2(frame.midY - layout.center.y, frame.midX - layout.center.x)
            let path = CGMutablePath(); path.addArc(center: center, radius: core.bounds.width * 0.36, startAngle: angle - 0.22, endAngle: angle + 0.22, clockwise: false)
            shape(directional, frame: core.bounds, path: path, color: module == .ai ? violet : white, width: 3)
            directional.opacity = 0.95
            if !reducedMotion && dashboard.config.decorativeMotion && dashboard.config.scanSpeed > 0 {
                let scan = CABasicAnimation(keyPath: "strokeEnd")
                scan.fromValue = 0; scan.toValue = 1
                scan.duration = min(0.6, max(0.1, 6 / dashboard.config.scanSpeed))
                scan.timingFunction = CAMediaTimingFunction(name: .easeOut)
                directional.add(scan, forKey: "directional-scan")
            }
        } else { directional.opacity = 0 }
    }

    private func updateText(layout: HUDLayout, progress: Double) {
        let snapshot = dashboard.snapshot
        let radius = core.bounds.width / 2, center = CGPoint(x: radius, y: radius)
        let fontScale = min(1.3, max(0.9, dashboard.config.textScale))
        let expanded = dashboard.expanded && dashboard.selected != nil
        let chosen = dashboard.selected ?? .performance
        let coreY = expanded ? center.y - 52 : center.y - 58
        text(coreTitle, value: expanded ? title(chosen).uppercased() : tr("LOCAL SYSTEM", "本机系统"), size: 11 * fontScale, color: cyan, alignment: .center)
        coreTitle.frame = CGRect(x: 30, y: coreY, width: core.bounds.width - 60, height: 18)
        let main = expanded ? expandedValue(chosen) : tr("READY", "就绪")
        text(coreValue, value: main, size: (expanded ? 29 : 24) * fontScale, color: white, alignment: .center, weight: .light)
        coreValue.frame = CGRect(x: 28, y: center.y - 24, width: core.bounds.width - 56, height: 42)
        text(coreSubtitle, value: expanded ? expandedSubtitle(chosen) : tr("HOST TELEMETRY", "本机实时遥测"), size: 11 * fontScale, color: muted, alignment: .center)
        coreSubtitle.frame = CGRect(x: 24, y: center.y + 21, width: core.bounds.width - 48, height: 20)
        let footer = expanded ? expandedDetail(chosen) : "CPU \(percent(snapshot.cpuUsage))   ·   RAM \(memoryPercent())"
        text(coreDetail, value: footer, size: 11 * fontScale, color: white.withAlphaComponent(0.75), alignment: .center)
        coreDetail.frame = CGRect(x: 24, y: center.y + 43, width: core.bounds.width - 48, height: 20)
        text(coreAction, value: expanded ? tr("‹  Back to overview", "‹  返回总览") : tr("Select a ring sector", "选择圆环区域"), size: 11 * fontScale, color: expanded ? cyan : muted.withAlphaComponent(0.65), alignment: .center)
        coreAction.frame = CGRect(x: 24, y: center.y + 67, width: core.bounds.width - 48, height: 20)
        for (index, module) in HUDModule.allCases.enumerated() {
            guard let panel = panels[module], layout.moduleFrames[module] != nil else { continue }
            let width = panel.root.bounds.width, height = panel.root.bounds.height
            let local = HUDGeneration(progress: progress, moduleIndex: index).content
            let inwardCurve = (module == .performance || module == .network) && panel.root.frame.midX > layout.center.x
            let inset = inwardCurve ? 28.0 : 15.0
            let contentWidth = width - inset - 15
            let labels = panel.labels
            for item in labels { item.isHidden = false; item.string = "" }
            text(labels[0], value: title(module).uppercased(), size: 11 * fontScale, color: module == .ai ? violet : cyan, weight: .semibold)
            labels[0].frame = CGRect(x: inset, y: 12, width: width - 78, height: 17)
            let mock = snapshot.isFixture || module == .ai || module == .activity
            let disabled = dashboard.config.disabledModules.contains(module)
            let badge = disabled ? tr("DISABLED", "不可用") : mock ? "MOCK" : module == .controls ? "" : module == .network ?
                snapshot.networkConnected.map { $0 ? tr("ONLINE", "已连接") : tr("OFFLINE", "未连接") } ?? "—" : tr("LIVE", "实时")
            text(labels[1], value: badge, size: 9 * fontScale, color: mock ? amber : muted, alignment: .right)
            labels[1].frame = CGRect(x: width - 68, y: 13, width: 52, height: 15)
            panel.chart.path = nil; panel.secondaryChart.path = nil
            let bodyY = 35.0
            switch module {
            case .system:
                set(labels[2], snapshot.deviceName, x: inset, y: bodyY, width: contentWidth, height: 24, size: 17 * fontScale, color: white)
                set(labels[3], snapshot.osVersion, x: inset, y: bodyY + 27, width: contentWidth, height: 18, size: 11 * fontScale, color: muted)
                let uptime = uptimeString(snapshot.uptime)
                set(labels[4], tr("UPTIME", "运行时长") + "  " + uptime, x: inset, y: height - 39, width: contentWidth, height: 18, size: 11 * fontScale, color: white.withAlphaComponent(0.8))
                let formatter = DateFormatter(); formatter.locale = language.locale; formatter.dateFormat = "MM/dd  HH:mm:ss"
                set(labels[5], formatter.string(from: snapshot.date), x: inset, y: height - 22, width: contentWidth, height: 16, size: 10 * fontScale, color: muted)
            case .performance:
                set(labels[2], percent(snapshot.cpuUsage.map { $0 * local }), x: inset, y: bodyY, width: 100, height: 35, size: 27 * fontScale, color: white)
                set(labels[3], "CPU", x: inset + 104, y: bodyY + 13, width: width - inset - 110, height: 18, size: 11 * fontScale, color: muted)
                set(labels[4], tr("Memory", "内存") + "  " + memoryString(), x: inset, y: bodyY + 37, width: contentWidth, height: 18, size: 11 * fontScale, color: muted)
                chart(panel.chart, values: snapshot.cpuHistory, frame: CGRect(x: inset, y: height - 34, width: contentWidth, height: 19), color: cyan, maximum: 1)
                if snapshot.cpuHistory.isEmpty { set(labels[5], tr("Collecting local samples", "正在采集本机样本"), x: inset, y: height - 28, width: contentWidth, height: 18, size: 10 * fontScale, color: muted) }
            case .ai:
                set(labels[2], language.text(snapshot.mockAI.status), x: inset, y: bodyY, width: width - 30, height: 26, size: 20 * fontScale, color: white)
                set(labels[3], language.text(snapshot.mockAI.task), x: inset, y: bodyY + 28, width: width - 30, height: 18, size: 11 * fontScale, color: muted)
                set(labels[4], language.text(snapshot.mockAI.model), x: inset, y: height - 36, width: width - 30, height: 18, size: 10 * fontScale, color: violet.withAlphaComponent(0.9))
                set(labels[5], tr("Tokens", "令牌") + "  \(Int(Double(snapshot.mockAI.tokenUsage) * local))  ·  " + tr("simulated", "模拟"), x: inset, y: height - 20, width: width - 30, height: 16, size: 10 * fontScale, color: muted)
            case .network:
                set(labels[2], "↓ " + rate(snapshot.downloadBytesPerSecond.map { $0 * local }), x: inset, y: bodyY, width: contentWidth, height: 27, size: 19 * fontScale, color: white)
                set(labels[3], "↑ " + rate(snapshot.uploadBytesPerSecond.map { $0 * local }), x: inset, y: bodyY + 29, width: contentWidth, height: 19, size: 12 * fontScale, color: muted)
                let maximum = max(1, (snapshot.downloadHistory + snapshot.uploadHistory).max() ?? 1)
                let chartFrame = CGRect(x: inset, y: height - 31, width: contentWidth, height: 17)
                chart(panel.chart, values: snapshot.downloadHistory, frame: chartFrame, color: cyan, maximum: maximum)
                chart(panel.secondaryChart, values: snapshot.uploadHistory, frame: chartFrame, color: violet, maximum: maximum)
                if snapshot.networkConnected == false { set(labels[4], tr("Disconnected", "未连接"), x: inset, y: height - 23, width: width - 30, height: 16, size: 10 * fontScale, color: amber) }
            case .activity:
                for (eventIndex, event) in snapshot.activities.prefix(2).enumerated() {
                    set(labels[2 + eventIndex], "·  " + language.text(event.title), x: inset, y: bodyY + Double(eventIndex) * 20, width: width - 30, height: 18, size: 11 * fontScale, color: eventIndex == 0 ? white : muted)
                }
            case .controls:
                let third = (width - 30) / 3
                for (i, value) in [tr("Motion", "动态"), tr("Density", "密度"), expanded ? tr("Overview", "总览") : tr("Detail", "详情")].enumerated() {
                    set(labels[2 + i], value, x: inset + third * Double(i), y: bodyY + 2, width: third - 3, height: 18, size: 11 * fontScale, color: white)
                }
                set(labels[5], dashboard.config.decorativeMotion ? tr("Running", "运行") : tr("Paused", "暂停"), x: inset, y: bodyY + 24, width: third - 3, height: 17, size: 10 * fontScale, color: cyan)
                set(labels[6], language.text(dashboard.config.density.rawValue.capitalized), x: inset + third, y: bodyY + 24, width: third - 3, height: 17, size: 10 * fontScale, color: cyan)
                set(labels[7], "↗", x: inset + third * 2, y: bodyY + 24, width: third - 3, height: 17, size: 12 * fontScale, color: cyan)
            }
        }
    }

    private func title(_ module: HUDModule) -> String {
        guard language == .simplifiedChinese else { return module.title }
        switch module {
        case .system: return "系统"
        case .performance: return "性能"
        case .ai: return "AI"
        case .network: return "网络"
        case .activity: return "活动"
        case .controls: return "快捷控制"
        }
    }
    private func tr(_ english: String, _ chinese: String) -> String { language == .simplifiedChinese ? chinese : english }
    private func percent(_ value: Double?) -> String { value.map { String(format: "%.0f%%", min(1, max(0, $0)) * 100) } ?? "—" }
    private func memoryPercent() -> String {
        guard let used = dashboard.snapshot.memoryUsedBytes, let total = dashboard.snapshot.memoryTotalBytes, total > 0 else { return "—" }
        return percent(Double(used) / Double(total))
    }
    private func memoryString() -> String {
        guard let used = dashboard.snapshot.memoryUsedBytes, let total = dashboard.snapshot.memoryTotalBytes else { return "—" }
        return String(format: "%.1f / %.0f GiB", Double(used) / 1_073_741_824, Double(total) / 1_073_741_824)
    }
    private func rate(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value >= 1_048_576 { return String(format: "%.1f MiB/s", value / 1_048_576) }
        if value >= 1024 { return String(format: "%.0f KiB/s", value / 1024) }
        return String(format: "%.0f B/s", value)
    }
    private func uptimeString(_ interval: TimeInterval) -> String {
        let hours = Int(max(0, interval)) / 3600
        return language == .simplifiedChinese ? "\(hours / 24)天 \(hours % 24)小时" : "\(hours / 24)d \(hours % 24)h"
    }
    private func expandedValue(_ module: HUDModule) -> String {
        switch module {
        case .system: return uptimeString(dashboard.snapshot.uptime)
        case .performance: return percent(dashboard.snapshot.cpuUsage)
        case .ai: return language.text(dashboard.snapshot.mockAI.status)
        case .network: return rate(dashboard.snapshot.downloadBytesPerSecond)
        case .activity: return "\(dashboard.snapshot.activities.count)"
        case .controls: return dashboard.config.decorativeMotion ? tr("Running", "运行中") : tr("Paused", "已暂停")
        }
    }
    private func expandedSubtitle(_ module: HUDModule) -> String {
        switch module {
        case .system: return dashboard.snapshot.deviceName
        case .performance: return tr("CPU · native host statistics", "CPU · 原生系统统计")
        case .ai: return tr("Mock provider · no service connected", "模拟提供器 · 未连接服务")
        case .network: return tr("Download · local interfaces", "下载 · 本机网络接口")
        case .activity: return tr("Mock events", "模拟事件")
        case .controls: return tr("Decoration only", "仅控制装饰动态")
        }
    }
    private func expandedDetail(_ module: HUDModule) -> String {
        switch module {
        case .performance: return tr("Memory", "内存") + "  " + memoryString()
        case .network: return "↑ " + rate(dashboard.snapshot.uploadBytesPerSecond)
        case .ai: return tr("Mock tokens", "模拟令牌") + "  \(dashboard.snapshot.mockAI.tokenUsage)"
        case .system: return dashboard.snapshot.osVersion
        case .activity: return dashboard.snapshot.activities.first.map { language.text($0.title) } ?? "—"
        case .controls: return tr("Motion · density · overview", "动态 · 密度 · 总览")
        }
    }

    private func set(_ layer: CATextLayer, _ value: String, x: Double, y: Double, width: Double, height: Double, size: Double, color: NSColor) {
        layer.frame = CGRect(x: x, y: y, width: width, height: height)
        text(layer, value: value, size: size, color: color)
    }
    private func text(_ layer: CATextLayer, value: String, size: Double, color: NSColor, alignment: CATextLayerAlignmentMode = .left, weight: NSFont.Weight = .regular) {
        layer.string = value; layer.font = HUDDesignTokens.metricFont(size: size, weight: weight)
        layer.fontSize = size; layer.foregroundColor = color.cgColor; layer.alignmentMode = alignment
        layer.contentsScale = scale; layer.truncationMode = .end; layer.isWrapped = false
    }
    private func shape(_ layer: CAShapeLayer, frame: CGRect, path: CGPath, color: NSColor, width: Double) {
        layer.frame = frame; layer.path = path; layer.fillColor = nil; layer.strokeColor = color.cgColor
        layer.lineWidth = width; layer.lineCap = .round; layer.lineJoin = .round; layer.contentsScale = scale
    }
    private func circle(_ center: CGPoint, _ radius: Double) -> CGPath {
        CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2), transform: nil)
    }
    private func radial(_ gradient: CAGradientLayer, colors: [NSColor]) {
        gradient.type = .radial; gradient.startPoint = CGPoint(x: 0.5, y: 0.5); gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.colors = colors.map(\.cgColor); gradient.locations = [0, 0.43, 1]
    }
    private func modulePath(_ bounds: CGRect, curved: Bool, facesRight: Bool) -> CGPath {
        let path = CGMutablePath(), cut = HUDDesignTokens.moduleCornerCut
        path.move(to: CGPoint(x: cut, y: 0))
        if curved && facesRight {
            path.addLine(to: CGPoint(x: bounds.maxX, y: 0))
            path.addQuadCurve(to: CGPoint(x: bounds.maxX, y: bounds.maxY - cut),
                              control: CGPoint(x: bounds.maxX - 40, y: (bounds.maxY - cut) / 2))
        } else {
            path.addLine(to: CGPoint(x: bounds.maxX - 5, y: 0))
            path.addQuadCurve(to: CGPoint(x: bounds.maxX, y: 5), control: CGPoint(x: bounds.maxX, y: 0))
            path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY - cut))
        }
        path.addLine(to: CGPoint(x: bounds.maxX - cut, y: bounds.maxY))
        path.addLine(to: CGPoint(x: 5, y: bounds.maxY))
        path.addQuadCurve(to: CGPoint(x: 0, y: bounds.maxY - 5), control: CGPoint(x: 0, y: bounds.maxY))
        if curved && !facesRight { path.addQuadCurve(to: CGPoint(x: 0, y: cut), control: CGPoint(x: 40, y: (bounds.maxY - 5 + cut) / 2)) }
        else { path.addLine(to: CGPoint(x: 0, y: cut)) }
        path.closeSubpath(); return path
    }
    private func bracketPath(_ bounds: CGRect) -> CGPath {
        let path = CGMutablePath(), cut = HUDDesignTokens.moduleCornerCut
        path.move(to: CGPoint(x: 0, y: 35)); path.addLine(to: CGPoint(x: 0, y: cut))
        path.addLine(to: CGPoint(x: cut, y: 0)); path.addLine(to: CGPoint(x: bounds.width * 0.48, y: 0))
        path.move(to: CGPoint(x: bounds.maxX, y: bounds.maxY - 35))
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY - cut))
        path.addLine(to: CGPoint(x: bounds.maxX - cut, y: bounds.maxY))
        path.addLine(to: CGPoint(x: bounds.maxX - 72, y: bounds.maxY))
        return path
    }
    private func chart(_ layer: CAShapeLayer, values: [Double], frame: CGRect, color: NSColor, maximum: Double) {
        guard values.count > 1 else { layer.path = nil; return }
        let path = CGMutablePath()
        for (index, value) in values.enumerated() {
            let point = CGPoint(x: frame.minX + Double(index) / Double(values.count - 1) * frame.width,
                                y: frame.maxY - min(1, max(0, value / maximum)) * frame.height)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        shape(layer, frame: layer.superlayer?.bounds ?? .zero, path: path, color: color.withAlphaComponent(0.8), width: 1.15)
    }
}

@MainActor
private final class ModuleLayers {
    let root = CALayer()
    let glass = CAShapeLayer()
    let border = CAShapeLayer()
    let accent = CAShapeLayer()
    let feedback = CAShapeLayer()
    let content = CALayer()
    let chart = CAShapeLayer()
    let secondaryChart = CAShapeLayer()
    let labels = (0..<8).map { _ in CATextLayer() }
    init() {
        root.addSublayer(glass); root.addSublayer(border); root.addSublayer(accent); root.addSublayer(feedback); root.addSublayer(content)
        content.addSublayer(chart); content.addSublayer(secondaryChart)
        for label in labels { content.addSublayer(label) }
    }
}
