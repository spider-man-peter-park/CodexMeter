import AppKit
import CodexMeterCore
import SwiftUI

struct FocusPopoverView: View {
    @ObservedObject var model: AppModel
    let onOpenWorkspace: (WorkspaceDestination) -> Void
    let onOpenSettings: () -> Void
    let onOpenAbout: () -> Void

    private var summary: FocusSummary {
        FocusSummary(quota: model.quota, warning: model.quotaWarning,
            automaticRefresh: model.autoRefresh, now: model.now,
            refreshInterval: model.refreshOptions.quotaInterval)
    }

    private var tint: Color {
        switch summary.state {
        case .low, .exhausted: .orange
        case .ready: .accentColor
        default: .secondary
        }
    }

    private var localTotal: String {
        guard let usage = model.localDayUsage, let total = usage.displayTotal(at: model.now) else { return "—" }
        return TokenCountFormatter.compact(total) + (usage.isPartial ? " ≈" : "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 18)).foregroundStyle(Color.accentColor).accessibilityHidden(true)
                ProviderPicker(selection: $model.provider).labelsHidden()
                Spacer()
                MeterIconButton(symbol: "gearshape", title: L10n.text("Settings"), action: onOpenSettings)
                Menu(L10n.text("More actions"), systemImage: "ellipsis") {
                    Button(L10n.text("About CodexMeter"), action: onOpenAbout)
                    Divider()
                    Button(L10n.text("Quit CodexMeter")) { NSApp.terminate(nil) }
                }
                .labelStyle(.iconOnly).menuStyle(.borderlessButton).menuIndicator(.hidden)
                .frame(width: 20).help(L10n.text("More actions"))
            }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: summary.symbolName)
                    .font(.system(size: 21, weight: .medium)).foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(summary.title).font(.system(size: 21, weight: .semibold))
                    Text(summary.message).font(MeterStyle.bodyFont).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                if model.fiveHourAvailable != false || model.quota?.fiveHour != nil {
                    quotaCard(L10n.text("5-hour quota"), window: model.quota?.fiveHour)
                }
                quotaCard(L10n.text("7-day quota"), window: model.quota?.weekly)
            }
            HStack(spacing: 16) {
                activity(L10n.text("Today · this Mac"), value: localTotal,
                    note: localQuality)
                Divider().frame(height: 28)
                activity(model.latestUnmeasurable ? L10n.text("Last valid response") : L10n.text("Latest response"), value: model.sample.map {
                    String(format: "≈ %.0f TPS", $0.tokensPerSecond)
                } ?? "—", note: model.sample.map {
                    $0.completedAt.formatted(.dateTime.hour().minute().locale(L10n.locale))
                })
            }
            .padding(.vertical, 2)
            Button { onOpenWorkspace(.overview) } label: {
                Label(L10n.text("Open workspace"), systemImage: "sidebar.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            HStack {
                if let updatedAt = summary.updatedAt {
                    Text(L10n.text("Quota updated: \(updatedAt.formatted(.dateTime.hour().minute().locale(L10n.locale)))"))
                } else {
                    Text(L10n.text("Waiting for Codex"))
                }
                Spacer()
                MeterIconButton(symbol: "arrow.clockwise", title: L10n.text("Refresh")) { model.refresh() }
                    .disabled(model.refreshing || model.accountRefreshing)
            }
            .font(MeterStyle.captionFont).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 392)
        .background(MeterStyle.background)
        .environment(\.locale, L10n.locale)
        .id(model.language)
    }

    private func quotaCard(_ title: String, window: QuotaWindow?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(MeterStyle.captionFont).foregroundStyle(.secondary)
            Text(window.map { $0.remainingPercent > 0 && $0.remainingPercent < 0.5
                ? "<1%" : String(format: "%.0f%%", $0.remainingPercent) } ?? "—")
                .font(.system(size: 32, weight: .medium)).monospacedDigit()
            ProgressView(value: window?.remainingPercent ?? 0, total: 100)
                .tint((window?.remainingPercent ?? 100) <= 10 ? .orange : .accentColor)
                .accessibilityLabel(title)
                .accessibilityValue(window.map { $0.remainingPercent > 0 && $0.remainingPercent < 0.5
                    ? L10n.text("Less than 1 percent remaining")
                    : L10n.text("\(Int($0.remainingPercent.rounded())) percent remaining") }
                    ?? L10n.text("Unavailable"))
            Text(window?.resetsAt.map {
                L10n.text("Resets \(MenuBarFormatter.countdown(until: $0, now: model.now, style: .compact))")
            } ?? L10n.text("Reset time unavailable"))
                .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                .lineLimit(2).frame(minHeight: 26, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(MeterStyle.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var localQuality: String {
        if model.localDayUsage?.isBackfilling == true { return L10n.text("Backfilling today's logs…") }
        if model.localDayUsage?.isPartial == true { return L10n.text("Partial estimate") }
        return L10n.text("Local estimate")
    }

    private func activity(_ title: String, value: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(MeterStyle.captionFont).foregroundStyle(.secondary)
            Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit()
            if let note { Text(note).font(MeterStyle.captionFont).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
