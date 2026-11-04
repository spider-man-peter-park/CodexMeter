import AppKit
import CoreText
import Foundation
import Testing
@testable import CodexMeterApp
@testable import CodexMeterCore

@Suite(.serialized) @MainActor struct MenuBarFixedWidthTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func readings(_ options: DisplayOptions) -> [[MenuBarItem]] {
        let missing = MenuBarFormatter.items(quota: nil, sample: nil, options: options, now: now)
        let cases: [(Int, Int, Int, Double, Bool)] = [
            (0, 0, 0, 0, false), (9, 9, 9, 9, false),
            (99, 999, 999_949_999, 99_999_999, false),
            (100, 99_999, Int.max, 9_900_000_000, true),
            (10, 1_000_000, 1_000, Double(UInt64.max), false)
        ]
        return [missing] + cases.map { percent, speed, tokens, rate, cached in
            let quota = QuotaSnapshot(
                fiveHour: QuotaWindow(usedPercent: Double(100 - percent), windowDurationMins: 300,
                    resetsAt: now.addingTimeInterval(percent == 0 ? -1 : 5 * 3600 - 1)),
                weekly: QuotaWindow(usedPercent: Double(percent), windowDurationMins: 10_080,
                    resetsAt: now.addingTimeInterval(percent == 0 ? 59 : 7 * 86400 - 1)),
                updatedAt: now, source: cached ? .logCache : .appServer)
            let sample = TPSSample(id: "fixed-width", model: "fixture", outputTokens: speed,
                reasoningTokens: 0, elapsedSeconds: 1, completedAt: now)
            let usage = LocalDayUsage(dayStart: Calendar.current.startOfDay(for: now),
                timeZoneIdentifier: Calendar.current.timeZone.identifier, input: tokens,
                updatedAt: now, hasDesktopLogs: true)
            let hardware = SystemMetricsSnapshot(sampledAt: now, cpuUsagePercent: Double(percent),
                gpuUsagePercent: Double(100 - percent), memoryUsedBytes: UInt64(percent), memoryTotalBytes: 100,
                networkUploadBytesPerSecond: rate, networkDownloadBytesPerSecond: rate / 1000)
            return MenuBarFormatter.items(quota: quota, sample: sample, options: options,
                todayUsage: usage, now: now, systemMetrics: hardware)
        }
    }

    private func assertStable(_ options: DisplayOptions, dark: Bool = false) async throws {
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        var sizes: [MenuBarMetric: NSSize] = [:]
        for items in readings(options) {
            for item in items {
                for active in [false, true] {
                    let image = StatusItemAppearance.makeImage(item, options: options, remaining: 80,
                        appearance: appearance, isActive: active)
                    if let expected = sizes[item.metric] {
                        #expect(image.size == expected, "\(item.metric.rawValue): \(item.title)")
                    } else { sizes[item.metric] = image.size }
                    #expect(image.accessibilityDescription == item.accessibilityLabel)
                }
            }
            await Task.yield()
        }
        #expect(sizes.count == 8)
    }

    @Test func everyItemKeepsItsInitialSizeThroughValuesUnitsAndCacheChanges() async throws {
        for dark in [false, true] {
            for style in MenuBarItemStyle.allCases {
                var options = AppDefaults.display
                options.itemStyle = style
                try await assertStable(options, dark: dark)
            }
        }
    }

    @Test func independentLayoutsAndFontsReserveSpaceBeforeTheFirstReading() async throws {
        for font in MenuBarFontDesign.allCases {
            for size in [9.0, 12.0, 16.0] {
                for layout in MenuBarTPSLayout.allCases {
                    for position in MenuBarLabelPosition.allCases {
                        for (icon, label) in [(true, true), (false, true), (true, false), (false, false)] {
                            let display = SystemMetricDisplayOptions(showIcon: icon, showLabel: label, labelPosition: position)
                            let options = DisplayOptions(cpuDisplay: display, gpuDisplay: display, ramDisplay: display,
                                tpsDecimals: 1, showTPSLabel: label, showTPSIcon: icon, tpsLayout: layout,
                                fontSize: size, fontDesign: font)
                            try await assertStable(options)
                        }
                    }
                }
            }
        }
    }

    @Test func quotaFormattingChoicesKeepCountdownGeometryWithoutCacheMarkerSpace() async throws {
        for label in QuotaLabelStyle.allCases {
            for countdown in CountdownStyle.allCases {
                for separator in CountdownSeparator.allCases {
                    for visible in [false, true] {
                        let options = DisplayOptions(showCountdown: visible, quotaLabelStyle: label,
                            countdownStyle: countdown, customQuotaLabel: "My Codex", showPercentSign: visible,
                            countdownSeparator: separator)
                        try await assertStable(options)
                    }
                }
            }
        }
    }

    @Test func weeklyCountdownReachesTheTrailingInsetWithoutResizingAsItShortens() throws {
        var options = AppDefaults.display
        options.quotaLabelStyle = .window
        let appearance = try #require(NSAppearance(named: .aqua))
        var referenceSize: NSSize?
        for (minutes, percent) in [(10080, 100), (8639, 82), (1440, 9), (1439, 100), (59, 0), (0, 100)] {
            let quota = QuotaSnapshot(fiveHour: nil,
                weekly: .init(usedPercent: Double(100 - percent), windowDurationMins: 10080,
                    resetsAt: now.addingTimeInterval(Double(minutes) * 60)),
                updatedAt: now, source: .logCache)
            let item = try #require(MenuBarFormatter.items(quota: quota, sample: nil, options: options, now: now).first { $0.metric == .weekly })
            let image = StatusItemAppearance.makeImage(item, options: options, remaining: nil, appearance: appearance)
            if let referenceSize { #expect(image.size == referenceSize) } else { referenceSize = image.size }
            let primary = try #require(item.quotaPrimary)
            let geometry = StatusItemAppearance.quotaGeometry(primary: primary, countdown: item.quotaCountdown,
                symbolSize: nil, options: options, reservedSize: image.size)
            let countdown = try #require(geometry.countdown)
            #expect(abs(countdown.maxX - (image.size.width - options.itemHorizontalPadding)) < 0.001)
            #expect(countdown.minX > geometry.primary.maxX)
            #expect(!item.title.contains("*"))
        }
        var defaults = AppDefaults.display
        let item = try #require(readings(defaults)[0].first { $0.metric == .weekly })
        let image = StatusItemAppearance.makeImage(item, options: defaults, remaining: nil, appearance: appearance)
        defaults.showCountdown = false
        let withoutCountdown = try #require(readings(defaults)[0].first { $0.metric == .weekly })
        #expect(StatusItemAppearance.makeImage(withoutCountdown, options: defaults, remaining: nil, appearance: appearance).size.width < image.size.width)
    }

    @Test func weeklyReserves100PercentAnd20h20mAtTheSelectedFontSize() throws {
        let appearance = try #require(NSAppearance(named: .aqua))
        for size in [9.0, 12.0, 16.0] {
            var options = AppDefaults.display
            options.quotaLabelStyle = .none
            options.countdownSeparator = .space
            options.fontSize = size
            let quota = QuotaSnapshot(fiveHour: nil,
                weekly: .init(usedPercent: 0, windowDurationMins: 10080, resetsAt: now.addingTimeInterval(1220 * 60)),
                updatedAt: now, source: .appServer)
            let item = try #require(MenuBarFormatter.items(quota: quota, sample: nil, options: options, now: now).first { $0.metric == .weekly })
            let capacity = StatusItemAppearance.capacityDescriptor(for: item, options: options)
            #expect(capacity.quotaPrimary == "100%")
            #expect(capacity.quotaCountdown == "20h20m")
            #expect(item.title == "100% 20h20m")
            let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
            func inkWidth(_ text: String) -> CGFloat {
                CTLineGetImageBounds(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font])), nil).width
            }
            let image = StatusItemAppearance.makeImage(item, options: options, remaining: nil, appearance: appearance)
            let expected = ceil(inkWidth("100%") + inkWidth("20h20m") + 3 + options.itemHorizontalPadding * 2)
            #expect(abs(Double(image.size.width) - Double(expected)) < 0.001)
        }
    }

    @Test func quotaDotCentersBetweenVisibleTextAndSharesItsVerticalCenter() throws {
        for design in MenuBarFontDesign.allCases {
            for size in [9.0, 12.0, 16.0] {
                for symbol in [nil, NSSize(width: 20, height: 20)] {
                    for style in CountdownStyle.allCases {
                        var options = AppDefaults.display
                        options.fontDesign = design
                        options.fontSize = size
                        options.countdownStyle = style
                        let times = style == .compact ? ["20h20m", "23h59m", "6d8h", "59m", "now"] : ["7d23:59", "6d00:00", "00:59"]
                        let capacity = StatusItemAppearance.quotaGeometry(primary: "100%", countdown: times[0], symbolSize: symbol, options: options)
                        for primary in ["100%", "99%", "9%", "0%"] {
                            for time in times {
                                let actual = StatusItemAppearance.quotaGeometry(primary: primary, countdown: time,
                                    symbolSize: symbol, options: options, reservedSize: capacity.size)
                                let dot = try #require(actual.separator)
                                let countdown = try #require(actual.countdown)
                                #expect(actual.size == capacity.size)
                                let leftGap = dot.minX - actual.primary.maxX
                                let rightGap = countdown.minX - dot.maxX
                                #expect(leftGap > 0 && rightGap > 0)
                                #expect(abs(leftGap - rightGap) < 0.001)
                                #expect(dot.midY == actual.primary.midY && dot.midY == countdown.midY)
                                #expect(abs(countdown.maxX - (actual.size.width - options.itemHorizontalPadding)) < 0.001)
                            }
                        }
                        #expect(StatusItemAppearance.quotaGeometry(primary: "—", countdown: nil,
                            symbolSize: symbol, options: options, reservedSize: capacity.size).separator == nil)
                    }
                }
            }
        }
    }

    @Test func tpsUsesAThreeDigitReservationWithoutClippingNormalReadings() throws {
        let appearance = try #require(NSAppearance(named: .aqua))
        for precision in [0, 1] {
            var options = AppDefaults.display
            options.showTPSIcon = false
            options.tpsDecimals = precision
            let largest = precision == 0 ? "999" : "999.9"
            let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            var size: NSSize?
            for value in ["—", "0", "9", "73", "100", largest] {
                let descriptor = MenuBarItem(metric: .tps, title: value + " TPS", accessibilityLabel: "Response speed", tpsValue: value)
                #expect(StatusItemAppearance.capacityDescriptor(for: descriptor, options: options).tpsValue == largest)
                let image = StatusItemAppearance.makeImage(descriptor, options: options, remaining: nil, appearance: appearance)
                if let size { #expect(image.size == size) } else { size = image.size }
                let original = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [.font: font]))
                let fitted = StatusItemAppearance.textLine(value, font: font, foreground: .black, availableWidth: image.size.width - 4)
                #expect(CTLineGetGlyphCount(fitted) == CTLineGetGlyphCount(original))
            }
            if precision == 0 { #expect(try #require(size).width <= 30) }
        }
    }

    @Test func inkThatFitsIsNotTruncatedBecauseOfUnusedFontSideBearings() {
        for text in ["9999", "9999.9", "100.0 MB/s", "999.9M", "100%"] {
            for size in [9.0, 12.0, 16.0] {
                let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
                let original = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
                let width = ceil(CTLineGetImageBounds(original, nil).width)
                let fitted = StatusItemAppearance.textLine(text, font: font, foreground: .black, availableWidth: width)
                #expect(CTLineGetGlyphCount(fitted) == CTLineGetGlyphCount(original))
            }
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let overflow = StatusItemAppearance.textLine("12345678901234567890 TPS", font: font, foreground: .black, availableWidth: 50)
        #expect(CTLineGetImageBounds(overflow, nil).width <= 50)
    }

    @Test func defaultWidthsAreTighterThanThePreviousReservations() throws {
        let options = AppDefaults.display
        let appearance = try #require(NSAppearance(named: .aqua))
        let previous: [MenuBarMetric: CGFloat] = [.fiveHour: 140, .weekly: 140, .tps: 78,
            .todayTokens: 105, .cpu: 95, .gpu: 97, .ram: 97, .network: 79]
        for item in readings(options)[0] {
            let image = StatusItemAppearance.makeImage(item, options: options, remaining: nil, appearance: appearance)
            #expect(image.size.width < (previous[item.metric] ?? .infinity), "\(item.metric): \(image.size.width)")
        }
    }

    @Test func stackedRAMCentersItsLabelOverDigitsExcludingThePercentSign() throws {
        for size in [9.0, 12.0, 16.0] {
            for font in MenuBarFontDesign.allCases {
                for symbol in [nil, NSSize(width: 11, height: 8)] {
                    var options = AppDefaults.display
                    options.fontSize = size
                    options.fontDesign = font
                    let capacity = StatusItemAppearance.stackedSystemGeometry(value: "100%", label: "RAM", symbolSize: symbol,
                        options: options, alignLabelToDigits: true)
                    for reading in ["—", "0%", "7%", "42%", "100%"] {
                        let actual = StatusItemAppearance.stackedSystemGeometry(value: reading, label: "RAM", symbolSize: symbol,
                            options: options, reservedSize: capacity.size, alignLabelToDigits: true)
                        let digits = try #require(actual.digits)
                        #expect(actual.size == capacity.size)
                        #expect(abs(actual.label.midX - digits.midX) < 0.001)
                        #expect(abs(actual.label.midX - capacity.label.midX) < 0.001)
                        if reading.hasSuffix("%") { #expect(actual.label.midX < actual.number.midX) }
                        #expect(actual.number.minX >= 0 && actual.number.maxX <= actual.size.width)
                        #expect(actual.upper.minX >= 0 && actual.upper.maxX <= actual.size.width)
                        #expect(actual.number.minY >= 0 && actual.upper.maxY <= actual.size.height)
                        #expect(actual.number.maxY < actual.upper.minY)
                    }
                }
            }
        }
    }

    @Test func hidingTheTokenLabelShrinksOnlyItsReservationAndReadingsStillStayFixed() async throws {
        let appearance = try #require(NSAppearance(named: .aqua))
        let labeled = AppDefaults.display
        var hidden = labeled
        hidden.showTodayTokensLabel = false
        try await assertStable(labeled)
        try await assertStable(hidden)
        for (withLabel, withoutLabel) in zip(readings(labeled)[0], readings(hidden)[0]) {
            let first = StatusItemAppearance.makeImage(withLabel, options: labeled, remaining: nil, appearance: appearance)
            let second = StatusItemAppearance.makeImage(withoutLabel, options: hidden, remaining: nil, appearance: appearance)
            if withLabel.metric == .todayTokens { #expect(first.size.width > second.size.width) }
            else { #expect(first.size == second.size) }
        }
    }

    @Test func commonReadingsFitTheCompactNumericReservations() throws {
        let options = AppDefaults.display
        let font = NSFont.monospacedDigitSystemFont(ofSize: options.normalizedFontSize, weight: .medium)
        let networkFont = NSFont.monospacedDigitSystemFont(ofSize: min(10, max(8, options.normalizedFontSize - 2)), weight: .medium)
        func width(_ text: String, font: NSFont) -> CGFloat {
            CTLineGetImageBounds(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font])), nil).width
        }
        for items in readings(options).prefix(4) {
            for item in items {
                let capacity = StatusItemAppearance.capacityDescriptor(for: item, options: options)
                if item.metric == .network {
                    let reserved = try #require(capacity.networkUploadValue)
                    for rate in [0.0, 999, 1_500, 99_949_000, 99_999_999, 999_499_999, 1_000_000_000, Double(UInt64.max)] {
                        #expect(width(SystemMetricsFormatter.rate(rate), font: networkFont) <= ceil(width(reserved, font: networkFont)))
                    }
                } else {
                    #expect(width(item.title, font: font) <= ceil(width(capacity.title, font: font)), "\(item.title)")
                }
            }
        }
    }

    @Test func optionalExportsCompareReadingWidthsAndAreNotSystemScreenshots() throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXMETER_FIXED_WIDTH_REVIEW_DIR"] else { return }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let options = AppDefaults.display
        let inputs = readings(options)
        let columns = [inputs[0], inputs[2], inputs[3], inputs[4]]
        let metrics = columns[0].map(\.metric)
        let scale: CGFloat = 2
        let size = NSSize(width: 880, height: 50 + CGFloat(metrics.count) * 60)
        var csv = "appearance,metric,state,width,height\n"
        for dark in [false, true] {
            let pixels = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let graphics = try #require(NSGraphicsContext(bitmapImageRep: pixels))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            graphics.cgContext.scaleBy(x: scale, y: scale)
            let foreground: NSColor = dark ? .white : .black
            (dark ? NSColor(white: 0.12, alpha: 1) : .white).setFill()
            NSRect(origin: .zero, size: size).fill()
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: foreground]
            let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
            let captions = ["Unavailable", "Small readings", "Large readings", "Cached / unit changes"]
            for (column, caption) in captions.enumerated() {
                NSAttributedString(string: caption, attributes: attributes)
                    .draw(at: NSPoint(x: 100 + column * 195, y: Int(size.height) - 28))
            }
            for (row, metric) in metrics.enumerated() {
                let y = size.height - 76 - CGFloat(row) * 60
                NSAttributedString(string: metric.rawValue, attributes: attributes).draw(at: NSPoint(x: 8, y: y + 6))
                for (column, items) in columns.enumerated() {
                    let item = try #require(items.first { $0.metric == metric })
                    let image = StatusItemAppearance.makeImage(item, options: options, remaining: nil, appearance: appearance)
                    let rect = NSRect(origin: NSPoint(x: 100 + column * 195, y: Int(y)), size: image.size)
                    graphics.cgContext.saveGState()
                    if image.isTemplate, let mask = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        graphics.cgContext.clip(to: rect, mask: mask)
                        foreground.setFill()
                        rect.fill()
                    } else { image.draw(in: rect) }
                    graphics.cgContext.restoreGState()
                    NSColor.systemBlue.setStroke()
                    NSBezierPath(rect: rect.insetBy(dx: -1, dy: -1)).stroke()
                    NSAttributedString(string: "\(Int(image.size.width)) pt", attributes: attributes)
                        .draw(at: NSPoint(x: rect.minX, y: rect.minY - 18))
                    csv += "\(dark ? "dark" : "light"),\(metric.rawValue),\(column),\(image.size.width),\(image.size.height)\n"
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            let png = try #require(pixels.representation(using: .png, properties: [:]))
            try png.write(to: folder.appendingPathComponent("renderer-widths-\(dark ? "dark" : "light").png"))
        }
        try csv.write(to: folder.appendingPathComponent("renderer-widths.csv"), atomically: true, encoding: .utf8)
    }
}
