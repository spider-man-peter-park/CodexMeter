import AppKit
import CodexMeterCore
import SwiftUI

enum MeterStyle {
    static let pageInset: CGFloat = 20
    static let sectionGap: CGFloat = 16
    static let contentGap: CGFloat = 12
    static let controlHeight: CGFloat = 28
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let rule = Color(nsColor: .separatorColor)
    static let bodyFont = Font.system(size: 13)
    static let captionFont = Font.system(size: 11)
    static let sectionFont = Font.system(size: 12, weight: .semibold)
    static let titleFont = Font.system(size: 15, weight: .semibold)
    static let paneTitleFont = Font.system(size: 20, weight: .semibold)
    static let numberFont = Font.system(size: 28, weight: .medium)
}

struct MeterIconButton: View {
    let symbol: String
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .regular))
                .frame(width: MeterStyle.controlHeight, height: MeterStyle.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless).help(title).accessibilityLabel(title)
    }
}

struct MeterFontStepper: View {
    @Binding var value: Double
    private var normalized: Double { value.isFinite ? min(16, max(9, value)) : 12 }

    var body: some View {
        HStack(spacing: 6) {
            Button { value = max(9, normalized - 1) } label: {
                Image(systemName: "minus").font(.system(size: 11, weight: .medium))
                    .frame(width: 12, height: 14)
            }
            .disabled(normalized <= 9)
            .help(L10n.text("Decrease font size"))
            .accessibilityLabel(L10n.text("Decrease font size"))
            Button { value = min(16, normalized + 1) } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .medium))
                    .frame(width: 12, height: 14)
            }
            .disabled(normalized >= 16)
            .help(L10n.text("Increase font size"))
            .accessibilityLabel(L10n.text("Increase font size"))
        }
        .buttonStyle(.bordered).controlSize(.small).buttonRepeatBehavior(.enabled)
    }
}

struct MeterStatusLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(.orange).accessibilityHidden(true)
            Text(title).foregroundStyle(.primary)
        }
        .font(MeterStyle.captionFont).accessibilityElement(children: .combine)
    }
}
