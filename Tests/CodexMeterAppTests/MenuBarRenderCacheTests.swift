import AppKit
import CodexMeterCore
import Testing
@testable import CodexMeterApp

@Suite(.serialized) @MainActor struct MenuBarRenderCacheTests {
    private func appearance(_ dark: Bool = false) throws -> NSAppearance {
        try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
    }

    @Test func unchangedPixelsReuseImageWhileAccessibilityStaysCurrent() throws {
        let cache = StatusItemRenderCache()
        let options = DisplayOptions()
        let nativeAppearance = try appearance()
        let initial = MenuBarItem(metric: .ram, title: "RAM 50%", accessibilityLabel: "Memory 50%",
            symbolName: "memorychip", systemValue: "50%", systemLabel: "RAM")
        let first = cache.render(initial, options: options, remaining: nil, appearance: nativeAppearance)
        let refreshed = MenuBarItem(metric: .ram, title: "RAM 50%", accessibilityLabel: "Memory 50%, fresh reading",
            symbolName: "memorychip", systemValue: "50%", systemLabel: "RAM")
        let second = cache.render(refreshed, options: options, remaining: nil, appearance: nativeAppearance)
        #expect(first.changed)
        #expect(!second.changed)
        #expect(first.image === second.image)
        #expect(second.image.accessibilityDescription == refreshed.accessibilityLabel)

        let updated = MenuBarItem(metric: .ram, title: "RAM 51%", accessibilityLabel: "Memory 51%",
            symbolName: "memorychip", systemValue: "51%", systemLabel: "RAM")
        let third = cache.render(updated, options: options, remaining: nil, appearance: nativeAppearance)
        #expect(third.changed)
        #expect(third.image !== second.image)
        #expect(third.image.size == first.image.size)
    }

    @Test func appearanceSelectionThresholdAndPreferencesInvalidateCurrentImage() throws {
        let cache = StatusItemRenderCache()
        let descriptor = MenuBarItem(metric: .weekly, title: "70% · 2d4h", accessibilityLabel: "Weekly quota",
            symbolName: "calendar", quotaPrimary: "70%", quotaCountdown: "2d4h")
        let options = DisplayOptions(countdownSeparator: .dot)
        let light = cache.render(descriptor, options: options, remaining: 70, appearance: try appearance())
        let dark = cache.render(descriptor, options: options, remaining: 70, appearance: try appearance(true))
        let selected = cache.render(descriptor, options: options, remaining: 70,
            appearance: try appearance(true), isActive: true)
        let lowQuota = cache.render(descriptor, options: options, remaining: 10,
            appearance: try appearance(true), isActive: true)
        #expect(dark.changed && dark.image !== light.image)
        #expect(selected.changed && selected.image !== dark.image)
        #expect(lowQuota.changed && lowQuota.image !== selected.image)
        #expect(light.image.size == dark.image.size)
        #expect(dark.image.size == selected.image.size)

        var larger = options
        larger.fontSize = 16
        larger.fontDesign = .rounded
        larger.spacing = .comfortable
        let resized = cache.render(descriptor, options: larger, remaining: 10,
            appearance: try appearance(true), isActive: true)
        #expect(resized.changed && resized.image !== lowQuota.image)
        let expected = StatusItemAppearance.makeImage(descriptor, options: larger, remaining: 10,
            appearance: try appearance(true), isActive: true)
        #expect(resized.image.size == expected.size)
        #expect(resized.image.size != lowQuota.image.size)
    }

    @Test func valueAndFormatChangesKeepMatchingUncachedGeometry() throws {
        let cache = StatusItemRenderCache()
        let options = DisplayOptions()
        let nativeAppearance = try appearance()
        let descriptors = [
            MenuBarItem(metric: .network, title: "—", accessibilityLabel: "Upload",
                networkUploadValue: "1.0 KB/s"),
            MenuBarItem(metric: .network, title: "—", accessibilityLabel: "Upload",
                networkUploadValue: "2.0 MB/s"),
            MenuBarItem(metric: .network, title: "—", accessibilityLabel: "Upload and download",
                networkUploadValue: "2.0 MB/s", networkDownloadValue: "1.0 KB/s"),
            MenuBarItem(metric: .ram, title: "RAM 50%", accessibilityLabel: "RAM",
                systemValue: "50%", systemLabel: "RAM"),
            MenuBarItem(metric: .ram, title: "Memory 50%", accessibilityLabel: "RAM",
                symbolName: "memorychip", systemValue: "50%", systemLabel: "Memory")
        ]
        var previous: NSImage?
        for descriptor in descriptors {
            let result = cache.render(descriptor, options: options, remaining: nil, appearance: nativeAppearance)
            let expected = StatusItemAppearance.makeImage(descriptor, options: options,
                remaining: nil, appearance: nativeAppearance)
            #expect(result.changed)
            #expect(result.image !== previous)
            #expect(result.image.size == expected.size)
            previous = result.image
        }
    }

    @Test func cacheRetainsOnlyCurrentMetricsAcrossManyReadings() throws {
        let cache = StatusItemRenderCache()
        let options = DisplayOptions()
        let nativeAppearance = try appearance()
        let metrics = MenuBarMetric.allCases.filter { $0 != .fallback }
        cache.retainMetrics(Set(metrics))
        for reading in 0..<100 {
            for metric in metrics {
                let descriptor = MenuBarItem(metric: metric, title: "\(reading)", accessibilityLabel: metric.rawValue)
                _ = cache.render(descriptor, options: options, remaining: nil, appearance: nativeAppearance)
            }
            #expect(cache.imageCount == metrics.count)
            #expect(cache.capacityCount == metrics.count)
        }
        cache.retainMetrics([.ram])
        #expect(cache.imageCount == 1)
        #expect(cache.capacityCount == 1)
        cache.retainMetrics([.fallback])
        #expect(cache.imageCount == 0)
        #expect(cache.capacityCount == 0)
        let fallback = MenuBarItem(metric: .fallback, title: "AI", accessibilityLabel: "CodexMeter")
        #expect(cache.render(fallback, options: options, remaining: nil, appearance: nativeAppearance).changed)
        #expect(cache.imageCount == 1)
        #expect(cache.capacityCount == 1)
    }
}
