import AppKit
import Combine
import CodexMeterCore
import OrbMotionKit
import PlaygroundLocalization
import ProjectionMotionKit
import SwiftUI

@MainActor private final class FloatingHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor private final class FloatingHUDTrackingView<Content: View>: NSHostingView<Content> {
    var onPointer: (() -> Void)?
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { onPointer?() }
    override func mouseExited(with event: NSEvent) { onPointer?() }
    override func mouseMoved(with event: NSEvent) { onPointer?() }
}

@MainActor final class FloatingHUDPresentation: ObservableObject {
    @Published var layout: FloatingHUDLayout
    @Published var expanded = false
    @Published var visible = false
    @Published var clickSequence = 0

    init(layout: FloatingHUDLayout) { self.layout = layout }
}

@MainActor final class FloatingHUDController {
    private let model: AppModel
    private let defaults: UserDefaults
    private let orbPanel: FloatingHUDPanel
    private let dashboardPanel: FloatingHUDPanel
    private let beamPanel: FloatingHUDPanel
    private let backdropPanel: FloatingHUDPanel
    private let backdropView = ProjectionBackdropView()
    private let beamScene = ProjectionSceneView(drawsSkeleton: false)
    private let dashboardScene: HUDDashboardView
    private let projection: ProjectionAnimationController
    private let profile: FloatingHUDProjectionProfile
    private var projectedGeometry: FloatingHUDProjectionGeometry?
    private var timeline = ProjectionTimeline()
    private var subscriptions = Set<AnyCancellable>()
    private var lifecycleObservations: [(NotificationCenter, NSObjectProtocol)] = []
    private var suspended = false
    private let presentation: FloatingHUDPresentation
    private var orb: NSRect
    private var interaction = FloatingHUDInteraction()
    private var visible = false
    private var stopped = false
    private var dashboardPreviewOnly = false
    private var pointerRetained = false
    private var menuTracking = false
    private var suppressHoverUntilExit = false
    private var collapseTask: Task<Void, Never>?
    private var screenObservation: NSObjectProtocol?
    private var localPointerMonitor: Any?
    private var globalPointerMonitor: Any?
    private var dragOrigin: NSRect?

    init(model: AppModel, usage: AssistantUsageStore, defaults: UserDefaults = .standard,
         onOpenMetric: @escaping (MenuBarMetric) -> Void,
         onOpenWorkspace: @escaping () -> Void, onOpenSettings: @escaping () -> Void,
         onHide: @escaping () -> Void) {
        self.model = model
        self.defaults = defaults
        let profile = FloatingHUDProjectionProfile.loadBundled() ?? FloatingHUDProjectionProfile()
        self.profile = profile
        let provider = FloatingHUDDataProvider(model: model, usage: usage)
        projection = ProjectionAnimationController(orbParameters: OrbParameters(), dataProvider: provider,
            initialSnapshot: provider.sample(modules: Set(HUDModule.allCases), now: model.now))
        projection.config = profile.projection
        projection.backdropConfig = profile.backdrop
        projection.hud.config = profile.hud
        dashboardScene = HUDDashboardView(controller: projection)
        dashboardScene.interactionEnabled = false
        let fallback = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let x = CGFloat(defaults.object(forKey: "floatingHUDOrbX") as? Double ?? Double(fallback.maxX - 92))
        let y = CGFloat(defaults.object(forKey: "floatingHUDOrbY") as? Double ?? Double(fallback.midY - FloatingHUDGeometry.orbSize / 2))
        let proposed = NSRect(x: x, y: y, width: FloatingHUDGeometry.orbSize, height: FloatingHUDGeometry.orbSize)
        let screen = FloatingHUDGeometry.screen(for: proposed, among: NSScreen.screens.map(\.visibleFrame), fallback: fallback)
        orb = FloatingHUDGeometry.snappedOrb(proposed, on: screen)
        presentation = FloatingHUDPresentation(layout: FloatingHUDGeometry.layout(orb: orb, on: screen, expanded: false))
        orbPanel = Self.makePanel(frame: orb, title: L10n.text("Floating HUD"))
        dashboardPanel = Self.makePanel(frame: screen, title: L10n.text("Projected dashboard"))
        dashboardPanel.ignoresMouseEvents = true
        beamPanel = Self.makePanel(frame: screen, title: L10n.text("HUD projection light"))
        beamPanel.ignoresMouseEvents = true
        backdropPanel = Self.makePanel(frame: screen, title: L10n.text("Projection backdrop"))
        backdropPanel.level = .statusBar
        backdropPanel.ignoresMouseEvents = true
        backdropView.configure(profile.backdrop)
        backdropPanel.contentView = backdropView
        let orbView = FloatingHUDOrbView(model: model, presentation: presentation,
            onExpand: { [weak self] in self?.pressOrb() },
            onDragStart: { [weak self] in self?.beginDrag() },
            onDrag: { [weak self] offset in self?.drag(by: offset) },
            onDragEnd: { [weak self] in self?.endDrag() },
            onOpenWorkspace: { [weak self] in
                self?.dismissProjectionForAction()
                onOpenWorkspace()
            },
            onOpenSettings: { [weak self] in
                self?.dismissProjectionForAction()
                onOpenSettings()
            },
            onRefresh: model.refresh, onHide: onHide,
            onMenuTrackingChanged: { [weak self] tracking in self?.setMenuTracking(tracking) })
        let orbHost = FloatingHUDTrackingView(rootView: orbView)
        orbHost.onPointer = { [weak self] in self?.updatePointer() }
        Self.install(orbHost, in: orbPanel)
        dashboardPanel.contentView = dashboardScene
        beamPanel.contentView = beamScene
        projection.$timeline.sink { [weak self] timeline in
            self?.timeline = timeline
            self?.renderProjection()
        }.store(in: &subscriptions)
        model.$language.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.projection.hud.refresh(); self?.renderProjection() }
        }.store(in: &subscriptions)
        model.$provider.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.projection.hud.refresh() }
        }.store(in: &subscriptions)
        screenObservation = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reposition(snap: true) }
            }
        observeLifecycle(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification) { $0.setSuspended(true) }
        observeLifecycle(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification) { $0.setSuspended(false) }
        observeLifecycle(NotificationCenter.default, NSApplication.didHideNotification) { $0.setSuspended(true) }
        observeLifecycle(NotificationCenter.default, NSApplication.didUnhideNotification) { $0.setSuspended(false) }
        observeLifecycle(NSWorkspace.shared.notificationCenter, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) {
            $0.projection.setReduceMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            $0.renderProjection()
        }
    }

    deinit {
        collapseTask?.cancel()
        if let screenObservation { NotificationCenter.default.removeObserver(screenObservation) }
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
        if let globalPointerMonitor { NSEvent.removeMonitor(globalPointerMonitor) }
        for (center, token) in lifecycleObservations { center.removeObserver(token) }
    }

    private static func makePanel(frame: NSRect, title: String) -> FloatingHUDPanel {
        let panel = FloatingHUDPanel(contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = title
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.isExcludedFromWindowsMenu = true
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }

    private static func install<Content: View>(_ host: NSHostingView<Content>, in panel: NSPanel) {
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
    }

    func setVisible(_ value: Bool) {
        guard !stopped else { return }
        visible = value
        presentation.visible = value
        if value {
            projection.setReduceMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            projection.start()
            reposition(snap: true)
            orbPanel.orderFrontRegardless()
            writePreviewGeometryReport(stage: "initial")
        } else {
            collapseTask?.cancel()
            pointerRetained = false
            interaction.setExpanded(false)
            presentation.expanded = false
            model.setFloatingHUDExpanded(false)
            projection.stop()
            projection.reset()
            updateDashboardMouseEvents()
            removePointerMonitors()
            for panel in [beamPanel, dashboardPanel, backdropPanel, orbPanel] { panel.orderOut(nil) }
        }
    }

    func setExpanded(_ expanded: Bool) {
        guard visible, !stopped else { return }
        collapseTask?.cancel()
        if !expanded { pointerRetained = false }
        interaction.setExpanded(expanded)
        applyExpansion(reveal: expanded && !presentation.expanded)
    }

    func showDashboardForPreview() {
        guard CommandLine.arguments.contains("--ui-preview-fixtures"),
              CommandLine.arguments.contains("--ui-preview-dashboard-only"), visible, !stopped else { return }
        dashboardPreviewOnly = true
        collapseTask?.cancel()
        removePointerMonitors()
        pointerRetained = true
        setExpanded(true)
        projection.scrub(to: 1)
        orbPanel.orderOut(nil)
        beamPanel.orderOut(nil)
        backdropPanel.orderOut(nil)
        dashboardPanel.orderFrontRegardless()
    }

    func stop() {
        guard !stopped else { return }
        setVisible(false)
        stopped = true
        if let screenObservation { NotificationCenter.default.removeObserver(screenObservation) }
        screenObservation = nil
        subscriptions.removeAll()
        for (center, token) in lifecycleObservations { center.removeObserver(token) }
        lifecycleObservations.removeAll()
        for panel in [beamPanel, dashboardPanel, backdropPanel, orbPanel] {
            panel.contentView = nil
            panel.close()
        }
    }

    private func installPointerMonitors() {
        guard !dashboardPreviewOnly, localPointerMonitor == nil, globalPointerMonitor == nil else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.pointerEvent(event)
            return event
        }
        globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            self?.pointerEvent(event)
        }
    }

    private func removePointerMonitors() {
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
        if let globalPointerMonitor { NSEvent.removeMonitor(globalPointerMonitor) }
        localPointerMonitor = nil
        globalPointerMonitor = nil
    }

    private func pressOrb() {
        presentation.clickSequence &+= 1
        setExpanded(true)
    }

    private func dismissProjectionForAction() {
        suppressHoverUntilExit = true
        setExpanded(false)
    }

    private func setMenuTracking(_ tracking: Bool) {
        menuTracking = tracking
        collapseTask?.cancel()
        if tracking {
            pointerRetained = true
        } else if visible {
            pointerRetained = !(projectedGeometry?.containsRetentionPoint(NSEvent.mouseLocation) ?? false)
            updatePointer()
        }
    }

    private func pointerEvent(_ event: NSEvent) {
        guard visible, !suspended, interaction.expanded, !menuTracking, !dashboardPreviewOnly else { return }
        updateDashboardMouseEvents()
        if event.type != .mouseMoved,
           !orb.contains(NSEvent.mouseLocation) {
            setExpanded(false)
            return
        }
        updatePointer()
    }

    private func updatePointer() {
        guard visible, !stopped, !suspended, !interaction.dragging, !menuTracking, !dashboardPreviewOnly else { return }
        updateDashboardMouseEvents()
        if suppressHoverUntilExit {
            if !presentation.layout.orbFrame.contains(NSEvent.mouseLocation) {
                suppressHoverUntilExit = false
                pointerRetained = false
            }
            return
        }
        let retained = projectedGeometry?.containsRetentionPoint(NSEvent.mouseLocation) ?? false
        guard retained != pointerRetained else { return }
        pointerRetained = retained
        collapseTask?.cancel()
        if retained {
            let wasExpanded = interaction.expanded
            interaction.pointerEntered()
            if !wasExpanded { applyExpansion(reveal: true) }
        } else if let ticket = interaction.pointerExited() {
            collapseTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
                guard let self, self.visible else { return }
                let inside = self.projectedGeometry?.containsRetentionPoint(NSEvent.mouseLocation) ?? false
                if inside {
                    self.pointerRetained = true
                    self.interaction.pointerEntered()
                } else if self.interaction.completeExit(ticket, pointerInside: false) {
                    self.applyExpansion(reveal: false)
                }
            }
        }
    }

    private func updateDashboardMouseEvents() {
        dashboardPanel.ignoresMouseEvents = true
    }

    private func applyExpansion(reveal: Bool) {
        presentation.expanded = interaction.expanded
        reposition(snap: false)
        if interaction.expanded {
            installPointerMonitors()
            projection.expand()
        } else {
            removePointerMonitors()
            projection.retract()
        }
        renderProjection()
    }

    private func reposition(snap: Bool) {
        let fallback = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let bounds = FloatingHUDGeometry.screen(for: orb, among: NSScreen.screens.map(\.visibleFrame), fallback: fallback)
        orb = snap ? FloatingHUDGeometry.snappedOrb(orb, on: bounds) : FloatingHUDGeometry.clampedOrb(orb, on: bounds)
        let layout = FloatingHUDGeometry.layout(orb: orb, on: bounds, expanded: interaction.expanded)
        presentation.layout = layout
        orbPanel.setFrame(layout.orbFrame, display: true)
        beamPanel.setFrame(layout.screenFrame, display: true)
        let geometry = FloatingHUDProjectionGeometry(orb: orb, visibleFrame: bounds, profile: profile)
        projectedGeometry = geometry
        dashboardPanel.setFrame(geometry.dashboardFrame, display: true)
        dashboardScene.viewportOrigin = geometry.viewportOrigin
        dashboardScene.frame = CGRect(origin: .zero, size: geometry.dashboardFrame.size)
        beamScene.frame = CGRect(origin: .zero, size: bounds.size)
        let fullScreen = NSScreen.screens.first(where: { $0.visibleFrame == bounds })?.frame ?? bounds
        backdropPanel.setFrame(fullScreen, display: true)
        updateDashboardMouseEvents()
        renderProjection()
    }

    private func renderProjection() {
        guard visible, !stopped, !suspended, let geometry = projectedGeometry else { return }
        let language: PlaygroundLanguage = model.language.resolvedCode() == "zh-Hans" ? .simplifiedChinese : .english
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        model.setFloatingHUDExpanded(interaction.expanded || timeline.progress > 0.45)
        let backdropOpacity = dashboardPreviewOnly ? 0 : profile.backdrop.opacity(at: timeline.progress)
        if backdropOpacity > 0 {
            backdropPanel.alphaValue = CGFloat(backdropOpacity)
            if !backdropPanel.isVisible { backdropPanel.orderFrontRegardless() }
        } else { backdropPanel.orderOut(nil) }
        let showBeam = !dashboardPreviewOnly && timeline.sample.beamExtension > 0
        let showDashboard = timeline.progress > 0.35
        beamScene.render(geometry: geometry.projection, config: profile.projection, orb: projection.orbParameters,
            timeline: timeline, reducedMotion: reduced, language: language)
        dashboardScene.language = language
        dashboardScene.render(geometry: geometry.projection, timeline: timeline, reducedMotion: reduced)
        var ordered = false
        if showBeam {
            if !beamPanel.isVisible { beamPanel.orderFrontRegardless(); ordered = true }
        } else { beamPanel.orderOut(nil) }
        if showDashboard {
            if !dashboardPanel.isVisible { dashboardPanel.orderFrontRegardless(); ordered = true }
        } else { dashboardPanel.orderOut(nil) }
        if ordered, !dashboardPreviewOnly { orbPanel.orderFrontRegardless() }
    }

    private func observeLifecycle(_ center: NotificationCenter, _ name: Notification.Name,
                                  action: @escaping (FloatingHUDController) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                action(self)
            }
        }
        lifecycleObservations.append((center, token))
    }

    private func setSuspended(_ value: Bool) {
        suspended = value
        projection.suspend(value)
        presentation.visible = visible && !value
        if value {
            collapseTask?.cancel()
            removePointerMonitors()
            model.setFloatingHUDExpanded(false)
            for panel in [orbPanel, beamPanel, dashboardPanel, backdropPanel] { panel.orderOut(nil) }
        } else if visible, !stopped {
            reposition(snap: false)
            if interaction.expanded { installPointerMonitors() }
            if !dashboardPreviewOnly { orbPanel.orderFrontRegardless() }
            renderProjection()
        }
    }

    private func beginDrag() {
        collapseTask?.cancel()
        dragOrigin = orb
        interaction.beginDrag()
        applyExpansion(reveal: false)
    }

    private func drag(by offset: NSSize) {
        guard let dragOrigin else { return }
        orb = dragOrigin.offsetBy(dx: offset.width, dy: offset.height)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            orb = FloatingHUDGeometry.clampedOrb(orb, on: screen.visibleFrame)
        }
        reposition(snap: false)
    }

    private func endDrag() {
        dragOrigin = nil
        interaction.endDrag()
        pointerRetained = false
        reposition(snap: true)
        defaults.set(orb.minX, forKey: "floatingHUDOrbX")
        defaults.set(orb.minY, forKey: "floatingHUDOrbY")
        writePreviewGeometryReport(stage: "drag-end")
    }

    private func writePreviewGeometryReport(stage: String) {
        guard CommandLine.arguments.contains("--ui-preview-fixtures"),
              CommandLine.arguments.contains("--ui-preview-hud-geometry") else { return }
        let frame = orbPanel.frame
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) })
            ?? NSScreen.main
        guard let screen else { return }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        func rect(_ value: NSRect) -> [String: Double] {
            ["x": Double(value.minX), "y": Double(value.minY),
             "width": Double(value.width), "height": Double(value.height)]
        }
        func topLeft(_ value: NSRect) -> NSRect {
            NSRect(x: value.minX, y: primaryTop - value.maxY, width: value.width, height: value.height)
        }
        let report: [String: Any] = [
            "event": "floating-hud-geometry", "stage": stage, "coordinateUnits": "points",
            "orbCocoa": rect(frame), "orbTopLeftGlobal": rect(topLeft(frame)),
            "screenCocoa": rect(screen.frame), "visibleScreenCocoa": rect(screen.visibleFrame),
            "screenTopLeftGlobal": rect(topLeft(screen.frame)),
            "visibleScreenTopLeftGlobal": rect(topLeft(screen.visibleFrame)),
            "primaryScreenTopCocoa": Double(primaryTop), "backingScaleFactor": Double(screen.backingScaleFactor)
        ]
        guard var data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }
}
