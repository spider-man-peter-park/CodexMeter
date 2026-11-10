import Darwin
import Foundation
import Testing
@testable import CodexMeterCore

struct LogMonitorTests {
    private final class FileEvents: LogFileEventReading, @unchecked Sendable {
        private let lock = NSLock()
        private var changes: LogFileChanges?

        init(available: Bool = true) { changes = available ? LogFileChanges() : nil }

        func post(_ paths: URL..., mustRescan: Bool = false) {
            lock.lock()
            defer { lock.unlock() }
            changes?.paths.formUnion(paths.map { LogFilePaths.canonical($0) })
            changes?.mustRescan = mustRescan
        }

        func drain() -> LogFileChanges? {
            lock.lock()
            defer { lock.unlock() }
            let result = changes
            if changes != nil { changes = LogFileChanges() }
            return result
        }
    }

    private func row(_ second: Int, _ type: String, _ payload: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: [
            "timestamp": String(format: "2026-10-28T00:00:%02d.000Z", second), "type": type, "payload": payload])
        data.append(10)
        return data
    }
    private func response(_ id: String, end: Int, origin: String = "Codex Desktop", input: Int? = nil) throws -> Data {
        var data = Data()
        data.append(try row(0, "session_meta", ["id": id, "originator": origin, "source": "vscode"]))
        data.append(try row(1, "event_msg", ["type": "task_started", "turn_id": "turn-\(id)"]))
        data.append(try row(1, "turn_context", ["model": "fixture-model"]))
        data.append(try row(2, "response_item", ["type": "message", "role": "user"]))
        data.append(try row(end, "response_item", ["type": "message", "role": "assistant", "id": "item-\(id)"]))
        var usage = ["output_tokens": 100, "reasoning_output_tokens": 40]
        if let input { usage["input_tokens"] = input }
        data.append(try row(end, "token_usage_record", ["thread_id": id, "response_id": "response-\(id)",
            "usage": usage]))
        return data
    }
    private func temporaryHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("codexmeter-test-\(UUID())")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("sessions/2026/10/28"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("archived_sessions"), withIntermediateDirectories: true)
        return home
    }

    @Test func filesystemNotificationsIncludeWritesBeforeTheWriterCloses() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent("archived_sessions/notification.jsonl")
        try Data().write(to: path)
        let events = LogFileEvents(home: home)
        events.update(files: [LogFilePaths.canonical(path)], directories: [LogFilePaths.canonical(home)])
        _ = try #require(events.drain())
        let handle = try FileHandle(forWritingTo: path)
        defer { try? handle.close() }
        try handle.write(contentsOf: response("notification", end: 6))
        let changes = try #require(events.drain())
        #expect(changes.paths.contains(LogFilePaths.canonical(path)))
    }

    @Test func exhaustedWatcherBudgetRequestsOneReconciliationOnEveryPoll() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent("archived_sessions/unwatched.jsonl")
        try Data().write(to: path)
        let canonicalPath = LogFilePaths.canonical(path)
        let events = LogFileEvents(home: home, maximumWatches: 1)
        events.update(files: [canonicalPath], directories: [LogFilePaths.canonical(home)])
        #expect(try #require(events.drain()).requiresPolling)
        #expect(try #require(events.drain()).requiresPolling)
    }

    @Test func watchBudgetRaisesOnlyTheSoftLimitAndPreservesHeadroom() {
        var requests: [rlim_t] = []
        let increased = LogFileWatchBudget.limit(maximumWatches: 2_048, soft: 256, hard: 4_096) {
            requests.append($0)
            return true
        }
        #expect(increased == 2_048)
        #expect(requests == [2_112])
        requests.removeAll()
        let failed = LogFileWatchBudget.limit(maximumWatches: 2_048, soft: 256, hard: 4_096) {
            requests.append($0)
            return false
        }
        #expect(failed == 192)
        #expect(requests == [2_112])
        let bounded = LogFileWatchBudget.limit(maximumWatches: 2_048, soft: 256, hard: 512) {
            #expect($0 == 512)
            return true
        }
        #expect(bounded == 448)
        let alreadyAvailable = LogFileWatchBudget.limit(maximumWatches: 192, soft: 4_096, hard: 4_096) { _ in
            Issue.record("An adequate soft limit must not be changed.")
            return false
        }
        #expect(alreadyAvailable == 192)
    }

    @Test func registrationRechecksMetadataChangedBetweenDiscoveryAndWatching() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent("archived_sessions/registration.jsonl")
        try Data().write(to: path)
        let canonicalPath = LogFilePaths.canonical(path)
        let events = LogFileEvents(home: home)
        _ = events.drain()
        try response("registration", end: 6).write(to: path)
        events.update(files: [canonicalPath], directories: [LogFilePaths.canonical(home)])
        #expect(try #require(events.drain()).paths.contains(canonicalPath))
        #expect(try #require(events.drain()).paths.isEmpty)
    }

    @Test func notificationRefreshesAnOldFileAndNewNestedDirectoryImmediately() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let events = FileEvents()
        let path = home.appendingPathComponent("archived_sessions/old.jsonl")
        try response("old", end: 6).write(to: path)
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: path.path)
        let monitor = LogMonitor(home: home, persist: false, fileEvents: events)
        let now = Date()
        #expect((await monitor.poll(now: now)).latestSample?.id == "response-old")
        try response("replacement-with-longer-name", end: 9).write(to: path, options: .atomic)
        #expect((await monitor.poll(now: now.addingTimeInterval(2))).latestSample?.id == "response-old")
        events.post(path)
        #expect((await monitor.poll(now: now.addingTimeInterval(4))).latestSample?.id == "response-replacement-with-longer-name")

        let directory = home.appendingPathComponent("sessions/2026/11/07/new")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try response("nested", end: 12).write(to: directory.appendingPathComponent("new.jsonl"))
        events.post(home.appendingPathComponent("sessions/2026/11"))
        #expect((await monitor.poll(now: now.addingTimeInterval(6))).latestSample?.id == "response-nested")
    }

    @Test func periodicReconciliationAndDroppedEventsRecoverMissedChanges() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let events = FileEvents()
        let monitor = LogMonitor(home: home, persist: false, fileEvents: events)
        let now = Date()
        _ = await monitor.poll(now: now)
        let path = home.appendingPathComponent("archived_sessions/missed.jsonl")
        try response("missed", end: 6).write(to: path)
        #expect((await monitor.poll(now: now.addingTimeInterval(59))).latestSample == nil)
        #expect((await monitor.poll(now: now.addingTimeInterval(60))).latestSample?.id == "response-missed")
        try response("dropped", end: 9).write(to: path)
        events.post(mustRescan: true)
        #expect((await monitor.poll(now: now.addingTimeInterval(62))).latestSample?.id == "response-dropped")
    }

    @Test func unavailableNotificationsRetainImmediatePollingFallback() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let monitor = LogMonitor(home: home, persist: false, fileEvents: FileEvents(available: false))
        _ = await monitor.poll()
        let path = home.appendingPathComponent("archived_sessions/fallback.jsonl")
        try response("fallback", end: 6).write(to: path)
        #expect((await monitor.poll()).latestSample?.id == "response-fallback")
    }

    @Test func failedDirectoryListingRetriesWithoutAnotherNotification() async throws {
        let home = try temporaryHome()
        let directory = home.appendingPathComponent("sessions/2026/10/28")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: home)
        }
        let events = FileEvents()
        let monitor = LogMonitor(home: home, persist: false, fileEvents: events)
        _ = await monitor.poll()
        let path = directory.appendingPathComponent("unreadable.jsonl")
        try response("unreadable", end: 6).write(to: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: directory.path)
        events.post(directory)
        let failed = await monitor.poll()
        #expect(failed.latestSample == nil)
        #expect(failed.todayUsage?.logsAvailable == false)
        #expect((await monitor.poll()).todayUsage?.logsAvailable == false)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let recovered = await monitor.poll()
        #expect(recovered.latestSample?.id == "response-unreadable")
        #expect(recovered.todayUsage?.logsAvailable == true)
    }

    @Test func quotaTimestampsAcceptFractionalAndWholeSeconds() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent("archived_sessions/quota-dates.jsonl")
        var data = Data()
        for timestamp in ["2026-10-28T00:00:01.250Z", "2026-10-28T00:00:02Z"] {
            data.append(try JSONSerialization.data(withJSONObject: ["timestamp": timestamp, "type": "event_msg",
                "payload": ["type": "token_count", "rate_limits": ["primary": ["used_percent": 63,
                    "window_minutes": 10080, "resets_at": 1793602724]]]]))
            data.append(10)
        }
        try data.write(to: path)
        let snapshot = await LogMonitor(home: home, persist: false).poll()
        #expect(snapshot.cachedQuota?.weekly?.remainingPercent == 37)
        #expect(snapshot.cachedQuota?.updatedAt == Date(timeIntervalSince1970: 1_793_145_602))
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

    @Test func equalSizeRewriteWithinOneSecondIsDetected() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent("sessions/2026/10/28/rewrite.jsonl")
        let original = try response("old", end: 6)
        let replacement = try response("new", end: 9)
        #expect(original.count == replacement.count)
        try original.write(to: path)
        let second = Date(timeIntervalSince1970: 1_793_145_600)
        try FileManager.default.setAttributes([.modificationDate: second.addingTimeInterval(0.1)], ofItemAtPath: path.path)
        let monitor = LogMonitor(home: home, persist: false)
        #expect((await monitor.poll()).latestSample?.id == "response-old")

        let handle = try FileHandle(forWritingTo: path)
        try handle.write(contentsOf: replacement)
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: second.addingTimeInterval(0.2)], ofItemAtPath: path.path)
        #expect((await monitor.poll()).latestSample?.id == "response-new")
        #expect((await monitor.poll()).recentSamples.count == 2)
    }

    @Test func foundationTimestampCheckpointKeepsExistingParserState() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent("archived_sessions/legacy.jsonl")
        try response("legacy", end: 6).write(to: path)
        let timestamp = timespec(tv_sec: 1_793_145_600, tv_nsec: 123_456_789)
        let result = path.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return [timestamp, timestamp].withUnsafeBufferPointer { times in
                Darwin.utimensat(AT_FDCWD, path, times.baseAddress, 0)
            }
        }
        #expect(result == 0)
        let legacyDate = try #require(FileManager.default.attributesOfItem(atPath: path.path)[.modificationDate] as? Date)
        let cache = home.appendingPathComponent("checkpoint.json")
        let original = LogMonitor(home: home, cacheURL: cache)
        let before = await original.poll()
        await original.flush()
        var saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: cache)) as? [String: Any])
        var files = try #require(saved["files"] as? [String: [String: Any]])
        let identity = try #require(files.keys.first)
        var cursor = try #require(files[identity])
        cursor["modifiedAt"] = legacyDate.timeIntervalSinceReferenceDate
        var parser = try #require(cursor["parser"] as? [String: Any])
        var responseIDs = parser["seenResponseIDs"] as? [String] ?? []
        responseIDs.append("checkpoint-only-response")
        parser["seenResponseIDs"] = responseIDs
        cursor["parser"] = parser
        files[identity] = cursor
        saved["files"] = files
        try JSONSerialization.data(withJSONObject: saved).write(to: cache)

        let restored = LogMonitor(home: home, cacheURL: cache)
        #expect((await restored.poll()).latestSample == before.latestSample)
        await restored.flush()
        let updated = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: cache)) as? [String: Any])
        let updatedFiles = try #require(updated["files"] as? [String: [String: Any]])
        let updatedParser = try #require(updatedFiles[identity]?["parser"] as? [String: Any])
        #expect((updatedParser["seenResponseIDs"] as? [String])?.contains("checkpoint-only-response") == true)
    }

    @Test func archiveMoveKeepsOneCursorAndLaterAppendsRemainVisible() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent("sessions/2026/10/28/moving.jsonl")
        try response("moving", end: 6).write(to: path)
        let cache = home.appendingPathComponent("checkpoint.json")
        let monitor = LogMonitor(home: home, cacheURL: cache)
        let original = await monitor.poll()
        let archive = home.appendingPathComponent("archived_sessions/moving.jsonl")
        try FileManager.default.moveItem(at: path, to: archive)
        #expect((await monitor.poll()).latestSample == original.latestSample)

        var appended = try row(7, "event_msg", ["type": "task_started", "turn_id": "second"])
        appended.append(try row(11, "response_item", ["type": "message", "role": "assistant", "id": "second-item"]))
        appended.append(try row(11, "token_usage_record", ["thread_id": "moving", "response_id": "second-response",
            "usage": ["output_tokens": 200, "reasoning_output_tokens": 40]]))
        let handle = try FileHandle(forWritingTo: archive)
        try handle.seekToEnd()
        try handle.write(contentsOf: appended)
        try handle.close()
        let updated = await monitor.poll()
        #expect(updated.latestSample?.id == "second-response")
        #expect(updated.recentSamples.count == 2)
        await monitor.flush()
        let saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: cache)) as? [String: Any])
        #expect((saved["files"] as? [String: Any])?.count == 1)
    }

    @Test func completeReconciliationReleasesDeletedCursorsAndKeepsRecordedUsage() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent("sessions/2026/10/28/deleted.jsonl")
        var data = try response("deleted", end: 6, input: 50)
        data.append(try row(7, "event_msg", ["type": "token_count", "rate_limits": [
            "primary": ["used_percent": 63, "window_minutes": 10080]]]))
        try data.write(to: path)
        let cache = home.appendingPathComponent("checkpoint.json")
        let events = FileEvents()
        let monitor = LogMonitor(home: home, cacheURL: cache, fileEvents: events)
        let now = try Date.ISO8601FormatStyle().parse("2026-10-28T12:00:00Z")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let original = await monitor.poll(now: now, calendar: calendar)
        #expect(original.todayUsage?.input == 50)
        #expect(original.todayUsage?.output == 100)
        #expect(original.todayUsage?.isPartial == false)
        await monitor.flush()
        #expect(try checkpointFiles(cache).count == 1)

        try FileManager.default.removeItem(at: path)
        events.post(path)
        _ = await monitor.poll(now: now.addingTimeInterval(2), calendar: calendar)
        await monitor.flush()
        #expect(try checkpointFiles(cache).count == 1)

        events.post(mustRescan: true)
        let cleaned = await monitor.poll(now: now.addingTimeInterval(4), calendar: calendar)
        await monitor.flush()
        #expect(try checkpointFiles(cache).isEmpty)
        #expect(cleaned.latestSample == original.latestSample)
        #expect(cleaned.latestResponseAt == original.latestResponseAt)
        #expect(cleaned.cachedQuota == original.cachedQuota)
        #expect(cleaned.recentSamples == original.recentSamples)
        #expect(cleaned.todayUsage?.input == 50)
        #expect(cleaned.todayUsage?.output == 100)
        #expect(cleaned.todayUsage?.responses == 1)
        #expect(cleaned.todayUsage?.isPartial == false)

        let restarted = LogMonitor(home: home, cacheURL: cache)
        let restored = await restarted.poll(now: now.addingTimeInterval(6), calendar: calendar)
        #expect(restored.latestSample == original.latestSample)
        #expect(restored.todayUsage?.output == 100)
        try response("replacement", end: 9, input: 100).write(to: path)
        events.post(path)
        let replaced = await monitor.poll(now: now.addingTimeInterval(8), calendar: calendar)
        #expect(replaced.latestSample?.id == "response-replacement")
        #expect(replaced.todayUsage?.input == 150)
        #expect(replaced.todayUsage?.output == 200)
        #expect(replaced.todayUsage?.responses == 2)
    }

    @Test func incompleteReconciliationRetainsUnreachableCursors() async throws {
        let home = try temporaryHome()
        let directory = home.appendingPathComponent("sessions/2026/10/28")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: home)
        }
        let path = directory.appendingPathComponent("retained.jsonl")
        try response("retained", end: 6, input: 50).write(to: path)
        let cache = home.appendingPathComponent("checkpoint.json")
        let events = FileEvents()
        let monitor = LogMonitor(home: home, cacheURL: cache, fileEvents: events)
        let now = Date()
        let original = await monitor.poll(now: now)
        await monitor.flush()
        let initialFiles = try checkpointFiles(cache)
        #expect(initialFiles.count == 1)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: directory.path)
        events.post(mustRescan: true)
        let failed = await monitor.poll(now: now.addingTimeInterval(2))
        await monitor.flush()
        #expect(try checkpointFiles(cache).keys.sorted() == initialFiles.keys.sorted())
        #expect(failed.latestSample == original.latestSample)
        #expect(failed.todayUsage?.logsAvailable == false)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        #expect((await monitor.poll(now: now.addingTimeInterval(4))).latestSample == original.latestSample)
        await monitor.flush()
        #expect(try checkpointFiles(cache).keys.sorted() == initialFiles.keys.sorted())
    }

    @Test func restoredCleanupIsAutomaticallySavedWithoutNewLogBytes() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent("archived_sessions/restored-cleanup.jsonl")
        try response("restored-cleanup", end: 6, input: 50).write(to: path)
        let cache = home.appendingPathComponent("checkpoint.json")
        let original = LogMonitor(home: home, cacheURL: cache)
        let before = await original.poll()
        await original.flush()
        #expect(try checkpointFiles(cache).count == 1)
        try FileManager.default.removeItem(at: path)

        let restored = LogMonitor(home: home, cacheURL: cache)
        #expect((await restored.poll()).latestSample == before.latestSample)
        // A cleanup-only poll must persist on the normal save schedule, without a manual flush.
        #expect(try checkpointFiles(cache).isEmpty)
    }

    @Test func failedCheckpointSaveRetriesOnAnIdlePollAfterTheThrottle() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent("archived_sessions/save-retry.jsonl")
        try response("save-retry", end: 6, input: 50).write(to: path)
        let parent = home.appendingPathComponent("blocked-cache")
        try Data().write(to: parent)
        let cache = parent.appendingPathComponent("checkpoint.json")
        let monitor = LogMonitor(home: home, cacheURL: cache, fileEvents: FileEvents())
        let now = Date()
        let original = await monitor.poll(now: now)
        #expect(!FileManager.default.fileExists(atPath: cache.path))

        try FileManager.default.removeItem(at: parent)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        _ = await monitor.poll(now: now.addingTimeInterval(1))
        #expect(!FileManager.default.fileExists(atPath: cache.path))
        // Real time verifies that retries obey the production disk-write throttle without new log bytes.
        try await Task.sleep(for: .seconds(10.1))
        #expect((await monitor.poll(now: now.addingTimeInterval(12))).latestSample == original.latestSample)
        #expect(FileManager.default.fileExists(atPath: cache.path))
        #expect(try checkpointFiles(cache).count == 1)
    }

    @Test func deletedUnsupportedCursorKeepsTodayPartialUntilTheNextDay() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent("archived_sessions/unsupported.jsonl")
        try response("unsupported", end: 6).write(to: path)
        let cache = home.appendingPathComponent("checkpoint.json")
        let events = FileEvents()
        let monitor = LogMonitor(home: home, cacheURL: cache, fileEvents: events)
        let now = try Date.ISO8601FormatStyle().parse("2026-10-28T12:00:00Z")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        #expect((await monitor.poll(now: now, calendar: calendar)).todayUsage?.isPartial == true)
        try FileManager.default.removeItem(at: path)
        events.post(mustRescan: true)
        #expect((await monitor.poll(now: now.addingTimeInterval(2), calendar: calendar)).todayUsage?.isPartial == true)
        await monitor.flush()
        #expect(try checkpointFiles(cache).count == 1)
        events.post(mustRescan: true)
        #expect((await monitor.poll(now: now.addingTimeInterval(86400), calendar: calendar)).todayUsage?.isPartial == false)
        await monitor.flush()
        #expect(try checkpointFiles(cache).isEmpty)
    }

    private func checkpointFiles(_ url: URL) throws -> [String: [String: Any]] {
        let saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try #require(saved["files"] as? [String: [String: Any]])
    }

    @Test func symlinkFilesAndDirectoriesAreSkippedEvenWithCachedListing() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appendingPathComponent("sessions/2026/10/28")
        let original = folder.appendingPathComponent("original.jsonl")
        try response("original", end: 6).write(to: original)
        let outside = home.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let target = outside.appendingPathComponent("newer.jsonl")
        try response("linked", end: 12).write(to: target)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("file-link.jsonl"), withDestinationURL: target)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("directory-link"), withDestinationURL: outside)
        let monitor = LogMonitor(home: home, persist: false)
        let initial = await monitor.poll()
        #expect(initial.latestSample?.id == "response-original")

        let folderDate = try #require(FileManager.default.attributesOfItem(atPath: folder.path)[.modificationDate] as? Date)
        try FileManager.default.removeItem(at: original)
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: target)
        try FileManager.default.setAttributes([.modificationDate: folderDate], ofItemAtPath: folder.path)
        #expect((await monitor.poll()).latestSample == initial.latestSample)
        #expect((await monitor.poll()).recentSamples.count == 1)
    }

}
