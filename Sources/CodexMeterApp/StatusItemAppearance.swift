import AppKit
import CodexMeterCore

@MainActor
enum StatusItemAppearance {
    static func apply(_ descriptor: MenuBarItem, to item: NSStatusItem,
                      options: DisplayOptions, window: QuotaWindow?) {
        guard let button = item.button else { return }
        let font = makeFont(options)
        let color = makeColor(options.colorStyle, remaining: window?.remainingPercent)
        let title = NSMutableAttributedString(string: descriptor.title, attributes: [
            .font: font, .foregroundColor: color
        ])
        button.font = font
        button.attributedTitle = title
        button.contentTintColor = color
        if let symbol = descriptor.symbolName,
           let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let configuration = NSImage.SymbolConfiguration(pointSize: options.normalizedFontSize, weight: .medium)
            let image = base.withSymbolConfiguration(configuration) ?? base
            image.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
        } else {
            button.image = nil
            button.imagePosition = .noImage
        }
        let imageWidth = button.image == nil ? 0 : options.normalizedFontSize + 5
        item.length = max(22, ceil(title.size().width + imageWidth + options.itemHorizontalPadding * 2))
        button.wantsLayer = true
        if options.itemStyle == .capsule {
            button.effectiveAppearance.performAsCurrentDrawingAppearance {
                button.layer?.backgroundColor = color.withAlphaComponent(0.11).cgColor
                button.layer?.borderColor = color.withAlphaComponent(0.18).cgColor
            }
            button.layer?.borderWidth = 0.5
            button.layer?.cornerRadius = 8
        } else {
            button.layer?.backgroundColor = nil
            button.layer?.borderColor = nil
            button.layer?.borderWidth = 0
            button.layer?.cornerRadius = 0
        }
    }

    private static func makeFont(_ options: DisplayOptions) -> NSFont {
        let weight: NSFont.Weight
        switch options.fontWeight {
        case .regular: weight = .regular
        case .medium: weight = .medium
        case .semibold: weight = .semibold
        }
        let size = options.normalizedFontSize
        if options.fontDesign == .monospaced { return NSFont.monospacedSystemFont(ofSize: size, weight: weight) }
        let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        if options.fontDesign == .rounded, let descriptor = base.fontDescriptor.withDesign(.rounded),
           let rounded = NSFont(descriptor: descriptor, size: size) { return rounded }
        return base
    }

    private static func makeColor(_ style: MenuBarColorStyle, remaining: Double?) -> NSColor {
        if style != .monochrome, let remaining {
            if remaining <= 10 { return .systemRed }
            if remaining <= 20 { return .systemOrange }
        }
        switch style {
        case .adaptive, .monochrome: return .labelColor
        case .blue: return .systemBlue
        case .teal: return .systemTeal
        case .purple: return .systemPurple
        }
    }
}
