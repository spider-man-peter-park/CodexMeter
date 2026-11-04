import Darwin
import Foundation
import Testing
@testable import CodexMeterCore

@Suite struct SystemMetricsTests {
    private func cpu(_ user: UInt32, _ idle: UInt32, system: UInt32 = 0, nice: UInt32 = 0) -> SystemCPUTicks {
        SystemCPUTicks(user: user, system: system, idle: idle, nice: nice)
    }

    @Test func cpuUsesIntervalAcrossAllStatesAndRejectsMissingOrResetCounters() {
        let previous = cpu(100, 100, system: 50, nice: 50)
        #expect(cpu(110, 160, system: 70, nice: 60).utilization(since: previous) == 40)
        #expect(previous.utilization(since: previous) == nil)
        #expect(cpu(0, 200).utilization(since: previous) == nil)
        #expect(cpu(0, 1).utilization(since: cpu(.max, .max)) == nil)
        #expect(cpu(150, 100, system: 50, nice: 50).utilization(since: previous) == 100)
        let breakdown = cpu(110, 160, system: 70, nice: 60).percentages(since: previous)
        #expect(breakdown?.user == 20)
        #expect(breakdown?.system == 20)
        #expect(breakdown?.idle == 60)
        #expect(previous.percentages(since: previous)?.user == nil)
    }

    @Test func ratesUseMonotonicIntervalAndPreserveUploadDownloadDirections() {
        var state = SystemMetricDeltas()
        let first = state.consume(cpu: cpu(100, 100), network: ["en0": .init(received: 100, sent: 200)], uptime: 10)
        #expect(first.cpu == nil && first.upload == nil && first.download == nil)
        let next = state.consume(cpu: cpu(140, 160), network: ["en0": .init(received: 900, sent: 600)], uptime: 12)
        #expect(next.cpu == 40)
        #expect(next.upload == 200)
        #expect(next.download == 400)
        #expect(next.user == 40 && next.system == 0 && next.idle == 60)
    }

    @Test func topologyChangesCounterResetsAndFailedReadsNeedFreshBaseline() {
        var state = SystemMetricDeltas()
        _ = state.consume(cpu: nil, network: ["en0": .init(received: 100, sent: 100)], uptime: 0)
        let added = state.consume(cpu: nil, network: ["en0": .init(received: 200, sent: 200), "en1": .init(received: 99999, sent: 99999)], uptime: 2)
        #expect(added.upload == nil && added.download == nil)
        let removed = state.consume(cpu: nil, network: ["en0": .init(received: 300, sent: 300)], uptime: 4)
        #expect(removed.upload == nil && removed.download == nil)
        let reset = state.consume(cpu: nil, network: ["en0": .init(received: 1, sent: 1)], uptime: 6)
        #expect(reset.upload == nil && reset.download == nil)
        let good = state.consume(cpu: nil, network: ["en0": .init(received: 101, sent: 201)], uptime: 8)
        #expect(good.upload == 100 && good.download == 50)
        _ = state.consume(cpu: nil, network: nil, uptime: 10)
        let recovery = state.consume(cpu: nil, network: ["en0": .init(received: 500, sent: 500)], uptime: 12)
        #expect(recovery.upload == nil && recovery.download == nil)
    }

    @Test func sleepAndNonpositiveOrExcessivelyShortIntervalsDoNotProduceSpikes() {
        for interval in [0.0, -1, 0.001, 11, Double.infinity, Double.nan] {
            var state = SystemMetricDeltas()
            _ = state.consume(cpu: cpu(1, 1), network: ["en0": .init(received: 1, sent: 1)], uptime: 100)
            let result = state.consume(cpu: cpu(1000, 1000), network: ["en0": .init(received: .max, sent: .max)], uptime: 100 + interval)
            #expect(result.cpu == nil && result.upload == nil && result.download == nil)
        }
    }

    @Test func networkUses64BitCountersAndEmptySuccessfulReadMeansOfflineZero() {
        var state = SystemMetricDeltas()
        let base: UInt64 = 1 << 40
        _ = state.consume(cpu: nil, network: ["en0": .init(received: base, sent: base)], uptime: 0)
        let result = state.consume(cpu: nil, network: ["en0": .init(received: base + 1000, sent: base + 4000)], uptime: 2)
        #expect(result.upload == 2000 && result.download == 500)
        var offline = SystemMetricDeltas()
        _ = offline.consume(cpu: nil, network: [:], uptime: 0)
        let empty = offline.consume(cpu: nil, network: [:], uptime: 2)
        #expect(empty.upload == 0 && empty.download == 0)
    }

    @Test func physicalInterfaceFilterExcludesVirtualAndInactiveLinks() {
        let active = Int32(IFF_UP | IFF_RUNNING)
        #expect(SystemMetricValues.includesInterface(name: "en0", type: UInt8(IFT_ETHER), flags: active))
        #expect(SystemMetricValues.includesInterface(name: "en12", type: UInt8(IFT_ETHER), flags: active))
        for name in ["lo0", "utun0", "awdl0", "llw0", "bridge0", "vmenet0", "en", "enX"] {
            #expect(!SystemMetricValues.includesInterface(name: name, type: UInt8(IFT_ETHER), flags: active))
        }
        #expect(!SystemMetricValues.includesInterface(name: "en0", type: UInt8(IFT_ETHER), flags: Int32(IFF_UP)))
        #expect(!SystemMetricValues.includesInterface(name: "en0", type: UInt8(IFT_LOOP), flags: active))
    }

    @Test func memoryCountsPhysicalCompressedPagesAndExcludesPurgeableAnonymousPages() {
        #expect(SystemMetricValues.memoryUsedBytes(wired: 10, anonymous: 50, purgeable: 5, compressed: 20, pageSize: 4096, total: 1_000_000) == 75 * 4096)
        #expect(SystemMetricValues.memoryUsedBytes(wired: 10, anonymous: 5, purgeable: 50, compressed: 20, pageSize: 4096, total: 1_000_000) == 30 * 4096)
        #expect(SystemMetricValues.memoryUsedBytes(wired: .max, anonymous: .max, purgeable: 0, compressed: .max, pageSize: .max, total: 1000) == 1000)
        #expect(SystemMetricValues.memoryUsedBytes(wired: 1, anonymous: 1, purgeable: 0, compressed: 1, pageSize: 0, total: 1000) == nil)
        #expect(SystemMetricsSnapshot(memoryUsedBytes: 200, memoryTotalBytes: 1000).memoryUsagePercent == 20)
        #expect(SystemMetricsSnapshot(memoryUsedBytes: 200, memoryTotalBytes: 0).memoryUsagePercent == nil)
    }

    @Test func gpuOnlyAcceptsExplicitValidDeviceUtilization() {
        #expect(SystemMetricValues.gpuUtilization(["Device Utilization %": 0]) == 0)
        #expect(SystemMetricValues.gpuUtilization(["Device Utilization %": 42.5]) == 42.5)
        for value: Any in [true, -1, 101, Double.nan, Double.infinity, "42"] {
            #expect(SystemMetricValues.gpuUtilization(["Device Utilization %": value]) == nil)
        }
        #expect(SystemMetricValues.gpuUtilization(["Renderer Utilization %": 10]) == nil)
        #expect(SystemMetricValues.gpuUtilization([:]) == nil)
        #expect(SystemMetricValues.gpuUtilization(["Renderer Utilization %": 20], key: "Renderer Utilization %") == 20)
        #expect(SystemMetricValues.gpuUtilization(["Tiler Utilization %": 35], key: "Tiler Utilization %") == 35)
        #expect(SystemMetricValues.gpuUtilization(["Device Utilization %": 10], key: "Tiler Utilization %") == nil)
    }

    @Test func pressureOnlyUsesKnownNativeLevelsWithoutInferringFromMemoryUsage() {
        #expect(SystemMetricValues.memoryPressure(1) == .normal)
        #expect(SystemMetricValues.memoryPressure(2) == .warning)
        #expect(SystemMetricValues.memoryPressure(4) == .critical)
        for value: Int32? in [nil, -1, 0, 3, 5, .max] {
            #expect(SystemMetricValues.memoryPressure(value) == nil)
        }
        #expect(SystemMetricsSnapshot(memoryUsedBytes: 1, memoryTotalBytes: 100).memoryPressure == nil)
        #expect(SystemMetricsSnapshot(memoryUsedBytes: 99, memoryTotalBytes: 100).memoryPressure == nil)
    }

    private func process(_ pid: Int32 = 1, start: UInt64 = 10, memory: UInt64 = 100,
                         user: UInt64 = 0, system: UInt64 = 0) -> SystemProcessCounter {
        SystemProcessCounter(pid: pid, name: "Test process \(pid)", startIdentity: start, memoryBytes: memory,
                             userTicks: user, systemTicks: system)
    }

    @Test func processDeltasStartUnavailableAndUsePerCoreCPUPercentages() {
        var state = SystemProcessDeltas()
        let timebase = SystemProcessTimebase(numerator: 1, denominator: 1)
        let first = state.consume([process(memory: 0)], uptime: 0, timebase: timebase)
        #expect(first.cpu.isEmpty)
        #expect(first.memory.first?.memoryBytes == 0)
        #expect(first.memory.first?.cpuUsagePercent == nil)
        let next = state.consume([process(memory: 2048, user: 4_000_000_000, system: 2_000_000_000)], uptime: 2, timebase: timebase)
        #expect(next.cpu.first?.cpuUsagePercent == 300)
        #expect(next.memory.first?.memoryBytes == 2048)
        let idle = state.consume([process(memory: 2048, user: 4_000_000_000, system: 2_000_000_000)], uptime: 4, timebase: timebase)
        #expect(idle.cpu.first?.cpuUsagePercent == 0)
    }

    @Test func processDeltasRejectPidReuseResetFailedReadsAndSleepGaps() {
        var state = SystemProcessDeltas()
        let timebase = SystemProcessTimebase(numerator: 1, denominator: 1)
        _ = state.consume([process(user: 100)], uptime: 0, timebase: timebase)
        #expect(state.consume([process(start: 20, user: 1_000_000)], uptime: 2, timebase: timebase).cpu.isEmpty)
        #expect(state.consume([process(start: 20, user: 1)], uptime: 4, timebase: timebase).cpu.isEmpty)
        #expect(state.consume([process(start: 20, user: 2)], uptime: 100, timebase: timebase).cpu.isEmpty)
        #expect(state.consume(nil, uptime: 102, timebase: timebase).memory.isEmpty)
        #expect(state.consume([process(start: 20, user: 3)], uptime: 104, timebase: timebase).cpu.isEmpty)
        #expect(state.consume([process(start: 20, user: 4)], uptime: 104, timebase: timebase).cpu.isEmpty)
    }

    @Test func processRankingsAreIndependentlySortedAndBoundedToEight() {
        var state = SystemProcessDeltas()
        let timebase = SystemProcessTimebase(numerator: 1, denominator: 1)
        let initial = (1...12).map { process(Int32($0), memory: UInt64($0)) }
        _ = state.consume(initial, uptime: 0, timebase: timebase)
        let current = (1...12).map { process(Int32($0), memory: UInt64($0), user: UInt64(13 - $0) * 1_000_000_000) }
        let ranked = state.consume(current, uptime: 5, timebase: timebase)
        #expect(ranked.cpu.map(\.pid) == [1, 2, 3, 4, 5, 6, 7, 8])
        #expect(ranked.memory.map(\.pid) == [12, 11, 10, 9, 8, 7, 6, 5])
    }

    @Test func processCPUDeltasConvertAppleSiliconAndIntelMachTimebases() {
        let cases: [(UInt32, UInt32, UInt64)] = [(125, 3, 48_000_000), (1, 1, 2_000_000_000)]
        for (numerator, denominator, ticks) in cases {
            var state = SystemProcessDeltas()
            let timebase = SystemProcessTimebase(numerator: numerator, denominator: denominator)
            let baseline = UInt64.max - ticks
            _ = state.consume([process(user: baseline)], uptime: 0, timebase: timebase)
            let result = state.consume([process(user: .max)], uptime: 2, timebase: timebase)
            #expect(result.cpu.first?.cpuUsagePercent == 100)
        }
    }

    @Test func missingOrInvalidMachTimebaseKeepsProcessCPUUnavailable() {
        let cases: [SystemProcessTimebase?] = [nil, .init(numerator: 1, denominator: 0), .init(numerator: 0, denominator: 1)]
        for timebase in cases {
            var state = SystemProcessDeltas()
            _ = state.consume([process()], uptime: 0, timebase: timebase)
            let result = state.consume([process(user: 2_000_000_000)], uptime: 2, timebase: timebase)
            #expect(result.cpu.isEmpty)
            #expect(result.memory.first?.cpuUsagePercent == nil)
            #expect(result.memory.first?.memoryBytes == 100)
        }
    }

    @Test func executableBasenamesPreserveLongProcessNamesWithoutRetainingPaths() {
        let name = "Google Chrome Helper (Aperitif Renderer)"
        let path = "/Applications/Example.app/Contents/Frameworks/Helper.app/Contents/MacOS/" + name
        #expect(SystemMetricValues.processName(executablePath: path, fallbackName: "Google Chrome Helper (Aperitif") == name)
        #expect(SystemMetricValues.processName(executablePath: nil, fallbackName: "launchd") == "launchd")
        #expect(SystemMetricValues.processName(executablePath: "relative/path", fallbackName: "Fallback process") == "Fallback process")
        #expect(SystemMetricValues.processName(executablePath: "/", fallbackName: "Fallback process") == "Fallback process")
        #expect(SystemMetricValues.processName(executablePath: "", fallbackName: "Fallback process") == "Fallback process")
        #expect(SystemMetricValues.processName(executablePath: nil, fallbackName: "/private/example/Fallback process") == "Fallback process")
        #expect(SystemMetricValues.processName(executablePath: nil, fallbackName: nil) == nil)
        #expect(SystemMetricValues.processName(executablePath: nil, fallbackName: "   ") == nil)
    }

    @Test func nativeCollectorSamplesWithoutPersistingAndResetClearsRates() async throws {
        let monitor = SystemMetricsMonitor()
        let first = await monitor.sample()
        #expect(first.cpuUsagePercent == nil)
        #expect(first.networkUploadBytesPerSecond == nil && first.networkDownloadBytesPerSecond == nil)
        #expect(first.cpuTopProcesses.isEmpty)
        try await Task.sleep(for: .milliseconds(150))
        let next = await monitor.sample()
        for percent in [next.cpuUsagePercent, next.gpuUsagePercent, next.memoryUsagePercent,
                        next.cpuUserPercent, next.cpuSystemPercent, next.cpuIdlePercent,
                        next.gpuRendererUsagePercent, next.gpuTilerUsagePercent].compactMap({ $0 }) {
            #expect(percent.isFinite && (0...100).contains(percent))
        }
        for rate in [next.networkUploadBytesPerSecond, next.networkDownloadBytesPerSecond].compactMap({ $0 }) {
            #expect(rate.isFinite && rate >= 0)
        }
        if let used = next.memoryUsedBytes, let total = next.memoryTotalBytes {
            #expect(next.memoryFreeBytes == total - used)
            #expect(next.memoryAppBytes != nil && next.memoryWiredBytes != nil && next.memoryCompressedBytes != nil)
        }
        if let averages = next.loadAverages {
            #expect(averages.count == 3 && averages.allSatisfy { $0.isFinite && $0 >= 0 })
        }
        #expect(next.memoryTopProcesses.count <= 8 && next.cpuTopProcesses.count <= 8)
        print("System metrics smoke: CPU=\(String(describing: next.cpuUsagePercent)), GPU=\(String(describing: next.gpuUsagePercent)), RAM=\(String(describing: next.memoryUsagePercent)), upload=\(String(describing: next.networkUploadBytesPerSecond)), download=\(String(describing: next.networkDownloadBytesPerSecond))")
        print("System details smoke: GPU devices=\(next.gpuDeviceNames), unified=\(String(describing: next.gpuHasUnifiedMemory)), budget=\(String(describing: next.gpuRecommendedWorkingSetBytes)), renderer=\(String(describing: next.gpuRendererUsagePercent)), tiler=\(String(describing: next.gpuTilerUsagePercent)), pressure=\(String(describing: next.memoryPressure)), swap=\(String(describing: next.memorySwapUsedBytes)), cores=\(String(describing: next.physicalCoreCount))/\(String(describing: next.logicalCoreCount)), memory processes=\(next.memoryTopProcesses.count)")
        await monitor.reset()
        let reset = await monitor.sample()
        #expect(reset.cpuUsagePercent == nil)
        #expect(reset.networkUploadBytesPerSecond == nil && reset.networkDownloadBytesPerSecond == nil)
        #expect(reset.cpuTopProcesses.isEmpty)
    }

    @Test func freshnessRejectsStaleAndFutureReadings() {
        let time = Date(timeIntervalSince1970: 1000)
        let snapshot = SystemMetricsSnapshot(sampledAt: time, cpuUsagePercent: 50)
        #expect(snapshot.fresh(at: time) == snapshot)
        #expect(snapshot.fresh(at: time.addingTimeInterval(10)) == snapshot)
        #expect(snapshot.fresh(at: time.addingTimeInterval(-1)) == snapshot)
        #expect(snapshot.fresh(at: time.addingTimeInterval(10.01)) == nil)
        #expect(snapshot.fresh(at: time.addingTimeInterval(-1.01)) == nil)
    }

    @Test func nativeProcessCPUScanUsesASecondIntervalWithoutPersisting() async throws {
        let monitor = SystemMetricsMonitor()
        let first = await monitor.sample()
        #expect(first.cpuTopProcesses.isEmpty)
        try await Task.sleep(for: .milliseconds(5_100))
        let next = await monitor.sample()
        #expect(next.cpuTopProcesses.count <= 8)
        #expect(next.cpuTopProcesses.allSatisfy {
            $0.pid > 0 && !$0.name.isEmpty && $0.cpuUsagePercent.map { $0.isFinite && $0 >= 0 } == true
        })
        // A protected host may deny every process read; successful scans should establish an interval ranking.
        if !first.memoryTopProcesses.isEmpty && !next.memoryTopProcesses.isEmpty {
            #expect(!next.cpuTopProcesses.isEmpty)
        }
        print("Native process interval smoke: initial memory count=\(first.memoryTopProcesses.count), second memory count=\(next.memoryTopProcesses.count), CPU count=\(next.cpuTopProcesses.count), CPU percentages=\(next.cpuTopProcesses.compactMap(\.cpuUsagePercent))")
    }
}
