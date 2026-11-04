import AppKit
import Foundation
import Testing
@testable import CodexMeterApp
@testable import CodexMeterCore

@Suite(.serialized) @MainActor struct SystemMetricsIntegrationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var snapshot: SystemMetricsSnapshot {
        SystemMetricsSnapshot(sampledAt: now, cpuUsagePercent: 37, gpuUsagePercent: 12,
            memoryUsedBytes: 12_000_000_000, memoryTotalBytes: 24_000_000_000,
            networkUploadBytesPerSecond: 125_000, networkDownloadBytesPerSecond: 2_500_000)
    }

    private func baseOptions() -> DisplayOptions {
        DisplayOptions(showFiveHour: false, showWeekly: false, showTPS: false,
            showTodayTokens: false, colorStyle: .monochrome)
    }

    private func descriptors(_ options: DisplayOptions) -> [MenuBarItem] {
        MenuBarFormatter.items(quota: nil, sample: nil, options: options, now: now, systemMetrics: snapshot)
    }

    private func appearance(_ dark: Bool) throws -> NSAppearance {
        try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
    }

    private func render(_ descriptor: MenuBarItem, options: DisplayOptions, dark: Bool, active: Bool = false) throws -> NSImage {
        StatusItemAppearance.makeImage(descriptor, options: options, remaining: nil,
            appearance: try appearance(dark), isActive: active)
    }

    private func bitmap(_ image: NSImage) throws -> NSBitmapImageRep {
        let data = try #require(image.tiffRepresentation)
        return try #require(NSBitmapImageRep(data: data))
    }

    private func verify(_ image: NSImage, descriptor: MenuBarItem, filled: Bool) throws {
        #expect((20...400).contains(image.size.width))
        #expect((20...26).contains(image.size.height))
        #expect(image.isTemplate == !filled)
        #expect(image.accessibilityDescription == descriptor.accessibilityLabel)
        let pixels = try bitmap(image)
        var visible = false
        for y in stride(from: 0, to: pixels.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: pixels.pixelsWide, by: 2) {
                if (pixels.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 { visible = true; break }
            }
            if visible { break }
        }
        #expect(visible)
        let marginX = Int(2 * CGFloat(pixels.pixelsWide) / image.size.width)
        let margin = try #require(pixels.colorAt(x: marginX, y: pixels.pixelsHigh / 2))
        #expect(filled ? margin.alphaComponent > 0.95 : margin.alphaComponent < 0.01)
    }

    @Test func systemItemsFitTheMenuBarAcrossLayoutsFontBoundsAndNativeSelection() throws {
        for dark in [false, true] {
            for style in MenuBarItemStyle.allCases {
                for fontSize in [9.0, 16.0] {
                    for position in MenuBarLabelPosition.allCases {
                        for icon in [false, true] {
                            for label in [false, true] {
                                var options = baseOptions()
                                options.itemStyle = style
                                options.fontSize = fontSize
                                let display = SystemMetricDisplayOptions(showIcon: icon, showLabel: label, labelPosition: position)
                                options.cpuDisplay = display
                                options.gpuDisplay = display
                                options.ramDisplay = display
                                let items = descriptors(options)
                                #expect(items.map(\.metric) == [.cpu, .gpu, .ram, .network])
                                for descriptor in items {
                                    if let symbol = descriptor.symbolName {
                                        #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil)
                                    }
                                    let idle = try render(descriptor, options: options, dark: dark)
                                    let selected = try render(descriptor, options: options, dark: dark, active: true)
                                    try verify(idle, descriptor: descriptor, filled: style == .capsule)
                                    try verify(selected, descriptor: descriptor, filled: false)
                                    #expect(idle.size == selected.size)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func systemIconAndLabelChoicesChangeTheRenderedContentAndWidth() throws {
        for dark in [false, true] {
            for metric in [MenuBarMetric.cpu, .gpu, .ram] {
                var options = baseOptions()
                let full = try #require(descriptors(options).first { $0.metric == metric })
                let fullImage = try render(full, options: options, dark: dark)
                let key: WritableKeyPath<DisplayOptions, SystemMetricDisplayOptions> =
                    metric == .cpu ? \.cpuDisplay : metric == .gpu ? \.gpuDisplay : \.ramDisplay
                options[keyPath: key].showIcon = false
                let noIcon = try #require(descriptors(options).first { $0.metric == metric })
                #expect(noIcon.symbolName == nil)
                #expect(try render(noIcon, options: options, dark: dark).size.width < fullImage.size.width)
                options[keyPath: key].showIcon = true
                options[keyPath: key].showLabel = false
                let noLabel = try #require(descriptors(options).first { $0.metric == metric })
                #expect(noLabel.systemLabel == nil)
                #expect(try render(noLabel, options: options, dark: dark).size.width < fullImage.size.width)
                options[keyPath: key].showLabel = true
                options[keyPath: key].labelPosition = .above
                let above = try #require(descriptors(options).first { $0.metric == metric })
                #expect(above.systemLabel != nil)
                #expect(try render(above, options: options, dark: dark).size.width <= fullImage.size.width)
            }
        }
    }

    @Test func networkUsesOneItemForBothDirectionsAndRetainsEachSingleDirection() throws {
        for upload in [false, true] {
            for download in [false, true] where upload || download {
                var options = baseOptions()
                options.showNetworkUpload = upload
                options.showNetworkDownload = download
                let networkItems = descriptors(options).filter { $0.metric == .network }
                #expect(networkItems.count == 1)
                let item = try #require(networkItems.first)
                #expect((item.networkUploadValue != nil) == upload)
                #expect((item.networkDownloadValue != nil) == download)
                for dark in [false, true] {
                    for size in [9.0, 16.0] {
                        options.fontSize = size
                        let idle = try render(item, options: options, dark: dark)
                        let selected = try render(item, options: options, dark: dark, active: true)
                        try verify(idle, descriptor: item, filled: false)
                        try verify(selected, descriptor: item, filled: false)
                        #expect(idle.size == selected.size)
                    }
                }
            }
        }
    }

    @Test func systemVisibilityAndIndependentDisplayChoicesSurviveRestartWithoutChangingOtherPreferences() throws {
        let suite = "io.github.codexmeter.system-metrics-tests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("/private/tmp/" + suite, forKey: "codexHome")
        let model = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        let visibility: [WritableKeyPath<DisplayOptions, Bool>] = [
            \.showCPU, \.showGPU, \.showRAM, \.showNetworkUpload, \.showNetworkDownload
        ]
        let displays: [WritableKeyPath<DisplayOptions, SystemMetricDisplayOptions>] = [\.cpuDisplay, \.gpuDisplay, \.ramDisplay]
        #expect(visibility.allSatisfy { model.options[keyPath: $0] })
        #expect(displays.allSatisfy { model.options[keyPath: $0] == .init() })
        var expected = model.options
        let layout = model.detailLayout
        let refresh = model.refreshOptions
        let reminders = model.reminders.options
        let language = model.language
        let appearance = model.appearance
        let autoRefresh = model.autoRefresh
        for option in visibility {
            model.options[keyPath: option] = false
            expected[keyPath: option] = false
            #expect(AppModel(defaults: defaults, notificationCenter: TestReminderCenter()).options == expected)
        }
        for (index, option) in displays.enumerated() {
            let style = SystemMetricDisplayOptions(showIcon: index == 1, showLabel: index == 0,
                labelPosition: index == 1 ? .leading : .above)
            model.options[keyPath: option] = style
            expected[keyPath: option] = style
            let restarted = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
            #expect(restarted.options == expected)
            #expect(restarted.detailLayout == layout)
            #expect(restarted.refreshOptions == refresh)
            #expect(restarted.reminders.options == reminders)
            #expect(restarted.language == language)
            #expect(restarted.appearance == appearance)
            #expect(restarted.autoRefresh == autoRefresh)
        }
    }

    @Test func optionalExportsAreRawRendererPreviewsRatherThanSystemScreenshots() throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXMETER_UI_REVIEW_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("system-menu-renderer", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func export(_ image: NSImage, name: String) throws {
            let dark = name.hasPrefix("dark-")
            let scale: CGFloat = 4
            let pixels = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int(image.size.width * scale), pixelsHigh: Int(image.size.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let context = try #require(NSGraphicsContext(bitmapImageRep: pixels))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.scaleBy(x: scale, y: scale)
            let rect = NSRect(origin: .zero, size: image.size)
            (dark ? NSColor(white: 0.12, alpha: 1) : .white).setFill()
            rect.fill()
            if image.isTemplate, let mask = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                context.cgContext.saveGState()
                context.cgContext.clip(to: rect, mask: mask)
                (dark ? NSColor.white : .black).setFill()
                rect.fill()
                context.cgContext.restoreGState()
            } else {
                image.draw(in: rect)
            }
            NSGraphicsContext.restoreGraphicsState()
            let png = try #require(pixels.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent(name), options: .atomic)
        }
        for dark in [false, true] {
            let theme = dark ? "dark" : "light"
            for position in MenuBarLabelPosition.allCases {
                for icon in [false, true] {
                    for label in [false, true] {
                        var options = baseOptions()
                        let display = SystemMetricDisplayOptions(showIcon: icon, showLabel: label, labelPosition: position)
                        options.cpuDisplay = display
                        options.gpuDisplay = display
                        options.ramDisplay = display
                        for descriptor in descriptors(options) where descriptor.metric != .network {
                            try export(render(descriptor, options: options, dark: dark),
                                name: "\(theme)-\(descriptor.metric.rawValue)-\(position.rawValue)-icon-\(icon)-label-\(label).png")
                        }
                    }
                }
            }
            for (upload, download) in [(true, true), (true, false), (false, true)] {
                var options = baseOptions()
                options.showNetworkUpload = upload
                options.showNetworkDownload = download
                let network = try #require(descriptors(options).first { $0.metric == .network })
                try export(render(network, options: options, dark: dark),
                    name: "\(theme)-network-upload-\(upload)-download-\(download).png")
            }
        }
    }
}
