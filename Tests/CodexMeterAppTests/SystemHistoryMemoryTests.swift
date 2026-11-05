import AppKit
import CodexMeterCore
import Darwin
import Foundation
import QuartzCore
import SwiftUI
import Testing
@testable import CodexMeterApp

@Suite(.serialized) @MainActor struct SystemHistoryMemoryTests {
    // Run this separately so unrelated tests do not contaminate the process footprint.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CODEXMETER_MEMORY_SOAK_ITERATIONS"] != nil))
    func renderedSystemHistoryMemoryPlateausAfterWarmup() throws {
        let environment = ProcessInfo.processInfo.environment
        let iterations = max(100, Int(environment["CODEXMETER_MEMORY_SOAK_ITERATIONS"] ?? "") ?? 3000)
        let warmup = max(100, Int(environment["CODEXMETER_MEMORY_SOAK_WARMUP"] ?? "") ?? 1000)
        let interval = max(0.01, Double(environment["CODEXMETER_MEMORY_SOAK_INTERVAL"] ?? "") ?? 0.02)
        let allowance = max(0, Double(environment["CODEXMETER_MEMORY_SOAK_MAX_GROWTH_MIB"] ?? "") ?? 32)
        let section = DetailSection(rawValue: environment["CODEXMETER_MEMORY_SOAK_SECTION"] ?? "ram") ?? .ram
        let reportDirectory = environment["CODEXMETER_MEMORY_SOAK_REPORT_DIRECTORY"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        if let reportDirectory {
            try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
        }
        let reportURL = reportDirectory?.appendingPathComponent("samples.jsonl")
        let pid = ProcessInfo.processInfo.processIdentifier
        if let reportDirectory {
            try String(pid).write(to: reportDirectory.appendingPathComponent("pid"), atomically: true, encoding: .utf8)
        }

        _ = NSApplication.shared
        let state = SystemHistorySoakState()
        state.advance(to: 0)
        let controller = NSHostingController(rootView: SystemHistorySoakView(state: state, section: section))
        let window = NSWindow(contentViewController: controller)
        window.title = "CodexMeter system history memory regression"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 480, height: 680))
        window.orderFront(nil)
        defer { window.close() }

        let began = ProcessInfo.processInfo.systemUptime
        func record(_ iteration: Int) throws -> UInt64 {
            let bytes = try physicalFootprint()
            let sample = SystemHistoryMemorySample(pid: pid, iteration: iteration,
                measuredIteration: max(0, iteration - warmup),
                elapsedSeconds: ProcessInfo.processInfo.systemUptime - began, footprintBytes: bytes)
            var data = try JSONEncoder().encode(sample)
            data.append(10)
            if let reportURL {
                if !FileManager.default.fileExists(atPath: reportURL.path) {
                    try data.write(to: reportURL)
                } else {
                    let handle = try FileHandle(forWritingTo: reportURL)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                }
            }
            print("MEMORY_SOAK " + String(decoding: data.dropLast(), as: UTF8.self))
            fflush(stdout)
            return bytes
        }

        pumpEvents(for: 1, hostingView: controller.view)
        _ = try record(0)
        var warmupBytes: UInt64 = 0
        var finalBytes: UInt64 = 0
        for iteration in 1...(warmup + iterations) {
            autoreleasepool {
                state.advance(to: iteration)
                pumpEvents(for: interval, hostingView: controller.view)
            }
            if iteration % 100 == 0 || iteration == warmup || iteration == warmup + iterations {
                let bytes = try record(iteration)
                if iteration == warmup {
                    warmupBytes = bytes
                    let hold = max(0, Double(environment["CODEXMETER_MEMORY_SOAK_WARMUP_HOLD_SECONDS"] ?? "") ?? 0)
                    if hold > 0 { pumpEvents(for: hold, hostingView: controller.view) }
                }
                if iteration == warmup + iterations { finalBytes = bytes }
            }
        }
        #expect(state.history.count == 61)
        #expect(finalBytes <= warmupBytes + UInt64(allowance * 1_048_576),
            "Rendered history grew by more than \(allowance) MiB after \(warmup) warmup updates.")

        // Keep the real chart alive briefly for an optional external heap summary.
        let hold = max(0, Double(environment["CODEXMETER_MEMORY_SOAK_HOLD_SECONDS"] ?? "") ?? 0)
        if hold > 0 { pumpEvents(for: hold, hostingView: controller.view) }
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

    private func physicalFootprint() throws -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        try #require(result == KERN_SUCCESS)
        return info.phys_footprint
    }
}

private struct SystemHistoryMemorySample: Encodable {
    let pid: Int32
    let iteration: Int
    let measuredIteration: Int
    let elapsedSeconds: TimeInterval
    let footprintBytes: UInt64
}

@MainActor private final class SystemHistorySoakState: ObservableObject {
    @Published var history: [SystemMetricsSnapshot] = []
    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    func advance(to iteration: Int) {
        // Rebuild the sliding window like the app, without retaining previous windows in the harness.
        history = (0...60).map { index in
            let step = iteration + index
            let used = UInt64(12_000_000_000 + (step % 100) * 10_000_000)
            let processes = (1...8).map { number in
                SystemProcessUsage(pid: Int32(number), name: "Synthetic process \(number)",
                    memoryBytes: UInt64(500_000_000 + number * 1_000_000),
                    cpuUsagePercent: Double((step + number) % 100))
            }
            return SystemMetricsSnapshot(sampledAt: epoch.addingTimeInterval(Double(step * 2)),
                cpuUsagePercent: Double(step % 100), gpuUsagePercent: Double((step * 3) % 100),
                memoryUsedBytes: used, memoryTotalBytes: 32_000_000_000,
                memoryAppBytes: used - 4_000_000_000, memoryWiredBytes: 3_000_000_000,
                memoryCompressedBytes: 1_000_000_000, memoryFreeBytes: 32_000_000_000 - used,
                memorySwapUsedBytes: 500_000_000, memoryPressure: .normal,
                cpuUserPercent: 20, cpuSystemPercent: 10, cpuIdlePercent: 70,
                physicalCoreCount: 8, logicalCoreCount: 8, loadAverages: [1, 2, 3],
                cpuTopProcesses: processes, memoryTopProcesses: processes,
                gpuDeviceNames: ["Synthetic GPU"], gpuHasUnifiedMemory: true)
        }
    }
}

private struct SystemHistorySoakView: View {
    @ObservedObject var state: SystemHistorySoakState
    let section: DetailSection

    var body: some View {
        SystemMetricsDetailView(section: section, snapshot: state.history.last, history: state.history)
            .padding(20)
            .frame(width: 480)
            .environment(\.locale, Locale(identifier: "en"))
    }
}
