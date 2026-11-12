import Foundation
import Testing
@testable import ProjectionMotionKit

@MainActor
private final class CountingHUDProvider: HUDDataProviding {
    var samples = 0
    var resets = 0
    var modules: Set<HUDModule> = []
    func sample(modules: Set<HUDModule>, now: Date) -> HUDDataSnapshot {
        samples += 1; self.modules = modules
        var value = HUDDataSnapshot.preview
        value.date = now
        return value
    }
    func reset() { resets += 1 }
}

struct HUDModelTests {
    @Test func cpuRatesUseDeltasAndRejectResetOrUnchangedCounters() {
        let old = HUDCPUCounters(user: 100, system: 20, idle: 300, nice: 5)
        let current = HUDCPUCounters(user: 120, system: 30, idle: 360, nice: 15)
        #expect(current.fraction(since: old) == 0.4)
        #expect(old.fraction(since: current) == nil)
        #expect(old.fraction(since: old) == nil)
    }

    @Test func networkRatesExcludeNewInterfacesAndDoNotInventRatesAfterResetOrSleep() {
        var meter = HUDNetworkRateAccumulator()
        let first = ["en0#4": HUDNetworkCounters(received: 1_000, sent: 500)]
        #expect(meter.sample(first, at: 10).upload == nil)
        let second = ["en0#4": HUDNetworkCounters(received: 1_800, sent: 900),
                      "en1#5": HUDNetworkCounters(received: 1_000_000, sent: 1_000_000)]
        let rates = meter.sample(second, at: 12)
        #expect(rates.upload == 200 && rates.download == 400)
        let reset = ["en0#4": HUDNetworkCounters(received: 2, sent: 1)]
        #expect(meter.sample(reset, at: 14).download == nil)
        #expect(meter.sample(first, at: 40).upload == nil)
        #expect(meter.sample(nil, at: 42).upload == nil)
        #expect(meter.sample(first, at: 44).upload == nil)
        #expect(meter.sample(first, at: 44).upload == nil)
    }

    @MainActor @Test func hiddenHUDDoesNotSampleAndRestartsWithFreshCounterBaselines() {
        let provider = CountingHUDProvider()
        let controller = HUDDashboardController(provider: provider)
        controller.refresh()
        #expect(provider.samples == 0)
        controller.config.enabledModules = [.system, .ai]
        controller.setVisible(true)
        #expect(provider.samples == 1 && provider.modules == [.system, .ai])
        controller.setVisible(true)
        #expect(provider.samples == 1)
        controller.setVisible(false)
        controller.refresh()
        #expect(provider.samples == 1)
        controller.setVisible(true)
        #expect(provider.samples == 2 && provider.resets == 3)
        controller.setVisible(false)
    }

    @MainActor @Test func disabledModulesCannotRetainHoverSelectionOrDetailState() {
        let controller = HUDDashboardController(provider: CountingHUDProvider())
        controller.hover(.performance)
        controller.select(.performance)
        controller.expandSelection()
        #expect(controller.selected == .performance && controller.expanded)
        controller.config.enabledModules.remove(.performance)
        #expect(controller.selected == nil && !controller.expanded && controller.hovered == nil)
        controller.select(.performance); controller.hover(.performance)
        #expect(controller.selected == nil && controller.hovered == nil)
        controller.select(.network)
        #expect(controller.selected == .network && !controller.expanded)
        controller.select(.network)
        #expect(controller.expanded)
        controller.overview()
        #expect(controller.selected == nil && !controller.expanded)
    }

    @MainActor @Test func cancellingSamplingReleasesTheController() async throws {
        var controller: HUDDashboardController? = HUDDashboardController(provider: CountingHUDProvider())
        weak var reference = controller
        controller?.setVisible(true)
        controller = nil
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(reference == nil)
    }

    @MainActor @Test func unavailableModulesStayVisibleButCannotInteractOrRequestTelemetry() {
        let provider = CountingHUDProvider()
        let controller = HUDDashboardController(provider: provider)
        controller.hover(.performance); controller.select(.performance); controller.expandSelection()
        controller.config.disabledModules.insert(.performance)
        #expect(controller.config.enabledModules.contains(.performance))
        #expect(controller.selected == nil && controller.hovered == nil && !controller.expanded)
        controller.hover(.performance); controller.select(.performance)
        #expect(controller.selected == nil && controller.hovered == nil)
        controller.setVisible(true)
        #expect(!provider.modules.contains(.performance) && provider.modules.contains(.network))
        controller.config.disabledModules.remove(.performance)
        controller.refresh()
        #expect(provider.modules.contains(.performance))
        controller.select(.performance)
        #expect(controller.selected == .performance)
        controller.setVisible(false)
    }

    @Test func fixtureDataIsExplicitAndGPUIsUnavailableRatherThanFabricated() {
        let fixture = HUDDataSnapshot.preview
        #expect(fixture.isFixture && fixture.mockAI.isMock)
        #expect(fixture.activities.count == 3 && fixture.activities.allSatisfy(\.isMock))
        #expect(fixture.gpuUsage == nil)
        #expect(HUDDataSnapshot().cpuUsage == nil && !HUDDataSnapshot().isFixture)
    }

    @Test func invalidDebugValuesCannotEscapeLayoutAndFeedbackBounds() throws {
        var config = HUDConfiguration()
        config.coreDiameter = .infinity; config.textScale = -2
        config.exitDelay = .nan; config.clockwiseSpeed = 100
        config.transitGrace = -10; config.layoutVariant = 40
        let safe = config.sanitized
        #expect(safe.coreDiameter == 280 && safe.textScale == 0.9)
        #expect(safe.exitDelay == 0.55 && safe.clockwiseSpeed == 8)
        #expect(safe.transitGrace == 0.4 && safe.layoutVariant == 2)
        let data = try JSONEncoder().encode(safe)
        #expect(try JSONDecoder().decode(HUDConfiguration.self, from: data) == safe)
    }
}
