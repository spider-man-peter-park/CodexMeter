import Darwin
import Foundation

public struct SystemNetworkProcessUsage: Equatable, Identifiable, Sendable {
    public let pid: Int32
    public let name: String
    public let uploadBytesPerSecond: Double
    public let downloadBytesPerSecond: Double
    public var id: Int32 { pid }

    public init(pid: Int32, name: String, uploadBytesPerSecond: Double, downloadBytesPerSecond: Double) {
        self.pid = pid
        self.name = name
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.downloadBytesPerSecond = downloadBytesPerSecond
    }
}

struct NetworkProcessSnapshot: Sendable {
    let updatedAt: Date
    let processes: [SystemNetworkProcessUsage]
}

struct NettopCSVParser {
    private struct Counter {
        let name: String
        let received: UInt64
        let sent: UInt64
    }

    private var columns: (received: Int, sent: Int)?
    private var current: [Int32: Counter] = [:]
    private var currentTime: TimeInterval?
    private var previous: [Int32: Counter]?
    private var previousTime: TimeInterval?

    mutating func consume(_ line: String, uptime: TimeInterval) {
        guard let fields = Self.fields(line.trimmingCharacters(in: .newlines)), !fields.isEmpty else { return }
        if fields[0].isEmpty, let received = fields.firstIndex(of: "bytes_in"), let sent = fields.firstIndex(of: "bytes_out") {
            previous = currentTime == nil ? nil : current
            previousTime = currentTime
            current = [:]
            currentTime = uptime
            columns = (received, sent)
            return
        }
        guard currentTime != nil, let columns, fields.indices.contains(max(columns.received, columns.sent)),
              let separator = fields[0].lastIndex(of: "."),
              let pid = Int32(fields[0][fields[0].index(after: separator)...]), pid > 0,
              let received = UInt64(fields[columns.received]), let sent = UInt64(fields[columns.sent]) else { return }
        let name = String(fields[0][..<separator]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        current[pid] = Counter(name: name, received: received, sent: sent)
    }

    func snapshot(at date: Date = Date()) -> NetworkProcessSnapshot? {
        guard let currentTime, let previousTime, let previous else { return nil }
        let elapsed = currentTime - previousTime
        guard elapsed.isFinite, (0.05...5).contains(elapsed) else { return nil }
        let processes = current.compactMap { pid, counter -> SystemNetworkProcessUsage? in
            guard let old = previous[pid], old.name == counter.name,
                  counter.received >= old.received, counter.sent >= old.sent else { return nil }
            let upload = Double(counter.sent - old.sent) / elapsed
            let download = Double(counter.received - old.received) / elapsed
            guard upload > 0 || download > 0 else { return nil }
            return SystemNetworkProcessUsage(pid: pid, name: counter.name,
                uploadBytesPerSecond: upload, downloadBytesPerSecond: download)
        }.sorted {
            let lhs = $0.uploadBytesPerSecond + $0.downloadBytesPerSecond
            let rhs = $1.uploadBytesPerSecond + $1.downloadBytesPerSecond
            return lhs == rhs ? $0.pid < $1.pid : lhs > rhs
        }
        return NetworkProcessSnapshot(updatedAt: date, processes: Array(processes.prefix(8)))
    }

    static func fields(_ line: String) -> [String]? {
        var result: [String] = []
        var field = ""
        var quoted = false
        var cursor = line.startIndex
        while cursor < line.endIndex {
            let character = line[cursor]
            let next = line.index(after: cursor)
            if character == "\"" {
                if quoted, next < line.endIndex, line[next] == "\"" {
                    field.append("\"")
                    cursor = line.index(after: next)
                    continue
                }
                quoted.toggle()
            } else if character == ",", !quoted {
                result.append(field)
                field = ""
            } else {
                field.append(character)
            }
            cursor = next
        }
        guard !quoted else { return nil }
        result.append(field)
        return result
    }
}

protocol NetworkProcessReading: Sendable {
    func collect() -> NetworkProcessSnapshot?
    func cancel()
}

private final class NettopReader: NetworkProcessReading, @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        let current = process
        lock.unlock()
        if current?.isRunning == true { current?.terminate() }
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func collect() -> NetworkProcessSnapshot? {
        var master: Int32 = -1
        var slave: Int32 = -1
        // nettop fully buffers a pipe. A terminal flushes each sample so its monotonic timestamp is observable.
        guard openpty(&master, &slave, nil, nil, nil) == 0 else { return nil }
        _ = fcntl(master, F_SETFD, FD_CLOEXEC)
        _ = fcntl(slave, F_SETFD, FD_CLOEXEC)
        let input = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        let output = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        command.arguments = ["-P", "-L", "2", "-s", "1", "-n", "-x", "-J", "bytes_in,bytes_out", "-t", "external"]
        command.standardInput = FileHandle.nullDevice
        command.standardOutput = output
        command.standardError = FileHandle.nullDevice
        lock.lock()
        process = command
        let stopped = cancelled
        lock.unlock()
        let timeout = DispatchWorkItem { [weak self] in self?.cancel() }
        defer {
            timeout.cancel()
            try? output.close()
            try? input.close()
            lock.lock()
            process = nil
            lock.unlock()
        }
        guard !stopped else { return nil }
        do { try command.run() } catch { return nil }
        try? output.close()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: timeout)
        if isCancelled { cancel() }
        var parser = NettopCSVParser()
        var pending = Data()
        var bytes = 0
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while !isCancelled {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(master, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            // A pseudo-terminal reports EIO when the child closes its final slave descriptor.
            guard count > 0 else { break }
            let chunk = Data(buffer.prefix(count))
            bytes += chunk.count
            guard bytes <= 1_048_576 else { cancel(); break }
            pending.append(chunk)
            let time = ProcessInfo.processInfo.systemUptime
            while let newline = pending.firstIndex(of: 10) {
                let line = String(decoding: pending[..<newline], as: UTF8.self)
                parser.consume(line, uptime: time)
                pending.removeSubrange(...newline)
            }
        }
        command.waitUntilExit()
        guard !isCancelled, command.terminationStatus == 0 else { return nil }
        return parser.snapshot()
    }
}

actor NetworkProcessMonitor {
    private var current: NetworkProcessSnapshot?
    private var task: Task<Void, Never>?
    private var reader: (any NetworkProcessReading)?
    private var lastStarted: TimeInterval?
    private var generation = 0
    private let makeReader: @Sendable () -> any NetworkProcessReading

    init() { makeReader = { NettopReader() } }

    init(makeReader: @escaping @Sendable () -> any NetworkProcessReading) {
        self.makeReader = makeReader
    }

    func snapshot(enabled: Bool = true) -> NetworkProcessSnapshot? {
        guard enabled else {
            if task != nil || current != nil || lastStarted != nil { reset() }
            return nil
        }
        let time = ProcessInfo.processInfo.systemUptime
        if task == nil, lastStarted == nil || time - (lastStarted ?? 0) >= 4 {
            let reader = makeReader()
            self.reader = reader
            lastStarted = time
            let generation = generation
            task = Task { [weak self] in
                let value = await Task.detached(priority: .utility) { reader.collect() }.value
                await self?.complete(value, generation: generation)
            }
        }
        guard let current, Date().timeIntervalSince(current.updatedAt) <= 10 else { return nil }
        return current
    }

    private func complete(_ value: NetworkProcessSnapshot?, generation: Int) {
        guard generation == self.generation else { return }
        current = value
        reader = nil
        task = nil
    }

    func reset() {
        generation += 1
        reader?.cancel()
        task?.cancel()
        reader = nil
        task = nil
        current = nil
        lastStarted = nil
    }

    deinit { reader?.cancel(); task?.cancel() }
}
