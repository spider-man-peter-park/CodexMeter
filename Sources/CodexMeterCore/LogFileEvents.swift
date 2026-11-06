import Darwin
import Foundation

enum LogFilePaths {
    static func canonical(_ url: URL) -> URL {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path, let resolved = realpath(path, nil) else { return url.standardizedFileURL }
            defer { free(resolved) }
            return URL(fileURLWithPath: String(cString: resolved), isDirectory: url.hasDirectoryPath)
        }
    }
}

struct LogFileChanges: Sendable {
    var paths: Set<URL> = []
    var mustRescan = false
    var requiresPolling = false
}

enum LogFileWatchBudget {
    static func limit(maximumWatches: Int, soft: rlim_t, hard: rlim_t,
                      raiseSoftLimit: (rlim_t) -> Bool) -> Int {
        let requested = min(2_048, max(0, maximumWatches))
        let target = min(hard, rlim_t(requested + 64), 4_096)
        let available = soft < target && raiseSoftLimit(target) ? target : soft
        return min(requested, max(0, Int(min(available, 4_096)) - 64))
    }
}

protocol LogFileEventReading: Sendable {
    /// Returns nil when notifications are unavailable and polling must reconcile every file.
    func drain() -> LogFileChanges?
    func update(files: [URL], directories: [URL])
}

extension LogFileEventReading {
    func update(files: [URL], directories: [URL]) {}
}

/// Vnode events are immediately observable without waiting for a daemon or a callback queue.
final class LogFileEvents: LogFileEventReading, @unchecked Sendable {
    private let lock = NSLock()
    private let queue: Int32
    private let watchLimit: Int
    private var descriptors: [URL: Int32] = [:]
    private var pathsByDescriptor: [Int32: URL] = [:]
    private var unwatched: Set<URL> = []
    private var newlyWatched: Set<URL> = []

    init(home: URL, maximumWatches: Int = 2_048) {
        queue = Darwin.kqueue()
        if queue >= 0 { _ = fcntl(queue, F_SETFD, FD_CLOEXEC) }
        var limits = rlimit()
        if getrlimit(RLIMIT_NOFILE, &limits) == 0 {
            watchLimit = LogFileWatchBudget.limit(maximumWatches: maximumWatches, soft: limits.rlim_cur,
                hard: limits.rlim_max) { target in
                    // Raise only this process's soft limit; preserve the existing hard limit.
                    var proposed = limits
                    proposed.rlim_cur = target
                    return setrlimit(RLIMIT_NOFILE, &proposed) == 0
                }
        } else {
            watchLimit = LogFileWatchBudget.limit(maximumWatches: maximumWatches, soft: 256, hard: 256,
                raiseSoftLimit: { _ in false })
        }
        update(files: [], directories: [LogFilePaths.canonical(home)])
    }

    func update(files: [URL], directories: [URL]) {
        lock.lock()
        defer { lock.unlock() }
        guard queue >= 0 else { return }
        let desired = Set(directories + files)
        for path in descriptors.keys.filter({ !desired.contains($0) }) { remove(path) }
        unwatched.removeAll(keepingCapacity: true)
        // Directory notifications keep new files discoverable even when the descriptor budget is exhausted.
        for path in directories + files where descriptors[path] == nil {
            guard descriptors.count < watchLimit else { unwatched.insert(path); continue }
            let descriptor = path.withUnsafeFileSystemRepresentation { path in
                path.map { Darwin.open($0, O_EVTONLY | O_CLOEXEC | O_NOFOLLOW) } ?? -1
            }
            guard descriptor >= 0 else { unwatched.insert(path); continue }
            var event = kevent64_s(ident: UInt64(descriptor), filter: Int16(EVFILT_VNODE), flags: UInt16(EV_ADD | EV_CLEAR),
                fflags: UInt32(NOTE_WRITE | NOTE_EXTEND | NOTE_ATTRIB | NOTE_LINK | NOTE_RENAME | NOTE_DELETE | NOTE_REVOKE),
                data: 0, udata: 0, ext: (0, 0))
            guard Darwin.kevent64(queue, &event, 1, nil, 0, 0, nil) == 0 else {
                Darwin.close(descriptor)
                unwatched.insert(path)
                continue
            }
            descriptors[path] = descriptor
            pathsByDescriptor[descriptor] = path
            // Recheck once after registration: metadata discovery may have raced with this open.
            newlyWatched.insert(path)
        }
    }

    func drain() -> LogFileChanges? {
        lock.lock()
        defer { lock.unlock() }
        guard queue >= 0 else { return nil }
        // Reconcile once per poll when the budget cannot cover the tree, rather than invalidating each subtree.
        var changes = LogFileChanges(paths: newlyWatched, requiresPolling: !unwatched.isEmpty)
        newlyWatched.removeAll(keepingCapacity: true)
        var events = [kevent64_s](repeating: kevent64_s(), count: 256)
        var timeout = timespec(tv_sec: 0, tv_nsec: 0)
        for _ in 0..<16 {
            let count = events.withUnsafeMutableBufferPointer {
                Darwin.kevent64(queue, nil, 0, $0.baseAddress, Int32($0.count), 0, &timeout)
            }
            if count < 0 {
                if errno == EINTR { continue }
                changes.mustRescan = true
                return changes
            }
            for event in events.prefix(Int(count)) {
                guard let path = pathsByDescriptor[Int32(event.ident)] else { continue }
                changes.paths.insert(path)
                if event.flags & UInt16(EV_ERROR) != 0 { changes.mustRescan = true }
                if event.fflags & UInt32(NOTE_RENAME | NOTE_DELETE | NOTE_REVOKE) != 0 {
                    remove(path)
                    unwatched.insert(path)
                }
            }
            if count < events.count { return changes }
        }
        // A continuously changing tree must not make a poll unbounded.
        changes.mustRescan = true
        return changes
    }

    private func remove(_ path: URL) {
        guard let descriptor = descriptors.removeValue(forKey: path) else { return }
        pathsByDescriptor.removeValue(forKey: descriptor)
        newlyWatched.remove(path)
        Darwin.close(descriptor)
    }

    deinit {
        for descriptor in descriptors.values { Darwin.close(descriptor) }
        if queue >= 0 { Darwin.close(queue) }
    }
}
