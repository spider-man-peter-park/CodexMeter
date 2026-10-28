import AppKit
import CodexMeterCore
import Foundation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItems: [MenuBarMetric: NSStatusItem] = [:]
    private var anchorMetric: MenuBarMetric?
    private let popover = NSPopover()
    private let model = AppModel()
    private var appearanceObservation: NSKeyValueObservation?
    private var outsideMouseMonitor: Any?
    private var pendingPopoverWork: DispatchWorkItem?
    private var popoverGeneration = 0
    private var popoverRequested = false
    private var relocatingPopover = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = true
        let controller = NSHostingController(rootView: PopoverView(model: model))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        model.changed = { [weak self] in self?.updateStatusItems() }
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.updateStatusItems() }
        }
        updateStatusItems()
        model.start()
        if CommandLine.arguments.contains("--show-popover") || CommandLine.arguments.contains("--inspect-ui") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, let button = self.firstButton else { return }
                self.showPopover(button)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        finishPopoverInteraction()
        model.stop()
    }

    func applicationDidResignActive(_ notification: Notification) {
        dismissPopover()
    }

    func popoverWillClose(_ notification: Notification) {
        if !relocatingPopover { finishPopoverInteraction() }
    }

    private var firstButton: NSStatusBarButton? {
        [MenuBarMetric.tps, .weekly, .fiveHour, .fallback].compactMap { statusItems[$0]?.button }.first
    }

    private func updateStatusItems() {
        let descriptors = MenuBarFormatter.items(quota: model.quota, sample: model.sample,
            options: model.options, now: model.now, stale: model.quotaWarning != nil)
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
                                           isActive: popover.isShown && anchorMetric == descriptor.metric)
            }
            button.setAccessibilityLabel(descriptor.accessibilityLabel)
            button.setAccessibilityValue(descriptor.title)
            var tooltip = descriptor.accessibilityLabel + " · Click for details"
            if descriptor.metric == .tps {
                if let sample = model.sample { tooltip += "\nResponse completed: \(sample.completedAt.formatted())" }
                if model.latestUnmeasurable { tooltip += "\nShowing the last response with reliable timing" }
            } else if let quota = model.quota {
                tooltip += "\nQuota updated: \(quota.updatedAt.formatted())"
                if let reset = window?.resetsAt { tooltip += "\nResets: \(reset.formatted())" }
                if quota.isStale || quota.source == .logCache || model.quotaWarning != nil {
                    tooltip += "\n* Cached quota; may be outdated"
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
        let work = DispatchWorkItem { [weak self, weak button] in
            guard let self, self.popoverRequested, self.popoverGeneration == generation else { return }
            self.pendingPopoverWork = nil
            guard NSApplication.shared.isActive,
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
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        updateStatusItems()
    }
}

@main
struct CodexMeterMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            Task { @MainActor in
                await diagnose()
                exit(0)
            }
            dispatchMain()
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
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
            options: AppModel().options).map { ["metric": $0.metric.rawValue, "title": $0.title] }
        if let encoded = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys, .prettyPrinted]),
           let text = String(data: encoded, encoding: .utf8) { print(text) }
    }
}
