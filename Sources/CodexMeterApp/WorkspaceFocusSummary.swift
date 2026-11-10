import CodexMeterCore
import SwiftUI

struct WorkspaceFocusSummary: View {
    let summary: FocusSummary

    private var symbol: String {
        switch summary.state {
        case .ready: "checkmark.circle"
        case .low: "exclamationmark.circle"
        case .exhausted: "pause.circle"
        case .cached: "clock.arrow.circlepath"
        case .paused: "pause.circle"
        case .unavailable: "circle.dashed"
        }
    }

    private var tint: Color {
        switch summary.state {
        case .ready: .accentColor
        case .low: .orange
        case .exhausted: .red
        case .cached, .paused, .unavailable: .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .light)).foregroundStyle(tint)
                .frame(width: 44).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(summary.title).font(.system(size: 24, weight: .semibold))
                Text(summary.message)
                    .font(MeterStyle.bodyFont).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let date = summary.updatedAt {
                    Text(L10n.text("Quota updated \(date.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(L10n.locale)))"))
                        .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
