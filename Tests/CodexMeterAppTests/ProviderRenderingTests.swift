import AppKit
import CodexMeterCore
import Testing
@testable import CodexMeterApp

@Suite(.serialized) @MainActor struct ProviderRenderingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func result(_ provider: AssistantProvider, status: ProviderConnectionStatus = .ready,
                        used: Double? = nil, cost: Double? = nil, tokens: Int? = nil) -> ProviderUsageResult {
        var snapshot = ProviderUsageSnapshot(provider: provider,
            scope: provider == .deepseekHarness ? .localSessions : .accountPeriod, sampledAt: now)
        snapshot.usedPercent = used
        snapshot.costUSD = cost
        snapshot.totalTokens = tokens
        return ProviderUsageResult(provider: provider, status: status, snapshot: snapshot, message: "Synthetic provider state")
    }

    private func codex(cached: Bool = false) -> MenuBarItem {
        let quota = QuotaSnapshot(fiveHour: nil,
            weekly: QuotaWindow(usedPercent: 39, windowDurationMins: 10_080, resetsAt: now.addingTimeInterval(600)),
            updatedAt: now, source: cached ? .logCache : .appServer)
        return MenuBarFormatter.focusItem(quota: quota, warning: nil, autoRefresh: true, now: now)
    }

    @Test func sharedPauseAndClockGlyphsStillInvalidateProviderCapacity() throws {
        let paused = [
            MenuBarFormatter.providerItem(result(.cursor, used: 30), autoRefresh: false),
            MenuBarFormatter.providerItem(result(.deepseekHarness, tokens: Int.max), autoRefresh: false),
            MenuBarFormatter.providerItem(result(.codex), autoRefresh: false)
        ]
        let loading = [
            MenuBarFormatter.providerItem(result(.cursor, status: .loading, used: 30), autoRefresh: true),
            MenuBarFormatter.providerItem(result(.deepseekHarness, status: .loading, tokens: Int.max), autoRefresh: true),
            codex(cached: true)
        ]
        #expect(Set(paused.compactMap(\.symbolName)) == ["pause.fill"])
        #expect(Set(loading.compactMap(\.symbolName)) == ["clock"])
        for descriptors in [paused, loading] {
            for dark in [false, true] {
                let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
                for fontSize in [9.0, 12, 16] {
                    let options = DisplayOptions(fontSize: fontSize)
                    let cache = StatusItemRenderCache()
                    // Revisit each format to catch capacity retained from either direction of the switch.
                    for descriptor in descriptors + Array(descriptors.reversed()) {
                        let cached = cache.render(descriptor, options: options, remaining: nil, appearance: appearance)
                        let independent = StatusItemAppearance.makeImage(descriptor, options: options,
                            remaining: nil, appearance: appearance)
                        #expect(cached.image.size == independent.size, "Provider image: \(descriptor.title)")
                        #expect(cached.image.accessibilityDescription == descriptor.accessibilityLabel)
                        #expect(cache.capacityCount == 1 && cache.imageCount == 1)
                    }
                }
            }
        }
    }

    @Test func eachProviderKeepsItsOwnWidthThroughAvailableUnknownAndLargeReadings() throws {
        let cursor = [
            result(.cursor, used: 0), result(.cursor, used: 100), result(.cursor, used: 99.9),
            result(.cursor, cost: 9999.9), result(.cursor, status: .unavailable)
        ]
        let deepseek = [
            result(.deepseekHarness, tokens: 0), result(.deepseekHarness, tokens: 999),
            result(.deepseekHarness, tokens: 999_949_999), result(.deepseekHarness, tokens: Int.max),
            result(.deepseekHarness, status: .unavailable)
        ]
        for values in [cursor, deepseek] {
            for autoRefresh in [false, true] {
                for font in MenuBarFontDesign.allCases {
                    let options = DisplayOptions(fontSize: 16, fontDesign: font)
                    let appearance = try #require(NSAppearance(named: .aqua))
                    let cache = StatusItemRenderCache()
                    var expected: NSSize?
                    for value in values {
                        let descriptor = MenuBarFormatter.providerItem(value, autoRefresh: autoRefresh)
                        let image = cache.render(descriptor, options: options, remaining: nil, appearance: appearance).image
                        if let expected { #expect(image.size == expected) } else { expected = image.size }
                        #expect(descriptor.title.hasPrefix(value.provider == .cursor ? "Cu " : "DS "))
                    }
                }
            }
        }
    }

    @Test func activeProviderImagesLeaveTheSelectionBackgroundToMacOS() throws {
        let descriptors = [
            MenuBarFormatter.providerItem(result(.cursor, used: 30), autoRefresh: false),
            MenuBarFormatter.providerItem(result(.deepseekHarness, tokens: 100_000), autoRefresh: false),
            codex(cached: true)
        ]
        for dark in [false, true] {
            let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
            var options = DisplayOptions()
            options.itemStyle = .capsule
            let cache = StatusItemRenderCache()
            for descriptor in descriptors {
                let inactive = cache.render(descriptor, options: options, remaining: 5, appearance: appearance).image
                let active = cache.render(descriptor, options: options, remaining: 5,
                    appearance: appearance, isActive: true).image
                #expect(!inactive.isTemplate)
                #expect(active.isTemplate)
                #expect(active.size == inactive.size)
                #expect(try marginAlpha(inactive) > 0.95)
                #expect(try marginAlpha(active) < 0.01)
            }
        }
    }

    private func marginAlpha(_ image: NSImage) throws -> CGFloat {
        let data = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: data))
        let x = max(0, Int(CGFloat(bitmap.pixelsWide) / image.size.width))
        return try #require(bitmap.colorAt(x: x, y: bitmap.pixelsHigh / 2)).alphaComponent
    }
}
