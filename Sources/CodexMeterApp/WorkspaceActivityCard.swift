import SwiftUI

struct WorkspaceActivityCard: View {
    let title: String
    let symbol: String
    let value: String
    let unit: String
    let note: String
    let warning: String?
    let action: () -> Void

    var body: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(title, systemImage: symbol).font(MeterStyle.sectionFont)
                        .accessibilityLabel(title)
                    Spacer(minLength: 4)
                    Button(title, systemImage: "arrow.up.right", action: action)
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                        .help(title)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value).font(.system(size: 30, weight: .medium)).monospacedDigit()
                    Text(unit).font(MeterStyle.captionFont).foregroundStyle(.secondary)
                }
                Text(note).font(MeterStyle.captionFont).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let warning {
                    Label(warning, systemImage: "exclamationmark.circle")
                        .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                        .accessibilityLabel(warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minHeight: 132, alignment: .topLeading)
        }
    }
}
