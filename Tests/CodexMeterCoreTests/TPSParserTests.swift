import Foundation
import Testing
@testable import CodexMeterCore

struct TPSParserTests {
    private let session = "session-main"

    private func row(_ second: Double, _ type: String, _ payload: [String: Any]) -> Data {
        let timestamp = "2026-10-28T00:00:" + String(format: "%06.3f", second) + "Z"
        return try! JSONSerialization.data(withJSONObject: ["timestamp": timestamp, "type": type, "payload": payload])
    }

    private func meta(_ extra: [String: Any] = [:]) -> Data {
        var payload: [String: Any] = ["id": session, "originator": "Codex Desktop", "source": "vscode", "thread_source": "user"]
        payload.merge(extra, uniquingKeysWith: { _, new in new })
        return row(0, "session_meta", payload)
    }

    private func start(_ second: Double = 0, model: String = "test-model") -> [Data] {
        [row(second, "event_msg", ["type": "task_started", "turn_id": "turn-a"]),
         row(second + 0.1, "turn_context", ["turn_id": "turn-a", "model": model]),
         row(second + 1, "response_item", ["type": "message", "role": "user", "id": "user-\(second)"])]
    }

    private func generated(_ second: Double, id: String = "message-a") -> Data {
        row(second, "response_item", ["type": "message", "role": "assistant", "status": "completed", "id": id])
    }

    private func usage(_ output: Int, reasoning: Int = 0, input: Int = 1000) -> [String: Any] {
        ["output_tokens": output, "reasoning_output_tokens": reasoning, "input_tokens": input, "total_tokens": input + output]
    }

    private func count(_ second: Double, output: Int, reasoning: Int = 0, totalOutput: Int? = nil, input: Int = 1000) -> Data {
        row(second, "event_msg", ["type": "token_count", "info": [
            "last_token_usage": usage(output, reasoning: reasoning, input: input),
            "total_token_usage": usage(totalOutput ?? output, reasoning: reasoning, input: input)]])
    }

    private func modern(_ second: Double, id: String = "response-a", output: Int = 100,
                        reasoning: Int = 0, totalOutput: Int? = nil, thread: String? = nil) -> Data {
        row(second, "token_usage_record", ["response_id": id, "thread_id": thread ?? session,
            "usage": usage(output, reasoning: reasoning),
            "thread_token_usage": usage(totalOutput ?? output, reasoning: reasoning)])
    }

    @discardableResult
    private func feed(_ parser: inout SessionParser, _ lines: [Data]) -> [TPSSample] {
        lines.compactMap { parser.consume($0) }
    }

    @Test func testOrdinaryResponseUsesIncrementAndIncludesReasoningExactlyOnce() throws {
        var parser = SessionParser()
        let samples = feed(&parser, [meta()] + start() + [generated(6), count(6.1, output: 100, reasoning: 40, totalOutput: 9000)])
        let sample = try #require(samples.first)
        #expect((samples.count) == (1))
        #expect((sample.outputTokens) == (100))
        #expect((sample.reasoningTokens) == (40))
        #expect(abs((sample.elapsedSeconds) - (5)) <= 0.0001)
        #expect(abs((sample.tokensPerSecond) - (20)) <= 0.0001)
        #expect((sample.model) == ("test-model"))
        #expect(sample.isEstimated)
        #expect((parser.source) == (.desktop))
    }

    @Test func testModernResponseEndsBeforeToolExecutionAndDeduplicatesLegacyUsage() throws {
        var parser = SessionParser()
        let call = row(5, "response_item", ["type": "custom_tool_call", "status": "completed", "call_id": "call-a", "id": "tool-a"])
        let output = row(15, "response_item", ["type": "custom_tool_call_output", "call_id": "call-a"])
        let samples = feed(&parser, [meta()] + start() + [call, modern(5.1), output,
            count(15.1, output: 100), generated(19, id: "message-b"),
            modern(19.1, id: "response-b", output: 80, totalOutput: 180)])
        #expect((samples.count) == (2))
        #expect(abs((samples[0].elapsedSeconds) - (4)) <= 0.0001)
        #expect(abs((samples[1].elapsedSeconds) - (4)) <= 0.0001)
        #expect(abs((samples[1].tokensPerSecond) - (20)) <= 0.0001)
    }

    @Test func testLegacyToolBoundaryExcludesExecutionInsteadOfUsingUsageTimestamps() {
        var parser = SessionParser()
        let samples = feed(&parser, [meta()] + start() + [
            row(5, "response_item", ["type": "function_call", "call_id": "call-a"]),
            row(15, "response_item", ["type": "function_call_output", "call_id": "call-a"]),
            count(16, output: 100), generated(19), count(20, output: 80, totalOutput: 180)])
        #expect((samples.count) == (2))
        #expect(abs((samples[0].elapsedSeconds) - (4)) <= 0.0001)
        #expect(abs((samples[1].elapsedSeconds) - (4)) <= 0.0001)
    }

    @Test func testRepeatedUsageAndReplayAreNotNewSamples() {
        var parser = SessionParser()
        let lines = [meta()] + start() + [generated(6), modern(6.1), modern(7), count(8, output: 100), count(9, output: 100)]
        let samples = feed(&parser, lines)
        #expect((samples.count) == (1))
        #expect((samples[0].id) == ("response-a"))
        #expect((feed(&parser, lines).count) == (0))
    }

    @Test func testCancellationCannotCreateASampleFromPartialOutput() {
        var parser = SessionParser()
        #expect(feed(&parser, [meta()] + start() + [generated(4),
            row(5, "event_msg", ["type": "turn_aborted"]), modern(6)]).isEmpty)
        #expect(parser.hasUnmeasurableResponse)
    }

    @Test func testMalformedLineInvalidatesWindowAndNextTurnRecovers() {
        var parser = SessionParser()
        let first = feed(&parser, [meta()] + start() + [generated(4), Data("{bad json}".utf8), modern(5)])
        #expect(first.isEmpty)
        let next = feed(&parser, start(10, model: "switched-model") + [generated(16, id: "message-b"),
            modern(16.1, id: "response-b", output: 90, totalOutput: 190)])
        #expect((next.first?.model) == ("switched-model"))
        #expect((next.count) == (1))
    }

    @Test func testLegacyWithoutTaskStartedHasNoReliableTiming() {
        var parser = SessionParser()
        #expect(feed(&parser, [meta(), row(1, "turn_context", ["model": "test-model"]),
            generated(5), count(6, output: 100)]).isEmpty)
    }

    @Test func testInvalidUsageMarksLatestResponseUnavailable() {
        var parser = SessionParser()
        #expect(feed(&parser, [meta()] + start() + [generated(6),
            modern(6.1, output: 10, reasoning: 20)]).isEmpty)
        #expect(parser.hasUnmeasurableResponse)
        #expect((parser.latestResponseAt) != nil)
    }

    @Test func testSubagentSourceCannotBeOverwrittenByCopiedParentMetadata() {
        var parser = SessionParser()
        let child = meta(["source": ["subagent": ["thread_spawn": [:]]], "thread_source": "subagent"])
        #expect(feed(&parser, [child, meta()] + start() + [generated(6), modern(6.1)]).isEmpty)
        #expect((parser.source) == (.excluded))
    }

    @Test func testGuardianAndCLIExcludedButUnattributedLogRemainsUnknown() {
        var guardian = SessionParser()
        #expect(feed(&guardian, [meta(["thread_source": "guardian_review"])] + start() + [generated(6), modern(6.1)]).isEmpty)
        var cli = SessionParser()
        #expect(feed(&cli, [meta(["originator": "codex_cli_rs", "source": "cli"])] + start() + [generated(6), modern(6.1)]).isEmpty)
        #expect((cli.source) == (.other))
        var unknown = SessionParser()
        #expect((feed(&unknown, start() + [generated(6), modern(6.1)]).count) == (1))
        #expect((unknown.source) == (.unknown))
    }

    @Test func testForkRejectsReplayedParentUsageAndRequiresOwnThreadIdentity() {
        var parser = SessionParser()
        let initial = meta(["forked_from_id": "parent-session"])
        #expect(feed(&parser, [initial, meta(["id": "parent-session"])] + start() + [generated(1.001),
            modern(1.002, thread: "parent-session"), count(1.003, output: 100)]).isEmpty)
        let own = feed(&parser, start(10) + [generated(16, id: "own-message"),
            modern(16.1, id: "own-response", output: 90)])
        #expect((own.count) == (1))
        #expect((own.first?.id) == ("own-response"))
    }

    @Test func testCheckpointRoundTripPreservesPendingToolStateAndDoesNotRetainContent() throws {
        var parser = SessionParser()
        feed(&parser, [meta()] + start() + [row(5, "response_item", ["type": "custom_tool_call", "call_id": "call-a", "input": "synthetic-private-command"]), modern(5.1)])
        let data = try JSONEncoder().encode(parser)
        #expect(!(String(decoding: data, as: UTF8.self).contains("synthetic-private-command")))
        var restored = try JSONDecoder().decode(SessionParser.self, from: data)
        let samples = feed(&restored, [row(15, "response_item", ["type": "custom_tool_call_output", "call_id": "call-a", "output": "synthetic-private-output"]),
            generated(19, id: "next-message"), modern(19.1, id: "response-b", output: 80, totalOutput: 180)])
        #expect((samples.first?.elapsedSeconds) == (4))
    }

    @Test func testNoGeneratedItemCannotInventTimingFromTokenCountPair() {
        var parser = SessionParser()
        #expect(feed(&parser, [meta()] + start() + [count(5, output: 100), count(10, output: 200, totalOutput: 300)]).isEmpty)
    }

    @Test func testZeroDurationAndIncompleteStatusHaveNoTPS() {
        var zero = SessionParser()
        #expect(feed(&zero, [meta()] + start() + [generated(1), modern(1.01)]).isEmpty)
        var partial = SessionParser()
        #expect(feed(&partial, [meta()] + start() + [row(6, "response_item", ["type": "message", "role": "assistant", "status": "in_progress"]), modern(6.1)]).isEmpty)
    }

    @Test func testUnrecognizedFinalResponseKeepsLatestCompletionUnavailable() {
        var parser = SessionParser()
        feed(&parser, [meta()] + start() + [row(6, "event_msg", ["type": "task_complete"])])
        #expect(parser.hasUnmeasurableResponse)
        #expect(parser.latestResponseAt != nil)
    }

    @Test func testMissingReasoningFieldDoesNotInventZero() {
        var parser = SessionParser()
        let record = row(6.1, "token_usage_record", ["response_id": "missing-reasoning", "thread_id": session,
            "usage": ["output_tokens": 100]])
        #expect(feed(&parser, [meta()] + start() + [generated(6), record]).isEmpty)
        #expect(parser.hasUnmeasurableResponse)
    }

}
