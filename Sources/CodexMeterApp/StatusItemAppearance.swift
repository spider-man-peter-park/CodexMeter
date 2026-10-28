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
        // Template content lets the menu bar choose its own foreground in every native state.
        // Filled badges include their opaque background in the image, outside glass-layer compositing.
        button.attributedTitle = NSAttributedString(string: "")
        button.title = ""
        button.contentTintColor = nil
        button.image = image
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.appearsDisabled = false
        button.alphaValue = 1
        item.length = image.size.width + 2
    }

    static func makeImage(_ descriptor: MenuBarItem, options: DisplayOptions,
                          remaining: Double?, appearance: NSAppearance, isActive: Bool = false) -> NSImage {
        let font = makeFont(options)
        let capsule = options.itemStyle == .capsule || (options.itemStyle == .activeCapsule && isActive)
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let accent = accentColor(options.colorStyle, remaining: remaining)
        let template = !capsule && accent == nil
        let plainAccent = dark ? accent?.blended(withFraction: 0.6, of: .white) : accent
        let background: NSColor? = capsule ? (accent ?? (dark ? .white : .black)) : nil
        let foreground: NSColor = capsule ? (accent == nil && dark ? .black : .white) : (plainAccent ?? .black)
        if descriptor.metric == .tps, options.tpsLayout == .stacked, let value = descriptor.tpsValue {
            return stackedTPS(value, descriptor: descriptor, options: options, foreground: foreground,
                              background: background, template: template)
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
        } else if let symbol = descriptor.symbolName,
           let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let configuration = NSImage.SymbolConfiguration(pointSize: options.normalizedFontSize, weight: .semibold)
            let configured = base.withSymbolConfiguration(configuration) ?? base
            let tinted = NSImage(size: configured.size, flipped: false) { rect in
                configured.draw(in: rect)
                foreground.setFill()
                rect.fill(using: .sourceIn)
                return true
            }
            symbolImage = tinted
        }
        let padding = max(capsule ? 6 : 3, options.itemHorizontalPadding)
        let symbolWidth = symbolImage.map { $0.size.width + 4 } ?? 0
        let titleSize = title.size()
        let size = NSSize(width: max(20, ceil(titleSize.width + symbolWidth + padding * 2)),
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
            title.draw(at: NSPoint(x: padding + symbolWidth, y: (size.height - titleSize.height) / 2))
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = descriptor.accessibilityLabel
        return image
    }

    private static func stackedTPS(_ value: String, descriptor: MenuBarItem, options: DisplayOptions,
                                   foreground: NSColor, background: NSColor?, template: Bool) -> NSImage {
        let valueSize = min(17, max(11, options.normalizedFontSize + 1))
        let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        let number = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [
            .font: makeFont(options, size: valueSize), colorKey: foreground.cgColor
        ]) as CFAttributedString)
        let label = CTLineCreateWithAttributedString(NSAttributedString(string: options.showTPSLabel ? "TPS" : "", attributes: [
            .font: NSFont.systemFont(ofSize: 7, weight: .semibold), colorKey: foreground.cgColor
        ]) as CFAttributedString)
        let numberBounds = CTLineGetImageBounds(number, nil)
        let labelBounds = options.showTPSLabel ? CTLineGetImageBounds(label, nil) : .zero
        let gap: CGFloat = options.showTPSLabel ? 1.5 : 0
        let contentHeight = numberBounds.height + labelBounds.height + gap
        let padding = max(6, options.itemHorizontalPadding)
        let size = NSSize(width: ceil(max(numberBounds.width, labelBounds.width) + padding * 2),
                          height: max(20, ceil(contentHeight + 4)))
        let image = NSImage(size: size, flipped: false) { rect in
            if let background {
                background.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            }
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.textMatrix = .identity
            let bottom = (size.height - contentHeight) / 2
            context.textPosition = CGPoint(x: (size.width - numberBounds.width) / 2 - numberBounds.minX,
                                           y: bottom - numberBounds.minY)
            CTLineDraw(number, context)
            if options.showTPSLabel {
                context.textPosition = CGPoint(x: (size.width - labelBounds.width) / 2 - labelBounds.minX,
                                               y: bottom + numberBounds.height + gap - labelBounds.minY)
                CTLineDraw(label, context)
            }
            context.restoreGState()
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = descriptor.accessibilityLabel
        return image
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
