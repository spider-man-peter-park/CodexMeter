import Foundation
import CoreFoundation

public struct TPSSample: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let model: String?
    public let outputTokens: Int
    public let reasoningTokens: Int
    public let elapsedSeconds: Double
    public let completedAt: Date
    public let isEstimated: Bool
    public var tokensPerSecond: Double { Double(outputTokens) / elapsedSeconds }

    public init(id: String, model: String?, outputTokens: Int, reasoningTokens: Int,
                elapsedSeconds: Double, completedAt: Date, isEstimated: Bool = true) {
        self.id = id
        self.model = model
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.elapsedSeconds = elapsedSeconds
        self.completedAt = completedAt
        self.isEstimated = isEstimated
    }
}

public enum SessionSource: String, Codable, Sendable {
    case desktop, other, unknown, excluded
}

/// Extracts completed sampling cycles without retaining prompt or response content.
public struct SessionParser: Codable, Sendable {
    public private(set) var source: SessionSource = .unknown
    public private(set) var latestResponseAt: Date?
    public private(set) var hasUnmeasurableResponse = false
    private var sawMetadata = false
    private var sessionID: String?
    private var isFork = false
    private var turnID: String?
    private var model: String?
    private var activeTurn = false
    private var turnHasSample = false
    private var samplingStart: Date?
    private var generatedEnd: Date?
    private var generatedID: String?
    private var latestInputAfterGeneration: Date?
    private var pendingCalls: Set<String> = []
    private var seenResponseIDs: [String] = []
    private var seenUsageTotals: [String] = []
    private var seenItemIDs: [String] = []

    public init() {}

    public mutating func invalidatePendingResponse() { invalidateWindow() }

    /// The caller supplies one complete JSONL line; incomplete tails belong in its byte buffer.
    public mutating func consume(_ line: Data) -> TPSSample? {
        guard !line.isEmpty else { return nil }
        guard let row = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = row["type"] as? String,
              let payload = row["payload"] as? [String: Any] else {
            invalidateWindow()
            return nil
        }
        if type == "session_meta" {
            readMetadata(payload)
            return nil
        }
        guard source != .excluded && source != .other else { return nil }
        guard let text = row["timestamp"] as? String, let timestamp = Self.parseDate(text) else {
            if ["event_msg", "response_item", "turn_context", "token_usage_record"].contains(type) { invalidateWindow() }
            return nil
        }
        let subtype = payload["type"] as? String ?? ""
        switch type {
        case "turn_context":
            model = payload["model"] as? String
            turnID = payload["turn_id"] as? String ?? turnID
            if activeTurn && generatedEnd == nil && pendingCalls.isEmpty {
                samplingStart = timestamp
            }
        case "event_msg":
            switch subtype {
            case "task_started":
                clearWindow()
                activeTurn = true
                turnHasSample = false
                turnID = payload["turn_id"] as? String
                model = nil
                samplingStart = timestamp
            case "user_message":
                recordInput(at: timestamp)
            case "turn_aborted", "task_cancelled", "task_failed":
                latestResponseAt = timestamp
                hasUnmeasurableResponse = true
                clearWindow()
                activeTurn = false
            case "task_complete":
                if let end = generatedEnd {
                    latestResponseAt = end
                    hasUnmeasurableResponse = true
                } else if !turnHasSample {
                    latestResponseAt = timestamp
                    hasUnmeasurableResponse = true
                }
                clearWindow()
                activeTurn = false
            case "token_count":
                guard !isFork,
                      let info = payload["info"] as? [String: Any],
                      let usage = info["last_token_usage"] as? [String: Any],
                      let totals = info["total_token_usage"] as? [String: Any] else { return nil }
                let fingerprint = Self.usageFingerprint(totals)
                guard !seenUsageTotals.contains(fingerprint) else { return nil }
                if generatedEnd == nil {
                    Self.remember(fingerprint, in: &seenUsageTotals)
                    return nil
                }
                let identity = [sessionID ?? "unknown", turnID ?? "unknown",
                                generatedID ?? String(generatedEnd!.timeIntervalSince1970), fingerprint].joined(separator: ":")
                Self.remember(fingerprint, in: &seenUsageTotals)
                return finish(usage: usage, id: identity)
            default:
                break
            }
        case "response_item":
            guard activeTurn else { return nil }
            if let id = payload["id"] as? String {
                guard !seenItemIDs.contains(id) else { return nil }
                Self.remember(id, in: &seenItemIDs)
            }
            let role = payload["role"] as? String
            let isInput = subtype == "function_call_output" || subtype == "custom_tool_call_output"
                || subtype == "agent_message" || (subtype == "message" && ["user", "developer", "system"].contains(role ?? ""))
            if isInput {
                if let callID = payload["call_id"] as? String { pendingCalls.remove(callID) }
                recordInput(at: timestamp)
            } else if subtype == "reasoning" || (subtype == "message" && role == "assistant") || subtype.hasSuffix("_call") {
                if let status = payload["status"] as? String, status != "completed" {
                    invalidateWindow()
                    return nil
                }
                generatedEnd = timestamp
                generatedID = payload["id"] as? String ?? generatedID
                if ["function_call", "custom_tool_call"].contains(subtype), let callID = payload["call_id"] as? String {
                    pendingCalls.insert(callID)
                }
            }
        case "token_usage_record":
            guard let responseID = payload["response_id"] as? String,
                  !seenResponseIDs.contains(responseID) else { return nil }
            if let recordedThread = payload["thread_id"] as? String, let sessionID, recordedThread != sessionID {
                return nil
            }
            // Fork histories may replay parent usage with rewritten timestamps.
            if isFork && payload["thread_id"] as? String != sessionID { return nil }
            Self.remember(responseID, in: &seenResponseIDs)
            if let totals = payload["thread_token_usage"] as? [String: Any] {
                Self.remember(Self.usageFingerprint(totals), in: &seenUsageTotals)
            }
            guard let usage = payload["usage"] as? [String: Any] else {
                markUnmeasurable(at: timestamp)
                return nil
            }
            return finish(usage: usage, id: responseID, completionEvidence: timestamp)
        case "compacted":
            invalidateWindow()
        default:
            break
        }
        return nil
    }

    private mutating func readMetadata(_ payload: [String: Any]) {
        // Copied parent metadata must never replace the actual file's identity or source.
        guard !sawMetadata else { return }
        sawMetadata = true
        sessionID = payload["id"] as? String ?? payload["session_id"] as? String
        isFork = payload["forked_from_id"] != nil || payload["history_base"] is [String: Any]
        let originator = (payload["originator"] as? String ?? "").lowercased()
        let sourceName = (payload["source"] as? String ?? "").lowercased()
        let threadSource = (payload["thread_source"] as? String ?? "").lowercased()
        if (payload["source"] as? [String: Any])?["subagent"] != nil
            || ["subagent", "guardian_review"].contains(threadSource) {
            source = .excluded
        } else if originator == "codex desktop" {
            source = .desktop
        } else if ["cli", "exec"].contains(sourceName) || originator.contains("cli") {
            source = .other
        }
    }

    private mutating func recordInput(at timestamp: Date) {
        guard activeTurn else { return }
        if generatedEnd != nil {
            latestInputAfterGeneration = max(latestInputAfterGeneration ?? timestamp, timestamp)
        } else if pendingCalls.isEmpty {
            samplingStart = timestamp
        }
    }

    private mutating func finish(usage: [String: Any], id: String, completionEvidence: Date? = nil) -> TPSSample? {
        let end = generatedEnd
        let start = samplingStart
        if let end { latestResponseAt = end }
        else if let completionEvidence { latestResponseAt = completionEvidence }
        guard activeTurn, let start, let end, end > start,
              let output = Self.integer(usage["output_tokens"]), output > 0,
              let reasoning = Self.integer(usage["reasoning_output_tokens"]),
              reasoning >= 0, reasoning <= output else {
            hasUnmeasurableResponse = true
            advanceBoundary()
            return nil
        }
        let elapsed = end.timeIntervalSince(start)
        guard elapsed.isFinite else {
            hasUnmeasurableResponse = true
            advanceBoundary()
            return nil
        }
        let sample = TPSSample(id: id, model: model, outputTokens: output,
                               reasoningTokens: reasoning, elapsedSeconds: elapsed, completedAt: end)
        hasUnmeasurableResponse = false
        turnHasSample = true
        advanceBoundary()
        return sample
    }

    private mutating func advanceBoundary() {
        // A previous model completion is a boundary only when no local tool is still running.
        samplingStart = pendingCalls.isEmpty ? (latestInputAfterGeneration ?? generatedEnd) : nil
        generatedEnd = nil
        generatedID = nil
        latestInputAfterGeneration = nil
    }

    private mutating func markUnmeasurable(at timestamp: Date) {
        latestResponseAt = generatedEnd ?? timestamp
        hasUnmeasurableResponse = true
        advanceBoundary()
    }

    private mutating func invalidateWindow() {
        if let end = generatedEnd {
            latestResponseAt = end
            hasUnmeasurableResponse = true
        }
        clearWindow()
        activeTurn = false
    }

    private mutating func clearWindow() {
        samplingStart = nil
        generatedEnd = nil
        generatedID = nil
        latestInputAfterGeneration = nil
        pendingCalls.removeAll(keepingCapacity: true)
    }

    private static func remember(_ value: String, in values: inout [String]) {
        values.append(value)
        if values.count > 512 { values.removeFirst(values.count - 512) }
    }

    private static func usageFingerprint(_ usage: [String: Any]) -> String {
        ["input_tokens", "cached_input_tokens", "output_tokens", "reasoning_output_tokens", "total_tokens"]
            .map { String(integer(usage[$0]) ?? -1) }.joined(separator: "/")
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let value = value as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite, value.doubleValue.rounded() == value.doubleValue,
              value.doubleValue >= Double(Int.min), value.doubleValue < Double(Int.max) else { return nil }
        return value.intValue
    }

    private static func parseDate(_ text: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
            ?? (try? Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(text))
    }
}
