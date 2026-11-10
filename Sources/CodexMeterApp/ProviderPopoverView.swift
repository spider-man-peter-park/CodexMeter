import CodexMeterCore
import SwiftUI

struct ProviderPopoverView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var usage: AssistantUsageStore
    let onOpenWorkspace: (WorkspaceDestination) -> Void
    let onOpenSettings: () -> Void
    let onOpenAbout: () -> Void

    var body: some View {
        if model.provider == .codex {
            FocusPopoverView(model: model, onOpenWorkspace: onOpenWorkspace,
                onOpenSettings: onOpenSettings, onOpenAbout: onOpenAbout)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    ProviderPicker(selection: $model.provider).labelsHidden()
                    Spacer()
                    MeterIconButton(symbol: "gearshape", title: L10n.text("Settings"), action: onOpenSettings)
                }
                ProviderUsageView(model: model, usage: usage, compact: true)
                Button { onOpenWorkspace(.overview) } label: {
                    Label(L10n.text("Open workspace"), systemImage: "sidebar.left").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                Button(L10n.text("Refresh"), systemImage: "arrow.clockwise") { model.refresh() }
                    .buttonStyle(.borderless)
            }
            .padding(20).frame(width: 392)
            .background(MeterStyle.background)
        }
    }
}
