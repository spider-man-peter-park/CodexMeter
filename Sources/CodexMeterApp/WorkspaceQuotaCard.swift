import CodexMeterCore
import SwiftUI

struct WorkspaceQuotaCard: View {
    let title: String
    let symbol: String
    let window: QuotaWindow?
    let now: Date
    let hasQuota: Bool
    let action: () -> Void

    private var value: String {
        guard let window else { return "—" }
        let rounded = Int(window.remainingPercent.rounded())
        return window.remainingPercent > 0 && rounded == 0 ? "<1" : String(rounded)
    }

    private var tint: Color {
        guard let window else { return .secondary }
        if window.remainingPercent <= 10 { return .red }
        if window.remainingPercent <= 20 { return .orange }
        return .accentColor
    }

    var body: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(title, systemImage: symbol).font(MeterStyle.sectionFont)
                        .accessibilityLabel(title)
                    Spacer(minLength: 4)
                    Button(title, systemImage: "arrow.up.right", action: action)
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                        .help(title)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(.system(size: 44, weight: .medium)).monospacedDigit()
                    if window != nil {
                        Text("%").font(.system(size: 20, weight: .medium)).foregroundStyle(.secondary)
                        Text(L10n.text("left")).font(MeterStyle.captionFont).foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle((window?.remainingPercent ?? 100) <= 10 ? tint : Color.primary)
                ProgressView(value: window?.remainingPercent ?? 0, total: 100)
                    .tint(tint)
                    .accessibilityLabel(title)
                    .accessibilityValue(window.map { _ in L10n.text("\(value) percent remaining") } ?? L10n.text("Not reported"))
                Text(window == nil
                     ? (hasQuota ? L10n.text("This account has no reported window") : L10n.text("Waiting for quota data"))
                     : L10n.text("Resets in \(MenuBarFormatter.countdown(until: window?.resetsAt, now: now, style: .compact))"))
                    .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 144, alignment: .topLeading)
        }
    }
}
