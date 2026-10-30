import Foundation
import Testing
@testable import CodexMeterCore

@Suite struct ActivityMonitorTests {
    private let base = Date(timeIntervalSince1970: 1_793_145_600)
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private func row(_ seconds: Double, _ type: String, _ payload: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: ["timestamp": base.addingTimeInterval(seconds).ISO8601Format(.init(includingFractionalSeconds: true)),
            "type": type, "payload": payload])
        data.append(10)
        return data
    }
    private func metadata(_ id: String, origin: String = "Codex Desktop") throws -> Data {
        try row(0, "session_meta", ["id": id, "originator": origin, "cwd": "/synthetic/private/project"])
    }
    private func response(_ id: String, session: String = "main", index: Int = 0, validTPS: Bool = true) throws -> Data {
        let time = Double(index * 10 + 1)
        var data = Data()
        if validTPS {
            data.append(try row(time, "event_msg", ["type": "task_started", "turn_id": "turn-\(id)"]))
            data.append(try row(time, "turn_context", ["model": index < 20 ? "model-a" : "model-b"]))
            data.append(try row(time + 4, "response_item", ["type": "message", "role": "assistant", "id": "item-\(id)", "content": "synthetic-private-reply"]))
        }
        data.append(try row(time + 4.1, "token_usage_record", ["response_id": id, "thread_id": session,
            "usage": ["input_tokens": 1000, "cached_input_tokens": 400, "output_tokens": 100,
                      "reasoning_output_tokens": 40, "total_tokens": 1100],
            "thread_token_usage": ["input_tokens": 1000 * (index + 1), "output_tokens": 100 * (index + 1),
                                   "total_tokens": 1100 * (index + 1)]]))
        return data
    }
    private func home() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("codexmeter-activity-\(UUID())")
        try FileManager.default.createDirectory(at: url.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("archived_sessions"), withIntermediateDirectories: true)
        return url
    }

    @Test func todayIncludesUsageWithoutTPSWhileHistoryKeepsThirtyValidResponses() async throws {
        let home = try home(); defer { try? FileManager.default.removeItem(at: home) }
        var data = try metadata("main")
        for index in 0..<40 { data.append(try response("response-\(index)", index: index)) }
        data.append(try response("usage-only", index: 40, validTPS: false))
        try data.write(to: home.appendingPathComponent("sessions/main.jsonl"))
        let monitor = LogMonitor(home: home, persist: false)
        let snapshot = await monitor.poll(now: base.addingTimeInterval(1000), calendar: calendar)
        #expect(snapshot.todayUsage?.total == 41 * 1100)
        #expect(snapshot.todayUsage?.responses == 41)
        #expect(snapshot.recentSamples.count == 30)
        #expect(snapshot.recentSamples.first?.id == "response-10")
        #expect(snapshot.recentSamples.last?.id == "response-39")
        #expect(snapshot.latestSample?.id == "response-39")
    }

    @Test func partialAppendArchiveRestartAndCopiesDoNotDoubleCount() async throws {
        let home = try home(); defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent("sessions/main.jsonl")
        var data = try metadata("main"); data.append(try response("first"))
        try data.dropLast(12).write(to: path)
        let cache = home.appendingPathComponent("cache.json")
        let monitor = LogMonitor(home: home, cacheURL: cache)
        let first = await monitor.poll(now: base.addingTimeInterval(1000), calendar: calendar)
        #expect(first.todayUsage?.total == 0)
        let handle = try FileHandle(forWritingTo: path)
        try handle.seekToEnd(); try handle.write(contentsOf: data.suffix(12)); try handle.close()
        let complete = await monitor.poll(now: base.addingTimeInterval(1000), calendar: calendar)
        #expect(complete.todayUsage?.total == 1100)
        await monitor.flush()
        let archived = home.appendingPathComponent("archived_sessions/main.jsonl")
        try FileManager.default.moveItem(at: path, to: archived)
        try data.write(to: home.appendingPathComponent("sessions/copied.jsonl"))
        let restarted = LogMonitor(home: home, cacheURL: cache)
        for _ in 0..<3 { _ = await restarted.poll(now: base.addingTimeInterval(1000), calendar: calendar) }
        let result = await restarted.poll(now: base.addingTimeInterval(1000), calendar: calendar)
        #expect(result.todayUsage?.total == 1100)
        #expect(result.recentSamples.count == 1)
        await restarted.flush()
        let saved = try String(contentsOf: cache, encoding: .utf8)
        #expect(!saved.contains("synthetic-private") && !saved.contains("/synthetic/private/project"))
    }

    @Test func previousCheckpointBackfillsTodayWithoutDroppingLastValidSample() async throws {
        let home = try home(); defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent("sessions/main.jsonl")
        var data = try metadata("main")
        for index in 0..<4 { data.append(try response("response-\(index)", index: index)) }
        try data.write(to: path)
        let cache = home.appendingPathComponent("cache.json")
        let original = LogMonitor(home: home, cacheURL: cache)
        _ = await original.poll(now: base.addingTimeInterval(1000), calendar: calendar)
        await original.flush()
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: cache)) as? [String: Any])
        json["version"] = 2; json.removeValue(forKey: "activity"); json.removeValue(forKey: "history")
        var files = try #require(json["files"] as? [String: [String: Any]])
        for key in files.keys { files[key]?.removeValue(forKey: "usageParser") }
        json["files"] = files
        try JSONSerialization.data(withJSONObject: json).write(to: cache)
        let migrated = LogMonitor(home: home, cacheURL: cache)
        let result = await migrated.poll(now: base.addingTimeInterval(1000), calendar: calendar)
        #expect(result.todayUsage?.total == 4400)
        #expect(result.recentSamples.count == 4)
        #expect(result.latestSample?.id == "response-3")
    }

    @Test func midnightDoesNotCarryYesterdaysTotalAndMissingRootsAreUnavailable() async throws {
        let home = try home(); defer { try? FileManager.default.removeItem(at: home) }
        var data = try metadata("main"); data.append(try response("first"))
        try data.write(to: home.appendingPathComponent("sessions/main.jsonl"))
        let monitor = LogMonitor(home: home, persist: false)
        let before = await monitor.poll(now: base.addingTimeInterval(1000), calendar: calendar)
        let after = await monitor.poll(now: base.addingTimeInterval(86400 + 1000), calendar: calendar)
        #expect(before.todayUsage?.total == 1100)
        #expect(after.todayUsage?.total == 0)
        #expect(after.todayUsage?.dayStart != before.todayUsage?.dayStart)
        let missing = await LogMonitor(home: home.appendingPathComponent("missing"), persist: false).poll()
        #expect(missing.todayUsage?.logsAvailable == false)
        #expect(missing.todayUsage?.hasDesktopLogs == false)
    }

    @Test func historyPrefersDesktopOverNewerUnknownAndExcludesCLI() async throws {
        let home = try home(); defer { try? FileManager.default.removeItem(at: home) }
        for (name, origin, index) in [("main", "Codex Desktop", 1), ("unknown", "unknown", 2), ("cli", "codex_cli_rs", 3)] {
            var data = try metadata(name, origin: origin)
            data.append(try response("response-\(name)", session: name, index: index))
            try data.write(to: home.appendingPathComponent("sessions/\(name).jsonl"))
        }
        let result = await LogMonitor(home: home, persist: false).poll(now: base.addingTimeInterval(1000), calendar: calendar)
        #expect(result.recentSamples.map(\.id) == ["response-main"])
        #expect(result.todayUsage?.total == 1100)
    }

    @Test func boundedBackfillExposesProgressAndDoesNotStoreLargeIgnoredRecords() async throws {
        let home = try home(); defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent("sessions/large.jsonl")
        var initial = try metadata("main"); initial.append(try response("first"))
        try initial.write(to: path)
        let handle = try FileHandle(forWritingTo: path); try handle.seekToEnd()
        let ignored = try row(20, "ignored_record", ["text": String(repeating: "x", count: 2 * 1024 * 1024)])
        for _ in 0..<9 { try handle.write(contentsOf: ignored) }
        try handle.write(contentsOf: response("second", index: 2)); try handle.close()
        let cache = home.appendingPathComponent("cache.json")
        let monitor = LogMonitor(home: home, cacheURL: cache)
        let partial = await monitor.poll(now: base.addingTimeInterval(1000), calendar: calendar)
        #expect(partial.todayUsage?.isBackfilling == true)
        for _ in 0..<8 { _ = await monitor.poll(now: base.addingTimeInterval(1000), calendar: calendar) }
        let complete = await monitor.poll(now: base.addingTimeInterval(1000), calendar: calendar)
        #expect(complete.todayUsage?.total == 2200)
        #expect(complete.todayUsage?.isBackfilling == false)
        await monitor.flush()
        #expect(try Data(contentsOf: cache).count < 20_000)
    }
}
