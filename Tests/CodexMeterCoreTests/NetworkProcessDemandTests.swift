import Foundation
import Testing
@testable import CodexMeterCore

struct NetworkProcessDemandTests {
    private final class Reader: NetworkProcessReading, @unchecked Sendable {
        private let condition = NSCondition()
        private var collecting = false
        private var released = false
        private var cancellations = 0
        private let value = NetworkProcessSnapshot(updatedAt: Date(), processes: [
            .init(pid: 42, name: "Fixture", uploadBytesPerSecond: 10, downloadBytesPerSecond: 20)
        ])

        var started: Bool {
            condition.lock()
            defer { condition.unlock() }
            return collecting
        }

        var cancelCount: Int {
            condition.lock()
            defer { condition.unlock() }
            return cancellations
        }

        func collect() -> NetworkProcessSnapshot? {
            condition.lock()
            collecting = true
            let deadline = Date().addingTimeInterval(2)
            while !released {
                if !condition.wait(until: deadline) { break }
            }
            condition.unlock()
            // Deliberately return a result after cancellation to exercise stale-generation rejection.
            return value
        }

        func finish() {
            condition.lock()
            released = true
            condition.broadcast()
            condition.unlock()
        }

        func cancel() {
            condition.lock()
            cancellations += 1
            released = true
            condition.broadcast()
            condition.unlock()
        }
    }

    private final class Factory: @unchecked Sendable {
        private let lock = NSLock()
        private var readers: [Reader] = []

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return readers.count
        }

        func make() -> any NetworkProcessReading {
            let reader = Reader()
            lock.lock()
            readers.append(reader)
            lock.unlock()
            return reader
        }

        func reader(at index: Int) -> Reader? {
            lock.lock()
            defer { lock.unlock() }
            return readers.indices.contains(index) ? readers[index] : nil
        }
    }

    @Test func hiddenNetworkDetailNeverStartsACollector() async {
        let factory = Factory()
        let monitor = NetworkProcessMonitor(makeReader: { factory.make() })
        for _ in 0..<20 {
            #expect(await monitor.snapshot(enabled: false) == nil)
        }
        #expect(factory.count == 0)
    }

    @Test func hidingCancelsAndClearsTheCaptureAndReopeningStartsFresh() async throws {
        let factory = Factory()
        let monitor = NetworkProcessMonitor(makeReader: { factory.make() })
        #expect(await monitor.snapshot() == nil)
        let first = try #require(factory.reader(at: 0))
        for _ in 0..<100 {
            if first.started { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(first.started)
        #expect(await monitor.snapshot(enabled: false) == nil)
        #expect(first.cancelCount == 1)
        #expect(await monitor.snapshot(enabled: false) == nil)
        #expect(factory.count == 1)

        #expect(await monitor.snapshot() == nil)
        #expect(factory.count == 2)
        let second = try #require(factory.reader(at: 1))
        second.finish()
        var result: NetworkProcessSnapshot?
        for _ in 0..<100 {
            result = await monitor.snapshot()
            if result != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(result?.processes.first?.pid == 42)
        #expect(result?.processes.first?.uploadBytesPerSecond == 10)
        #expect(await monitor.snapshot(enabled: false) == nil)
        #expect(await monitor.snapshot(enabled: false) == nil)
        #expect(factory.count == 2)
        await monitor.reset()
    }
}
