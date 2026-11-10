import CodexMeterCore
import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: AppUpdates
    @ObservedObject var usage: AssistantUsageStore
    @ObservedObject var navigation: WorkspaceNavigation
    var onOpenSettings: () -> Void = {}
    var onOpenAbout: () -> Void = {}

    private var selection: Binding<WorkspaceDestination?> {
        Binding(get: { navigation.destination }, set: { value in
            if let value { navigation.destination = value }
        })
    }

    var body: some View {
        GeometryReader { geometry in
            splitView.frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(minWidth: 760, idealWidth: 940, minHeight: 500, idealHeight: 700)
        .environment(\.locale, L10n.locale)
        .id(model.language)
    }

    private var splitView: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                WorkspaceBrand()
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("Assistant"))
                        .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                    ProviderPicker(selection: $model.provider).labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14).padding(.bottom, 12)
                List(selection: selection) {
                    WorkspaceNavigationRow(destination: .overview)
                    if model.provider == .codex {
                        Section(L10n.text("Codex")) {
                            ForEach(WorkspaceDestination.codexSections) { section in
                                WorkspaceNavigationRow(destination: .detail(section))
                            }
                        }
                    }
                    Section(L10n.text("This Mac")) {
                        ForEach(WorkspaceDestination.systemSections) { section in
                            WorkspaceNavigationRow(destination: .detail(section))
                        }
                    }
                }
                .listStyle(.sidebar)
                Divider()
                Button(action: onOpenSettings) {
                    Label(L10n.text("Settings"), systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 14)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(",", modifiers: .command)
            }
            .frame(width: 192)
            .frame(maxHeight: .infinity)
            Divider()
            VStack(spacing: 0) {
                WorkspaceHeader(destination: navigation.destination,
                    refreshing: model.provider == .codex ? (model.refreshing || model.accountRefreshing)
                        : usage.result(for: model.provider).status == .loading,
                    refresh: model.refresh, onOpenSettings: onOpenSettings, onOpenAbout: onOpenAbout)
                Divider()
                ScrollView {
                    Group {
                        switch navigation.destination {
                        case .overview where model.provider != .codex:
                            ProviderUsageView(model: model, usage: usage)
                        case .overview:
                            WorkspaceOverviewView(model: model, navigate: navigate)
                        case .detail(let section):
                            MetricDetailContent(model: model, updates: updates, section: section)
                                .frame(maxWidth: 820, alignment: .leading)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .id(navigation.destination.id + model.provider.rawValue)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MeterStyle.background)
                if updates.updateAvailable, let version = updates.latestVersion {
                    Divider()
                    Link(L10n.text("CodexMeter \(version.description) is available"), destination: AppMetadata.projectURL)
                        .font(MeterStyle.captionFont)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func navigate(_ destination: WorkspaceDestination) {
        navigation.destination = destination
    }
}
