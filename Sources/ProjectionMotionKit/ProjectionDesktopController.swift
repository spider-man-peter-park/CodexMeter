import AppKit
import Combine
import OrbMotionKit
import PlaygroundLocalization

@MainActor
public final class ProjectionPanel: NSPanel {
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    public init(title: String, ignoresMouseEvents: Bool) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.title = title
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        hidesOnDeactivate = false; isReleasedWhenClosed = false
        isFloatingPanel = true
        // Keep the orb and instruments above the backdrop, including over system chrome.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.ignoresMouseEvents = ignoresMouseEvents
        acceptsMouseMovedEvents = !ignoresMouseEvents
    }
}

public struct ProjectionDisplay: Identifiable, Equatable {
    public let id: String
    public let name: String
}

@MainActor
public final class ProjectionDesktopController: ObservableObject {
    @Published public private(set) var enabled = true
    @Published public private(set) var displays: [ProjectionDisplay] = []
    @Published public private(set) var selectedDisplay = "auto"
    @Published public private(set) var sourceVisible = false
    @Published public private(set) var projectionVisible = false
    @Published public private(set) var onActiveSpace = false
    @Published public private(set) var interactionPhase: HUDInteractionPhase = .idle
    @Published public private(set) var inspectionActive = false
    public let sourcePanel = ProjectionPanel(title: "Projection source orb", ignoresMouseEvents: false)
    public let projectionPanel = ProjectionPanel(title: "Holographic projection", ignoresMouseEvents: true)
    public let backdropPanel = ProjectionPanel(title: "Projection backdrop", ignoresMouseEvents: true)
    private let backdropView = ProjectionBackdropView()
    private var backdropConfig = ProjectionBackdropConfiguration()
    private let sourceView = ProjectionOrbInputView()
    private let scene: ProjectionSceneView
    private let controller: ProjectionAnimationController
    private var subscriptions = Set<AnyCancellable>()
    private var notifications: [(NotificationCenter, NSObjectProtocol)] = []
    private var currentScreen: NSScreen?
    private var geometry: ProjectionGeometry?
    private var config: ProjectionConfig
    private var timeline: ProjectionTimeline
    private var reducedMotion = false
    private var running = false
    private var asleep = false
    private var appHidden = false
    private var dragBase: CGRect?
    private var language: PlaygroundLanguage = .english
    private var interaction = HUDInteractionState()
    private var pointerTimer: Timer?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var applyingPointerIntent = false
    private var enabledBeforeInspection: Bool?
    private var inputSurfaces: [HUDTarget: InputSurface] = [:]

    @MainActor private final class InputSurface {
        let panel: ProjectionPanel
        let view: HUDDashboardView
        init(target: HUDTarget, controller: ProjectionAnimationController) {
            panel = ProjectionPanel(title: "HUD interaction", ignoresMouseEvents: true)
            view = HUDDashboardView(controller: controller)
            view.renderedTarget = target
            view.drawsContent = false
            panel.contentView = view
        }
    }

    public var interactivePanels: [ProjectionPanel] { inputSurfaces.values.map(\.panel) }

    public init(controller: ProjectionAnimationController) {
        self.controller = controller
        scene = ProjectionSceneView(controller: controller)
        config = controller.config
        timeline = controller.timeline
        sourcePanel.contentView = sourceView
        projectionPanel.contentView = scene
        backdropPanel.level = .statusBar
        backdropPanel.contentView = backdropView
        sourceView.diameter = controller.orbParameters.diameter
        sourceView.onHover = { [weak self] inside in
            self?.controller.trackSourcePointer(inside)
            self?.evaluateDesktopPointer()
        }
        sourceView.onDrag = { [weak self] in self?.drag(offset: $0, ended: $1) }
        controller.$config.removeDuplicates().sink { [weak self] value in
            guard let self else { return }
            self.config = value.sanitized
            if self.running { self.arrange(); self.render() }
        }.store(in: &subscriptions)
        controller.$timeline.sink { [weak self] value in self?.timeline = value; self?.render() }
            .store(in: &subscriptions)
        controller.$backdropConfig.removeDuplicates().sink { [weak self] value in
            guard let self else { return }
            self.backdropConfig = value.sanitized
            self.backdropView.configure(self.backdropConfig)
            self.render()
        }.store(in: &subscriptions)
        controller.$reduceMotion.sink { [weak self] value in self?.reducedMotion = value; self?.render() }
            .store(in: &subscriptions)
        controller.$lastAction.sink { [weak self] action in
            guard let self, !self.applyingPointerIntent else { return }
            if action == "Retract" || action == "Reset" { self.interaction.manualClose() }
            else if action == "Expand" { self.interaction.manualOpen() }
            else if ["Scrubbed", "Pause", "Play", "Loop enabled", "Loop disabled", "Simulated entry", "Simulated exit"].contains(action) {
                self.interaction.manualPlayback(progress: self.timeline.progress)
            }
            self.publishInteraction()
        }.store(in: &subscriptions)
        controller.hud.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in
            guard let self, self.running else { return }
            self.arrangeInputSurfaces(); self.render()
        }.store(in: &subscriptions)
    }

    public func start() {
        guard !running else { return }
        running = true
        installMouseTracking()
        updateDisplays()
        arrange()
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { $0.updateDisplays(); $0.arrange() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification) { $0.asleep = true; $0.updateSuspension() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification) { $0.asleep = false; $0.updateSuspension(); $0.arrange() }
        observe(NotificationCenter.default, NSApplication.didHideNotification) { $0.appHidden = true; $0.updateSuspension() }
        observe(NotificationCenter.default, NSApplication.didUnhideNotification) { $0.appHidden = false; $0.updateSuspension() }
        controller.start()
        render()
    }
    public func setLanguage(_ value: PlaygroundLanguage) {
        language = value
        sourcePanel.title = value.text("Projection source orb")
        projectionPanel.title = value.text("Holographic projection")
        backdropPanel.title = value.text("Projection backdrop")
        sourceView.language = value
        render()
    }
    public func stop() {
        running = false
        removeMouseTracking()
        controller.stop(); controller.clearPointer(); sourceView.clearPointerTracking()
        sourcePanel.orderOut(nil); projectionPanel.orderOut(nil); backdropPanel.orderOut(nil)
        hideInputSurfaces()
        interaction = HUDInteractionState(); publishInteraction()
        updateWindowState()
        for (center, token) in notifications { center.removeObserver(token) }
        notifications.removeAll()
    }
    public func setEnabled(_ value: Bool) {
        if inspectionActive {
            enabledBeforeInspection = value
            return
        }
        enabled = value
        controller.clearPointer(); sourceView.clearPointerTracking()
        if value { arrange(); render() }
        else {
            sourcePanel.orderOut(nil); projectionPanel.orderOut(nil); backdropPanel.orderOut(nil); hideInputSurfaces()
            pointerTimer?.invalidate(); pointerTimer = nil
            interaction = HUDInteractionState(); publishInteraction(); updateWindowState()
        }
    }
    public func setInspectionActive(_ value: Bool) {
        guard inspectionActive != value else { return }
        if value {
            enabledBeforeInspection = enabled
            setEnabled(false)
            inspectionActive = true
        } else {
            let restore = enabledBeforeInspection ?? enabled
            enabledBeforeInspection = nil
            inspectionActive = false
            setEnabled(restore)
        }
    }
    public func selectDisplay(_ value: String) {
        selectedDisplay = value
        currentScreen = nil
        arrange(); render()
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ action: @escaping (ProjectionDesktopController) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }; action(self)
        }
        notifications.append((center, token))
    }
    private func updateSuspension() {
        controller.suspend(asleep || appHidden)
        if asleep || appHidden {
            sourcePanel.orderOut(nil); projectionPanel.orderOut(nil); backdropPanel.orderOut(nil); hideInputSurfaces()
            pointerTimer?.invalidate(); pointerTimer = nil
            updateWindowState()
        }
        else { arrange(); render() }
    }
    private func updateDisplays() {
        displays = NSScreen.screens.map { ProjectionDisplay(id: Self.id($0), name: $0.localizedName) }
        if selectedDisplay != "auto", !displays.contains(where: { $0.id == selectedDisplay }) { selectedDisplay = "auto" }
        if let currentScreen, !NSScreen.screens.contains(where: { Self.id($0) == Self.id(currentScreen) }) { self.currentScreen = nil }
    }
    private static func id(_ screen: NSScreen) -> String {
        String((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0)
    }
    private func arrange() {
        guard running, !asleep, !appHidden else { return }
        let screen = NSScreen.screens.first(where: { Self.id($0) == selectedDisplay }) ?? currentScreen
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        guard let screen else { return }
        currentScreen = screen
        let g = ProjectionGeometry(visibleFrame: screen.visibleFrame, config: config, orb: controller.orbParameters)
        geometry = g
        let moved = sourcePanel.frame != g.orbFrame
        sourcePanel.setFrame(g.orbFrame, display: true)
        projectionPanel.setFrame(g.visibleFrame, display: true)
        backdropPanel.setFrame(screen.frame, display: true)
        scene.frame = CGRect(origin: .zero, size: g.visibleFrame.size)
        if moved { sourceView.clearPointerTracking(); controller.clearPointer() }
        arrangeInputSurfaces()
        if enabled { sourcePanel.orderFrontRegardless() }
        updateWindowState()
    }
    private func render() {
        guard running, enabled, !asleep, !appHidden, let geometry else { return }
        sourceView.orbView.update(parameters: controller.orbParameters, progress: timeline.sample.orbActivation,
                                 ambientTime: timeline.ambientTime, rotorTime: timeline.rotorTime, reducedMotion: reducedMotion)
        let backdropOpacity = CGFloat(backdropConfig.opacity(at: timeline.progress))
        if backdropOpacity > 0 {
            if backdropPanel.alphaValue != backdropOpacity { backdropPanel.alphaValue = backdropOpacity }
            if !backdropPanel.isVisible { backdropPanel.orderFrontRegardless() }
        } else if backdropPanel.isVisible { backdropPanel.orderOut(nil) }
        if timeline.sample.beamExtension > 0 {
            if !projectionPanel.isVisible { projectionPanel.orderFrontRegardless() }
            scene.render(geometry: geometry, config: config, orb: controller.orbParameters, timeline: timeline, reducedMotion: reducedMotion, language: language)
        } else if projectionPanel.isVisible { projectionPanel.orderOut(nil) }
        renderInputSurfaces(geometry)
        if timeline.progress <= 0, controller.hud.selected != nil { controller.hud.overview() }
        publishInteraction()
        updateWindowState()
    }

    private func arrangeInputSurfaces() {
        guard running, let geometry else { return }
        let layout = HUDLayout(visibleSize: geometry.visibleFrame.size, config: controller.hud.config.sanitized)
        let frames = layout.interactionFrames
        for target in Array(inputSurfaces.keys) where frames[target] == nil {
            inputSurfaces.removeValue(forKey: target)?.panel.orderOut(nil)
        }
        for (target, frame) in frames {
            let surface: InputSurface
            if let existing = inputSurfaces[target] { surface = existing }
            else {
                surface = InputSurface(target: target, controller: controller)
                surface.view.onHoverRegion = { [weak self] _ in self?.evaluateDesktopPointer() }
                surface.view.onAction = { [weak self] in self?.engageHUD() }
                inputSurfaces[target] = surface
            }
            surface.view.viewportOrigin = frame.origin
            let screenFrame = Self.screenFrame(for: frame, visibleFrame: geometry.visibleFrame)
            if surface.panel.frame != screenFrame { surface.panel.setFrame(screenFrame, display: true) }
            surface.view.frame = CGRect(origin: .zero, size: frame.size)
        }
    }

    nonisolated public static func screenFrame(for localFrame: CGRect, visibleFrame: CGRect) -> CGRect {
        CGRect(x: visibleFrame.minX + localFrame.minX, y: visibleFrame.maxY - localFrame.maxY,
               width: localFrame.width, height: localFrame.height)
    }

    private func isInteractive(_ target: HUDTarget) -> Bool {
        switch target {
        case .core: return HUDGeneration(progress: timeline.progress).rings > 0.2
        case .module(let module):
            let index = HUDModule.allCases.firstIndex(of: module) ?? 0
            return HUDGeneration(progress: timeline.progress, moduleIndex: index).content > 0.1
        }
    }

    private func renderInputSurfaces(_ geometry: ProjectionGeometry) {
        guard timeline.progress > 0.5 else { hideInputSurfaces(); return }
        let pointer = NSEvent.mouseLocation
        for (target, surface) in inputSurfaces {
            surface.view.language = language
            surface.view.render(geometry: geometry, timeline: timeline, reducedMotion: reducedMotion)
            let visible = isInteractive(target)
            if visible {
                if !surface.panel.isVisible { surface.panel.orderFrontRegardless() }
                let local = localPoint(pointer, in: surface.panel)
                surface.panel.ignoresMouseEvents = surface.view.target(at: local) != target
            } else {
                surface.panel.ignoresMouseEvents = true
                if surface.panel.isVisible { surface.panel.orderOut(nil) }
            }
        }
    }

    private func hideInputSurfaces() {
        for surface in inputSurfaces.values {
            surface.panel.ignoresMouseEvents = true
            surface.panel.orderOut(nil)
        }
    }

    private func localPoint(_ point: CGPoint, in panel: NSPanel) -> CGPoint {
        CGPoint(x: point.x - panel.frame.minX, y: panel.frame.maxY - point.y)
    }

    private func installMouseTracking() {
        guard globalMouseMonitor == nil, localMouseMonitor == nil else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            self?.evaluateDesktopPointer()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.evaluateDesktopPointer()
            return event
        }
    }

    private func removeMouseTracking() {
        pointerTimer?.invalidate(); pointerTimer = nil
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        globalMouseMonitor = nil; localMouseMonitor = nil
    }

    private func evaluateDesktopPointer() {
        guard running, enabled, !asleep, !appHidden, let geometry else { return }
        let point = NSEvent.mouseLocation
        let local = CGPoint(x: point.x - geometry.visibleFrame.minX, y: geometry.visibleFrame.maxY - point.y)
        let sourceInside = ProjectionGeometry.containsOrb(point, in: geometry.orbFrame, diameter: controller.orbParameters.diameter)
        let layout = HUDLayout(visibleSize: geometry.visibleFrame.size, config: controller.hud.config.sanitized)
        let target = layout.target(at: local)
        let hudInside = target.map(isInteractive) ?? false
        var hudBounds = layout.coreFrame
        for frame in layout.moduleFrames.values { hudBounds = hudBounds.union(frame) }
        let region: HUDPointerRegion = sourceInside ? .source : hudInside ? .hud :
            HUDInteractionState.isInTransit(local, source: geometry.source, hudBounds: hudBounds) ? .transit : .outside
        controller.trackSourcePointer(sourceInside)
        for (target, surface) in inputSurfaces {
            surface.panel.ignoresMouseEvents = !isInteractive(target) || surface.view.target(at: localPoint(point, in: surface.panel)) != target
        }
        evaluatePointerRegion(region)
    }

    public func evaluatePointerRegion(_ region: HUDPointerRegion, now: Double = ProcessInfo.processInfo.systemUptime) {
        let p = controller.hud.config.sanitized
        interaction.exitDelay = p.exitDelay; interaction.transitGrace = p.transitGrace
        let intent = interaction.update(region: region, now: now, progress: timeline.progress)
        if !timeline.isLooping, let intent {
            applyingPointerIntent = true
            if intent == .open { controller.expand() } else { controller.retract() }
            applyingPointerIntent = false
        }
        publishInteraction()
        schedulePointerDeadline()
    }

    private func engageHUD() {
        interaction.engageHUD()
        applyingPointerIntent = true
        controller.expand()
        applyingPointerIntent = false
        publishInteraction()
        schedulePointerDeadline()
    }

    private func schedulePointerDeadline() {
        pointerTimer?.invalidate(); pointerTimer = nil
        guard running, enabled, !asleep, !appHidden,
              interaction.needsDeadline,
              interaction.phase == .opening || interaction.phase == .previewing else { return }
        let timer = Timer(timeInterval: 0.05, repeats: false) { [weak self] _ in self?.evaluateDesktopPointer() }
        pointerTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func publishInteraction() {
        var value = interaction.phase
        if timeline.progress <= 0, value == .closing { value = .idle }
        if timeline.progress >= 1, value == .opening { value = .previewing }
        if interactionPhase != value { interactionPhase = value }
    }
    private func updateWindowState() {
        let source = sourcePanel.isVisible
        let projection = projectionPanel.isVisible
        let active = source && sourcePanel.isOnActiveSpace && (!projection || projectionPanel.isOnActiveSpace)
        if sourceVisible != source { sourceVisible = source }
        if projectionVisible != projection { projectionVisible = projection }
        if onActiveSpace != active { onActiveSpace = active }
    }
    private func drag(offset: CGPoint, ended: Bool) {
        guard let screen = currentScreen else { return }
        if dragBase == nil { dragBase = sourcePanel.frame }
        guard let dragBase else { return }
        let visible = screen.visibleFrame
        var frame = dragBase.offsetBy(dx: offset.x, dy: offset.y)
        frame.origin.x = min(visible.maxX - frame.width, max(visible.minX, frame.minX))
        frame.origin.y = min(visible.maxY - frame.height, max(visible.minY, frame.minY))
        if ended {
            self.dragBase = nil
            var p = config
            p.edge = frame.midX < visible.midX ? .left : .right
            p.verticalPosition = (frame.midY - visible.minY) / visible.height
            controller.config = p
        } else {
            sourcePanel.setFrame(frame, display: true)
            geometry = ProjectionGeometry(visibleFrame: visible, config: config, orb: controller.orbParameters, orbFrame: frame)
            render()
        }
    }
}
