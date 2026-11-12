import AppKit
import CodexMeterCore
import Combine
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate, NSMenuItemValidation {
    private var installedLanguage: AppLanguage?
    private var statusItems: [MenuBarMetric: NSStatusItem] = [:]
    private let statusItemRenderCache = StatusItemRenderCache()
    private var statusUpdateScheduled = false
    private var anchorMetric: MenuBarMetric?
    private var contextMenuMetric: MenuBarMetric?
    private let popover = NSPopover()
    private let model: AppModel
    private let updates = AppUpdates()
    private let usageStore = AssistantUsageStore(preview: CommandLine.arguments.contains("--ui-preview-fixtures"))
    private var workspaceController: NSWindowController?
    private let workspaceNavigation = WorkspaceNavigation()
    private var workspaceObservation: AnyCancellable?
    private var floatingHUD: FloatingHUDController?
    private var floatingHUDObservation: AnyCancellable?
    private var focusController: NSHostingController<ProviderPopoverView>?
    private var workspaceFrame: NSRect?
    private var detailPreviewController: NSWindowController?
    private var detailPreviewSizeObservation: NSKeyValueObservation?
    private lazy var popoverContent = PopoverContentHost(popover: popover, model: model, updates: updates,
        onOpenSettings: { [weak self] in self?.showSettings(nil) },
        onOpenAbout: { [weak self] in self?.showAbout(nil) })
    private var appearanceObservation: NSKeyValueObservation?
    private var outsideMouseMonitor: Any?
    private var pendingPopoverWork: DispatchWorkItem?
    private var popoverGeneration = 0
    private var popoverRequested = false
    private var relocatingPopover = false
    private var interruptionMonitor: InterruptionMonitor?

    override init() {
        if CommandLine.arguments.contains("--ui-preview-fixtures") {
            model = AppModel(readQuota: { _ in UIPreviewFixtures.quota(at: Date()) },
                readAccount: { _ in UIPreviewFixtures.account(at: Date()) })
        } else {
            model = AppModel()
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        model.appearanceChanged = { [weak self] in self?.applyAppearance() }
        if !CommandLine.arguments.contains("--ui-preview-light") && !CommandLine.arguments.contains("--ui-preview-dark") {
            applyAppearance()
        }
        installApplicationMenu()
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = true
        model.changed = { [weak self] in self?.scheduleStatusItemUpdate() }
        usageStore.changed = { [weak self] in self?.scheduleStatusItemUpdate() }
        model.externalRefreshRequested = { [weak self] in self?.usageStore.refresh($0) }
        model.providerChanged = { [weak self] provider in
            guard let self else { return }
            if !self.workspaceNavigation.destination.isSettings { self.workspaceNavigation.select(.overview) }
            self.selectWorkspaceDestination(self.workspaceNavigation.destination)
            self.usageStore.refresh(provider)
        }
        workspaceObservation = workspaceNavigation.$destination.removeDuplicates().sink { [weak self] destination in
            self?.selectWorkspaceDestination(destination)
        }
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in
                self?.popover.appearance = NSApplication.shared.effectiveAppearance
                self?.updateStatusItems()
            }
        }
        updateStatusItems()
        if CommandLine.arguments.contains("--ui-preview-fixtures") {
            UIPreviewFixtures.apply(to: model)
            if model.provider != .codex { usageStore.refresh(model.provider) }
        } else {
            model.applyInitialLoginPreference()
            model.reminders.activateSystemNotifications { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    // These alerts describe Codex; never open another assistant's unrelated readings.
                    self.model.provider = .codex
                    self.openWorkspace(.detail(.quota))
                }
            }
            model.start()
            interruptionMonitor = InterruptionMonitor(sleep: { [weak self] in self?.model.systemWillSleep() },
                wake: { [weak self] in self?.model.systemDidWake(canRefresh: $0) },
                connection: { [weak self] available, recovered in self?.model.networkPathChanged(available: available, recovered: recovered) })
            interruptionMonitor?.start()
            updates.start()
        }
        floatingHUDObservation = model.$showFloatingHUD.removeDuplicates().sink { [weak self] visible in
            self?.setFloatingHUDVisible(visible)
        }
        if CommandLine.arguments.contains("--ui-preview-fixtures"),
           CommandLine.arguments.contains("--ui-preview-hud-expanded") {
            floatingHUD?.setExpanded(true)
        }
        if CommandLine.arguments.contains("--ui-preview-fixtures"),
           CommandLine.arguments.contains("--ui-preview-dashboard-only") {
            floatingHUD?.showDashboardForPreview()
        }
        if CommandLine.arguments.contains("--show-workspace") {
            DispatchQueue.main.async { [weak self] in self?.openWorkspace() }
        } else if CommandLine.arguments.contains("--ui-preview-detail-window") {
            DispatchQueue.main.async { [weak self] in self?.showDetailPreview() }
        } else if CommandLine.arguments.contains("--show-settings") {
            DispatchQueue.main.async { [weak self] in self?.showSettings(nil) }
        } else if CommandLine.arguments.contains("--show-popover") || CommandLine.arguments.contains("--inspect-ui") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, let button = self.firstButton else { return }
                self.showPopover(button)
            }
        }
        if CommandLine.arguments.contains("--ui-preview-fixtures"),
           CommandLine.arguments.contains("--ui-preview-status-click") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self else { return }
                let flag = CommandLine.arguments.firstIndex(of: "--ui-preview-metric")
                let metric = flag.flatMap { index in
                    CommandLine.arguments.indices.contains(index + 1)
                        ? MenuBarMetric(rawValue: CommandLine.arguments[index + 1]) : nil
                }
                let button = metric.flatMap { self.statusItems[$0]?.button }
                    ?? self.statusItems[.tps]?.button ?? self.firstButton
                button?.performClick(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    guard let self else { return }
                    let workspaceWindow = self.workspaceController?.window
                    let popoverWindow = self.popover.contentViewController.flatMap {
                        $0.isViewLoaded ? $0.view.window : nil
                    }
                    let independentWindow = popoverWindow.map { $0 !== workspaceWindow } ?? false
                    let report = "CodexMeter UI preview status click: workspaceVisible=\(workspaceWindow?.isVisible == true) popoverShown=\(self.popover.isShown) independentPopoverWindow=\(independentWindow)\n"
                    FileHandle.standardOutput.write(Data(report.utf8))
                }
            }
        }
    }

    private func applyAppearance() {
        NSApplication.shared.appearance = model.appearance.nativeAppearance
    }

    private func setFloatingHUDVisible(_ visible: Bool) {
        guard visible else {
            floatingHUD?.stop()
            floatingHUD = nil
            return
        }
        if visible && floatingHUD == nil {
            floatingHUD = FloatingHUDController(model: model, usage: usageStore,
                onOpenMetric: { [weak self] metric in
                    self?.openWorkspace(metric == .focus ? .overview : .detail(metric.detailSection))
                },
                onOpenWorkspace: { [weak self] in self?.openWorkspace(.overview) },
                onOpenSettings: { [weak self] in self?.showSettings(nil) },
                onHide: { [weak self] in self?.model.showFloatingHUD = false })
        }
        floatingHUD?.setVisible(visible)
    }

    private func showDetailPreview() {
        if let flag = CommandLine.arguments.firstIndex(of: "--ui-preview-metric"),
           CommandLine.arguments.indices.contains(flag + 1),
           let metric = MenuBarMetric(rawValue: CommandLine.arguments[flag + 1]) {
            model.selectedDetailSection = metric.detailSection
            model.selectedQuotaMetric = [.fiveHour, .weekly].contains(metric) ? metric : nil
        }
        let height = max(180, (NSScreen.main?.visibleFrame.height ?? 800) - 60)
        let controller = NSHostingController(rootView: PopoverView(model: model, updates: updates,
            onOpenSettings: { [weak self] in self?.showSettings(nil) },
            onOpenAbout: { [weak self] in self?.showAbout(nil) }, panelHeight: height))
        controller.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        window.title = "CodexMeter · Detail preview"
        window.delegate = self
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 480, height: 400))
        detailPreviewSizeObservation = controller.observe(\.preferredContentSize, options: [.initial, .new]) { [weak window] controller, _ in
            let size = controller.preferredContentSize
            Task { @MainActor in
                guard let window, size.width > 0, size.height > 0 else { return }
                let top = window.frame.maxY
                window.setContentSize(size)
                var frame = window.frame
                let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame
                frame.origin.y = max(screen.minY, min(top, screen.maxY) - frame.height)
                window.setFrame(frame, display: true)
            }
        }
        window.isReleasedWhenClosed = false
        window.center()
        detailPreviewController = NSWindowController(window: window)
        NSApp.activate(ignoringOtherApps: true)
        detailPreviewController?.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        model.setDetailPresented(true, on: .preview)
    }

    func applicationWillTerminate(_ notification: Notification) {
        finishPopoverInteraction()
        floatingHUDObservation?.cancel()
        floatingHUD?.stop()
        interruptionMonitor?.stop()
        model.stop()
        updates.stop()
        usageStore.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshLoginStatus()
        model.reminders.refreshAuthorization()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openWorkspace()
        return true
    }

    func applicationDidResignActive(_ notification: Notification) {
        dismissPopover()
    }

    func popoverWillClose(_ notification: Notification) {
        if !relocatingPopover { finishPopoverInteraction() }
    }

    func popoverDidClose(_ notification: Notification) {
        guard !relocatingPopover, !popoverRequested, !popover.isShown else { return }
        model.setDetailPresented(false, on: .popover)
        releasePopoverContent()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === detailPreviewController?.window { model.setDetailPresented(false, on: .preview) }
        if window === workspaceController?.window { model.setDetailPresented(false, on: .workspace) }
        let originalFrame = window.frame
        let originalContentSize = window.contentLayoutRect.size
        if window === workspaceController?.window { workspaceFrame = originalFrame }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, !window.isVisible else { return }
            if window === self.workspaceController?.window {
                window.contentViewController = nil
                window.contentView = NSView(frame: NSRect(origin: .zero, size: originalContentSize))
                window.minSize = NSSize(width: 780, height: 540)
                window.setFrame(originalFrame, display: false)
            } else if window === self.detailPreviewController?.window {
                self.detailPreviewSizeObservation = nil
                window.contentViewController = nil
                window.contentView = NSView(frame: NSRect(origin: .zero, size: window.contentLayoutRect.size))
                self.detailPreviewController = nil
            }
        }
    }

    func windowDidMiniaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === workspaceController?.window else { return }
        model.setDetailPresented(false, on: .workspace)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === workspaceController?.window else { return }
        dismissPopover()
        selectWorkspaceDestination(workspaceNavigation.destination)
        model.setDetailPresented(true, on: .workspace)
    }

    private var firstButton: NSStatusBarButton? {
        [MenuBarMetric.focus, .tps, .todayTokens, .weekly, .fiveHour, .cpu, .gpu, .ram, .network, .fallback]
            .compactMap { statusItems[$0]?.button }.first
    }

    private func scheduleStatusItemUpdate() {
        guard !statusUpdateScheduled else { return }
        statusUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.statusUpdateScheduled = false
            self.updateStatusItems()
        }
    }

    private func updateStatusItems() {
        if installedLanguage != model.language {
            installedLanguage = model.language
            installApplicationMenu()
            workspaceController?.window?.title = AppMetadata.name
        }
        let descriptors = model.provider != .codex
            ? [MenuBarFormatter.providerItem(usageStore.result(for: model.provider), autoRefresh: model.autoRefresh)]
            : MenuBarFormatter.items(quota: model.quota, sample: model.sample,
            options: model.options, todayUsage: model.localDayUsage, now: model.now, stale: model.quotaWarning != nil,
            systemMetrics: model.systemMetrics, systemNow: model.systemMetricsNow)
        let needed = Set(descriptors.map(\.metric))
        statusItemRenderCache.retainMetrics(needed)
        let reanchor = (popover.isShown || popoverRequested)
            && (anchorMetric.map { !needed.contains($0) } ?? false)
        if reanchor { closePopoverImmediately(preservingIntent: true) }
        for metric in Array(statusItems.keys) where !needed.contains(metric) {
            if let item = statusItems.removeValue(forKey: metric) {
                NSStatusBar.system.removeStatusItem(item)
            }
        }
        // Each metric owns a native item and a stable identity for macOS position restoration.
        for descriptor in descriptors.reversed() where statusItems[descriptor.metric] == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "CodexMeter.\(descriptor.metric.rawValue)"
            item.isVisible = true
            item.button?.target = self
            item.button?.action = #selector(togglePopover(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            item.button?.tag = MenuBarMetric.allCases.firstIndex(of: descriptor.metric) ?? 0
            statusItems[descriptor.metric] = item
        }
        for descriptor in descriptors {
            guard let button = statusItems[descriptor.metric]?.button else { continue }
            let window: QuotaWindow?
            switch descriptor.metric {
            case .focus:
                window = model.provider == .codex ? FocusSummary(quota: model.quota, warning: model.quotaWarning,
                    automaticRefresh: model.autoRefresh, now: model.now,
                    refreshInterval: model.refreshOptions.quotaInterval).window : nil
            case .fiveHour: window = model.quota?.fiveHour
            case .weekly: window = model.quota?.weekly
            default: window = nil
            }
            if let item = statusItems[descriptor.metric] {
                let result = statusItemRenderCache.render(descriptor, options: model.options,
                    remaining: window?.remainingPercent, appearance: button.effectiveAppearance,
                    isActive: (popover.isShown && anchorMetric == descriptor.metric)
                        || contextMenuMetric == descriptor.metric)
                if result.changed { StatusItemAppearance.apply(result.image, to: item) }
            }
            var tooltip = descriptor.accessibilityLabel + L10n.text(" · Click for details")
            if model.provider != .codex {
                if let snapshot = usageStore.result(for: model.provider).snapshot {
                    tooltip += "\n" + L10n.text("Checked \(snapshot.sampledAt.formatted(.dateTime.locale(L10n.locale)))")
                }
            } else if descriptor.metric == .tps {
                if let sample = model.sample { tooltip += L10n.text("\nResponse completed: \(sample.completedAt.formatted(.dateTime.locale(L10n.locale)))") }
                if model.latestUnmeasurable { tooltip += L10n.text("\nShowing the last response with reliable timing") }
            } else if descriptor.metric == .todayTokens {
                tooltip += "\n" + L10n.text("Desktop logs and linked subagents, by usage-record time. Other-device or cloud activity without local records is not covered. Separate from account daily totals.")
            } else if descriptor.metric.isSystemMetric {
                if let metrics = model.systemMetrics {
                    tooltip += L10n.text("\nSystem updated: \(metrics.sampledAt.formatted(.dateTime.locale(L10n.locale)))")
                }
            } else if let quota = model.quota {
                tooltip += L10n.text("\nQuota updated: \(quota.updatedAt.formatted(.dateTime.locale(L10n.locale)))")
                if let reset = window?.resetsAt { tooltip += L10n.text("\nResets: \(reset.formatted(.dateTime.locale(L10n.locale)))") }
                if quota.isStale || quota.source == .logCache || model.quotaWarning != nil {
                    tooltip += L10n.text("\nCached quota; may be outdated")
                }
            }
            StatusItemMetadata.apply(label: descriptor.accessibilityLabel, value: descriptor.title,
                tooltip: tooltip, to: button)
        }
        if reanchor {
            schedulePopover(after: 0.2)
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        model.refresh()
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            dismissPopover()
            contextMenuMetric = MenuBarMetric.allCases[sender.tag]
            updateStatusItems()
            defer { contextMenuMetric = nil; updateStatusItems() }
            NSMenu.popUpContextMenu(makeActionMenu(), with: event, for: sender)
            return
        }
        let metric = MenuBarMetric.allCases[sender.tag]
        if popover.isShown || popoverRequested {
            if anchorMetric == metric { dismissPopover(); return }
            closePopoverImmediately(preservingIntent: true)
            schedulePopover(on: sender)
            return
        }
        showPopover(sender)
    }

    private func closePopoverImmediately(preservingIntent: Bool = false) {
        if !preservingIntent { finishPopoverInteraction() }
        relocatingPopover = preservingIntent
        popover.animates = false
        popover.close()
        popover.animates = true
        relocatingPopover = false
    }

    private func schedulePopover(on button: NSStatusBarButton? = nil, after delay: TimeInterval = 0) {
        cancelScheduledPopover()
        let generation = popoverGeneration
        let expectedApplication = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let work = DispatchWorkItem { [weak self, weak button] in
            guard let self, self.popoverRequested, self.popoverGeneration == generation else { return }
            self.pendingPopoverWork = nil
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedApplication,
                  let button = button ?? self.firstButton else {
                self.dismissPopover()
                return
            }
            self.showPopover(button)
        }
        pendingPopoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func dismissPopover() {
        finishPopoverInteraction()
        popover.performClose(nil)
    }

    private func finishPopoverInteraction() {
        let hadSelection = anchorMetric != nil
        popoverRequested = false
        anchorMetric = nil
        cancelScheduledPopover()
        model.setDetailPresented(false, on: .popover)
        if !popover.isShown { releasePopoverContent() }
        if let outsideMouseMonitor {
            NSEvent.removeMonitor(outsideMouseMonitor)
            self.outsideMouseMonitor = nil
        }
        if hadSelection { updateStatusItems() }
    }

    private func cancelScheduledPopover() {
        popoverGeneration &+= 1
        pendingPopoverWork?.cancel()
        pendingPopoverWork = nil
    }

    private func releasePopoverContent() {
        guard !popover.isShown else { return }
        popoverContent.releaseIfHidden()
        focusController = nil
    }

    private func monitorOutsideClicks() {
        guard outsideMouseMonitor == nil else { return }
        // Mouse-only global monitoring needs no Accessibility permission and leaves in-app menus alone.
        outsideMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.dismissPopover()
        }
    }

    private func showPopover(_ button: NSStatusBarButton) {
        cancelScheduledPopover()
        popoverRequested = true
        anchorMetric = MenuBarMetric.allCases[button.tag]
        model.selectedDetailSection = MenuBarMetric.allCases[button.tag].detailSection
        let metric = MenuBarMetric.allCases[button.tag]
        model.selectedQuotaMetric = [.fiveHour, .weekly].contains(metric) ? metric : nil
        monitorOutsideClicks()
        let screenHeight = button.window?.screen?.visibleFrame.height ?? 800
        if metric == .focus {
            popoverContent.releaseIfHidden()
            let controller = NSHostingController(rootView: ProviderPopoverView(model: model, usage: usageStore,
                onOpenWorkspace: { [weak self] in self?.openWorkspace($0) },
                onOpenSettings: { [weak self] in self?.showSettings(nil) },
                onOpenAbout: { [weak self] in self?.showAbout(nil) }))
            controller.sizingOptions = [.preferredContentSize]
            focusController = controller
            popover.contentViewController = controller
        } else {
            focusController = nil
            popoverContent.prepare(panelHeight: max(180, screenHeight - 60))
        }
        // Match app appearance rather than the menu bar anchor's wallpaper-dependent appearance.
        popover.appearance = NSApplication.shared.effectiveAppearance
        // A status-item popover must not raise the app's background settings window.
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        model.setDetailPresented(popover.isShown && metric != .focus, on: .popover)
        if !popover.isShown { finishPopoverInteraction() }
        updateStatusItems()
    }

    private func installApplicationMenu() {
        let menu = NSMenu()
        let application = NSMenuItem(title: AppMetadata.name, action: nil, keyEquivalent: "")
        application.submenu = makeActionMenu()
        menu.addItem(application)
        let file = NSMenuItem(title: L10n.text("File"), action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: L10n.text("File"))
        fileMenu.addItem(NSMenuItem(title: L10n.text("Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        file.submenu = fileMenu
        menu.addItem(file)
        let edit = NSMenuItem(title: L10n.text("Edit"), action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: L10n.text("Edit"))
        for (title, action, key) in [(L10n.text("Undo"), "undo:", "z"), (L10n.text("Cut"), "cut:", "x"),
                                     (L10n.text("Copy"), "copy:", "c"), (L10n.text("Paste"), "paste:", "v"),
                                     (L10n.text("Select All"), "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: NSSelectorFromString(action), keyEquivalent: key))
        }
        edit.submenu = editMenu
        menu.addItem(edit)
        NSApp.mainMenu = menu
    }

    private func makeActionMenu() -> NSMenu {
        let menu = NSMenu(title: AppMetadata.name)
        func add(_ title: String, _ selector: Selector, key: String = "") {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        add(L10n.text("Open workspace"), #selector(showWorkspace(_:)), key: "0")
        add(L10n.text("About CodexMeter"), #selector(showAbout(_:)))
        menu.addItem(.separator())
        add(L10n.text("Settings…"), #selector(showSettings(_:)), key: ",")
        add(L10n.text("Show floating HUD"), #selector(toggleFloatingHUD(_:)))
        add(L10n.text("Check for Updates…"), #selector(checkForUpdates(_:)))
        menu.addItem(.separator())
        add(L10n.text("CodexMeter on GitHub"), #selector(openProject(_:)))
        add(L10n.text("Report an Issue…"), #selector(reportIssue(_:)))
        menu.addItem(.separator())
        add(L10n.text("Quit CodexMeter"), #selector(quit(_:)), key: "q")
        return menu
    }

    @objc private func showWorkspace(_ sender: Any?) { openWorkspace(.overview) }

    @objc private func toggleFloatingHUD(_ sender: Any?) { model.showFloatingHUD.toggle() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleFloatingHUD(_:)) {
            menuItem.state = model.showFloatingHUD ? .on : .off
        }
        return true
    }

    private func selectWorkspaceDestination(_ destination: WorkspaceDestination) {
        model.setDetailSelection(destination.detailSection, on: .workspace)
    }

    private func openWorkspace(_ destination: WorkspaceDestination? = nil) {
        dismissPopover()
        if let destination { workspaceNavigation.select(destination) }
        selectWorkspaceDestination(workspaceNavigation.destination)
        if workspaceController == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = AppMetadata.name
            window.delegate = self
            window.minSize = NSSize(width: 780, height: 540)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("CodexMeter.Workspace")
            if !window.setFrameUsingName("CodexMeter.Workspace") { window.center() }
            workspaceController = NSWindowController(window: window)
        }
        if let window = workspaceController?.window, window.contentViewController == nil {
            let frame = WorkspaceWindowGeometry.restored(workspaceFrame ?? window.frame,
                on: window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800))
            let controller = NSHostingController(rootView: WorkspaceView(model: model, updates: updates, usage: usageStore,
                navigation: workspaceNavigation,
                onOpenSettings: { [weak self] in self?.showSettings(nil) },
                onOpenAbout: { [weak self] in self?.showAbout(nil) }))
            // A workspace follows its window, never the unbounded height of its scroll contents.
            controller.sizingOptions = []
            (controller.view as? NSHostingView<WorkspaceView>)?.sizingOptions = []
            window.contentViewController = controller
            window.minSize = NSSize(width: 780, height: 540)
            window.setFrame(frame, display: false)
            workspaceFrame = frame
        }
        NSApp.activate(ignoringOtherApps: true)
        if workspaceController?.window?.isMiniaturized == true { workspaceController?.window?.deminiaturize(nil) }
        workspaceController?.showWindow(nil)
        workspaceController?.window?.makeKeyAndOrderFront(nil)
        model.setDetailPresented(true, on: .workspace)
    }

    @objc private func showSettings(_ sender: Any?) {
        model.refreshLoginStatus()
        openWorkspace(workspaceNavigation.settingsDestination)
    }

    @objc private func showAbout(_ sender: Any?) {
        dismissPopover()
        let credits = NSMutableAttributedString(string: L10n.text("Codex Desktop quota, tokens and response speed.\n\n"))
        for (title, url) in [("GitHub", AppMetadata.projectURL), (L10n.text("Report an Issue"), AppMetadata.issuesURL),
                             (L10n.text("MIT License"), AppMetadata.licenseURL)] {
            credits.append(NSAttributedString(string: title + "\n", attributes: [.link: url]))
        }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: AppMetadata.name,
            .applicationVersion: AppMetadata.version, .version: AppMetadata.build, .credits: credits])
    }

    @objc private func checkForUpdates(_ sender: Any?) { showSettings(sender); updates.check(force: true) }
    @objc private func openProject(_ sender: Any?) { dismissPopover(); NSWorkspace.shared.open(AppMetadata.projectURL) }
    @objc private func reportIssue(_ sender: Any?) { dismissPopover(); NSWorkspace.shared.open(AppMetadata.issuesURL) }
    @objc private func quit(_ sender: Any?) { NSApp.terminate(sender) }
}

@MainActor
enum StatusItemMetadata {
    static func apply(label: String, value: String, tooltip: String, to button: NSButton) {
        if button.accessibilityLabel() != label { button.setAccessibilityLabel(label) }
        if button.accessibilityValue() as? String != value { button.setAccessibilityValue(value) }
        if button.toolTip != tooltip { button.toolTip = tooltip }
    }
}

@main
struct CodexMeterMain {
    @MainActor static func main() {
        if let flag = CommandLine.arguments.firstIndex(of: "--diagnose-provider"),
           CommandLine.arguments.indices.contains(flag + 1),
           let provider = AssistantProvider(rawValue: CommandLine.arguments[flag + 1]), provider != .codex {
            Task {
                await ProviderDiagnostics.run(provider)
                exit(0)
            }
            dispatchMain()
        }
        if CommandLine.arguments.contains("--verify-resources") {
            guard let coreURL = Bundle.main.url(forResource: "CodexMeter_CodexMeterCore", withExtension: "bundle"),
                  L10n.resourceBundleURL.standardizedFileURL == coreURL.standardizedFileURL,
                  L10n.text("Settings", language: .english) == "Settings",
                  L10n.text("Settings", language: .simplifiedChinese) == "设置",
                  let appURL = Bundle.main.url(forResource: "CodexMeter_CodexMeterApp", withExtension: "bundle"),
                  let assets = Bundle(url: appURL),
                  assets.url(forResource: "OpenAIBlossomBlack", withExtension: "png") != nil,
                  assets.url(forResource: "OpenAIBlossomWhite", withExtension: "png") != nil,
                  Bundle.main.url(forResource: "AppIcon", withExtension: "icns") != nil else {
                fputs("Packaged resource verification failed.\n", stderr)
                exit(1)
            }
            print("Packaged localization and artwork verified.")
            return
        }
        if CommandLine.arguments.contains("--unregister-login-item") {
            do {
                if SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
                exit(0)
            }
            catch { fputs(L10n.text("Remove CodexMeter from Login Items before uninstalling.\n"), stderr); exit(1) }
        }
        if CommandLine.arguments.contains("--diagnose") {
            Task { @MainActor in
                await diagnose()
                exit(0)
            }
            dispatchMain()
        }
        if let identifier = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }) {
            existing.activate(options: [])
            return
        }
        let application = NSApplication.shared
        if CommandLine.arguments.contains("--ui-preview-english") {
            var previewArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            previewArguments["appLanguage"] = "en"
            UserDefaults.standard.setVolatileDomain(previewArguments, forName: UserDefaults.argumentDomain)
        }
        if CommandLine.arguments.contains("--ui-preview-chinese") {
            var previewArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            previewArguments["appLanguage"] = "zh-Hans"
            UserDefaults.standard.setVolatileDomain(previewArguments, forName: UserDefaults.argumentDomain)
        }
        if CommandLine.arguments.contains("--ui-preview-fixtures") {
            var previewArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            previewArguments["codexHome"] = "/private/tmp/codexmeter-preview-empty"
            UserDefaults.standard.setVolatileDomain(previewArguments, forName: UserDefaults.argumentDomain)
        }
        if CommandLine.arguments.contains("--ui-preview-all-sections"),
           let layout = try? JSONEncoder().encode(DetailLayout()) {
            var previewArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            previewArguments["detailLayout"] = layout
            UserDefaults.standard.setVolatileDomain(previewArguments, forName: UserDefaults.argumentDomain)
        }
        let delegate = AppDelegate()
        if CommandLine.arguments.contains("--ui-preview-light") { application.appearance = NSAppearance(named: .aqua) }
        if CommandLine.arguments.contains("--ui-preview-dark") { application.appearance = NSAppearance(named: .darkAqua) }
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }

    @MainActor private static func diagnose() async {
        let home = AppModel.codexHome()
        let logs = await LogMonitor(home: home).poll()
        var quota = logs.cachedQuota
        var live = false
        do { quota = try await AppServerClient().readQuota(codexHome: home); live = true }
        catch { }
        let accountInfo = try? await AppServerClient().readAccountInfo(codexHome: home)
        let systemMonitor = SystemMetricsMonitor()
        _ = await systemMonitor.sample()
        try? await Task.sleep(for: .seconds(6))
        let systemMetrics = await systemMonitor.sample()
        var output: [String: Any] = ["liveQuota": live]
        output["systemMetrics"] = [
            "cpuUsagePercent": systemMetrics.cpuUsagePercent as Any? ?? NSNull(),
            "gpuUsagePercent": systemMetrics.gpuUsagePercent as Any? ?? NSNull(),
            "memoryUsagePercent": systemMetrics.memoryUsagePercent as Any? ?? NSNull(),
            "memoryUsedBytes": systemMetrics.memoryUsedBytes as Any? ?? NSNull(),
            "memoryTotalBytes": systemMetrics.memoryTotalBytes as Any? ?? NSNull(),
            "memoryAppBytes": systemMetrics.memoryAppBytes as Any? ?? NSNull(),
            "memoryWiredBytes": systemMetrics.memoryWiredBytes as Any? ?? NSNull(),
            "memoryCompressedBytes": systemMetrics.memoryCompressedBytes as Any? ?? NSNull(),
            "memoryFreeBytes": systemMetrics.memoryFreeBytes as Any? ?? NSNull(),
            "memorySwapUsedBytes": systemMetrics.memorySwapUsedBytes as Any? ?? NSNull(),
            "memoryPressure": systemMetrics.memoryPressure?.rawValue as Any? ?? NSNull(),
            "cpuUserPercent": systemMetrics.cpuUserPercent as Any? ?? NSNull(),
            "cpuSystemPercent": systemMetrics.cpuSystemPercent as Any? ?? NSNull(),
            "cpuIdlePercent": systemMetrics.cpuIdlePercent as Any? ?? NSNull(),
            "physicalCoreCount": systemMetrics.physicalCoreCount as Any? ?? NSNull(),
            "logicalCoreCount": systemMetrics.logicalCoreCount as Any? ?? NSNull(),
            "loadAverages": systemMetrics.loadAverages as Any? ?? NSNull(),
            "gpuDeviceNames": systemMetrics.gpuDeviceNames,
            "gpuHasUnifiedMemory": systemMetrics.gpuHasUnifiedMemory as Any? ?? NSNull(),
            "gpuRecommendedWorkingSetBytes": systemMetrics.gpuRecommendedWorkingSetBytes as Any? ?? NSNull(),
            "gpuRendererUsagePercent": systemMetrics.gpuRendererUsagePercent as Any? ?? NSNull(),
            "gpuTilerUsagePercent": systemMetrics.gpuTilerUsagePercent as Any? ?? NSNull(),
            "networkUploadBytesPerSecond": systemMetrics.networkUploadBytesPerSecond as Any? ?? NSNull(),
            "networkDownloadBytesPerSecond": systemMetrics.networkDownloadBytesPerSecond as Any? ?? NSNull()
        ]
        func processOutput(_ process: SystemProcessUsage) -> [String: Any] {
            ["pid": process.pid, "name": process.name, "memoryBytes": process.memoryBytes as Any? ?? NSNull(),
             "cpuUsagePercent": process.cpuUsagePercent as Any? ?? NSNull()]
        }
        output["cpuTopProcesses"] = systemMetrics.cpuTopProcesses.map(processOutput)
        output["memoryTopProcesses"] = systemMetrics.memoryTopProcesses.map(processOutput)
        output["networkTopProcesses"] = systemMetrics.networkTopProcesses.map {
            ["pid": $0.pid, "name": $0.name, "uploadBytesPerSecond": $0.uploadBytesPerSecond,
             "downloadBytesPerSecond": $0.downloadBytesPerSecond] as [String: Any]
        }
        output["networkProcessesUpdatedAt"] = systemMetrics.networkProcessesUpdatedAt.map {
            ISO8601DateFormatter().string(from: $0)
        } as Any? ?? NSNull()
        if let quota {
            var limits: [String: Any] = ["updatedAt": ISO8601DateFormatter().string(from: quota.updatedAt)]
            for (label, window) in [("5h", quota.fiveHour), ("7d", quota.weekly)] {
                if let window {
                    var value: [String: Any] = ["remainingPercent": window.remainingPercent]
                    if let reset = window.resetsAt { value["resetsAt"] = Int(reset.timeIntervalSince1970) }
                    limits[label] = value
                }
            }
            output["quota"] = limits
            if let credits = quota.resetCredits {
                output["resetCredits"] = ["availableCount": credits.availableCount,
                    "detailCount": credits.credits.map(\.count) as Any? ?? NSNull()]
            }
        }
        if let sample = logs.latestSample {
            output["tps"] = ["value": sample.tokensPerSecond, "outputTokens": sample.outputTokens,
                             "reasoningTokens": sample.reasoningTokens, "elapsedSeconds": sample.elapsedSeconds,
                             "completedAt": ISO8601DateFormatter().string(from: sample.completedAt),
                             "model": sample.model ?? "unknown", "estimated": sample.isEstimated]
        }
        if let accountInfo {
            var account: [String: Any] = ["updatedAt": ISO8601DateFormatter().string(from: accountInfo.updatedAt),
                "dailyBucketCount": accountInfo.dailyUsageBuckets?.count as Any? ?? NSNull()]
            account["lifetimeTokens"] = accountInfo.summary?.lifetimeTokens
            account["peakDailyTokens"] = accountInfo.summary?.peakDailyTokens
            if let day = accountInfo.latestDailyUsage {
                account["latestReportedDay"] = day.startDate
                account["latestDailyTokens"] = day.tokens
            }
            output["accountUsage"] = account
        }
        let preferences = AppModel()
        output["menuBarMode"] = preferences.menuBarMode.rawValue
        let items = MenuBarFormatter.items(quota: quota, sample: logs.latestSample, options: preferences.options,
            todayUsage: logs.todayUsage, systemMetrics: systemMetrics)
        output["menuItems"] = items.map { ["metric": $0.metric.rawValue, "title": $0.title] }
        if let encoded = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys, .prettyPrinted]),
           let text = String(data: encoded, encoding: .utf8) { print(text) }
    }
}
