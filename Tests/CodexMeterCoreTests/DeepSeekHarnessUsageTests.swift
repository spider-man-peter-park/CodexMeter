import Foundation
import Testing
@testable import CodexMeterCore

struct DeepSeekHarnessUsageTests {
    private func home() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("codexmeter-dsh-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("storages/session_projcache/sessions"), withIntermediateDirectories: true)
        return home
    }

    private func document(input: Int = 10, output: Int = 20, cache: Int = 3, write: Int = 2,
                          modelMS: Double = 2_000, decodeMS: Double = 1_000, decoded: Int = 20,
                          seeded: Bool = false, inherited: Int = 0) -> [String: Any] {
        ["version": 7, "record": [
            "identity": ["formatVersion": 4, "createdAt": 1, "isSeeded": seeded, "inheritedEventCount": inherited],
            "rows": [
                "tokenUsage": ["ver": 2, "seq": 10, "val": ["totals": ["uncachedInputTokens": input,
                    "outputTokens": output, "cacheReadTokens": cache, "cacheWriteTokens": write], "last": NSNull()]],
                "sessionStats": ["ver": 1, "seq": 10, "val": ["llmMs": modelMS, "decodeMs": decodeMS, "decodeTokens": decoded]]
            ]
        ]]
    }

    @discardableResult private func save(_ document: [String: Any], named name: String = "session-a", home: URL) throws -> URL {
        let file = home.appendingPathComponent("storages/session_projcache/sessions/" + name + ".json")
        try JSONSerialization.data(withJSONObject: document).write(to: file, options: .atomic)
        return file
    }

    @Test func aggregatesDisjointTokensAndWeightedDecodeWithoutInventingBillingOrDailyUsage() async throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        try save(document(), home: home)
        try save(document(input: 30, output: 40, cache: 5, write: 0, modelMS: 3_000, decodeMS: 2_000, decoded: 40), named: "session-b", home: home)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let result = await DeepSeekHarnessUsageReader(home: home).readUsage(now: now)
        let value = try #require(result.snapshot)
        #expect(result.status == .ready)
        #expect(value.scope == .localSessions && value.sampledAt == now)
        #expect(value.inputTokens == 50 && value.outputTokens == 60 && value.totalTokens == 110)
        #expect(value.cachedInputTokens == 8 && value.cacheWriteTokens == 2)
        #expect(value.modelSeconds == 5 && value.decodeTokensPerSecond == 20)
        #expect(value.sessionCount == 2 && value.sessions.count == 2 && !value.isPartial)
        #expect(value.costUSD == nil && value.usedPercent == nil && value.periodStart == nil && value.requestCount == nil)
        #expect(result.message.contains("not today's usage or an account bill"))
    }

    @Test func excludesInheritedPrefixesInsteadOfDoubleCountingForks() async throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        try save(document(), home: home)
        try save(document(input: 1_000, seeded: true), named: "fork", home: home)
        try save(document(input: 2_000, inherited: 3), named: "inherited", home: home)
        let value = try #require(await DeepSeekHarnessUsageReader(home: home).readUsage().snapshot)
        #expect(value.totalTokens == 35 && value.sessionCount == 1 && value.isPartial)
        #expect(value.sessions.map(\.id) == ["session-a"])
    }

    @Test func preservesRecordedZeroAndDoesNotTurnAbsentRowsIntoZero() async throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = try save(document(input: 0, output: 0, cache: 0, write: 0, modelMS: 0, decodeMS: 0, decoded: 0), home: home)
        let reader = DeepSeekHarnessUsageReader(home: home)
        let zero = try #require(await reader.readUsage().snapshot)
        #expect(zero.totalTokens == 0 && zero.modelSeconds == 0 && zero.decodeTokensPerSecond == nil)
        try FileManager.default.removeItem(at: file)
        try save(["version": 7, "record": ["identity": ["isSeeded": false, "inheritedEventCount": 0], "rows": [:]]], home: home)
        let missing = await reader.readUsage()
        #expect(missing.status == .unsupported && missing.snapshot == nil)
    }

    @Test func incompatibleMalformedAndUnsafeCountersCannotProduceAZeroSnapshot() async throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        var wrong = document()
        wrong["version"] = 8
        let file = try save(wrong, home: home)
        let reader = DeepSeekHarnessUsageReader(home: home)
        #expect(await reader.readUsage().status == .unsupported)
        try Data("{broken".utf8).write(to: file)
        #expect(await reader.readUsage().snapshot == nil)
        try save(document(input: Int.max), home: home)
        #expect(await reader.readUsage().snapshot == nil)
        try save(document(input: -1), home: home)
        #expect(await reader.readUsage().snapshot == nil)
        try save(document(), named: "good", home: home)
        let partial = try #require(await reader.readUsage().snapshot)
        #expect(partial.totalTokens == 35 && partial.isPartial && partial.sessionCount == 1)
    }

    @Test func rowVersionGatesPreserveOnlySupportedMeasurements() async throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        var fixture = document()
        var record = try #require(fixture["record"] as? [String: Any])
        var rows = try #require(record["rows"] as? [String: Any])
        rows["tokenUsage"] = ["ver": 3, "val": [:]]
        record["rows"] = rows
        fixture["record"] = record
        try save(fixture, home: home)
        let value = try #require(await DeepSeekHarnessUsageReader(home: home).readUsage().snapshot)
        #expect(value.totalTokens == nil && value.modelSeconds == 2 && value.isPartial)
    }

    @Test func metadataCacheInvalidatesOnReplacementAppendAndDeletionAndSkipsSymlinksAndBackups() async throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = try save(document(), home: home)
        let reader = DeepSeekHarnessUsageReader(home: home)
        #expect(await reader.readUsage().snapshot?.totalTokens == 35)
        let oldTime = try #require(file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        try save(document(input: 11), home: home)
        try FileManager.default.setAttributes([.modificationDate: oldTime], ofItemAtPath: file.path)
        #expect(await reader.readUsage().snapshot?.totalTokens == 36)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(" ".utf8))
        try handle.close()
        #expect(await reader.readUsage().snapshot?.totalTokens == 36)
        let backup = file.deletingLastPathComponent().appendingPathComponent("backup.json.bak")
        try FileManager.default.copyItem(at: file, to: backup)
        let link = file.deletingLastPathComponent().appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let linked = try #require(await reader.readUsage().snapshot)
        #expect(linked.totalTokens == 36 && linked.sessionCount == 1 && linked.isPartial)
        try FileManager.default.removeItem(at: link)
        try FileManager.default.removeItem(at: file)
        let empty = try #require(await reader.readUsage().snapshot)
        #expect(empty.totalTokens == nil && empty.sessionCount == 0)
        try FileManager.default.removeItem(at: home.appendingPathComponent("storages"))
        #expect(await reader.readUsage().status == .notFound)
    }

    @Test func aggregateOverflowAndSessionLimitRemainPartialAndBounded() async throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        let maximum = 9_007_199_254_740_991
        for index in 0..<2_001 {
            try save(document(input: maximum, output: 0, cache: 0, write: 0), named: "session-\(index)", home: home)
        }
        let value = try #require(await DeepSeekHarnessUsageReader(home: home).readUsage().snapshot)
        #expect(value.inputTokens == nil && value.totalTokens == nil && value.isPartial)
        #expect(value.outputTokens == 0 && value.sessionCount == 2_000 && value.sessions.count == 50)
    }

    @Test func oversizedCheckpointsAreSkippedWithoutHidingReadableSessions() async throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        try save(document(), home: home)
        let large = home.appendingPathComponent("storages/session_projcache/sessions/oversized.json")
        try Data().write(to: large)
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: 16 * 1_024 * 1_024 + 1)
        try handle.close()
        let value = try #require(await DeepSeekHarnessUsageReader(home: home).readUsage().snapshot)
        #expect(value.totalTokens == 35 && value.sessionCount == 1 && value.isPartial)
    }
}
