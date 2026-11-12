import CodexMeterCore
import SwiftUI

struct WorkspaceOverviewView: View {
    @ObservedObject var model: AppModel
    let navigate: (WorkspaceDestination) -> Void

    private var summary: FocusSummary {
        FocusSummary(quota: model.quota, warning: model.quotaWarning,
            automaticRefresh: model.autoRefresh, now: model.now, refreshInterval: model.refreshOptions.quotaInterval)
    }

    private var localTotal: String {
        TokenCountFormatter.compact(model.localDayUsage?.displayTotal(at: model.now))
    }

    private var localWarning: String? {
        guard let usage = model.localDayUsage, usage.matches(model.now) else { return L10n.text("Waiting for today's local log refresh…") }
        if usage.isBackfilling { return L10n.text("Backfilling today's logs…") }
        if usage.isPartial { return L10n.text("Partial estimate") }
        if !usage.logsAvailable { return L10n.text("Local logs are unavailable") }
        return nil
    }

    private var responseValue: String {
        model.sample.map { String(format: "%.1f", $0.tokensPerSecond) } ?? "—"
    }

    private var responseNote: String {
        guard let sample = model.sample else { return L10n.text("Waiting for a completed response") }
        return L10n.text("Estimated · \(sample.completedAt.formatted(.dateTime.hour().minute().locale(L10n.locale)))")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkspaceFocusSummary(summary: summary)
            HStack(alignment: .top, spacing: 16) {
                if model.fiveHourAvailable != false || model.quota?.fiveHour != nil {
                    WorkspaceQuotaCard(title: L10n.text("5-hour quota"), symbol: "clock",
                        window: model.quota?.fiveHour, now: model.now, hasQuota: model.quota != nil,
                        action: openQuota)
                }
                WorkspaceQuotaCard(title: L10n.text("7-day quota"), symbol: "calendar",
                    window: model.quota?.weekly, now: model.now, hasQuota: model.quota != nil,
                    action: openQuota)
            }
            HStack(alignment: .top, spacing: 16) {
                WorkspaceActivityCard(title: L10n.text("Today · this Mac"), symbol: "square.stack.3d.up",
                    value: localTotal, unit: L10n.text("tokens"),
                    note: L10n.text("Local estimate · Desktop records"), warning: localWarning,
                    action: openToday)
                WorkspaceActivityCard(title: L10n.text("Latest response"), symbol: "bolt",
                    value: responseValue, unit: "TPS", note: responseNote,
                    warning: model.latestUnmeasurable ? L10n.text("Showing the last response with reliable timing") : nil,
                    action: openResponses)
            }
            if let series = model.recentTokenUsage {
                WorkspaceCard {
                    if model.accountInfo?.isStale == true || model.accountWarning != nil {
                        MeterStatusLabel(title: L10n.text("Cached account data"), symbol: "clock.badge.exclamationmark")
                            .padding(.bottom, 8)
                    }
                    TokenUsageChart(series: series)
                    if let info = model.accountInfo {
                        Text(L10n.text("Usage updated \(info.updatedAt.formatted(.dateTime.month().day().hour().minute().locale(L10n.locale)))"))
                            .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                    }
                    Divider().padding(.vertical, 10)
                    HStack(alignment: .top, spacing: 16) {
                        Text(L10n.text("Account-wide totals. Reported dates may lag behind this Mac's local day."))
                            .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button(L10n.text("View usage"), systemImage: "arrow.right", action: openUsage)
                            .buttonStyle(.borderless).fixedSize()
                    }
                }
            }
            WorkspaceSystemStrip(snapshot: model.currentSystemMetrics, navigate: navigate)
        }
        .frame(maxWidth: 960, alignment: .leading)
    }

    private func openQuota() { navigate(.detail(.quota)) }
    private func openToday() { openUsage() }
    private func openResponses() { navigate(.detail(.speed)) }
    private func openUsage() { navigate(.usage) }
}
