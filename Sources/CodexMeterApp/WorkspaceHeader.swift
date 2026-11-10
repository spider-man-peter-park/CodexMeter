import CodexMeterCore
import SwiftUI

struct WorkspaceHeader: View {
    let destination: WorkspaceDestination
    let refreshing: Bool
    let refresh: () -> Void
    let onOpenSettings: () -> Void
    let onOpenAbout: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(destination.title).font(.system(size: 26, weight: .semibold))
                Text(destination.subtitle)
                    .font(MeterStyle.bodyFont).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if refreshing { ProgressView().controlSize(.small) }
            Button(L10n.text("Refresh"), systemImage: "arrow.clockwise", action: refresh)
                .disabled(refreshing)
                .keyboardShortcut("r", modifiers: .command)
            Menu(L10n.text("More"), systemImage: "ellipsis.circle") {
                Button(L10n.text("Settings…"), action: onOpenSettings)
                Button(L10n.text("About CodexMeter"), action: onOpenAbout)
            }
            .menuStyle(.borderlessButton)
            .labelStyle(.iconOnly)
            .fixedSize()
        }
        .padding(.horizontal, 28).padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MeterStyle.background)
    }
}
