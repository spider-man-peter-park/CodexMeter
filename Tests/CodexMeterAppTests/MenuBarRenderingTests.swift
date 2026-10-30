import AppKit
import Foundation
import Testing
@testable import CodexMeterApp
@testable import CodexMeterCore

@Suite(.serialized) @MainActor struct MenuBarRenderingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func appearance(_ dark: Bool) throws -> NSAppearance {
        try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
    }

    private func assertRenderable(_ image: NSImage, descriptor: MenuBarItem,
                                  template: Bool) throws {
        #expect(image.size.width.isFinite && image.size.height.isFinite)
        #expect((20...400).contains(image.size.width))
        #expect((20...40).contains(image.size.height))
        #expect(image.isTemplate == template)
        #expect(image.accessibilityDescription == descriptor.accessibilityLabel)
        let bytes = try #require(image.tiffRepresentation)
        #expect(!bytes.isEmpty)
        let bitmap = try #require(NSBitmapImageRep(data: bytes))
        #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
        var hasVisiblePixels = false
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                    hasVisiblePixels = true
                    break
                }
            }
            if hasVisiblePixels { break }
        }
        #expect(hasVisiblePixels)
    }

    private func isFilled(_ style: MenuBarItemStyle, active: Bool) -> Bool {
        style == .capsule && !active
    }

    private func marginAlpha(_ image: NSImage) throws -> CGFloat {
        let bytes = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: bytes))
        let x = Int(2 * CGFloat(bitmap.pixelsWide) / image.size.width)
        return try #require(bitmap.colorAt(x: x, y: bitmap.pixelsHigh / 2)).alphaComponent
    }

    @Test func selectedQuotaAndTPSImagesHaveTransparentMarginsAndNativeTemplateContrast() throws {
        for dark in [false, true] {
            for metric in [MenuBarMetric.weekly, .tps, .todayTokens] {
                let descriptor = MenuBarItem(metric: metric, title: metric == .weekly ? "70% · 5d0h" : "59 TPS",
                    accessibilityLabel: "Menu item", symbolName: metric == .todayTokens ? DetailSection.today.symbol : (metric == .tps ? "bolt.fill" : nil),
                    usesGPTLogo: metric == .weekly,
                    tpsValue: metric == .tps ? "59" : nil)
                for style in MenuBarItemStyle.allCases {
                    for color in MenuBarColorStyle.allCases {
                        for remaining in [5.0, 70.0] {
                            for layout in MenuBarTPSLayout.allCases {
                                let options = DisplayOptions(tpsLayout: layout, colorStyle: color, itemStyle: style)
                                let image = StatusItemAppearance.makeImage(descriptor, options: options,
                                    remaining: remaining, appearance: try appearance(dark), isActive: true)
                                try assertRenderable(image, descriptor: descriptor, template: true)
                                #expect(try marginAlpha(image) < 0.01)
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func permanentCapsulesReturnAfterSelectionWithoutMovingTheStatusItem() throws {
        for dark in [false, true] {
            for metric in [MenuBarMetric.weekly, .tps, .todayTokens] {
                let descriptor = MenuBarItem(metric: metric, title: "70% · 5d0h", accessibilityLabel: "Menu item",
                    symbolName: metric == .tps ? "bolt.fill" : nil,
                    tpsValue: metric == .tps ? "59" : nil)
                for style in MenuBarItemStyle.allCases {
                    let options = DisplayOptions(tpsLayout: .stacked, itemStyle: style)
                    let idle = StatusItemAppearance.makeImage(descriptor, options: options, remaining: 70,
                        appearance: try appearance(dark), isActive: false)
                    let selected = StatusItemAppearance.makeImage(descriptor, options: options, remaining: 70,
                        appearance: try appearance(dark), isActive: true)
                    #expect(idle.size == selected.size)
                    #expect(try marginAlpha(selected) < 0.01)
                    if style == .capsule { #expect(try marginAlpha(idle) > 0.95) }
                    else { #expect(try marginAlpha(idle) < 0.01) }
                }
            }
        }
    }

    @Test func quotaLabelsRenderAtBothFontBoundsInBothAppearances() throws {
        let snapshot = QuotaSnapshot(fiveHour: nil,
            weekly: QuotaWindow(usedPercent: 34, windowDurationMins: 10080,
                               resetsAt: now.addingTimeInterval(4 * 86400 + 8 * 3600)),
            updatedAt: now, source: .appServer)
        for dark in [false, true] {
            let nativeAppearance = try appearance(dark)
            for style in MenuBarItemStyle.allCases {
                for active in [false, true] {
                    for size in [9.0, 16.0] {
                        for label in QuotaLabelStyle.allCases {
                            let options = DisplayOptions(showFiveHour: false, showTPS: false,
                                quotaLabelStyle: label, fontSize: size, colorStyle: .monochrome,
                                itemStyle: style, customQuotaLabel: "Codex")
                            let descriptor = try #require(MenuBarFormatter.items(quota: snapshot, sample: nil,
                                options: options, now: now).first)
                            let image = StatusItemAppearance.makeImage(descriptor, options: options,
                                remaining: 66, appearance: nativeAppearance, isActive: active)
                            try assertRenderable(image, descriptor: descriptor,
                                                 template: !isFilled(style, active: active))
                        }
                    }
                }
            }
        }
    }

    @Test func inlineAndStackedTPSKeepNativeTemplateAndCapsuleSemantics() throws {
        let sample = TPSSample(id: "renderer-fixture", model: "fixture-model", outputTokens: 734,
            reasoningTokens: 300, elapsedSeconds: 10, completedAt: now)
        for dark in [false, true] {
            let nativeAppearance = try appearance(dark)
            for style in MenuBarItemStyle.allCases {
                for active in [false, true] {
                    for size in [9.0, 16.0] {
                        for layout in MenuBarTPSLayout.allCases {
                            for (showLabel, showIcon) in [(false, false), (false, true), (true, false), (true, true)] {
                                let options = DisplayOptions(showFiveHour: false, showWeekly: false,
                                    tpsDecimals: 1, showTPSLabel: showLabel, showTPSIcon: showIcon, tpsLayout: layout,
                                    fontSize: size, colorStyle: .monochrome, itemStyle: style)
                                let descriptor = try #require(MenuBarFormatter.items(quota: nil, sample: sample,
                                    options: options, now: now).first)
                                let image = StatusItemAppearance.makeImage(descriptor, options: options,
                                    remaining: nil, appearance: nativeAppearance, isActive: active)
                                try assertRenderable(image, descriptor: descriptor,
                                                     template: !isFilled(style, active: active))
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func warningAndChosenAccentColorsRemainNonTemplateWithoutDroppingLabels() throws {
        for dark in [false, true] {
            let nativeAppearance = try appearance(dark)
            for color in MenuBarColorStyle.allCases {
                for remaining in [5.0, 15.0, 80.0] {
                    let descriptor = MenuBarItem(metric: .weekly, title: "AI \(Int(remaining))%",
                        accessibilityLabel: "7-day quota, \(Int(remaining)) percent remaining")
                    let options = DisplayOptions(colorStyle: color, itemStyle: .plain)
                    let image = StatusItemAppearance.makeImage(descriptor, options: options,
                        remaining: remaining, appearance: nativeAppearance)
                    let template = color == .monochrome || (color == .adaptive && remaining > 20)
                    try assertRenderable(image, descriptor: descriptor, template: template)
                }
            }
        }
    }

    @Test func todayTokensRenderWithTheirSymbolAtBothFontBounds() throws {
        #expect(NSImage(systemSymbolName: DetailSection.today.symbol, accessibilityDescription: nil) != nil)
        for dark in [false, true] {
            for style in MenuBarItemStyle.allCases {
                for active in [false, true] {
                    for size in [9.0, 16.0] {
                        for value in ["—", "0", "69.2M", TokenCountFormatter.compact(Int.max)] {
                            let descriptor = MenuBarItem(metric: .todayTokens, title: value,
                                accessibilityLabel: "Today's local tokens", symbolName: DetailSection.today.symbol)
                            let options = DisplayOptions(fontSize: size, colorStyle: .monochrome, itemStyle: style)
                            let image = StatusItemAppearance.makeImage(descriptor, options: options, remaining: nil,
                                appearance: try appearance(dark), isActive: active)
                            try assertRenderable(image, descriptor: descriptor, template: !isFilled(style, active: active))
                        }
                    }
                }
            }
        }
    }

    @Test func lightningAddsAVisibleSymbolToInlineAndStackedTPS() throws {
        #expect(NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) != nil)
        for dark in [false, true] {
            for layout in MenuBarTPSLayout.allCases {
                for showLabel in [false, true] {
                    let options = DisplayOptions(showTPSLabel: showLabel, tpsLayout: layout, colorStyle: .monochrome)
                    let plain = MenuBarItem(metric: .tps, title: showLabel ? "59 TPS" : "59",
                        accessibilityLabel: "Response speed", tpsValue: "59")
                    let lightning = MenuBarItem(metric: .tps, title: plain.title, accessibilityLabel: plain.accessibilityLabel,
                        symbolName: "bolt.fill", tpsValue: "59")
                    let withoutIcon = StatusItemAppearance.makeImage(plain, options: options, remaining: nil,
                        appearance: try appearance(dark))
                    let withIcon = StatusItemAppearance.makeImage(lightning, options: options, remaining: nil,
                        appearance: try appearance(dark))
                    #expect(withIcon.size.width > withoutIcon.size.width + 4)
                    try assertRenderable(withIcon, descriptor: lightning, template: true)
                }
            }
        }
    }

    @Test func optionalExportsAreRawRendererPreviewsNotSystemScreenshots() throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXMETER_UI_REVIEW_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("menu-renderer", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sample = TPSSample(id: "preview-fixture", model: "fixture-model", outputTokens: 734,
            reasoningTokens: 300, elapsedSeconds: 10, completedAt: now)
        for dark in [false, true] {
            let nativeAppearance = try appearance(dark)
            for active in [false, true] {
                for layout in MenuBarTPSLayout.allCases {
                    for showIcon in [false, true] {
                        let options = DisplayOptions(showFiveHour: false, showWeekly: false,
                            tpsDecimals: 1, showTPSIcon: showIcon, tpsLayout: layout,
                            colorStyle: .monochrome, itemStyle: .activeCapsule)
                        let descriptor = try #require(MenuBarFormatter.items(quota: nil, sample: sample,
                            options: options, now: now).first)
                        let image = StatusItemAppearance.makeImage(descriptor, options: options,
                            remaining: nil, appearance: nativeAppearance, isActive: active)
                        let bytes = try #require(image.tiffRepresentation)
                        let bitmap = try #require(NSBitmapImageRep(data: bytes))
                        let png = try #require(bitmap.representation(using: .png, properties: [:]))
                        let name = "renderer-\(dark ? "dark" : "light")-\(active ? "open" : "closed")-tps-\(layout.rawValue)-icon-\(showIcon ? "on" : "off").png"
                        try png.write(to: directory.appendingPathComponent(name), options: .atomic)
                    }
                }
                let descriptor = MenuBarItem(metric: .todayTokens, title: "69.2M",
                    accessibilityLabel: "Today's local tokens", symbolName: DetailSection.today.symbol)
                let image = StatusItemAppearance.makeImage(descriptor, options: AppDefaults.display,
                    remaining: nil, appearance: nativeAppearance, isActive: active)
                let bytes = try #require(image.tiffRepresentation)
                let bitmap = try #require(NSBitmapImageRep(data: bytes))
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("renderer-\(dark ? "dark" : "light")-\(active ? "open" : "closed")-tokens-stacked-squares.png"), options: .atomic)
            }
        }
    }
}
