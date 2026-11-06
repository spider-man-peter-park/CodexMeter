import Foundation
import Testing
@testable import CodexMeterApp
import CodexMeterCore

@MainActor struct DetailDemandTests {
    private func makeDefaults() throws -> UserDefaults {
        let name = "io.github.codexmeter.detail-demand." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.set(name, forKey: "testSuiteName")
        defaults.set("/private/tmp/codexmeter-detail-demand-empty", forKey: "codexHome")
        return defaults
    }

    @Test func expensiveDetailsFollowVisibleModuleRatherThanConfiguredLayout() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaults.string(forKey: "testSuiteName")!) }
        let model = AppModel(defaults: defaults)
        model.selectedDetailSection = .cpu
        #expect(model.systemDetailDemand == SystemMetricsDetailDemand())
        model.setDetailPresented(true, on: .popover)
        #expect(model.systemDetailDemand == SystemMetricsDetailDemand(processes: true))
        model.selectedDetailSection = .ram
        #expect(model.systemDetailDemand == SystemMetricsDetailDemand(processes: true))
        model.selectedDetailSection = .network
        #expect(model.systemDetailDemand == SystemMetricsDetailDemand(networkProcesses: true))
        model.selectedDetailSection = .gpu
        #expect(model.systemDetailDemand == SystemMetricsDetailDemand(gpuHardware: true))
        model.selectedDetailSection = .quota
        #expect(model.systemDetailDemand == SystemMetricsDetailDemand())
    }

    @Test func closingOneSurfaceDoesNotStopAnotherVisibleDetail() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaults.string(forKey: "testSuiteName")!) }
        let model = AppModel(defaults: defaults)
        model.selectedDetailSection = .network
        model.setDetailPresented(true, on: .popover)
        model.setDetailPresented(true, on: .preview)
        model.setDetailPresented(false, on: .popover)
        #expect(model.systemDetailDemand.networkProcesses)
        model.setDetailPresented(false, on: .preview)
        #expect(model.systemDetailDemand == SystemMetricsDetailDemand())
        model.setDetailPresented(false, on: .preview)
        #expect(model.systemDetailDemand == SystemMetricsDetailDemand())
    }

    @Test func historyKeepsChartReadingsWithoutRetainingRichDetails() {
        let process = SystemProcessUsage(pid: 1, name: "Synthetic process", memoryBytes: 1_000_000,
            cpuUsagePercent: 10)
        let sample = SystemMetricsSnapshot(sampledAt: Date(), cpuUsagePercent: 35, gpuUsagePercent: 12,
            memoryUsedBytes: 10_000_000, memoryTotalBytes: 20_000_000, cpuTopProcesses: [process],
            memoryTopProcesses: [process], gpuDeviceNames: ["Synthetic GPU"], gpuHasUnifiedMemory: true,
            gpuRecommendedWorkingSetBytes: 1_000_000)
        let history = AppModel.historySnapshot(sample)
        #expect(history.sampledAt == sample.sampledAt)
        #expect(history.cpuUsagePercent == sample.cpuUsagePercent)
        #expect(history.gpuUsagePercent == sample.gpuUsagePercent)
        #expect(history.memoryUsagePercent == sample.memoryUsagePercent)
        #expect(history.cpuTopProcesses.isEmpty && history.memoryTopProcesses.isEmpty)
        #expect(history.networkTopProcesses.isEmpty && history.gpuDeviceNames.isEmpty)
        #expect(history.gpuHasUnifiedMemory == nil && history.gpuRecommendedWorkingSetBytes == nil)
    }
}
