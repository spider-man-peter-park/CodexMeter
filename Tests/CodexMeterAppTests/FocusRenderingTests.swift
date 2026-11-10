import AppKit
import CodexMeterCore
import CoreText
import Testing
@testable import CodexMeterApp

@Suite(.serialized) @MainActor struct FocusRenderingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func quota(_ remaining: Double, metric: MenuBarMetric = .weekly,
                       source: QuotaSource = .appServer) -> QuotaSnapshot {
        let window = QuotaWindow(usedPercent: 100 - remaining,
            windowDurationMins: metric == .fiveHour ? 300 : 10_080, resetsAt: now.addingTimeInterval(600))
        return QuotaSnapshot(fiveHour: metric == .fiveHour ? window : nil,
            weekly: metric == .weekly ? window : nil, updatedAt: now, source: source)
    }

    private func descriptors() -> [MenuBarItem] {
        let values: [QuotaSnapshot?] = [nil, quota(0), quota(0.1), quota(10), quota(11), quota(100),
            quota(100, metric: .fiveHour), quota(20, source: .logCache)]
        return values.map {
            MenuBarFormatter.focusItem(quota: $0, warning: nil, autoRefresh: true, now: now)
        } + [MenuBarFormatter.focusItem(quota: quota(70), warning: nil, autoRefresh: false, now: now)]
    }

    @Test func allFocusStatesAndPeriodsKeepOneNativeItemSize() throws {
        for dark in [false, true] {
            let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
            for font in MenuBarFontDesign.allCases {
                for size in [9.0, 12, 16] {
                    for style in MenuBarItemStyle.allCases {
                        let options = DisplayOptions(fontSize: size, fontDesign: font, itemStyle: style)
                        var expected: NSSize?
                        let cache = StatusItemRenderCache()
                        for descriptor in descriptors() {
                            for selected in [false, true] {
                                let image = StatusItemAppearance.makeImage(descriptor, options: options,
                                    remaining: 5, appearance: appearance, isActive: selected)
                                if let expected { #expect(image.size == expected) } else { expected = image.size }
                                #expect(image.accessibilityDescription == descriptor.accessibilityLabel)
                                if selected { #expect(image.isTemplate) }
                                else if style == .capsule { #expect(!image.isTemplate) }
                                let cached = cache.render(descriptor, options: options, remaining: 5,
                                    appearance: appearance, isActive: selected)
                                #expect(cached.image.size == image.size)
                            }
                        }
                        #expect(cache.imageCount == 1)
                        #expect(cache.capacityCount == 1)
                    }
                }
            }
        }
    }

    @Test func focusCapacityRetainsFullTextAtFontBounds() throws {
        for size in [9.0, 16] {
            let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
            let options = DisplayOptions(fontSize: size, fontWeight: .medium)
            for descriptor in descriptors() {
                let capacity = StatusItemAppearance.capacityDescriptor(for: descriptor, options: options)
                let reserved = NSAttributedString(string: capacity.title, attributes: [.font: font]).size().width
                let original = CTLineCreateWithAttributedString(NSAttributedString(string: descriptor.title,
                    attributes: [.font: font]))
                let fitted = StatusItemAppearance.textLine(descriptor.title, font: font,
                    foreground: .black, availableWidth: ceil(reserved))
                #expect(CTLineGetGlyphCount(fitted) == CTLineGetGlyphCount(original))
                if let symbol = descriptor.symbolName {
                    #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil)
                }
            }
        }
    }
}
