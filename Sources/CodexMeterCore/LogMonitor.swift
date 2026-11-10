import Darwin
import Foundation

public struct LogSnapshot: Sendable {
    public var latestSample: TPSSample?
    public var cachedQuota: QuotaSnapshot?
    public var latestResponseAt: Date?
    public var hasUnmeasurableResponse: Bool
    public var todayUsage: LocalDayUsage?
    public var recentSamples: [TPSSample] = []
    public var historyBackfilling = false
    public var historyIsUnattributed = false

    public init(latestSample: TPSSample?, cachedQuota: QuotaSnapshot?, latestResponseAt: Date?,
                hasUnmeasurableResponse: Bool, todayUsage: LocalDayUsage? = nil,
                recentSamples: [TPSSample] = [], historyBackfilling: Bool = false,
                historyIsUnattributed: Bool = false) {
        self.latestSample = latestSample
        self.cachedQuota = cachedQuota
        self.latestResponseAt = latestResponseAt
        self.hasUnmeasurableResponse = hasUnmeasurableResponse
        self.todayUsage = todayUsage
        self.recentSamples = recentSamples
        self.historyBackfilling = historyBackfilling
        self.historyIsUnattributed = historyIsUnattributed
    }
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
        var usageParser: LocalUsageParser?
    }
    private struct Checkpoint: Codable {
        var version = 3
        var files: [String: Cursor] = [:]
        var sample: TPSSample?
        var sampleSource: SessionSource?
        var quota: QuotaSnapshot?
        var latestResponseAt: Date?
        var latestResponseSource: SessionSource?
        var activity: LocalActivityState?
        var history: [SourcedTPSSample]?
    }
    private struct FileMetadata: Equatable {
        let identity: String
        let size: UInt64
        let modifiedAt: Date
        let modificationSeconds: Int
        let modificationNanoseconds: Int
        let type: mode_t
        let permissions: mode_t

        init?(_ url: URL) {
            var attributes = stat()
            let result = url.withUnsafeFileSystemRepresentation { path in
                guard let path else { return Int32(-1) }
                return Darwin.lstat(path, &attributes)
            }
            guard result == 0, attributes.st_size >= 0 else { return nil }
            identity = "\(attributes.st_dev)-\(attributes.st_ino)"
            size = UInt64(attributes.st_size)
            modificationSeconds = attributes.st_mtimespec.tv_sec
            modificationNanoseconds = attributes.st_mtimespec.tv_nsec
            // Match Foundation's reference-epoch precision so existing checkpoints remain unchanged.
            modifiedAt = Date(timeIntervalSinceReferenceDate: Double(modificationSeconds)
                - Date.timeIntervalBetween1970AndReferenceDate + Double(modificationNanoseconds) / 1_000_000_000)
            type = attributes.st_mode & mode_t(S_IFMT)
            permissions = attributes.st_mode & 0o7777
        }

        var isDirectory: Bool { type == mode_t(S_IFDIR) }
        var isRegularFile: Bool { type == mode_t(S_IFREG) }

        func hasSameDirectoryContents(as other: FileMetadata) -> Bool {
            identity == other.identity && modificationSeconds == other.modificationSeconds
                && modificationNanoseconds == other.modificationNanoseconds && permissions == other.permissions
        }
    }
    private struct LogFile: Equatable {
        let url: URL
        let metadata: FileMetadata
    }
    private struct DirectoryListing {
        let metadata: FileMetadata
        let entries: [URL]
    }
    private let home: URL
    private let cacheURL: URL?
    private var checkpoint: Checkpoint
    private var inventory: [String: LogFile] = [:]
    private var identitiesByPath: [URL: String] = [:]
    private var orderedInventory: [(key: String, value: LogFile)] = []
    private var inventoryChanged = false
    private var directories: [URL: DirectoryListing] = [:]
    private var visitedDirectories: Set<URL> = []
    private var rootIdentities: [URL: String] = [:]
    private var lastInventoryScan: Date?
    private let fileEvents: any LogFileEventReading
    private var backfillIndex = 0
    private var lastSaveAttempt = Date.distantPast
    private let maxLineBytes = 8 * 1024 * 1024
    private var activity: LocalActivityLedger
    private var readFailed = false
    private var inventoryReconciled = false
    private var checkpointNeedsSave = false

    public init(home: URL, cacheURL: URL? = nil, persist: Bool = true) {
        self.init(home: home, cacheURL: cacheURL, persist: persist, fileEvents: LogFileEvents(home: home))
    }

    init(home: URL, cacheURL: URL? = nil, persist: Bool = true, fileEvents: any LogFileEventReading) {
        self.home = LogFilePaths.canonical(home)
        self.fileEvents = fileEvents
        if persist {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            // A stable home hash separates custom CODEX_HOME counters without storing project paths.
            let hash = home.standardizedFileURL.path.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
            self.cacheURL = cacheURL ?? support.appendingPathComponent("CodexMeter/checkpoint-\(String(hash, radix: 16)).json")
        } else { self.cacheURL = nil }
        if let url = self.cacheURL, let bytes = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode(Checkpoint.self, from: bytes), [2, 3].contains(saved.version) {
            checkpoint = saved
        } else { checkpoint = Checkpoint() }
        checkpoint.version = 3
        activity = LocalActivityLedger(state: checkpoint.activity ?? LocalActivityState())
        checkpoint.activity = nil
        // Restore old parent identities once; newly parsed metadata registers them during reads.
        for cursor in checkpoint.files.values where cursor.parser.source == .desktop {
            if let id = cursor.parser.sessionIdentifier { activity.registerDesktop(id) }
        }
        if checkpoint.history == nil, let sample = checkpoint.sample {
            checkpoint.history = [SourcedTPSSample(sample: sample, source: checkpoint.sampleSource ?? .unknown)]
        }
    }

    public func poll(now: Date = Date(), calendar: Calendar = .current) -> LogSnapshot {
        readFailed = false
        activity.prune(now: now)
        let dayStart = calendar.startOfDay(for: now)
        let rootsReadable = refreshInventory(now: now)
        let ordered = orderedInventory
        let recent = TPSHistory.preferred(checkpoint.history ?? [])
        let cutoff = recent.count >= TPSHistory.limit ? recent.first?.completedAt : nil
        var historyCandidates: Set<String> = []
        for (identity, file) in ordered {
            guard let cursor = checkpoint.files[identity], cursor.usageParser == nil,
                  cursor.parser.source != .excluded, cursor.parser.source != .other else { continue }
            let modified = file.metadata.modifiedAt
            if let cutoff {
                if modified >= cutoff || (cursor.sample?.completedAt ?? .distantPast) >= cutoff { historyCandidates.insert(identity) }
            } else {
                historyCandidates.insert(identity)
                break
            }
        }
        var pending = ordered.filter { identity, file in
            let size = file.metadata.size
            guard let cursor = checkpoint.files[identity] else { return size > 0 }
            let modified = file.metadata.modifiedAt
            if cursor.usageParser == nil && cursor.parser.source != .other
                && (modified >= dayStart || historyCandidates.contains(identity)) { return size > 0 }
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
        for (identity, file) in pending {
            if budget <= 0 { break }
            changed = read(file, identity: identity, budget: &budget, now: now) || changed
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
        if inventoryReconciled && !readFailed {
            // Preserve today's uncertainty after its source log is removed, until that warning expires.
            let removed = checkpoint.files.keys.filter { identity in
                inventory[identity] == nil
                    && (checkpoint.files[identity]?.usageParser?.unsupportedAt ?? .distantPast) < dayStart
            }
            for identity in removed { checkpoint.files.removeValue(forKey: identity) }
            changed = changed || !removed.isEmpty
        }
        checkpointNeedsSave = checkpointNeedsSave || changed
        if checkpointNeedsSave && Date().timeIntervalSince(lastSaveAttempt) >= 10 { save() }
        let sample = checkpoint.sample
        let latest = checkpoint.latestResponseAt
        let pendingToday = ordered.contains { identity, file in
            guard file.metadata.modifiedAt >= dayStart else { return false }
            if checkpoint.files[identity]?.parser.source == .other { return false }
            guard let cursor = checkpoint.files[identity], cursor.usageParser != nil else { return true }
            return cursor.offset < file.metadata.size && !cursor.waitingForMore
        }
        let historyPending = !historyCandidates.isEmpty || ordered.contains { identity, file in
            guard let cursor = checkpoint.files[identity] else { return true }
            guard cursor.usageParser != nil, !cursor.waitingForMore else { return false }
            return cursor.offset < file.metadata.size
        }
        let unsupported = checkpoint.files.values.contains { ($0.usageParser?.unsupportedAt ?? .distantPast) >= dayStart }
        var today = activity.summary(now: now, calendar: calendar, backfilling: pendingToday,
            partial: readFailed || !rootsReadable || unsupported)
        today.logsAvailable = rootsReadable && !readFailed
        return LogSnapshot(latestSample: sample, cachedQuota: checkpoint.quota,
                           latestResponseAt: latest,
                           hasUnmeasurableResponse: latest.map { $0 > (sample?.completedAt ?? .distantPast) } ?? false,
                           todayUsage: today, recentSamples: TPSHistory.preferred(checkpoint.history ?? []),
                           historyBackfilling: historyPending,
                           historyIsUnattributed: !(checkpoint.history ?? []).isEmpty && !(checkpoint.history ?? []).contains { $0.source == .desktop })
    }

    private func refreshInventory(now: Date) -> Bool {
        inventoryReconciled = false
        let changes = fileEvents.drain()
        var roots: [(URL, FileMetadata)] = []
        var readable = false
        var rootsComplete = true
        for name in ["sessions", "archived_sessions"] {
            let root = home.appendingPathComponent(name)
            guard let metadata = FileMetadata(root) else {
                // Missing roots are expected; denied metadata access does not establish deletion.
                if !Self.isConfirmedMissing(root) { rootsComplete = false }
                continue
            }
            guard metadata.isDirectory else { rootsComplete = false; continue }
            roots.append((root, metadata))
            let rootReadable = FileManager.default.isReadableFile(atPath: root.path)
            rootsComplete = rootsComplete && rootReadable
            readable = rootReadable || readable
        }
        let identities = Dictionary(uniqueKeysWithValues: roots.map { ($0.0, $0.1.identity) })
        let elapsed = lastInventoryScan.map { now.timeIntervalSince($0) }
        let reconcile = changes == nil || changes?.mustRescan == true || changes?.requiresPolling == true || lastInventoryScan == nil
            || identities != rootIdentities || elapsed.map { $0 < 0 || $0 >= 60 } == true
        inventoryChanged = false
        if reconcile {
            inventoryReconciled = rootsComplete && readable
            inventory.removeAll(keepingCapacity: true)
            identitiesByPath.removeAll(keepingCapacity: true)
            visitedDirectories.removeAll(keepingCapacity: true)
            for (root, metadata) in roots { discover(root, metadata: metadata, depth: 0) }
            directories = directories.filter { visitedDirectories.contains($0.key) }
            lastInventoryScan = now
            inventoryChanged = true
        } else if let changes {
            // Process ancestors first; a recursive directory refresh already covers its descendants.
            var refreshedDirectories: [URL] = []
            for path in changes.paths.sorted(by: { $0.path.count < $1.path.count }) {
                if refreshedDirectories.contains(where: { Self.contains(path, under: $0) }) { continue }
                guard let root = roots.first(where: { Self.contains(path, under: $0.0) })?.0 else { continue }
                let relativeDepth = path.pathComponents.count - root.pathComponents.count
                guard relativeDepth <= 9, hasDirectoryAncestors(path, root: root) else {
                    removeInventory(under: path)
                    continue
                }
                guard let metadata = FileMetadata(path) else { removeInventory(under: path); continue }
                if metadata.isDirectory {
                    removeInventory(under: path)
                    discover(path, metadata: metadata, depth: relativeDepth)
                    refreshedDirectories.append(path)
                } else if metadata.isRegularFile && path.pathExtension == "jsonl" {
                    updateInventory(LogFile(url: path, metadata: metadata))
                } else {
                    removeInventory(under: path)
                }
            }
        }
        rootIdentities = identities
        if inventoryChanged {
            orderedInventory = inventory.sorted { $0.value.metadata.modifiedAt > $1.value.metadata.modifiedAt }
        }
        if reconcile || inventoryChanged || changes?.paths.isEmpty == false {
            fileEvents.update(files: orderedInventory.map { $0.value.url }, directories: Array(directories.keys) + [home])
        }
        // A failed listing is never a complete cached inventory; retry it even without another event.
        if readFailed { lastInventoryScan = nil; inventoryReconciled = false }
        return readable
    }

    private static func isConfirmedMissing(_ url: URL) -> Bool {
        var attributes = stat()
        return url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            let result = Darwin.lstat(path, &attributes)
            return result != 0 && (errno == ENOENT || errno == ENOTDIR)
        }
    }

    private static func contains(_ url: URL, under root: URL) -> Bool {
        url.path == root.path || url.path.hasPrefix(root.path + "/")
    }

    private func hasDirectoryAncestors(_ url: URL, root: URL) -> Bool {
        if url.path == root.path { return true }
        var parent = url.deletingLastPathComponent()
        while Self.contains(parent, under: root) {
            guard FileMetadata(parent)?.isDirectory == true else { return false }
            if parent.path == root.path { return true }
            parent.deleteLastPathComponent()
        }
        return false
    }

    private func removeInventory(under path: URL) {
        let removed = inventory.filter { Self.contains($0.value.url, under: path) }
        for (identity, file) in removed {
            inventory.removeValue(forKey: identity)
            identitiesByPath.removeValue(forKey: file.url)
        }
        directories = directories.filter { !Self.contains($0.key, under: path) }
        inventoryChanged = inventoryChanged || !removed.isEmpty
    }

    private func updateInventory(_ file: LogFile) {
        let identity = file.metadata.identity
        if let oldIdentity = identitiesByPath[file.url], oldIdentity != identity {
            inventory.removeValue(forKey: oldIdentity)
            inventoryChanged = true
        }
        if let previous = inventory[identity], previous.url != file.url {
            identitiesByPath.removeValue(forKey: previous.url)
        }
        if inventory[identity] != file { inventoryChanged = true }
        inventory[identity] = file
        identitiesByPath[file.url] = identity
    }

    private func discover(_ directory: URL, metadata: FileMetadata, depth: Int) {
        guard depth <= 8, metadata.isDirectory else { inventoryReconciled = false; return }
        visitedDirectories.insert(directory)
        let entries: [URL]
        if let cached = directories[directory], metadata.hasSameDirectoryContents(as: cached.metadata) {
            entries = cached.entries
        } else {
            do {
                entries = try FileManager.default.contentsOfDirectory(at: directory,
                    includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            } catch { readFailed = true; return }
            directories[directory] = DirectoryListing(metadata: metadata, entries: entries)
        }
        for url in entries {
            // lstat avoids following links and does not fetch unused extended attributes.
            guard let metadata = FileMetadata(url) else { readFailed = true; continue }
            if metadata.isDirectory {
                discover(url, metadata: metadata, depth: depth + 1)
            } else if metadata.isRegularFile && url.pathExtension == "jsonl" {
                updateInventory(LogFile(url: url, metadata: metadata))
            }
        }
    }

    private func read(_ file: LogFile, identity: String, budget: inout Int, now: Date) -> Bool {
        let size = file.metadata.size
        var cursor = checkpoint.files[identity] ?? Cursor()
        let modified = file.metadata.modifiedAt
        let reset = size < cursor.offset || (size == cursor.offset && modified != cursor.modifiedAt)
        if reset {
            cursor = Cursor()
            cursor.modifiedAt = modified
            checkpoint.files[identity] = cursor
        }
        if cursor.usageParser == nil {
            if cursor.parser.source != .other {
                let previous = cursor.sample
                cursor = Cursor()
                cursor.sample = previous
            }
            cursor.usageParser = LocalUsageParser()
        }
        guard size > cursor.offset else { return reset }
        if cursor.waitingForMore && cursor.observedSize == size && cursor.modifiedAt == modified { return false }
        let descriptor = file.url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { readFailed = true; return false }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var openedAttributes = stat()
        guard Darwin.fstat(descriptor, &openedAttributes) == 0,
              openedAttributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              "\(openedAttributes.st_dev)-\(openedAttributes.st_ino)" == identity else {
            readFailed = true
            return false
        }
        do {
            if let anchor = cursor.anchor, cursor.offset > 0 {
                let length = min(cursor.offset, 256)
                try handle.seek(toOffset: cursor.offset - length)
                let bytes = try handle.read(upToCount: Int(length)) ?? Data()
                if Self.fingerprint(bytes) != anchor { cursor = Cursor(); cursor.usageParser = LocalUsageParser() }
            }
            let readStart = cursor.offset
            try handle.seek(toOffset: cursor.offset)
            // Keep the cursor consistent with this poll's metadata if a writer appends during the read.
            let remaining = Int(min(size - cursor.offset, UInt64(Int.max)))
            let count = min(budget, remaining, cursor.discardingOversizedLine ? 2 * 1024 * 1024 : maxLineBytes)
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
                autoreleasepool {
                    let line = data.subdata(in: consumed..<index)
                    if let sample = cursor.parser.consume(line) {
                        cursor.sample = sample
                        checkpoint.history = TPSHistory.retainingSources((checkpoint.history ?? []) + [
                            SourcedTPSSample(sample: sample, source: cursor.parser.source)])
                    }
                    if let usage = cursor.usageParser?.consume(line, observedAt: now) { activity.consume(usage, now: now) }
                    activity.register(cursor.usageParser?.session, origin: cursor.usageParser?.origin)
                    if cursor.parser.source != .excluded && cursor.parser.source != .other {
                        readQuota(line)
                    }
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
        } catch { readFailed = true; return false }
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
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
            ?? (try? Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(text))
    }

    private func save() {
        guard let url = cacheURL else { checkpointNeedsSave = false; return }
        // Failed writes stay dirty, but observe the same disk-write throttle before retrying.
        lastSaveAttempt = Date()
        checkpointNeedsSave = true
        // Keep only one live ledger between saves, avoiding copy-on-write snapshots of its dictionaries.
        checkpoint.activity = activity.state
        defer { checkpoint.activity = nil }
        guard let data = autoreleasepool(invoking: { try? JSONEncoder().encode(checkpoint) }) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try data.write(to: url, options: .atomic)
        } catch { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        checkpointNeedsSave = false
    }

    public func flush() { save() }
}
