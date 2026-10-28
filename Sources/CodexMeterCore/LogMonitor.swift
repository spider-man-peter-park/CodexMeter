import Foundation

public struct LogSnapshot: Sendable {
    public var latestSample: TPSSample?
    public var cachedQuota: QuotaSnapshot?
    public var latestResponseAt: Date?
    public var hasUnmeasurableResponse: Bool
}

/// Reads only appended bytes. Checkpoints contain counters and parser boundaries, never message text.
public actor LogMonitor {
    private struct Cursor: Codable {
        var offset: UInt64 = 0
        var parser = SessionParser()
        var modifiedAt: Date = .distantPast
        var sample: TPSSample?
        var discardingOversizedLine = false
        var waitingForMore = false
        var observedSize: UInt64 = 0
        var anchor: UInt64?
    }
    private struct Checkpoint: Codable {
        var version = 2
        var files: [String: Cursor] = [:]
        var sample: TPSSample?
        var sampleSource: SessionSource?
        var quota: QuotaSnapshot?
        var latestResponseAt: Date?
        var latestResponseSource: SessionSource?
    }
    private let home: URL
    private let cacheURL: URL?
    private var checkpoint: Checkpoint
    private var inventory: [String: URL] = [:]
    private var directories: [URL: (Date, [URL], [URL])] = [:]
    private var backfillIndex = 0
    private var lastSave = Date.distantPast
    private let maxLineBytes = 8 * 1024 * 1024

    public init(home: URL, cacheURL: URL? = nil, persist: Bool = true) {
        self.home = home.standardizedFileURL
        if persist {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            // A stable home hash separates custom CODEX_HOME counters without storing project paths.
            let hash = home.standardizedFileURL.path.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
            self.cacheURL = cacheURL ?? support.appendingPathComponent("CodexMeter/checkpoint-\(String(hash, radix: 16)).json")
        } else { self.cacheURL = nil }
        if let url = self.cacheURL, let bytes = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode(Checkpoint.self, from: bytes), saved.version == 2 {
            checkpoint = saved
        } else { checkpoint = Checkpoint() }
    }

    public func poll() -> LogSnapshot {
        inventory.removeAll(keepingCapacity: true)
        for name in ["sessions", "archived_sessions"] {
            discover(home.appendingPathComponent(name), depth: 0)
        }
        let ordered = inventory.sorted { lhs, rhs in
            let left = (try? lhs.value.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.value.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }
        var pending = ordered.filter { identity, url in
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = (attrs[.size] as? NSNumber)?.uint64Value else { return false }
            guard let cursor = checkpoint.files[identity] else { return size > 0 }
            let modified = attrs[.modificationDate] as? Date
            if cursor.waitingForMore && size == cursor.observedSize && modified == cursor.modifiedAt { return false }
            return size != cursor.offset || modified != cursor.modifiedAt
        }
        // Reserve the first read for a rotating backlog file, then prioritize newest activity.
        if !pending.isEmpty {
            let index = backfillIndex % pending.count
            let reserved = pending.remove(at: index)
            pending.insert(reserved, at: 0)
            backfillIndex &+= 1
        }
        var budget = 16 * 1024 * 1024
        var changed = false
        for (identity, url) in pending {
            if budget <= 0 { break }
            changed = read(url, identity: identity, budget: &budget) || changed
        }
        let eligible = checkpoint.files.values.filter { $0.parser.source == .desktop || $0.parser.source == .unknown }
        var samples = eligible.compactMap { cursor -> (TPSSample, SessionSource)? in
            cursor.sample.map { ($0, cursor.parser.source) }
        }
        if let prior = checkpoint.sample { samples.append((prior, checkpoint.sampleSource ?? .unknown)) }
        if samples.contains(where: { $0.1 == .desktop }) { samples.removeAll { $0.1 != .desktop } }
        if let best = samples.max(by: { $0.0.completedAt < $1.0.completedAt }) {
            checkpoint.sample = best.0; checkpoint.sampleSource = best.1
        }
        var completions = eligible.compactMap { cursor -> (Date, SessionSource)? in
            cursor.parser.latestResponseAt.map { ($0, cursor.parser.source) }
        }
        if let prior = checkpoint.latestResponseAt { completions.append((prior, checkpoint.latestResponseSource ?? .unknown)) }
        if completions.contains(where: { $0.1 == .desktop }) { completions.removeAll { $0.1 != .desktop } }
        if let latest = completions.max(by: { $0.0 < $1.0 }) {
            checkpoint.latestResponseAt = latest.0; checkpoint.latestResponseSource = latest.1
        }
        if changed && Date().timeIntervalSince(lastSave) >= 10 { save() }
        let sample = checkpoint.sample
        let latest = checkpoint.latestResponseAt
        return LogSnapshot(latestSample: sample, cachedQuota: checkpoint.quota,
                           latestResponseAt: latest,
                           hasUnmeasurableResponse: latest.map { $0 > (sample?.completedAt ?? .distantPast) } ?? false)
    }

    private func discover(_ directory: URL, depth: Int) {
        guard depth <= 8, let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path),
              attributes[.type] as? FileAttributeType == .typeDirectory else { return }
        let modified = attributes[.modificationDate] as? Date ?? .distantPast
        let children: [URL]
        let files: [URL]
        if let cached = directories[directory], cached.0 == modified {
            children = cached.1; files = cached.2
        } else {
            let urls = (try? FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? []
            var childList: [URL] = [], fileList: [URL] = []
            for url in urls {
                guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]),
                      values.isSymbolicLink != true else { continue }
                if values.isDirectory == true { childList.append(url) }
                else if values.isRegularFile == true && url.pathExtension == "jsonl" { fileList.append(url) }
            }
            children = childList; files = fileList
            directories[directory] = (modified, children, files)
        }
        for url in files {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let inode = attrs[.systemFileNumber] as? NSNumber,
                  let device = attrs[.systemNumber] as? NSNumber else { continue }
            inventory["\(device)-\(inode)"] = url
        }
        for child in children { discover(child, depth: depth + 1) }
    }

    private func read(_ url: URL, identity: String, budget: inout Int) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value else { return false }
        var cursor = checkpoint.files[identity] ?? Cursor()
        let modified = attrs[.modificationDate] as? Date ?? .distantPast
        let reset = size < cursor.offset || (size == cursor.offset && modified != cursor.modifiedAt)
        if reset {
            cursor = Cursor()
            cursor.modifiedAt = modified
            checkpoint.files[identity] = cursor
        }
        guard size > cursor.offset else { return reset }
        if cursor.waitingForMore && cursor.observedSize == size && cursor.modifiedAt == modified { return false }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        do {
            if let anchor = cursor.anchor, cursor.offset > 0 {
                let length = min(cursor.offset, 256)
                try handle.seek(toOffset: cursor.offset - length)
                let bytes = try handle.read(upToCount: Int(length)) ?? Data()
                if Self.fingerprint(bytes) != anchor { cursor = Cursor() }
            }
            let readStart = cursor.offset
            try handle.seek(toOffset: cursor.offset)
            let count = min(budget, cursor.discardingOversizedLine ? 2 * 1024 * 1024 : maxLineBytes)
            guard let data = try handle.read(upToCount: count), !data.isEmpty else { return false }
            budget -= data.count
            var consumed = 0
            if cursor.discardingOversizedLine {
                if let newline = data.firstIndex(of: 10) {
                    consumed = newline + 1
                    cursor.discardingOversizedLine = false
                } else {
                    cursor.offset += UInt64(data.count)
                    cursor.modifiedAt = modified
                    cursor.anchor = nil
                    checkpoint.files[identity] = cursor
                    return true
                }
            }
            for index in data.indices where index >= consumed && data[index] == 10 {
                let line = data.subdata(in: consumed..<index)
                if let sample = cursor.parser.consume(line) {
                    cursor.sample = sample
                }
                if cursor.parser.source != .excluded && cursor.parser.source != .other {
                    readQuota(line)
                }
                consumed = index + 1
            }
            if consumed == 0 && data.count >= maxLineBytes {
                // Discard oversized records across bounded polls while retaining provenance.
                cursor.parser.invalidatePendingResponse()
                cursor.discardingOversizedLine = true
                cursor.offset += UInt64(data.count)
            } else {
                cursor.offset += UInt64(consumed)
            }
            cursor.waitingForMore = !cursor.discardingOversizedLine && cursor.offset < size && readStart + UInt64(data.count) >= size
            cursor.observedSize = size
            if cursor.offset > 0 {
                let length = min(cursor.offset, 256)
                try handle.seek(toOffset: cursor.offset - length)
                cursor.anchor = Self.fingerprint(try handle.read(upToCount: Int(length)) ?? Data())
            }
            cursor.modifiedAt = modified
            checkpoint.files[identity] = cursor
            return consumed > 0 || cursor.discardingOversizedLine
        } catch { return false }
    }

    private static let quotaMarker = Data("\"rate_limits\"".utf8)

    private func readQuota(_ line: Data) {
        guard line.range(of: Self.quotaMarker) != nil,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "event_msg",
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let limits = payload["rate_limits"] as? [String: Any],
              let timestamp = object["timestamp"] as? String,
              let at = Self.parseDate(timestamp),
              var quota = QuotaParser.parse(limits, at: at, source: .logCache),
              at > (checkpoint.quota?.updatedAt ?? .distantPast) else { return }
        quota.isStale = true
        checkpoint.quota = quota
    }

    private static func fingerprint(_ data: Data) -> UInt64 {
        data.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }

    private static func parseDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private func save() {
        guard let url = cacheURL, let data = try? JSONEncoder().encode(checkpoint) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        lastSave = Date()
    }

    public func flush() { save() }
}
