import Darwin
import Foundation
import Testing
@testable import CodexMeterCore

@Suite(.serialized) struct LogMonitorPerformanceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CODEXMETER_LOG_BENCHMARK"] == "1"))
    func excludedTPSCPU() throws {
        var parser = SessionParser()
        _ = parser.consume(try JSONSerialization.data(withJSONObject: ["timestamp": "2026-11-06T00:00:00Z",
            "type": "session_meta", "payload": ["id": "child", "source": ["subagent": "review"]]]))
        let line = try JSONSerialization.data(withJSONObject: ["timestamp": "2026-11-06T00:00:01Z",
            "type": "response_item", "payload": ["type": "custom_tool_call_output", "output": String(repeating: "x", count: 65_536)]])
        let records = 2_000
        let cpuStart = cpuSeconds()
        let wallStart = ProcessInfo.processInfo.systemUptime
        for _ in 0..<records { #expect(parser.consume(line) == nil) }
        let result: [String: Any] = ["records": records, "record_bytes": line.count,
            "cpu_seconds": cpuSeconds() - cpuStart,
            "wall_seconds": ProcessInfo.processInfo.systemUptime - wallStart]
        let encoded = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print("CODEXMETER_EXCLUDED_TPS_BENCHMARK \(String(decoding: encoded, as: UTF8.self))")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CODEXMETER_LOG_BENCHMARK"] == "1"))
    func idlePollCPU() async throws {
        try await measureIdlePoll(maximumWatches: nil, directoryCount: 1)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CODEXMETER_LOG_BENCHMARK"] == "1"))
    func idlePollCPUWithLimitedWatches() async throws {
        try await measureIdlePoll(maximumWatches: 192, directoryCount: 250)
    }

    private func measureIdlePoll(maximumWatches: Int?, directoryCount: Int) async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("codexmeter-log-benchmark-\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        let sessions = home.appendingPathComponent("sessions/2026/11/06")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("archived_sessions"), withIntermediateDirectories: true)
        let fileCount = 1_000
        let polls = 30
        let folders = try (0..<directoryCount).map { index in
            let folder = sessions.appendingPathComponent("bucket-\(index)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
        for index in 0..<fileCount {
            let source: [String: Any] = index % 5 == 0
                ? ["originator": "Codex Desktop"]
                : ["source": ["subagent": ["thread_spawn": ["parent_thread_id": "session-0"]]]]
            var payload = source
            payload["id"] = "session-\(index)"
            var line = try JSONSerialization.data(withJSONObject: ["timestamp": "2026-11-06T00:00:00.000Z",
                "type": "session_meta", "payload": payload])
            line.append(10)
            try line.write(to: folders[index % directoryCount].appendingPathComponent("session-\(index).jsonl"))
        }
        let monitor = maximumWatches.map {
            LogMonitor(home: home, persist: false, fileEvents: LogFileEvents(home: home, maximumWatches: $0))
        } ?? LogMonitor(home: home, persist: false)
        for _ in 0..<3 { _ = await monitor.poll() }
        let cpuStart = cpuSeconds()
        let wallStart = ProcessInfo.processInfo.systemUptime
        for _ in 0..<polls { _ = await monitor.poll() }
        let result: [String: Any] = ["files": fileCount, "polls": polls, "directories": directoryCount,
            "maximum_watches": maximumWatches ?? 2_048,
            "cpu_seconds": cpuSeconds() - cpuStart,
            "wall_seconds": ProcessInfo.processInfo.systemUptime - wallStart]
        let encoded = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print("CODEXMETER_LOG_BENCHMARK \(String(decoding: encoded, as: UTF8.self))")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CODEXMETER_LOG_BENCHMARK"] == "1"))
    func idleLedgerCPU() throws {
        let now = Date(timeIntervalSince1970: 1_793_188_800)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var state = LocalActivityState()
        state.origins["main"] = LocalSessionOrigin(kind: .desktop, modernSeen: true)
        let eventCount = 6_834
        let polls = 300
        for index in 0..<eventCount {
            let key = "response-\(index)"
            state.events[key] = LocalUsageEvent(session: "main", aliases: [key],
                timestamp: now.addingTimeInterval(-Double(index * 20)), input: 1000, output: 100,
                cached: 400, reasoning: 40, modern: true, responseKey: key)
        }
        var ledger = LocalActivityLedger(state: state)
        _ = ledger.summary(now: now, calendar: calendar, backfilling: false, partial: false)
        let cpuStart = cpuSeconds()
        let wallStart = ProcessInfo.processInfo.systemUptime
        for index in 0..<polls {
            let time = now.addingTimeInterval(Double(index * 2))
            ledger.prune(now: time)
            _ = ledger.summary(now: time, calendar: calendar, backfilling: false, partial: false)
        }
        let result: [String: Any] = ["events": eventCount, "polls": polls,
            "cpu_seconds": cpuSeconds() - cpuStart,
            "wall_seconds": ProcessInfo.processInfo.systemUptime - wallStart]
        let encoded = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print("CODEXMETER_LEDGER_BENCHMARK \(String(decoding: encoded, as: UTF8.self))")
    }

    private func cpuSeconds() -> Double {
        var time = timespec()
        clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &time)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
    }
}
