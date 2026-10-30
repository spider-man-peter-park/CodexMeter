import CoreFoundation
import CryptoKit
import Foundation

enum ActivityIdentity {
    static func key(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct LocalSessionOrigin: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case desktop, child, other, excluded, unknown }
    var kind: Kind
    var parent: String?
    var modernSeen = false
}

struct LocalUsageEvent: Codable, Sendable {
    var session: String
    var aliases: [String]
    var timestamp: Date
    var input: Int
    var output: Int
    var cached: Int?
    var reasoning: Int?
    var modern: Bool
    var responseKey: String?
}

/// Reads usage independently of response timing and never retains conversation content.
struct LocalUsageParser: Codable, Sendable {
    private(set) var session: String?
    private(set) var origin: LocalSessionOrigin?
    private(set) var unsupportedAt: Date?
    private var rawSession: String?
    private var fork = false
    private var sawMetadata = false
    private static let markers = ["\"session_meta\"", "\"token_usage_record\"", "\"token_count\""].map { Data($0.utf8) }

    mutating func consume(_ line: Data, observedAt: Date) -> LocalUsageEvent? {
        if origin?.kind == .excluded || origin?.kind == .other { return nil }
        guard Self.markers.contains(where: { line.range(of: $0) != nil }) else { return nil }
        guard let row = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = row["type"] as? String, let payload = row["payload"] as? [String: Any] else {
            unsupportedAt = max(unsupportedAt ?? .distantPast, observedAt); return nil
        }
        if type == "session_meta" {
            guard !sawMetadata else { return nil }
            sawMetadata = true
            rawSession = payload["id"] as? String ?? payload["session_id"] as? String
            session = rawSession.map { ActivityIdentity.key("session:" + $0) }
            fork = payload["forked_from_id"] != nil || payload["history_base"] is [String: Any]
            let source = payload["source"] as? [String: Any]
            let subagent = source?["subagent"] as? [String: Any]
            let spawn = subagent?["thread_spawn"] as? [String: Any]
            let threadSource = payload["thread_source"] as? String ?? ""
            if threadSource == "guardian_review" || (subagent != nil && spawn == nil) {
                origin = LocalSessionOrigin(kind: .excluded)
            } else if let parent = spawn?["parent_thread_id"] as? String {
                origin = LocalSessionOrigin(kind: .child, parent: ActivityIdentity.key("session:" + parent))
            } else if threadSource == "subagent" {
                origin = LocalSessionOrigin(kind: .unknown)
            } else if (payload["originator"] as? String ?? "").lowercased() == "codex desktop" {
                origin = LocalSessionOrigin(kind: .desktop)
            } else if ["cli", "exec"].contains(payload["source"] as? String ?? "")
                        || (payload["originator"] as? String ?? "").lowercased().contains("cli") {
                origin = LocalSessionOrigin(kind: .other)
            } else { origin = LocalSessionOrigin(kind: .unknown) }
            return nil
        }
        let modern = type == "token_usage_record"
        guard modern || (type == "event_msg" && payload["type"] as? String == "token_count") else { return nil }
        if !modern {
            // Quota-only updates do not represent missing token consumption.
            guard let info = payload["info"] as? [String: Any],
                  info["last_token_usage"] != nil, !(info["last_token_usage"] is NSNull) else { return nil }
        }
        let timestamp = (row["timestamp"] as? String).flatMap(Self.date)
        guard let session, let rawSession else {
            unsupportedAt = max(unsupportedAt ?? .distantPast, timestamp ?? observedAt); return nil
        }
        let usage: [String: Any]?
        let totals: [String: Any]?
        var aliases: [String] = []
        if modern {
            origin?.modernSeen = true
            guard let id = payload["response_id"] as? String, !id.isEmpty,
                  (payload["thread_id"] as? String).map({ $0 == rawSession }) ?? !fork else { return nil }
            aliases.append(ActivityIdentity.key("response:" + id))
            usage = payload["usage"] as? [String: Any]
            totals = payload["thread_token_usage"] as? [String: Any]
        } else {
            guard !fork else { return nil }
            let info = payload["info"] as? [String: Any]
            usage = info?["last_token_usage"] as? [String: Any]
            totals = info?["total_token_usage"] as? [String: Any]
        }
        if let totals, let fingerprint = Self.fingerprint(totals) {
            aliases.append(ActivityIdentity.key("total:" + session + ":" + fingerprint))
        }
        guard let timestamp, let usage, !aliases.isEmpty,
              let input = Self.integer(usage["input_tokens"]), let output = Self.integer(usage["output_tokens"]),
              !input.addingReportingOverflow(output).overflow else {
            unsupportedAt = max(unsupportedAt ?? .distantPast, timestamp ?? observedAt); return nil
        }
        let cached = Self.integer(usage["cached_input_tokens"])
        let reasoning = Self.integer(usage["reasoning_output_tokens"])
        guard (usage["cached_input_tokens"] == nil || cached != nil),
              (usage["reasoning_output_tokens"] == nil || reasoning != nil),
              cached.map({ $0 <= input }) ?? true, reasoning.map({ $0 <= output }) ?? true,
              usage["total_tokens"] == nil || Self.integer(usage["total_tokens"]) == input + output else {
            unsupportedAt = max(unsupportedAt ?? .distantPast, timestamp); return nil
        }
        return LocalUsageEvent(session: session, aliases: aliases, timestamp: timestamp,
            input: input, output: output, cached: cached, reasoning: reasoning, modern: modern,
            responseKey: modern ? aliases.first : nil)
    }

    private static func fingerprint(_ usage: [String: Any]) -> String? {
        guard let input = integer(usage["input_tokens"]), let output = integer(usage["output_tokens"]),
              !input.addingReportingOverflow(output).overflow,
              usage["total_tokens"] == nil || integer(usage["total_tokens"]) == input + output else { return nil }
        // Cache/reasoning detail updates are not additional token consumption.
        return "\(input)/\(output)"
    }
    private static func integer(_ raw: Any?) -> Int? {
        guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite, value.doubleValue >= 0, value.doubleValue < Double(Int.max),
              value.doubleValue.rounded() == value.doubleValue else { return nil }
        return value.intValue
    }
    private static func date(_ value: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value))
            ?? (try? Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(value))
    }
}

public struct LocalDayUsage: Sendable, Equatable {
    public var dayStart: Date
    public var timeZoneIdentifier: String
    public var input = 0
    public var output = 0
    public var cachedInput: Int? = 0
    public var reasoningOutput: Int? = 0
    public var responses = 0
    public var total: Int { input + output }
    public var updatedAt: Date
    public var isBackfilling = false
    public var isPartial = false
    public var hasDesktopLogs = false
    public var logsAvailable = true
    public func matches(_ date: Date, calendar: Calendar = .current) -> Bool {
        dayStart == calendar.startOfDay(for: date) && timeZoneIdentifier == calendar.timeZone.identifier
    }
    public func displayTotal(at date: Date, calendar: Calendar = .current) -> Int? {
        guard matches(date, calendar: calendar), hasDesktopLogs, logsAvailable || responses > 0,
              responses > 0 || (!isBackfilling && !isPartial) else { return nil }
        return total
    }
}

struct LocalActivityState: Codable, Sendable {
    var events: [String: LocalUsageEvent] = [:]
    var origins: [String: LocalSessionOrigin] = [:]
    var capacityExceededAt: Date?
}

struct LocalActivityLedger: Sendable {
    private(set) var state: LocalActivityState
    private var aliases: [String: String] = [:]
    init(state: LocalActivityState = LocalActivityState()) {
        self.state = state
        rebuildIndex()
    }
    mutating func register(_ session: String?, origin: LocalSessionOrigin?) {
        guard let session, var origin else { return }
        origin.modernSeen = origin.modernSeen || state.origins[session]?.modernSeen == true
        state.origins[session] = origin
    }
    mutating func registerDesktop(_ rawSession: String) {
        let key = ActivityIdentity.key("session:" + rawSession)
        if state.origins[key] == nil { state.origins[key] = LocalSessionOrigin(kind: .desktop) }
    }
    mutating func consume(_ event: LocalUsageEvent, now: Date) {
        guard event.timestamp >= now.addingTimeInterval(-3 * 86400), event.timestamp <= now.addingTimeInterval(86400) else { return }
        let owners = Set(event.aliases.compactMap { aliases[$0] }).filter { owner in
            guard event.modern, let existing = state.events[owner], existing.modern else { return true }
            return existing.responseKey == event.responseKey
        }
        if let owner = owners.sorted().first, var existing = state.events[owner] {
            let allAliases = Set(existing.aliases + event.aliases + owners.flatMap { state.events[$0]?.aliases ?? [] })
            if event.modern && !existing.modern { existing = event }
            existing.aliases = allAliases.sorted()
            state.events[owner] = existing
            for other in owners where other != owner { state.events.removeValue(forKey: other) }
            for alias in allAliases { aliases[alias] = owner }
        } else {
            guard state.events.count < 100_000, let key = event.aliases.first else { state.capacityExceededAt = now; return }
            state.events[key] = event
            for alias in event.aliases { aliases[alias] = key }
        }
    }
    mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-3 * 86400)
        if state.events.values.contains(where: { $0.timestamp < cutoff }) {
            state.events = state.events.filter { $0.value.timestamp >= cutoff }
            rebuildIndex()
        }
    }
    func summary(now: Date, calendar: Calendar, backfilling: Bool, partial: Bool) -> LocalDayUsage {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        var result = LocalDayUsage(dayStart: start, timeZoneIdentifier: calendar.timeZone.identifier, updatedAt: now)
        result.hasDesktopLogs = state.origins.values.contains { $0.kind == .desktop }
        result.isBackfilling = backfilling
        result.isPartial = partial || state.capacityExceededAt.map { $0 >= start } == true
        for event in state.events.values where event.timestamp >= start && event.timestamp < end {
            guard event.timestamp <= now.addingTimeInterval(60) else { result.isPartial = true; continue }
            guard desktopStatus(event.session) == true else {
                if desktopStatus(event.session) == nil { result.isPartial = true }
                continue
            }
            // Prefer response-ID records when a session contains both schema generations.
            if !event.modern && state.origins[event.session]?.modernSeen == true { result.isPartial = true; continue }
            guard event.input >= 0, event.output >= 0,
                  event.cached.map({ $0 >= 0 && $0 <= event.input }) ?? true,
                  event.reasoning.map({ $0 >= 0 && $0 <= event.output }) ?? true else { result.isPartial = true; continue }
            let newInput = result.input.addingReportingOverflow(event.input)
            let newOutput = result.output.addingReportingOverflow(event.output)
            guard !newInput.overflow, !newOutput.overflow, !newInput.partialValue.addingReportingOverflow(newOutput.partialValue).overflow else {
                result.isPartial = true; continue
            }
            result.input = newInput.partialValue; result.output = newOutput.partialValue
            if let previous = result.cachedInput, let cached = event.cached { result.cachedInput = previous + cached }
            else { result.cachedInput = nil }
            if let previous = result.reasoningOutput, let reasoning = event.reasoning { result.reasoningOutput = previous + reasoning }
            else { result.reasoningOutput = nil }
            result.responses += 1
        }
        return result
    }
    private func desktopStatus(_ session: String) -> Bool? {
        var key = session
        var visited: Set<String> = []
        for _ in 0..<16 {
            guard visited.insert(key).inserted, let origin = state.origins[key] else { return nil }
            if origin.kind == .desktop { return true }
            if origin.kind == .other || origin.kind == .excluded { return false }
            guard origin.kind == .child, let parent = origin.parent else { return nil }
            key = parent
        }
        return nil
    }
    private mutating func rebuildIndex() {
        aliases.removeAll(keepingCapacity: true)
        for (key, event) in state.events { for alias in event.aliases { aliases[alias] = key } }
    }
}

struct SourcedTPSSample: Codable, Sendable { var sample: TPSSample; var source: SessionSource }

public enum TPSHistory {
    public static let limit = 30
    public static func recent(_ samples: [TPSSample]) -> [TPSSample] {
        var unique: [String: TPSSample] = [:]
        for sample in samples where sample.tokensPerSecond.isFinite && sample.tokensPerSecond > 0 && sample.elapsedSeconds > 0 {
            if unique[sample.id] == nil || unique[sample.id]!.completedAt < sample.completedAt { unique[sample.id] = sample }
        }
        return Array(unique.values.sorted {
            $0.completedAt == $1.completedAt ? $0.id < $1.id : $0.completedAt < $1.completedAt
        }.suffix(limit))
    }
    public static func points(_ samples: [TPSSample]) -> [TPSHistoryPoint] {
        let recent = recent(samples)
        var segment = 0
        return recent.enumerated().map { index, sample in
            if index > 0 && sample.model != recent[index - 1].model { segment += 1 }
            return TPSHistoryPoint(sample: sample, index: index, segment: segment)
        }
    }
    static func retainingSources(_ values: [SourcedTPSSample]) -> [SourcedTPSSample] {
        [.desktop, .unknown].flatMap { source in
            recent(values.filter { $0.source == source }.map(\.sample)).map { SourcedTPSSample(sample: $0, source: source) }
        }
    }
    static func preferred(_ values: [SourcedTPSSample]) -> [TPSSample] {
        let source: SessionSource = values.contains { $0.source == .desktop } ? .desktop : .unknown
        return recent(values.filter { $0.source == source }.map(\.sample))
    }
}

public struct TPSHistoryPoint: Identifiable, Sendable, Equatable {
    public let sample: TPSSample
    public let index: Int
    public let segment: Int
    public var id: String { sample.id }
}
