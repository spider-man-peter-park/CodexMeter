import AppKit
import CodexMeterCore
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var installedLanguage: AppLanguage?
    private var statusItems: [MenuBarMetric: NSStatusItem] = [:]
    private var anchorMetric: MenuBarMetric?
    private var contextMenuMetric: MenuBarMetric?
    private let popover = NSPopover()
    private let model = AppModel()
    private let updates = AppUpdates()
    private var settingsController: NSWindowController?
    private var popoverController: NSHostingController<PopoverView>?
    private var appearanceObservation: NSKeyValueObservation?
    private var outsideMouseMonitor: Any?
    private var pendingPopoverWork: DispatchWorkItem?
    private var popoverGeneration = 0
    private var popoverRequested = false
    private var relocatingPopover = false
    private var interruptionMonitor: InterruptionMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        installApplicationMenu()
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = true
        let controller = NSHostingController(rootView: PopoverView(model: model, updates: updates,
            onOpenSettings: { [weak self] in self?.showSettings(nil) },
            onOpenAbout: { [weak self] in self?.showAbout(nil) }))
        popoverController = controller
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        model.changed = { [weak self] in self?.updateStatusItems() }
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in
                self?.popover.appearance = NSApplication.shared.effectiveAppearance
                self?.updateStatusItems()
            }
        }
        updateStatusItems()
        model.applyInitialLoginPreference()
        model.reminders.activateSystemNotifications { [weak self] in
            Task { @MainActor in
                guard let self, let button = self.firstButton else { return }
                self.showPopover(button)
            }
        }
        model.start()
        interruptionMonitor = InterruptionMonitor(sleep: { [weak self] in self?.model.systemWillSleep() },
            wake: { [weak self] in self?.model.systemDidWake(canRefresh: $0) },
            connection: { [weak self] available, recovered in self?.model.networkPathChanged(available: available, recovered: recovered) })
        interruptionMonitor?.start()
        updates.start()
        if CommandLine.arguments.contains("--show-settings") {
            DispatchQueue.main.async { [weak self] in self?.showSettings(nil) }
        } else if CommandLine.arguments.contains("--show-popover") || CommandLine.arguments.contains("--inspect-ui") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, let button = self.firstButton else { return }
                self.showPopover(button)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        finishPopoverInteraction()
        interruptionMonitor?.stop()
        model.stop()
        updates.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshLoginStatus()
        model.reminders.refreshAuthorization()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let button = firstButton { showPopover(button) }
        return true
    }

    func applicationDidResignActive(_ notification: Notification) {
        dismissPopover()
    }

    func popoverWillClose(_ notification: Notification) {
        if !relocatingPopover { finishPopoverInteraction() }
    }

    private var firstButton: NSStatusBarButton? {
        [MenuBarMetric.tps, .todayTokens, .weekly, .fiveHour, .fallback].compactMap { statusItems[$0]?.button }.first
    }

    private func updateStatusItems() {
        if installedLanguage != model.language {
            installedLanguage = model.language
            installApplicationMenu()
            settingsController?.window?.title = L10n.text("CodexMeter Settings")
        }
        let descriptors = MenuBarFormatter.items(quota: model.quota, sample: model.sample,
            options: model.options, todayUsage: model.localDayUsage, now: model.now, stale: model.quotaWarning != nil)
        let needed = Set(descriptors.map(\.metric))
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
            case .fiveHour: window = model.quota?.fiveHour
            case .weekly: window = model.quota?.weekly
            default: window = nil
            }
            if let item = statusItems[descriptor.metric] {
                StatusItemAppearance.apply(descriptor, to: item, options: model.options, window: window,
                                           isActive: (popover.isShown && anchorMetric == descriptor.metric)
                                               || contextMenuMetric == descriptor.metric)
            }
            button.setAccessibilityLabel(descriptor.accessibilityLabel)
            button.setAccessibilityValue(descriptor.title)
            var tooltip = descriptor.accessibilityLabel + L10n.text(" · Click for details")
            if descriptor.metric == .tps {
                if let sample = model.sample { tooltip += L10n.text("\nResponse completed: \(sample.completedAt.formatted(.dateTime.locale(L10n.locale)))") }
                if model.latestUnmeasurable { tooltip += L10n.text("\nShowing the last response with reliable timing") }
            } else if descriptor.metric == .todayTokens {
                tooltip += "\n" + L10n.text("Desktop logs and linked subagents, by usage-record time. Other-device or cloud activity without local records is not covered. Separate from account daily totals.")
            } else if let quota = model.quota {
                tooltip += L10n.text("\nQuota updated: \(quota.updatedAt.formatted(.dateTime.locale(L10n.locale)))")
                if let reset = window?.resetsAt { tooltip += L10n.text("\nResets: \(reset.formatted(.dateTime.locale(L10n.locale)))") }
                if quota.isStale || quota.source == .logCache || model.quotaWarning != nil {
                    tooltip += L10n.text("\n* Cached quota; may be outdated")
                }
            }
            button.toolTip = tooltip
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
        monitorOutsideClicks()
        let screenHeight = button.window?.screen?.visibleFrame.height ?? 800
        popoverController?.rootView.panelHeight = min(740, max(180, screenHeight - 60))
        // Match app appearance rather than the menu bar anchor's wallpaper-dependent appearance.
        popover.appearance = NSApplication.shared.effectiveAppearance
        // A status-item popover must not raise the app's background settings window.
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
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
        add(L10n.text("About CodexMeter"), #selector(showAbout(_:)))
        menu.addItem(.separator())
        add(L10n.text("Settings…"), #selector(showSettings(_:)), key: ",")
        add(L10n.text("Check for Updates…"), #selector(checkForUpdates(_:)))
        menu.addItem(.separator())
        add(L10n.text("CodexMeter on GitHub"), #selector(openProject(_:)))
        add(L10n.text("Report an Issue…"), #selector(reportIssue(_:)))
        menu.addItem(.separator())
        add(L10n.text("Quit CodexMeter"), #selector(quit(_:)), key: "q")
        return menu
    }

    @objc private func showSettings(_ sender: Any?) {
        dismissPopover()
        model.refreshLoginStatus()
        if settingsController == nil {
            let controller = NSHostingController(rootView: SettingsWindowView(model: model, updates: updates))
            let window = NSWindow(contentViewController: controller)
            window.title = L10n.text("CodexMeter Settings")
            window.styleMask = [.titled, .closable, .resizable]
            let height = min(600, max(280, (NSScreen.main?.visibleFrame.height ?? 800) - 100))
            window.setContentSize(NSSize(width: 740, height: height))
            window.minSize = NSSize(width: 680, height: 460)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("CodexMeter.Settings")
            if !window.setFrameUsingName("CodexMeter.Settings") { window.center() }
            if window.frame.width < 680 {
                window.setContentSize(NSSize(width: 740, height: height))
            }
            settingsController = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
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

@main
struct CodexMeterMain {
    @MainActor static func main() {
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
        var output: [String: Any] = ["liveQuota": live]
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
        output["menuItems"] = MenuBarFormatter.items(quota: quota, sample: logs.latestSample,
            options: AppModel().options, todayUsage: logs.todayUsage).map { ["metric": $0.metric.rawValue, "title": $0.title] }
        if let encoded = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys, .prettyPrinted]),
           let text = String(data: encoded, encoding: .utf8) { print(text) }
    }
}
