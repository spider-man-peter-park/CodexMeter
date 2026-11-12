import AppKit
import CodexMeterCore
import OrbMotionKit
import ProjectionMotionKit
import Testing
@testable import CodexMeterApp

@MainActor struct ProductionProjectionTests {
    private func makeDefaults() throws -> UserDefaults {
        let name = "io.github.codexmeter.production-projection." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.set(name, forKey: "testSuiteName")
        defaults.set("en", forKey: "appLanguage")
        return defaults
    }

    @Test func bundledProfileKeepsTheAcceptedPlaygroundTuning() throws {
        let profile = try #require(FloatingHUDProjectionProfile.loadBundled())
        #expect(profile.backdrop.isEnabled)
        #expect(profile.backdrop.opacity == 0.54 && profile.backdrop.tintOpacity == 0.53)
        #expect(profile.backdrop.blurIntensity == 1)
        #expect(profile.projection.beamWidth == 103 && profile.projection.brightness == 0.87)
        #expect(profile.projection.particleCount == 11 && profile.projection.beamLayers == 3)
        #expect(profile.projection.openDuration == 1.03 && profile.projection.closeDuration == 0.8)
        #expect(!profile.hud.decorativeMotion && profile.hud.coreDiameter == 280)
        #expect(profile.hud.enabledModules == Set(HUDModule.allCases))
    }

    @Test func productionReadoutsUseUnavailableValuesAndRejectPrototypeActions() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaults.string(forKey: "testSuiteName")!) }
        let model = AppModel(defaults: defaults)
        let usage = AssistantUsageStore()
        let provider = FloatingHUDDataProvider(model: model, usage: usage)
        let data = provider.sample(modules: Set(HUDModule.allCases), now: Date())
        #expect(data.coreContent?.value == "—")
        #expect(data.moduleContent.count == HUDModule.allCases.count)
        #expect(data.moduleContent.values.allSatisfy { !$0.accessibilityText.localizedCaseInsensitiveContains("mock") })
        let dashboard = HUDDashboardController(provider: provider, initialSnapshot: data)
        let view = HUDDashboardView(dashboard: dashboard)
        view.interactionEnabled = false
        let geometry = ProjectionGeometry(visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            config: ProjectionConfig(), orb: OrbParameters())
        var timeline = ProjectionTimeline(); timeline.scrub(to: 1)
        view.render(geometry: geometry, timeline: timeline, reducedMotion: false)
        #expect(view.target(at: CGPoint(x: 720, y: 450)) == nil)
        #expect(!view.acceptsFirstResponder && !view.accessibilityPerformPress())
        #expect(view.hitTest(CGPoint(x: 720, y: 450)) == nil)
        #expect(dashboard.selected == nil && !dashboard.expanded)
    }

    @Test func productionHardwareUsesExistingSamplesAndExpiresStaleReadings() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaults.string(forKey: "testSuiteName")!) }
        let model = AppModel(defaults: defaults)
        let now = Date()
        model.applySystemMetrics(SystemMetricsSnapshot(sampledAt: now, cpuUsagePercent: 25,
            gpuUsagePercent: nil, memoryUsedBytes: 8_000, memoryTotalBytes: 16_000,
            networkUploadBytesPerSecond: 123, networkDownloadBytesPerSecond: 456), at: now)
        let provider = FloatingHUDDataProvider(model: model, usage: AssistantUsageStore())
        let fresh = provider.sample(modules: Set(HUDModule.allCases), now: now)
        #expect(fresh.cpuUsage == 0.25 && fresh.gpuUsage == nil)
        #expect(fresh.memoryUsedBytes == 8_000 && fresh.uploadBytesPerSecond == 123)
        let stale = provider.sample(modules: Set(HUDModule.allCases), now: now.addingTimeInterval(11))
        #expect(stale.cpuUsage == nil && stale.memoryUsedBytes == nil && stale.downloadBytesPerSecond == nil)
        #expect(stale.cpuHistory.isEmpty && stale.downloadHistory.isEmpty)
    }

    @Test func croppedDashboardAndRetentionFollowTheOrbDisplayIncludingNegativeOrigins() throws {
        let profile = try #require(FloatingHUDProjectionProfile.loadBundled())
        for screen in [CGRect(x: 0, y: 24, width: 1440, height: 840),
                       CGRect(x: -1600, y: -100, width: 1600, height: 1000),
                       CGRect(x: 0, y: 0, width: 640, height: 430)] {
            let orb = CGRect(x: screen.maxX - 92, y: screen.midY, width: 68, height: 68)
            let geometry = FloatingHUDProjectionGeometry(orb: orb, visibleFrame: screen, profile: profile)
            #expect(screen.contains(geometry.dashboardFrame))
            #expect(geometry.projection.orbFrame == orb)
            #expect(geometry.containsRetentionPoint(CGPoint(x: orb.midX, y: orb.midY)))
            #expect(geometry.containsRetentionPoint(CGPoint(x: screen.midX, y: screen.midY)))
            #expect(!geometry.containsRetentionPoint(CGPoint(x: screen.maxX + 200, y: screen.maxY + 200)))
        }
    }

    @Test func productionChartsDoNotConnectAcrossMissingOrDelayedHardwareReadings() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaults.string(forKey: "testSuiteName")!) }
        let model = AppModel(defaults: defaults)
        let now = Date()
        for (offset, cpu) in [(-20.0, 10.0 as Double?), (-18.0, nil), (0.0, 25.0)] {
            let time = now.addingTimeInterval(offset)
            model.applySystemMetrics(SystemMetricsSnapshot(sampledAt: time, cpuUsagePercent: cpu), at: time)
        }
        let provider = FloatingHUDDataProvider(model: model, usage: AssistantUsageStore())
        #expect(provider.sample(modules: [.performance], now: now).cpuHistory == [0.25])
        model.applySystemMetrics(SystemMetricsSnapshot(sampledAt: now.addingTimeInterval(12), cpuUsagePercent: 30),
            at: now.addingTimeInterval(12))
        #expect(provider.sample(modules: [.performance], now: now.addingTimeInterval(12)).cpuHistory == [0.3])
    }
}
