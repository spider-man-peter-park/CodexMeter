import Combine
import Foundation
import Testing
@testable import CodexMeterApp
@testable import CodexMeterCore

@MainActor struct FocusModeIntegrationTests {
    @Test func successfulQuotaReadUsesReceiptTimeForFocusFreshness() async throws {
        let suite = "io.github.codexmeter.focus-receipt." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("/private/tmp/" + suite, forKey: "codexHome")
        let model = AppModel(defaults: defaults, notificationCenter: TestReminderCenter(), readQuota: { _ in
            try await Task.sleep(for: .milliseconds(10))
            return QuotaSnapshot(fiveHour: nil,
                weekly: QuotaWindow(usedPercent: 30, windowDurationMins: 10_080, resetsAt: nil),
                updatedAt: Date(), source: .appServer)
        }, readAccount: { _ in AccountInfoSnapshot() })
        defer { model.stop() }
        model.refresh()
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while model.refreshing {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(5))
        }
        let summary = FocusSummary(quota: model.quota, warning: model.quotaWarning,
            automaticRefresh: model.autoRefresh, now: model.now, refreshInterval: model.refreshOptions.quotaInterval)
        #expect(summary.state == .ready)
    }

    private func preferences() throws -> (String, UserDefaults) {
        let suite = "io.github.codexmeter.focus-mode-tests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("/private/tmp/" + suite, forKey: "codexHome")
        return (suite, defaults)
    }

    @Test func freshFocusModeLeavesConfiguredHardwareDormantWhenNoDetailIsVisible() throws {
        let (suite, defaults) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        #expect(model.menuBarMode == .focus)
        #expect(model.options.showCPU && model.options.showGPU && model.options.showRAM)
        #expect(model.options.showNetworkUpload && model.options.showNetworkDownload)
        #expect(!model.needsSystemMetrics)
        #expect(model.systemDetailDemand == SystemMetricsDetailDemand())
        #expect(defaults.data(forKey: "displayOptions") == nil)
    }

    @Test func modeSwitchingRestoresIndividualDemandAndPersistsWithoutReplacingDisplayChoices() throws {
        let (suite, defaults) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        model.options.showGPU = false
        model.options.ramDisplay.showIcon = false
        model.options.customQuotaLabel = "Personal"
        let original = model.options
        let originalData = defaults.data(forKey: "displayOptions")

        model.menuBarMode = .individual
        #expect(model.needsSystemMetrics)
        #expect(defaults.string(forKey: "menuBarMode") == "individual")
        let individual = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        #expect(individual.menuBarMode == .individual)
        #expect(individual.needsSystemMetrics)
        #expect(individual.options == original)

        model.menuBarMode = .focus
        #expect(!model.needsSystemMetrics)
        let restored = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        #expect(restored.menuBarMode == .focus)
        #expect(restored.options == original)
        #expect(defaults.data(forKey: "displayOptions") == originalData)
    }

    @Test func workspaceHardwareDemandFollowsTheVisiblePageAndEndsOnClose() throws {
        let (suite, defaults) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        model.selectedDetailSection = .cpu
        #expect(!model.needsSystemMetrics)
        model.setDetailPresented(true, on: .workspace)
        #expect(model.needsSystemMetrics)
        #expect(model.systemDetailDemand == SystemMetricsDetailDemand(processes: true))

        model.selectedDetailSection = .network
        #expect(model.needsSystemMetrics)
        #expect(model.systemDetailDemand == SystemMetricsDetailDemand(networkProcesses: true))
        // The workspace overview uses the quota destination and needs no hardware sampling.
        model.selectedDetailSection = .quota
        #expect(!model.needsSystemMetrics)
        #expect(model.systemDetailDemand == SystemMetricsDetailDemand())

        model.selectedDetailSection = .ram
        #expect(model.systemDetailDemand == SystemMetricsDetailDemand(processes: true))
        model.setDetailPresented(false, on: .workspace)
        #expect(!model.needsSystemMetrics)
        #expect(model.systemDetailDemand == SystemMetricsDetailDemand())
    }

    @Test func closingTheWorkspaceKeepsAnotherVisibleHardwareSurfaceAlive() throws {
        let (suite, defaults) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        model.selectedDetailSection = .network
        model.setDetailPresented(true, on: .workspace)
        model.setDetailPresented(true, on: .preview)
        model.setDetailPresented(false, on: .workspace)
        #expect(model.needsSystemMetrics)
        #expect(model.systemDetailDemand.networkProcesses)
        model.setDetailPresented(false, on: .preview)
        #expect(!model.needsSystemMetrics)
        #expect(model.systemDetailDemand == SystemMetricsDetailDemand())
    }

    @Test func settingsObserveModeChangesAndBindingsButIgnoreLiveMetrics() throws {
        let (suite, defaults) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        let settings = AppSettingsObservation(model: model)
        var changes = 0
        let subscription = settings.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }
        model.menuBarMode = .individual
        #expect(changes == 1)
        model.menuBarMode = .individual
        #expect(changes == 1)
        settings.binding(\.menuBarMode).wrappedValue = .focus
        #expect(changes == 2)
        #expect(defaults.string(forKey: "menuBarMode") == "focus")

        for index in 0..<100 {
            let time = Date(timeIntervalSince1970: Double(index))
            model.now = time
            model.sample = TPSSample(id: "focus-mode-\(index)", model: "Synthetic", outputTokens: index + 1,
                reasoningTokens: 0, elapsedSeconds: 1, completedAt: time)
            model.refreshing = index.isMultiple(of: 2)
            model.accountRefreshing = index.isMultiple(of: 3)
            model.quotaWarning = "Synthetic warning \(index)"
            model.applySystemMetrics(SystemMetricsSnapshot(sampledAt: time, cpuUsagePercent: Double(index % 100)), at: time)
        }
        #expect(changes == 2)
    }

    @Test func unknownSavedModeFallsBackToFocusWithoutOverwritingExistingDisplayOptions() throws {
        let (suite, defaults) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let saved = DisplayOptions(showFiveHour: false, showTPS: false, showGPU: false,
            quotaLabelStyle: .custom, fontSize: 15, customQuotaLabel: "Existing")
        let bytes = try JSONEncoder().encode(saved)
        defaults.set(bytes, forKey: "displayOptions")
        defaults.set("future-mode", forKey: "menuBarMode")
        let model = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        #expect(model.menuBarMode == .focus)
        #expect(model.options == saved)
        #expect(!model.needsSystemMetrics)
        #expect(defaults.data(forKey: "displayOptions") == bytes)
    }
}
