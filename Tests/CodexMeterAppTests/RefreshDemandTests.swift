import AppKit
import Combine
import Foundation
import Testing
@testable import CodexMeterApp
@testable import CodexMeterCore

@MainActor struct RefreshDemandTests {
    private func model() throws -> (AppModel, UserDefaults, String) {
        let suite = "io.github.codexmeter.refresh-demand." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("/private/tmp/codexmeter-refresh-demand-empty", forKey: "codexHome")
        return (AppModel(defaults: defaults), defaults, suite)
    }

    @Test func idleLogPollsPreserveFreshnessWithoutRefreshingTheMenu() throws {
        let (model, defaults, suite) = try model()
        defer { defaults.removePersistentDomain(forName: suite) }
        let time = Date()
        var usage = LocalDayUsage(dayStart: Calendar.current.startOfDay(for: time),
            timeZoneIdentifier: Calendar.current.timeZone.identifier, updatedAt: time)
        usage.output = 100
        usage.responses = 1
        usage.hasDesktopLogs = true
        var snapshot = LogSnapshot(latestSample: nil, cachedQuota: nil, latestResponseAt: nil,
            hasUnmeasurableResponse: false, todayUsage: usage)
        model.apply(snapshot)
        var menuChanges = 0
        var publications = 0
        model.changed = { menuChanges += 1 }
        let subscription = model.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }

        for _ in 0..<100 { model.apply(snapshot) }
        #expect(menuChanges == 0)
        #expect(publications == 0)
        usage.updatedAt = time.addingTimeInterval(2)
        snapshot.todayUsage = usage
        model.apply(snapshot)
        #expect(model.localDayUsage?.updatedAt == usage.updatedAt)
        #expect(publications == 1)
        #expect(menuChanges == 0)

        usage.output += 1
        snapshot.todayUsage = usage
        model.apply(snapshot)
        #expect(menuChanges == 1)
        snapshot.hasUnmeasurableResponse = true
        model.apply(snapshot)
        #expect(menuChanges == 2)
        snapshot.latestSample = TPSSample(id: "new-response", model: "synthetic", outputTokens: 20,
            reasoningTokens: 0, elapsedSeconds: 1, completedAt: time, isEstimated: true)
        model.apply(snapshot)
        #expect(menuChanges == 3)
    }

    @Test func configuredButHiddenHardwareDetailsDoNotRequestSampling() throws {
        let (model, defaults, suite) = try model()
        defer { defaults.removePersistentDomain(forName: suite) }
        model.options.showCPU = false
        model.options.showGPU = false
        model.options.showRAM = false
        model.options.showNetworkUpload = false
        model.options.showNetworkDownload = false
        #expect(model.detailLayout.visibleSections.contains(.cpu))
        #expect(!model.needsSystemMetrics)
        model.setDetailPresented(true, on: .popover)
        #expect(!model.needsSystemMetrics)
        for section in [DetailSection.cpu, .gpu, .ram, .network] {
            model.selectedDetailSection = section
            #expect(model.needsSystemMetrics)
        }
        model.setDetailPresented(false, on: .popover)
        #expect(!model.needsSystemMetrics)
        model.options.showCPU = true
        #expect(model.needsSystemMetrics)
    }

    @Test func hardwareSamplesPublishOneHistoryWindowAndOnlyExpireOnce() throws {
        let (model, defaults, suite) = try model()
        defer { defaults.removePersistentDomain(forName: suite) }
        let time = Date()
        var historyPublications = 0
        var clockPublications = 0
        var menuChanges = 0
        model.changed = { menuChanges += 1 }
        let history = model.$systemMetricsHistory.dropFirst().sink { _ in historyPublications += 1 }
        let clock = model.$systemMetricsNow.dropFirst().sink { _ in clockPublications += 1 }
        defer { history.cancel(); clock.cancel() }

        model.applySystemMetrics(SystemMetricsSnapshot(sampledAt: time, cpuUsagePercent: 20), at: time)
        #expect(historyPublications == 1)
        #expect(clockPublications == 1)
        model.expireSystemMetrics(at: time.addingTimeInterval(2))
        #expect(clockPublications == 1)
        #expect(menuChanges == 1)
        model.expireSystemMetrics(at: time.addingTimeInterval(60))
        #expect(clockPublications == 2)
        #expect(menuChanges == 2)
        #expect(model.currentSystemMetrics == nil)
        model.expireSystemMetrics(at: time.addingTimeInterval(62))
        #expect(clockPublications == 2)
        #expect(menuChanges == 2)

        model.applySystemMetrics(SystemMetricsSnapshot(sampledAt: time.addingTimeInterval(2), cpuUsagePercent: 30),
            at: time.addingTimeInterval(2))
        #expect(historyPublications == 2)
        #expect(model.systemMetricsHistory.count == 2)
        model.applySystemMetrics(SystemMetricsSnapshot(sampledAt: time.addingTimeInterval(-2), cpuUsagePercent: 10),
            at: time.addingTimeInterval(-2))
        #expect(historyPublications == 3)
        #expect(model.systemMetricsHistory.map(\.cpuUsagePercent) == [10])
    }

    @Test func unchangedStatusMetadataSkipsNativeSetters() {
        _ = NSApplication.shared
        let button = MetadataButton(frame: .zero)
        StatusItemMetadata.apply(label: "CPU, 20%", value: "CPU 20%", tooltip: "Updated now", to: button)
        button.resetCounts()
        for _ in 0..<100 {
            StatusItemMetadata.apply(label: "CPU, 20%", value: "CPU 20%", tooltip: "Updated now", to: button)
        }
        #expect(button.labelWrites == 0)
        #expect(button.valueWrites == 0)
        #expect(button.tooltipWrites == 0)
        StatusItemMetadata.apply(label: "CPU, 21%", value: "CPU 21%", tooltip: "Updated later", to: button)
        #expect(button.labelWrites == 1)
        #expect(button.valueWrites == 1)
        #expect(button.tooltipWrites == 1)
        #expect(button.accessibilityLabel() == "CPU, 21%")
        #expect(button.accessibilityValue() as? String == "CPU 21%")
        #expect(button.toolTip == "Updated later")
    }
}

@MainActor private final class MetadataButton: NSButton {
    var labelWrites = 0
    var valueWrites = 0
    var tooltipWrites = 0

    override func setAccessibilityLabel(_ accessibilityLabel: String?) {
        labelWrites += 1
        super.setAccessibilityLabel(accessibilityLabel)
    }

    override func setAccessibilityValue(_ accessibilityValue: Any?) {
        valueWrites += 1
        super.setAccessibilityValue(accessibilityValue)
    }

    override var toolTip: String? {
        didSet { tooltipWrites += 1 }
    }

    func resetCounts() { labelWrites = 0; valueWrites = 0; tooltipWrites = 0 }
}
