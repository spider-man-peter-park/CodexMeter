import AppKit
import CodexMeterCore
import CoreText

@MainActor
enum StatusItemAppearance {
    static func apply(_ descriptor: MenuBarItem, to item: NSStatusItem,
                      options: DisplayOptions, window: QuotaWindow?, isActive: Bool = false) {
        guard let button = item.button else { return }
        let image = makeImage(descriptor, options: options, remaining: window?.remainingPercent,
                              appearance: button.effectiveAppearance, isActive: isActive)
        // The system owns the selected background; active images contain template glyphs only.
        button.attributedTitle = NSAttributedString(string: "")
        button.title = ""
        button.contentTintColor = nil
        button.image = image
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.appearsDisabled = false
        button.alphaValue = 1
        item.length = image.size.width
    }

    static func makeImage(_ descriptor: MenuBarItem, options: DisplayOptions,
                          remaining: Double?, appearance: NSAppearance, isActive: Bool = false) -> NSImage {
        // Reserve geometry from the metric's format, never from its latest reading or largest value seen.
        let capacity = capacityDescriptor(for: descriptor, options: options)
        let size = renderImage(capacity, options: options, remaining: nil, appearance: appearance).size
        return renderImage(descriptor, options: options, remaining: remaining, appearance: appearance,
                           isActive: isActive, reservedSize: size)
    }

    static func capacityDescriptor(for descriptor: MenuBarItem, options: DisplayOptions) -> MenuBarItem {
        let font = makeFont(options)
        func widest(_ values: [String], font: NSFont) -> String {
            values.max {
                NSAttributedString(string: $0, attributes: [.font: font]).size().width
                    < NSAttributedString(string: $1, attributes: [.font: font]).size().width
            } ?? ""
        }
        let title: String
        var value: String?
        var upload: String?
        var download: String?
        var quotaPrimary: String?
        var quotaCountdown: String?
        switch descriptor.metric {
        case .fiveHour, .weekly:
            let prefix: String
            switch options.quotaLabelStyle {
            case .ai: prefix = "AI "
            case .window: prefix = descriptor.metric == .fiveHour ? "5h " : "7d "
            case .custom: prefix = options.normalizedCustomQuotaLabel + " "
            case .none, .icon, .gpt: prefix = ""
            }
            var countdown = ""
            if options.showCountdown {
                let clock = descriptor.metric == .fiveHour ? "23:59" : "7d23:59"
                let compact = descriptor.metric == .fiveHour ? "5h59m" : "20h20m"
                let text = options.countdownStyle == .clock ? clock : compact
                switch options.countdownSeparator {
                case .space: countdown = " " + text
                case .dot: countdown = " · " + text
                case .slash: countdown = " / " + text
                case .parentheses: countdown = " (" + text + ")"
                }
            }
            let primary = widest([prefix + "100" + (options.showPercentSign ? "%" : ""),
                                  prefix + "N/A", prefix + "—"], font: font)
            title = primary + countdown
            if descriptor.quotaPrimary != nil {
                quotaPrimary = primary
                quotaCountdown = options.showCountdown
                    ? (options.countdownStyle == .clock ? (descriptor.metric == .fiveHour ? "23:59" : "7d23:59")
                       : (descriptor.metric == .fiveHour ? "5h59m" : "20h20m")) : nil
            }
        case .tps:
            value = options.tpsDecimals > 0 ? "999.9" : "999"
            title = (value ?? "") + (options.showTPSLabel ? " TPS" : "")
        case .todayTokens:
            title = (options.showTodayTokensLabel ? "tok " : "") + widest(["999.9K", "999.9M", "999.9B", "999.9T"], font: font)
        case .cpu, .gpu, .ram:
            value = "100%"
            title = (descriptor.systemLabel.map { $0 + " " } ?? "") + "100%"
        case .network:
            let rowFont = makeFont(options, size: min(10, max(8, options.normalizedFontSize - 2)))
            let rate = widest(["B", "KB", "MB", "GB", "TB", "PB", "EB"].map { "99.9 " + $0 + "/s" }, font: rowFont)
            upload = descriptor.networkUploadValue == nil ? nil : rate
            download = descriptor.networkDownloadValue == nil ? nil : rate
            title = "—"
        case .fallback:
            title = "AI"
        }
        return MenuBarItem(metric: descriptor.metric, title: title, accessibilityLabel: descriptor.accessibilityLabel,
            symbolName: descriptor.symbolName, usesGPTLogo: descriptor.usesGPTLogo,
            tpsValue: descriptor.tpsValue == nil ? nil : value,
            systemValue: descriptor.systemValue == nil ? nil : value, systemLabel: descriptor.systemLabel,
            networkUploadValue: upload, networkDownloadValue: download,
            quotaPrimary: quotaPrimary, quotaCountdown: quotaCountdown)
    }

    private static func renderImage(_ descriptor: MenuBarItem, options: DisplayOptions,
                                    remaining: Double?, appearance: NSAppearance, isActive: Bool = false,
                                    reservedSize: NSSize? = nil) -> NSImage {
        let font = makeFont(options)
        // Do not nest a custom fill inside the menu bar's system-managed selected pill.
        let capsule = options.itemStyle == .capsule && !isActive
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let accent = isActive ? nil : accentColor(options.colorStyle, remaining: remaining)
        let template = !capsule && accent == nil
        let plainAccent = dark ? accent?.blended(withFraction: 0.6, of: .white) : accent
        let background: NSColor? = capsule ? (accent ?? (dark ? .white : .black)) : nil
        let foreground: NSColor = capsule ? (accent == nil && dark ? .black : .white) : (plainAccent ?? .black)
        if descriptor.metric == .tps, options.tpsLayout == .stacked, let value = descriptor.tpsValue {
            return stackedValue(value, label: options.showTPSLabel ? "TPS" : "", descriptor: descriptor,
                                options: options, foreground: foreground, background: background, template: template,
                                reservedSize: reservedSize)
        }
        let systemDisplay: SystemMetricDisplayOptions?
        switch descriptor.metric {
        case .cpu: systemDisplay = options.cpuDisplay
        case .gpu: systemDisplay = options.gpuDisplay
        case .ram: systemDisplay = options.ramDisplay
        default: systemDisplay = nil
        }
        if systemDisplay?.labelPosition == .above, let label = descriptor.systemLabel, let value = descriptor.systemValue {
            return stackedValue(value, label: label, descriptor: descriptor, options: options,
                                foreground: foreground, background: background, template: template, reservedSize: reservedSize)
        }
        if descriptor.metric == .network,
           let network = stackedNetwork(descriptor, options: options, foreground: foreground,
                                        background: background, template: template, reservedSize: reservedSize) {
            return network
        }
        let title = NSAttributedString(string: descriptor.title, attributes: [
            .font: font, .foregroundColor: foreground
        ])
        var symbolImage: NSImage?
        if descriptor.usesGPTLogo {
            let whiteLogo = capsule ? (accent != nil || !dark) : (!template && dark)
            if let logo = gptLogo(white: whiteLogo) {
                let side = min(22, max(18, options.normalizedFontSize + 8))
                symbolImage = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
                    logo.draw(in: rect)
                    return true
                }
            }
        } else if let symbol = descriptor.symbolName {
            symbolImage = makeSymbol(symbol, options: options, foreground: foreground)
        }
        if let primary = descriptor.quotaPrimary {
            return quotaImage(primary: primary, countdown: descriptor.quotaCountdown, descriptor: descriptor,
                              symbol: symbolImage, options: options, foreground: foreground,
                              background: background, template: template, reservedSize: reservedSize)
        }
        let padding = descriptor.metric == .tps ? tpsHorizontalPadding(options) : horizontalPadding(options)
        let symbolWidth = symbolImage.map { $0.size.width + symbolGap(options) } ?? 0
        let titleSize = title.size()
        let size = reservedSize ?? NSSize(width: max(20, ceil(titleSize.width + symbolWidth + padding * 2)),
                                         height: max(20, ceil(max(titleSize.height, symbolImage?.size.height ?? 0) + 2)))
        let image = NSImage(size: size, flipped: false) { rect in
            if let background {
                background.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            }
            if let symbolImage {
                symbolImage.draw(at: NSPoint(x: padding, y: (size.height - symbolImage.size.height) / 2),
                                 from: .zero, operation: .sourceOver, fraction: 1)
            }
            drawText(descriptor.title, font: font, foreground: foreground,
                     in: NSRect(x: padding + symbolWidth, y: 0,
                                width: size.width - symbolWidth - padding * 2, height: size.height))
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = descriptor.accessibilityLabel
        return image
    }

    struct QuotaGeometry {
        let size: NSSize
        let primary: NSRect
        let countdown: NSRect?
        let separator: NSRect?
        let symbol: NSRect?
    }

    private static func quotaCountdownText(_ countdown: String, options: DisplayOptions) -> String {
        switch options.countdownSeparator {
        case .space: countdown
        case .dot: "· " + countdown
        case .slash: "/ " + countdown
        case .parentheses: "(" + countdown + ")"
        }
    }

    private static func quotaCountdownFont(_ options: DisplayOptions) -> NSFont {
        makeFont(options)
    }

    static func quotaGeometry(primary: String, countdown: String?, symbolSize: NSSize?, options: DisplayOptions,
                              reservedSize: NSSize? = nil) -> QuotaGeometry {
        func bounds(_ text: String, font: NSFont) -> CGRect {
            CTLineGetImageBounds(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font])), nil)
        }
        let primaryBounds = bounds(primary, font: makeFont(options))
        let countdownBounds = countdown.map { bounds(quotaCountdownText($0, options: options), font: quotaCountdownFont(options)) }
        let padding = horizontalPadding(options)
        let leading = symbolSize.map { $0.width + symbolGap(options) } ?? 0
        let gap: CGFloat = countdown == nil ? 0 : (options.spacing == .compact ? 3 : 4)
        let dotGap: CGFloat = options.spacing == .compact ? 5 : 6
        let countdownWidth: CGFloat
        if let countdown, options.countdownSeparator == .dot {
            let font = quotaCountdownFont(options)
            countdownWidth = bounds(countdown, font: font).width + bounds("·", font: font).width + dotGap * 2
        } else {
            countdownWidth = gap + (countdownBounds?.width ?? 0)
        }
        let size = reservedSize ?? NSSize(width: max(20, ceil(padding * 2 + leading + primaryBounds.width + countdownWidth)),
            height: max(20, ceil(max(primaryBounds.height, countdownBounds?.height ?? 0, symbolSize?.height ?? 0) + 2)))
        let start = padding + leading
        let countdownStart = start + primaryBounds.width + gap
        let primaryRect = NSRect(x: start, y: 0,
            width: min(primaryBounds.width, max(0, size.width - padding - start)), height: size.height)
        var countdownRect = countdown.map { _ in NSRect(x: countdownStart, y: 0,
            width: max(0, size.width - padding - countdownStart), height: size.height) }
        var separatorRect: NSRect?
        if let countdown, options.countdownSeparator == .dot {
            let font = quotaCountdownFont(options)
            let timeWidth = bounds(countdown, font: font).width
            let dotWidth = bounds("·", font: font).width
            // Keep normal gaps around the dot; leave spare capacity after the countdown.
            let dotStart = primaryRect.maxX + dotGap
            let timeStart = dotStart + dotWidth + dotGap
            let available = max(0, size.width - padding - timeStart)
            countdownRect = NSRect(x: timeStart, y: 0, width: min(timeWidth, available), height: size.height)
            separatorRect = NSRect(x: dotStart, y: 0, width: dotWidth, height: size.height)
        }
        return QuotaGeometry(size: size, primary: primaryRect, countdown: countdownRect, separator: separatorRect,
            symbol: symbolSize.map { NSRect(x: padding, y: (size.height - $0.height) / 2, width: $0.width, height: $0.height) })
    }

    private static func quotaImage(primary: String, countdown: String?, descriptor: MenuBarItem, symbol: NSImage?,
                                   options: DisplayOptions, foreground: NSColor, background: NSColor?, template: Bool,
                                   reservedSize: NSSize?) -> NSImage {
        let geometry = quotaGeometry(primary: primary, countdown: countdown, symbolSize: symbol?.size,
                                     options: options, reservedSize: reservedSize)
        let image = NSImage(size: geometry.size, flipped: false) { rect in
            if let background {
                background.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            }
            if let symbol, let frame = geometry.symbol { symbol.draw(in: frame) }
            drawText(primary, font: makeFont(options), foreground: foreground, in: geometry.primary)
            if let frame = geometry.separator {
                drawText("·", font: quotaCountdownFont(options), foreground: foreground, in: frame, alignment: 0.5)
            }
            if let countdown, let frame = geometry.countdown {
                drawText(geometry.separator == nil ? quotaCountdownText(countdown, options: options) : countdown,
                         font: quotaCountdownFont(options),
                         foreground: foreground, in: frame, alignment: 1)
            }
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = descriptor.accessibilityLabel
        return image
    }

    private static func makeSymbol(_ name: String, options: DisplayOptions, foreground: NSColor,
                                   pointSize: Double? = nil) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize ?? options.normalizedFontSize, weight: .semibold)
        let configured = base.withSymbolConfiguration(configuration) ?? base
        return NSImage(size: configured.size, flipped: false) { rect in
            configured.draw(in: rect)
            foreground.setFill()
            rect.fill(using: .sourceIn)
            return true
        }
    }

    private static func stackedValue(_ value: String, label text: String, descriptor: MenuBarItem, options: DisplayOptions,
                                     foreground: NSColor, background: NSColor?, template: Bool,
                                     reservedSize: NSSize? = nil) -> NSImage {
        if descriptor.metric != .tps {
            return stackedSystem(value, label: text, descriptor: descriptor, options: options,
                                 foreground: foreground, background: background, template: template, reservedSize: reservedSize)
        }
        let valueSize = min(17, max(11, options.normalizedFontSize + 1))
        let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        let number = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [
            .font: makeFont(options, size: valueSize), colorKey: foreground.cgColor
        ]) as CFAttributedString)
        let label = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 7, weight: .semibold), colorKey: foreground.cgColor
        ]) as CFAttributedString)
        let numberBounds = CTLineGetImageBounds(number, nil)
        let labelBounds = text.isEmpty ? .zero : CTLineGetImageBounds(label, nil)
        let gap: CGFloat = text.isEmpty ? 0 : 1.5
        let contentHeight = numberBounds.height + labelBounds.height + gap
        let symbol = descriptor.symbolName.flatMap { makeSymbol($0, options: options, foreground: foreground) }
        let symbolWidth = symbol.map { $0.size.width + symbolGap(options) } ?? 0
        let padding = tpsHorizontalPadding(options)
        let size = reservedSize ?? NSSize(width: ceil(max(numberBounds.width, labelBounds.width) + symbolWidth + padding * 2),
                                         height: max(20, ceil(max(contentHeight, symbol?.size.height ?? 0) + 4)))
        let image = NSImage(size: size, flipped: false) { rect in
            if let background {
                background.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            }
            if let symbol {
                symbol.draw(at: NSPoint(x: padding, y: (size.height - symbol.size.height) / 2),
                            from: .zero, operation: .sourceOver, fraction: 1)
            }
            let numberFont = makeFont(options, size: valueSize)
            let reference = CTLineCreateWithAttributedString(NSAttributedString(
                string: "999.9", attributes: [.font: numberFont]))
            let numberHeight = max(numberFont.capHeight, CTLineGetImageBounds(reference, nil).height)
            let labelHeight = text.isEmpty ? 0 : max(labelBounds.height, NSFont.systemFont(ofSize: 7, weight: .semibold).capHeight)
            let bottom = (size.height - numberHeight - labelHeight - gap) / 2
            let width = size.width - symbolWidth - padding * 2
            drawText(value, font: makeFont(options, size: valueSize), foreground: foreground,
                     in: NSRect(x: padding + symbolWidth, y: bottom, width: width, height: numberHeight), alignment: 0.5)
            if !text.isEmpty {
                drawText(text, font: NSFont.systemFont(ofSize: 7, weight: .semibold), foreground: foreground,
                         in: NSRect(x: padding + symbolWidth, y: bottom + numberHeight + gap,
                                    width: width, height: labelHeight), alignment: 0.5)
            }
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = descriptor.accessibilityLabel
        return image
    }

    private static func stackedNetwork(_ descriptor: MenuBarItem, options: DisplayOptions,
                                        foreground: NSColor, background: NSColor?, template: Bool,
                                        reservedSize: NSSize? = nil) -> NSImage? {
        let values = [("arrow.up", descriptor.networkUploadValue), ("arrow.down", descriptor.networkDownloadValue)]
            .compactMap { symbol, value in value.map { (symbol, $0) } }
        guard !values.isEmpty else { return nil }
        let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        let font = makeFont(options, size: min(10, max(8, options.normalizedFontSize - 2)))
        let rows = values.map { symbol, value in
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [
                .font: font, colorKey: foreground.cgColor
            ]) as CFAttributedString)
            return (line: line, bounds: CTLineGetImageBounds(line, nil),
                    symbol: makeSymbol(symbol, options: options, foreground: foreground, pointSize: 7))
        }
        let reference = CTLineCreateWithAttributedString(NSAttributedString(string: "99.9 MB/s", attributes: [.font: font]))
        let rowHeight = max(CTLineGetImageBounds(reference, nil).height, rows.compactMap { $0.symbol?.size.height }.max() ?? 0)
        let symbolWidth = rows.compactMap { $0.symbol?.size.width }.max() ?? 0
        let textWidth = rows.map { $0.bounds.width }.max() ?? 0
        let gap: CGFloat = 1.5
        let padding = horizontalPadding(options)
        let symbolGap: CGFloat = symbolWidth > 0 ? 2 : 0
        let contentHeight = rowHeight * CGFloat(rows.count) + gap * CGFloat(rows.count - 1)
        let size = reservedSize ?? NSSize(width: ceil(padding * 2 + symbolWidth + symbolGap + textWidth),
                                         height: max(20, ceil(contentHeight + 3)))
        let image = NSImage(size: size, flipped: false) { rect in
            if let background {
                background.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            }
            let top = (size.height + contentHeight) / 2
            for (index, row) in rows.enumerated() {
                let bottom = top - rowHeight - CGFloat(index) * (rowHeight + gap)
                if let symbol = row.symbol {
                    symbol.draw(at: NSPoint(x: padding + (symbolWidth - symbol.size.width) / 2,
                                            y: bottom + (rowHeight - symbol.size.height) / 2),
                                from: .zero, operation: .sourceOver, fraction: 1)
                }
                drawText(values[index].1, font: font, foreground: foreground,
                         in: NSRect(x: padding + symbolWidth + symbolGap, y: bottom,
                                    width: size.width - padding * 2 - symbolWidth - symbolGap, height: rowHeight))
            }
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = descriptor.accessibilityLabel
        return image
    }

    private static func horizontalPadding(_ options: DisplayOptions) -> CGFloat {
        CGFloat(options.itemHorizontalPadding)
    }

    private static func tpsHorizontalPadding(_ options: DisplayOptions) -> CGFloat {
        options.spacing == .compact ? 2 : 4
    }

    private static func symbolGap(_ options: DisplayOptions) -> CGFloat {
        options.spacing == .compact ? 2 : 3
    }

    struct StackedSystemGeometry {
        let size: NSSize
        let upper: NSRect
        let number: NSRect
        let digits: NSRect?
        let label: NSRect
        let symbol: NSRect?
    }

    static func stackedSystemGeometry(value: String, label: String, symbolSize: NSSize?, options: DisplayOptions,
                                      reservedSize: NSSize? = nil, alignLabelToDigits: Bool = false) -> StackedSystemGeometry {
        let numberFont = makeFont(options, size: min(15, max(10, options.normalizedFontSize + 1)))
        let labelFont = NSFont.systemFont(ofSize: 7, weight: .semibold)
        func bounds(_ text: String, font: NSFont) -> CGRect {
            CTLineGetImageBounds(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font])), nil)
        }
        let number = bounds(value, font: numberFont)
        let numberHeight = max(numberFont.capHeight, bounds("100%", font: numberFont).height)
        let text = bounds(label, font: labelFont)
        let upperHeight = max(text.height, symbolSize?.height ?? 0)
        let gap: CGFloat = symbolSize == nil ? 0 : 2
        let upperWidth = text.width + (symbolSize?.width ?? 0) + gap
        let contentHeight = upperHeight + numberHeight + 1.5
        if alignLabelToDigits {
            let capacity = bounds("100%", font: numberFont)
            let capacityDigits = bounds("100", font: numberFont)
            let leftExtent = max(capacityDigits.midX - capacity.minX, text.width / 2 + (symbolSize?.width ?? 0) + gap)
            let rightExtent = max(capacity.maxX - capacityDigits.midX, text.width / 2)
            let size = reservedSize ?? NSSize(width: max(20, ceil(leftExtent + rightExtent + horizontalPadding(options) * 2)),
                                             height: max(20, ceil(contentHeight + 3)))
            let center = (size.width + leftExtent - rightExtent) / 2
            let bottom = (size.height - contentHeight) / 2
            let labelRect = NSRect(x: center - text.width / 2, y: bottom + numberHeight + 1.5 + (upperHeight - text.height) / 2,
                                   width: text.width, height: text.height)
            let upper = NSRect(x: labelRect.minX - (symbolSize?.width ?? 0) - gap, y: bottom + numberHeight + 1.5,
                               width: upperWidth, height: upperHeight)
            let digits = bounds(value.hasSuffix("%") ? String(value.dropLast()) : value, font: numberFont)
            // Keep the shaped percentage intact while centering the label over the numeric glyphs alone.
            let numberStart = center - (digits.midX - number.minX)
            return StackedSystemGeometry(size: size, upper: upper,
                number: NSRect(x: numberStart, y: bottom, width: number.width, height: numberHeight),
                digits: NSRect(x: center - digits.width / 2, y: bottom, width: digits.width, height: numberHeight),
                label: labelRect, symbol: symbolSize.map {
                    NSRect(x: upper.minX, y: upper.midY - $0.height / 2, width: $0.width, height: $0.height)
                })
        }
        let size = reservedSize ?? NSSize(width: max(20, ceil(max(upperWidth, number.width) + horizontalPadding(options) * 2)),
                                         height: max(20, ceil(contentHeight + 3)))
        let bottom = (size.height - contentHeight) / 2
        let upper = NSRect(x: (size.width - upperWidth) / 2, y: bottom + numberHeight + 1.5,
                           width: upperWidth, height: upperHeight)
        let symbol = symbolSize.map {
            NSRect(x: upper.minX, y: upper.midY - $0.height / 2, width: $0.width, height: $0.height)
        }
        return StackedSystemGeometry(size: size, upper: upper,
            number: NSRect(x: horizontalPadding(options), y: bottom,
                           width: size.width - horizontalPadding(options) * 2, height: numberHeight),
            digits: nil,
            label: NSRect(x: upper.minX + (symbolSize?.width ?? 0) + gap,
                          y: upper.midY - text.height / 2, width: text.width, height: text.height), symbol: symbol)
    }

    private static func stackedSystem(_ value: String, label: String, descriptor: MenuBarItem, options: DisplayOptions,
                                      foreground: NSColor, background: NSColor?, template: Bool, reservedSize: NSSize?) -> NSImage {
        let symbol = descriptor.symbolName.flatMap { makeSymbol($0, options: options, foreground: foreground, pointSize: 7) }
        let geometry = stackedSystemGeometry(value: value, label: label, symbolSize: symbol?.size,
                                              options: options, reservedSize: reservedSize, alignLabelToDigits: descriptor.metric == .ram)
        let image = NSImage(size: geometry.size, flipped: false) { rect in
            if let background {
                background.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            }
            if let symbol, let frame = geometry.symbol { symbol.draw(in: frame) }
            drawText(label, font: NSFont.systemFont(ofSize: 7, weight: .semibold), foreground: foreground,
                     in: geometry.label, alignment: 0.5)
            drawText(value, font: makeFont(options, size: min(15, max(10, options.normalizedFontSize + 1))),
                     foreground: foreground, in: geometry.number, alignment: 0.5)
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = descriptor.accessibilityLabel
        return image
    }

    static func textLine(_ text: String, font: NSFont, foreground: NSColor, availableWidth: CGFloat) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): foreground.cgColor
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        // Drawing aligns the ink bounds; advance widths also include unused side bearings.
        if CTLineGetImageBounds(line, nil).width > availableWidth {
            let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
            return CTLineCreateTruncatedLine(line, availableWidth, .middle, ellipsis) ?? ellipsis
        }
        return line
    }

    private static func drawText(_ text: String, font: NSFont, foreground: NSColor,
                                 in rect: NSRect, alignment: CGFloat = 0) {
        guard rect.width > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        let line = textLine(text, font: font, foreground: foreground, availableWidth: rect.width)
        let bounds = CTLineGetImageBounds(line, nil)
        context.saveGState()
        context.clip(to: rect.insetBy(dx: 0, dy: -1))
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: rect.minX + (rect.width - bounds.width) * alignment - bounds.minX,
                                       y: rect.midY - bounds.midY)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static let blackGPTLogo = loadLogo(named: "OpenAIBlossomBlack")
    private static let whiteGPTLogo = loadLogo(named: "OpenAIBlossomWhite")

    private static func gptLogo(white: Bool) -> NSImage? {
        white ? whiteGPTLogo : blackGPTLogo
    }

    private static func loadLogo(named name: String) -> NSImage? {
        // Prefer packaged resources so a moved .app never depends on the build directory.
        if let url = Bundle.main.url(forResource: name, withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        if let url = Bundle.main.url(forResource: "CodexMeter_CodexMeterApp", withExtension: "bundle"),
           let bundle = Bundle(url: url), let imageURL = bundle.url(forResource: name, withExtension: "png") {
            return NSImage(contentsOf: imageURL)
        }
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: name, withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        #endif
        return nil
    }

    private static func makeFont(_ options: DisplayOptions, size: Double? = nil) -> NSFont {
        let weight: NSFont.Weight
        switch options.fontWeight {
        case .regular: weight = .regular
        case .medium: weight = .medium
        case .semibold: weight = .semibold
        }
        let size = size ?? options.normalizedFontSize
        if options.fontDesign == .monospaced { return NSFont.monospacedSystemFont(ofSize: size, weight: weight) }
        let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        if options.fontDesign == .rounded, let descriptor = base.fontDescriptor.withDesign(.rounded),
           let rounded = NSFont(descriptor: descriptor, size: size) { return rounded }
        return base
    }

    private static func accentColor(_ style: MenuBarColorStyle, remaining: Double?) -> NSColor? {
        if style != .monochrome, let remaining {
            if remaining <= 10 { return NSColor(srgbRed: 0.70, green: 0.08, blue: 0.12, alpha: 1) }
            if remaining <= 20 { return NSColor(srgbRed: 0.60, green: 0.25, blue: 0.02, alpha: 1) }
        }
        switch style {
        case .adaptive, .monochrome: return nil
        case .blue: return NSColor(srgbRed: 0.08, green: 0.30, blue: 0.70, alpha: 1)
        case .teal: return NSColor(srgbRed: 0.02, green: 0.35, blue: 0.36, alpha: 1)
        case .purple: return NSColor(srgbRed: 0.38, green: 0.20, blue: 0.65, alpha: 1)
        }
    }
}
