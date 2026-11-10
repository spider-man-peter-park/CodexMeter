import Darwin
import Foundation

/// Reads only the numeric projection checkpoints; it never opens credentials or conversation logs.
public actor DeepSeekHarnessUsageReader {
    private static let maximumFiles = 2_000
    private static let maximumEntries = 4_000
    private static let maximumFileBytes = 16 * 1_024 * 1_024
    private static let maximumReadBytes = 64 * 1_024 * 1_024
    private let home: URL
    private var cache: [String: CachedFile] = [:]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh", isDirectory: true)) {
        self.home = home.standardizedFileURL
    }

    public func readUsage(now: Date = Date()) async -> ProviderUsageResult {
        let directory = home.appendingPathComponent("storages/session_projcache/sessions", isDirectory: true)
        for path in [home, home.appendingPathComponent("storages"), home.appendingPathComponent("storages/session_projcache"), directory] {
            guard let metadata = Metadata(path) else {
                let failure = errno
                cache.removeAll()
                return result(failure == ENOENT || failure == ENOTDIR ? .notFound : .unavailable,
                    message: "DeepSeek Harness local projection cache was not found or could not be read.")
            }
            guard metadata.kind == mode_t(S_IFDIR) else {
                cache.removeAll()
                return result(.unsupported, message: "DeepSeek Harness projection cache must be a local directory, not a symbolic link.")
            }
        }

        var incomplete = false
        guard let entries = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants], errorHandler: { _, _ in incomplete = true; return false }) else {
            return result(.unavailable, message: "DeepSeek Harness local projection cache could not be read.")
        }
        var files: [(URL, Metadata)] = []
        var inspected = 0
        for case let file as URL in entries {
            inspected += 1
            guard inspected <= Self.maximumEntries else { incomplete = true; break }
            guard file.pathExtension == "json" else { continue }
            guard let metadata = Metadata(file), metadata.kind == mode_t(S_IFREG) else { incomplete = true; continue }
            guard files.count < Self.maximumFiles else { incomplete = true; break }
            files.append((file, metadata))
        }
        files.sort { $0.1.modifiedAt == $1.1.modifiedAt ? $0.0.lastPathComponent < $1.0.lastPathComponent : $0.1.modifiedAt > $1.1.modifiedAt }

        var retained: Set<String> = []
        var sessions: [ScalarUsage] = []
        var validDocuments = 0
        var unsupported = false
        var bytesRead = 0
        for (file, metadata) in files {
            guard !Task.isCancelled else {
                return result(.unavailable, message: "DeepSeek Harness usage reading was cancelled.")
            }
            let key = file.lastPathComponent
            retained.insert(key)
            let outcome: FileOutcome
            if let saved = cache[key], saved.metadata == metadata {
                outcome = saved.outcome
            } else if metadata.size > Self.maximumFileBytes || metadata.size > Self.maximumReadBytes - bytesRead {
                cache.removeValue(forKey: key)
                incomplete = true
                continue
            } else {
                bytesRead += metadata.size
                outcome = autoreleasepool { Self.read(file, metadata: metadata) }
                cache[key] = CachedFile(metadata: metadata, outcome: outcome)
            }
            switch outcome {
            case .usage(let usage):
                validDocuments += 1
                sessions.append(usage)
                incomplete = incomplete || usage.isPartial
            case .inherited:
                validDocuments += 1
                incomplete = true
            case .unsupported:
                unsupported = true
                incomplete = true
            case .invalid:
                incomplete = true
            }
        }
        cache = cache.filter { retained.contains($0.key) }
        if validDocuments == 0 && (incomplete || unsupported) {
            return result(unsupported ? .unsupported : .unavailable,
                message: "No supported DeepSeek Harness usage checkpoints could be read. Missing or incompatible data is not zero usage.")
        }

        var input = CountSum(), output = CountSum(), cached = CountSum(), written = CountSum(), total = CountSum()
        var modelTime = DurationSum(), decodeTime = DurationSum(), decodeTokens = CountSum()
        for session in sessions {
            if let tokens = session.tokens {
                input.add(tokens.input)
                output.add(tokens.output)
                cached.add(tokens.cached)
                written.add(tokens.written)
                total.add(tokens.total)
            }
            if let stats = session.stats {
                modelTime.add(stats.modelMilliseconds)
                decodeTime.add(stats.decodeMilliseconds)
                decodeTokens.add(stats.decodeTokens)
            }
        }
        incomplete = incomplete || [input, output, cached, written, total, decodeTokens].contains { $0.overflowed }
            || modelTime.overflowed || decodeTime.overflowed
        var snapshot = ProviderUsageSnapshot(provider: .deepseekHarness, scope: .localSessions, sampledAt: now)
        snapshot.periodLabel = "Local non-forked session checkpoints"
        snapshot.inputTokens = input.value
        snapshot.outputTokens = output.value
        snapshot.cachedInputTokens = cached.value
        snapshot.cacheWriteTokens = written.value
        snapshot.totalTokens = total.value
        snapshot.sessionCount = sessions.count
        snapshot.modelSeconds = modelTime.value.map { $0 / 1_000 }
        snapshot.decodeTokensPerSecond = Self.decodeRate(tokens: decodeTokens.value, milliseconds: decodeTime.value)
        snapshot.isPartial = incomplete
        snapshot.sessions = sessions.prefix(50).map { session in
            ProviderSessionUsage(id: session.id, tokens: session.tokens?.total,
                modelSeconds: session.stats.map { $0.modelMilliseconds / 1_000 },
                decodeTokensPerSecond: Self.decodeRate(tokens: session.stats?.decodeTokens,
                    milliseconds: session.stats?.decodeMilliseconds), updatedAt: session.updatedAt)
        }
        return result(.ready, snapshot: snapshot, message: incomplete
            ? "Partial local non-forked session totals, not today's usage or an account bill. Checkpoints may lag behind Harness."
            : "Local non-forked session totals, not today's usage or an account bill. Checkpoints may lag behind Harness.")
    }

    private func result(_ status: ProviderConnectionStatus, snapshot: ProviderUsageSnapshot? = nil, message: String) -> ProviderUsageResult {
        ProviderUsageResult(provider: .deepseekHarness, status: status, snapshot: snapshot, message: message)
    }

    private static func decodeRate(tokens: Int?, milliseconds: Double?) -> Double? {
        guard let tokens, let milliseconds, milliseconds > 0 else { return nil }
        let value = Double(tokens) / milliseconds * 1_000
        return value.isFinite ? value : nil
    }

    private static func read(_ url: URL, metadata: Metadata) -> FileOutcome {
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) } ?? -1
        }
        guard descriptor >= 0 else { return .invalid }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0, Metadata(attributes) == metadata else { return .invalid }
        do {
            let data = try handle.read(upToCount: Self.maximumFileBytes + 1) ?? Data()
            guard data.count == metadata.size,
                  fstat(descriptor, &attributes) == 0, Metadata(attributes) == metadata else { return .invalid }
            let document = try JSONDecoder().decode(Document.self, from: data)
            if document.inherited { return .inherited }
            guard document.tokens != nil || document.stats != nil else { return .unsupported }
            return .usage(ScalarUsage(id: url.deletingPathExtension().lastPathComponent,
                tokens: document.tokens, stats: document.stats, updatedAt: metadata.modifiedAt,
                isPartial: document.tokens == nil || document.stats == nil))
        } catch ParseFailure.unsupported {
            return .unsupported
        } catch {
            return .invalid
        }
    }

    private struct Metadata: Equatable {
        let device: Int32
        let inode: UInt64
        let size: Int
        let kind: mode_t
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int
        var modifiedAt: Date { Date(timeIntervalSince1970: Double(modifiedSeconds) + Double(modifiedNanoseconds) / 1_000_000_000) }

        init?(_ url: URL) {
            var attributes = stat()
            let status = url.withUnsafeFileSystemRepresentation { path in
                path.map { Darwin.lstat($0, &attributes) } ?? -1
            }
            guard status == 0, attributes.st_size >= 0, attributes.st_size <= Int.max else { return nil }
            self.init(attributes)
        }

        init(_ attributes: stat) {
            device = attributes.st_dev
            inode = attributes.st_ino
            size = Int(attributes.st_size)
            kind = attributes.st_mode & mode_t(S_IFMT)
            modifiedSeconds = attributes.st_mtimespec.tv_sec
            modifiedNanoseconds = attributes.st_mtimespec.tv_nsec
            changedSeconds = attributes.st_ctimespec.tv_sec
            changedNanoseconds = attributes.st_ctimespec.tv_nsec
        }
    }

    private struct CachedFile { let metadata: Metadata; let outcome: FileOutcome }
    private enum FileOutcome { case usage(ScalarUsage), inherited, unsupported, invalid }
    private enum ParseFailure: Error { case unsupported, invalid }
    private struct ScalarUsage {
        let id: String
        let tokens: Tokens?
        let stats: Stats?
        let updatedAt: Date
        let isPartial: Bool
    }

    private struct Count: Decodable {
        let value: Int
        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer().decode(Int.self)
            guard (0...9_007_199_254_740_991).contains(value) else { throw ParseFailure.invalid }
            self.value = value
        }
    }

    private struct TokenBuckets: Decodable {
        let uncachedInputTokens: Count
        let outputTokens: Count
        let cacheReadTokens: Count
        let cacheWriteTokens: Count
    }

    private struct Tokens {
        let input: Int
        let output: Int
        let cached: Int
        let written: Int
        let total: Int

        init(_ buckets: TokenBuckets) throws {
            let inputSum = buckets.uncachedInputTokens.value.addingReportingOverflow(buckets.cacheReadTokens.value)
            let allInput = inputSum.partialValue.addingReportingOverflow(buckets.cacheWriteTokens.value)
            let allTokens = allInput.partialValue.addingReportingOverflow(buckets.outputTokens.value)
            guard !inputSum.overflow, !allInput.overflow, !allTokens.overflow else { throw ParseFailure.invalid }
            input = allInput.partialValue
            output = buckets.outputTokens.value
            cached = buckets.cacheReadTokens.value
            written = buckets.cacheWriteTokens.value
            total = allTokens.partialValue
        }
    }

    private struct Stats: Decodable {
        let modelMilliseconds: Double
        let decodeMilliseconds: Double
        let decodeTokens: Int
        private enum CodingKeys: String, CodingKey { case llmMs, decodeMs, decodeTokens }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            modelMilliseconds = try values.decode(Double.self, forKey: .llmMs)
            decodeMilliseconds = try values.decode(Double.self, forKey: .decodeMs)
            decodeTokens = try values.decode(Count.self, forKey: .decodeTokens).value
            guard modelMilliseconds.isFinite, modelMilliseconds >= 0,
                  decodeMilliseconds.isFinite, decodeMilliseconds >= 0 else { throw ParseFailure.invalid }
        }
    }

    private struct Document: Decodable {
        let inherited: Bool
        let tokens: Tokens?
        let stats: Stats?
        private enum Keys: String, CodingKey { case version, record, identity, isSeeded, inheritedEventCount, rows, tokenUsage, sessionStats, ver, seq, val, totals }

        init(from decoder: Decoder) throws {
            let root = try decoder.container(keyedBy: Keys.self)
            guard try root.decode(Int.self, forKey: .version) == 7 else { throw ParseFailure.unsupported }
            let record = try root.nestedContainer(keyedBy: Keys.self, forKey: .record)
            let identity = try record.nestedContainer(keyedBy: Keys.self, forKey: .identity)
            let seeded = try identity.decode(Bool.self, forKey: .isSeeded)
            let inheritedCount = try identity.decode(Count.self, forKey: .inheritedEventCount).value
            inherited = seeded || inheritedCount > 0
            if inherited { tokens = nil; stats = nil; return }
            let rows = try record.nestedContainer(keyedBy: Keys.self, forKey: .rows)
            if rows.contains(.tokenUsage) {
                let tokenRow = try rows.nestedContainer(keyedBy: Keys.self, forKey: .tokenUsage)
                if try tokenRow.decode(Int.self, forKey: .ver) == 2 {
                    guard try tokenRow.decode(Int.self, forKey: .seq) >= -1 else { throw ParseFailure.invalid }
                    let value = try tokenRow.nestedContainer(keyedBy: Keys.self, forKey: .val)
                    tokens = try Tokens(value.decode(TokenBuckets.self, forKey: .totals))
                } else { tokens = nil }
            } else { tokens = nil }
            if rows.contains(.sessionStats) {
                let statsRow = try rows.nestedContainer(keyedBy: Keys.self, forKey: .sessionStats)
                if try statsRow.decode(Int.self, forKey: .ver) == 1 {
                    guard try statsRow.decode(Int.self, forKey: .seq) >= -1 else { throw ParseFailure.invalid }
                    stats = try statsRow.decode(Stats.self, forKey: .val)
                } else { stats = nil }
            } else { stats = nil }
        }
    }

    private struct CountSum {
        private var total = 0
        private var hasValue = false
        private(set) var overflowed = false
        var value: Int? { hasValue && !overflowed ? total : nil }
        mutating func add(_ count: Int) {
            hasValue = true
            guard !overflowed else { return }
            let sum = total.addingReportingOverflow(count)
            overflowed = sum.overflow
            total = sum.partialValue
        }
    }

    private struct DurationSum {
        private var total = 0.0
        private var hasValue = false
        private(set) var overflowed = false
        var value: Double? { hasValue && !overflowed ? total : nil }
        mutating func add(_ duration: Double) {
            hasValue = true
            total += duration
            overflowed = !total.isFinite
        }
    }
}
