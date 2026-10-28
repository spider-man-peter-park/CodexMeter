import AppKit
import CodexMeterCore
import Foundation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.setAccessibilityLabel("CodexMeter")
        popover.behavior = .transient
        popover.animates = true
        let controller = NSHostingController(rootView: PopoverView(model: model))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        model.changed = { [weak self] in self?.updateTitle() }
        updateTitle()
        model.start()
        if CommandLine.arguments.contains("--show-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.togglePopover() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { model.stop() }

    private func updateTitle() {
        guard let button = statusItem?.button else { return }
        let title = MenuBarFormatter.title(quota: model.quota, sample: model.sample, options: model.options,
                                           now: model.now, stale: model.quotaWarning != nil)
        let text = NSMutableAttributedString(string: title, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ])
        for (label, window) in [("5h", model.quota?.fiveHour), ("7d", model.quota?.weekly)] {
            guard let window, window.remainingPercent <= 20 else { continue }
            let value = "\(label) \(Int(window.remainingPercent.rounded()))%"
            let range = (title as NSString).range(of: value)
            if range.location != NSNotFound {
                text.addAttribute(.foregroundColor, value: window.remainingPercent <= 10 ? NSColor.systemRed : NSColor.systemOrange,
                                  range: range)
            }
        }
        button.attributedTitle = text
        var tooltip = "CodexMeter · Click for details"
        if let date = model.quota?.updatedAt { tooltip += "\nQuota updated: \(date.formatted())" }
        if title.hasSuffix("*") { tooltip += "\n* Cached quota; may be outdated" }
        if let sample = model.sample { tooltip += "\nTPS completed: \(sample.completedAt.formatted())" }
        button.toolTip = tooltip
        button.setAccessibilityValue(title)
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
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
        }
        if let sample = logs.latestSample {
            output["tps"] = ["value": sample.tokensPerSecond, "outputTokens": sample.outputTokens,
                             "reasoningTokens": sample.reasoningTokens, "elapsedSeconds": sample.elapsedSeconds,
                             "completedAt": ISO8601DateFormatter().string(from: sample.completedAt),
                             "model": sample.model ?? "unknown", "estimated": sample.isEstimated]
        }
        if let encoded = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys, .prettyPrinted]),
           let text = String(data: encoded, encoding: .utf8) { print(text) }
    }
}
