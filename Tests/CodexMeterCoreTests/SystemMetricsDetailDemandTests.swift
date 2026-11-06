import Foundation
import Testing
@testable import CodexMeterCore

struct SystemMetricsDetailDemandTests {
    private final class Sources {
        var processReads = 0
        var timebaseReads = 0
        var gpuReads = 0
        var userTicks: UInt64 = 0

        func sample(_ state: inout SystemMetricsDetailState, demand: SystemMetricsDetailDemand,
                    uptime: TimeInterval) {
            state.sample(demand: demand, uptime: uptime, readProcesses: {
                self.processReads += 1
                return [.init(pid: 42, name: "Fixture", startIdentity: 1, memoryBytes: 1024,
                              userTicks: self.userTicks, systemTicks: 0)]
            }, readProcessTimebase: {
                self.timebaseReads += 1
                return .init(numerator: 1, denominator: 1)
            }, readGPUHardware: {
                self.gpuReads += 1
                return .init(names: ["Fixture GPU"], unifiedMemory: true, recommendedWorkingSet: 4096)
            })
        }
    }

    @Test func backgroundAndNetworkOnlyDemandDoNotReadExpensiveLocalDetails() {
        var state = SystemMetricsDetailState()
        let sources = Sources()
        for second in stride(from: 0, through: 120, by: 2) {
            sources.sample(&state, demand: .init(), uptime: Double(second))
            sources.sample(&state, demand: .init(networkProcesses: true), uptime: Double(second))
        }
        #expect(sources.processReads == 0)
        #expect(sources.timebaseReads == 0)
        #expect(sources.gpuReads == 0)
        #expect(state.processUsage.cpu.isEmpty && state.processUsage.memory.isEmpty)
        #expect(state.gpuHardware == nil)
        #expect(SystemMetricsDetailDemand.all == .init(processes: true, networkProcesses: true, gpuHardware: true))
    }

    @Test func processDetailKeepsItsCadenceAndClearsTheBaselineWhenHidden() {
        var state = SystemMetricsDetailState()
        let sources = Sources()
        let demand = SystemMetricsDetailDemand(processes: true)
        sources.sample(&state, demand: demand, uptime: 0)
        #expect(state.processUsage.cpu.isEmpty)
        #expect(state.processUsage.memory.first?.memoryBytes == 1024)
        sources.userTicks = 1_000_000_000
        sources.sample(&state, demand: demand, uptime: 2)
        #expect(sources.processReads == 1)
        sources.userTicks = 6_000_000_000
        sources.sample(&state, demand: demand, uptime: 6)
        #expect(sources.processReads == 2 && sources.timebaseReads == 2)
        #expect(state.processUsage.cpu.first?.cpuUsagePercent == 100)
        #expect(sources.gpuReads == 0)

        sources.sample(&state, demand: .init(), uptime: 7)
        #expect(state.processUsage.cpu.isEmpty && state.processUsage.memory.isEmpty)
        sources.userTicks = 7_000_000_000
        sources.sample(&state, demand: demand, uptime: 8)
        #expect(sources.processReads == 3)
        #expect(state.processUsage.cpu.isEmpty)
        #expect(state.processUsage.memory.first?.memoryBytes == 1024)
        sources.userTicks = 13_000_000_000
        sources.sample(&state, demand: demand, uptime: 14)
        #expect(state.processUsage.cpu.first?.cpuUsagePercent == 100)
    }

    @Test func gpuMetadataIsRequestedIndependentlyAndReleasedWhenHidden() {
        var state = SystemMetricsDetailState()
        let sources = Sources()
        let demand = SystemMetricsDetailDemand(gpuHardware: true)
        sources.sample(&state, demand: demand, uptime: 0)
        #expect(state.gpuHardware?.names == ["Fixture GPU"])
        #expect(state.gpuHardware?.unifiedMemory == true)
        sources.sample(&state, demand: demand, uptime: 2)
        #expect(sources.gpuReads == 1)
        sources.sample(&state, demand: demand, uptime: 30)
        #expect(sources.gpuReads == 2)
        #expect(sources.processReads == 0)
        sources.sample(&state, demand: .init(), uptime: 31)
        #expect(state.gpuHardware == nil)
        sources.sample(&state, demand: demand, uptime: 32)
        #expect(sources.gpuReads == 3)
    }

    @Test func resetAndLongPausesRequireFreshProcessRatesWithoutHidingMemory() {
        var state = SystemMetricsDetailState()
        let sources = Sources()
        sources.sample(&state, demand: .all, uptime: 100)
        sources.userTicks = 6_000_000_000
        sources.sample(&state, demand: .all, uptime: 106)
        #expect(state.processUsage.cpu.first?.cpuUsagePercent == 100)
        sources.userTicks = 100_000_000_000
        sources.sample(&state, demand: .all, uptime: 200)
        #expect(state.processUsage.cpu.isEmpty)
        #expect(!state.processUsage.memory.isEmpty)

        state = SystemMetricsDetailState()
        sources.sample(&state, demand: .all, uptime: 202)
        #expect(state.processUsage.cpu.isEmpty)
        #expect(!state.processUsage.memory.isEmpty)
        #expect(state.gpuHardware?.names == ["Fixture GPU"])
    }

    @Test func aggregateMetricsRemainAvailableWithNoDetailDemand() async throws {
        let monitor = SystemMetricsMonitor()
        let first = await monitor.sample(demand: .init())
        #expect(first.memoryTotalBytes != nil)
        #expect(first.cpuTopProcesses.isEmpty && first.memoryTopProcesses.isEmpty)
        #expect(first.networkTopProcesses.isEmpty && first.networkProcessesUpdatedAt == nil)
        #expect(first.gpuDeviceNames.isEmpty && first.gpuHasUnifiedMemory == nil)
        #expect(first.gpuRecommendedWorkingSetBytes == nil)
        try await Task.sleep(for: .milliseconds(100))
        let next = await monitor.sample(demand: .init())
        for value in [next.cpuUsagePercent, next.gpuUsagePercent, next.memoryUsagePercent].compactMap({ $0 }) {
            #expect(value.isFinite && (0...100).contains(value))
        }
        #expect(next.cpuTopProcesses.isEmpty && next.memoryTopProcesses.isEmpty)
        await monitor.reset()
        let reset = await monitor.sample(demand: .init())
        #expect(reset.cpuUsagePercent == nil)
        #expect(reset.networkUploadBytesPerSecond == nil && reset.networkDownloadBytesPerSecond == nil)
    }
}
