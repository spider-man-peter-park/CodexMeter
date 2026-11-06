import AppKit
import CodexMeterCore
import Darwin
import Foundation
import QuartzCore
import SwiftUI
import Testing
@testable import CodexMeterApp

@Suite(.serialized) @MainActor struct UIRefreshPerformanceTests {
    // Run in an isolated test process and compare the same workload before and after a change.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CODEXMETER_SETTINGS_PERF_ITERATIONS"] != nil))
    func profileSettingsDuringUnrelatedMetricRefreshes() throws {
        let environment = ProcessInfo.processInfo.environment
        let iterations = max(100, Int(environment["CODEXMETER_SETTINGS_PERF_ITERATIONS"] ?? "") ?? 500)
        let warmup = max(20, Int(environment["CODEXMETER_SETTINGS_PERF_WARMUP"] ?? "") ?? 100)
        let interval = max(0.01, Double(environment["CODEXMETER_SETTINGS_PERF_INTERVAL"] ?? "") ?? 0.02)
        let directory = environment["CODEXMETER_SETTINGS_PERF_REPORT_DIRECTORY"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        if let directory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try String(ProcessInfo.processInfo.processIdentifier)
                .write(to: directory.appendingPathComponent("pid"), atomically: true, encoding: .utf8)
        }

        let suite = "io.github.codexmeter.settings-perf." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: home)
        }
        defaults.set(home.path, forKey: "codexHome")
        defaults.set(false, forKey: "autoRefresh")
        defaults.set(false, forKey: "automaticallyCheckForUpdates")
        let model = AppModel(defaults: defaults,
            readQuota: { _ in throw AppServerError.queryFailed },
            readAccount: { _ in throw AppServerError.queryFailed })
        let updates = AppUpdates(defaults: defaults)

        // Neither model is started: this workload performs no account, log, hardware or login writes.
        _ = NSApplication.shared
        let controller = NSHostingController(rootView: ScrollView {
            SettingsContent(model: model, updates: updates).padding(20)
        }.frame(width: 720))
        let window = NSWindow(contentViewController: controller)
        window.title = "CodexMeter settings refresh performance regression"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 720, height: 600))
        window.orderFront(nil)
        defer { window.close() }
        pumpEvents(for: 1, hostingView: controller.view)

        let epoch = Date(timeIntervalSince1970: 1_800_000_000)
        func refreshMetrics(_ iteration: Int) {
            model.now = epoch.addingTimeInterval(Double(iteration * 2))
            model.sample = TPSSample(id: "settings-perf-\(iteration)", model: "synthetic",
                outputTokens: 100 + iteration % 50, reasoningTokens: 10, elapsedSeconds: 2,
                completedAt: epoch.addingTimeInterval(Double(iteration * 2)), isEstimated: true)
            model.refreshing = iteration.isMultiple(of: 2)
            model.accountRefreshing = iteration.isMultiple(of: 3)
            model.latestUnmeasurable = iteration.isMultiple(of: 5)
            model.quotaWarning = iteration.isMultiple(of: 2) ? "Synthetic quota warning" : nil
            model.accountWarning = iteration.isMultiple(of: 3) ? "Synthetic account warning" : nil
        }
        for iteration in 0..<warmup {
            autoreleasepool {
                refreshMetrics(iteration)
                pumpEvents(for: interval, hostingView: controller.view)
            }
        }

        var measurements: [SettingsRefreshPerformanceSample] = []
        for phase in ["idle", "metric-refreshes", "idle-after-refreshes"] {
            let began = ProcessInfo.processInfo.systemUptime
            let cpuBegan = try processCPUSeconds()
            for iteration in 0..<iterations {
                autoreleasepool {
                    if phase == "metric-refreshes" { refreshMetrics(warmup + iteration) }
                    pumpEvents(for: interval, hostingView: controller.view)
                }
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - began
            let cpuSeconds = try processCPUSeconds() - cpuBegan
            let measurement = SettingsRefreshPerformanceSample(phase: phase,
                pid: ProcessInfo.processInfo.processIdentifier, iterations: iterations, intervalSeconds: interval,
                elapsedSeconds: elapsed, cpuSeconds: cpuSeconds,
                meanCPUPercent: cpuSeconds / elapsed * 100, windowVisible: window.isVisible)
            measurements.append(measurement)
            let encoded = try JSONEncoder().encode(measurement)
            print("SETTINGS_REFRESH_PERF " + String(decoding: encoded, as: UTF8.self))
            fflush(stdout)
            if let directory {
                try JSONEncoder().encode(measurements)
                    .write(to: directory.appendingPathComponent("measurements.json"), options: .atomic)
            }
        }

        // An optional caller-supplied budget turns the benchmark into a machine-specific regression check.
        if let budgetText = environment["CODEXMETER_SETTINGS_PERF_MAX_ACTIVE_CPU_SECONDS"],
           let budget = Double(budgetText), let active = measurements.first(where: { $0.phase == "metric-refreshes" }) {
            #expect(active.cpuSeconds <= budget)
        }
    }

    private func pumpEvents(for duration: TimeInterval, hostingView: NSView) {
        let deadline = Date().addingTimeInterval(duration)
        repeat {
            hostingView.layoutSubtreeIfNeeded()
            CATransaction.flush()
            while let event = NSApp.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
            RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.005)))
        } while Date() < deadline
    }

    private func processCPUSeconds() throws -> TimeInterval {
        var usage = rusage()
        try #require(getrusage(RUSAGE_SELF, &usage) == 0)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
}

private struct SettingsRefreshPerformanceSample: Encodable {
    let phase: String
    let pid: Int32
    let iterations: Int
    let intervalSeconds: TimeInterval
    let elapsedSeconds: TimeInterval
    let cpuSeconds: TimeInterval
    let meanCPUPercent: Double
    let windowVisible: Bool
}
