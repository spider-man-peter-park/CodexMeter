import Foundation
import Testing
@testable import CodexMeterCore

struct LogMonitorTests {
    private func row(_ second: Int, _ type: String, _ payload: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: [
            "timestamp": String(format: "2026-10-28T00:00:%02d.000Z", second), "type": type, "payload": payload])
        data.append(10)
        return data
    }
    private func response(_ id: String, end: Int, origin: String = "Codex Desktop") throws -> Data {
        var data = Data()
        data.append(try row(0, "session_meta", ["id": id, "originator": origin, "source": "vscode"]))
        data.append(try row(1, "event_msg", ["type": "task_started", "turn_id": "turn-\(id)"]))
        data.append(try row(1, "turn_context", ["model": "fixture-model"]))
        data.append(try row(2, "response_item", ["type": "message", "role": "user"]))
        data.append(try row(end, "response_item", ["type": "message", "role": "assistant", "id": "item-\(id)"]))
        data.append(try row(end, "token_usage_record", ["thread_id": id, "response_id": "response-\(id)",
            "usage": ["output_tokens": 100, "reasoning_output_tokens": 40]]))
        return data
    }
    private func temporaryHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("codexmeter-test-\(UUID())")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("sessions/2026/10/28"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("archived_sessions"), withIntermediateDirectories: true)
        return home
    }

    @Test func latestValidAcrossSessionsIgnoresNewerInvalidResponse() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appendingPathComponent("sessions/2026/10/28")
        try response("older", end: 6).write(to: folder.appendingPathComponent("older.jsonl"))
        var newer = try response("newer", end: 9)
        newer.append(try row(11, "event_msg", ["type": "task_started", "turn_id": "bad"]))
        newer.append(try row(12, "token_usage_record", ["response_id": "unmeasurable", "thread_id": "newer", "usage": ["output_tokens": 200]]))
        try newer.write(to: folder.appendingPathComponent("newer.jsonl"))
        let monitor = LogMonitor(home: home, persist: false)
        let snapshot = await monitor.poll()
        #expect(snapshot.latestSample?.id == "response-newer")
        #expect(snapshot.hasUnmeasurableResponse)
        #expect(snapshot.latestSample?.outputTokens == 100)
    }

    @Test func partialTailThenAppendArchiveAndRestartAreIdempotent() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent("sessions/2026/10/28/partial.jsonl")
        let full = try response("partial", end: 6)
        let cut = full.count - 11
        try full.prefix(cut).write(to: path)
        let cache = home.appendingPathComponent("checkpoint.json")
        let monitor = LogMonitor(home: home, cacheURL: cache)
        let initial = await monitor.poll()
        #expect(initial.latestSample == nil)
        let handle = try FileHandle(forWritingTo: path)
        try handle.seekToEnd()
        try handle.write(contentsOf: full.suffix(from: cut))
        try handle.close()
        let complete = await monitor.poll()
        #expect(complete.latestSample?.tokensPerSecond == 25)
        await monitor.flush()
        let archive = home.appendingPathComponent("archived_sessions/moved.jsonl")
        try FileManager.default.moveItem(at: path, to: archive)
        let restarted = LogMonitor(home: home, cacheURL: cache)
        let restored = await restarted.poll()
        #expect(restored.latestSample == complete.latestSample)
        #expect((await restarted.poll()).latestSample == complete.latestSample)
        let checkpointText = try String(contentsOf: cache, encoding: .utf8)
        #expect(!checkpointText.contains("response_item"))
        #expect(!checkpointText.contains("content"))
    }

    @Test func failureCanUseLatestLogQuotaAndNoDataStaysMissing() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let monitor = LogMonitor(home: home, persist: false)
        let empty = await monitor.poll()
        #expect(empty.latestSample == nil)
        #expect(empty.cachedQuota == nil)
        let data = try row(1, "event_msg", ["type": "token_count", "rate_limits": [
            "primary": ["used_percent": 63, "window_minutes": 10080, "resets_at": 1793602724]]])
        try data.write(to: home.appendingPathComponent("archived_sessions/quota.jsonl"))
        let cached = await monitor.poll()
        #expect(cached.cachedQuota?.weekly?.remainingPercent == 37)
        #expect(cached.cachedQuota?.fiveHour == nil)
        #expect(cached.cachedQuota?.isStale == true)
        #expect(cached.cachedQuota?.source == .logCache)
    }

    @Test func desktopTakesPriorityOverUnknownAndCLI() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appendingPathComponent("archived_sessions")
        try response("desktop", end: 6).write(to: folder.appendingPathComponent("desktop.jsonl"))
        try response("unknown", end: 10, origin: "unknown").write(to: folder.appendingPathComponent("unknown.jsonl"))
        try response("cli", end: 12, origin: "Codex CLI").write(to: folder.appendingPathComponent("cli.jsonl"))
        let snapshot = await LogMonitor(home: home, persist: false).poll()
        #expect(snapshot.latestSample?.id == "response-desktop")
    }

    @Test func truncateThenRewriteStartsANewParser() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent("archived_sessions/session.jsonl")
        var original = try response("long-session-name", end: 6)
        original.append(Data(repeating: 32, count: 2000)); original.append(10)
        try original.write(to: path)
        let monitor = LogMonitor(home: home, persist: false)
        #expect((await monitor.poll()).latestSample?.id == "response-long-session-name")
        try response("new", end: 9).write(to: path)
        #expect((await monitor.poll()).latestSample?.id == "response-new")
    }
    @Test func oversizedUnterminatedRecordIsBoundedAndPreservesExcludedSource() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent("archived_sessions/oversized.jsonl")
        var data = try row(0, "session_meta", ["id": "subagent", "source": ["subagent": "review"]])
        data.append(Data(repeating: 65, count: 10 * 1024 * 1024))
        try data.write(to: path)
        let cache = home.appendingPathComponent("checkpoint.json")
        let monitor = LogMonitor(home: home, cacheURL: cache)
        for _ in 0..<4 { _ = await monitor.poll() }
        let handle = try FileHandle(forWritingTo: path)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([10]))
        try handle.write(contentsOf: response("replayed-parent", end: 6))
        try handle.close()
        for _ in 0..<3 { _ = await monitor.poll() }
        #expect((await monitor.poll()).latestSample == nil)
        await monitor.flush()
        #expect(try Data(contentsOf: cache).count < 5000)
    }

    @Test func rewriteBeyondCursorAndUnmeasurableTruncationKeepLastValid() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent("archived_sessions/rewrite.jsonl")
        try response("old", end: 6).write(to: path)
        let monitor = LogMonitor(home: home, persist: false)
        let previous = await monitor.poll()
        #expect(previous.latestSample?.id == "response-old")
        var replacement = try response("new-session-with-longer-header-and-different-identity", end: 9)
        replacement.append(try row(10, "event_msg", ["type": "token_count", "padding": String(repeating: "x", count: 1024)]))
        let handle = try FileHandle(forWritingTo: path)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: replacement)
        try handle.close()
        let rewritten = await monitor.poll()
        #expect(rewritten.latestSample?.id == "response-new-session-with-longer-header-and-different-identity")
        try Data().write(to: path)
        #expect((await monitor.poll()).latestSample == rewritten.latestSample)
        var invalid = try row(0, "session_meta", ["id": "unmeasurable", "originator": "Codex Desktop"])
        invalid.append(try row(12, "event_msg", ["type": "task_started"]))
        invalid.append(try row(13, "token_usage_record", ["response_id": "invalid", "thread_id": "unmeasurable", "usage": ["output_tokens": 100]]))
        try invalid.write(to: path)
        let latest = await monitor.poll()
        #expect(latest.latestSample == rewritten.latestSample)
        #expect(latest.hasUnmeasurableResponse)
    }

}
