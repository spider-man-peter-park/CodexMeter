import CodexMeterCore
import SwiftUI

struct ProviderUsageView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var usage: AssistantUsageStore
    var compact = false

    private var result: ProviderUsageResult { usage.result(for: model.provider) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 14 : 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    if result.status == .loading { ProgressView().controlSize(.small) }
                    Text(model.provider.title).font(.system(size: compact ? 22 : 28, weight: .semibold))
                }
                Text(L10n.lookup(result.message))
                    .font(MeterStyle.bodyFont).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.autoRefresh {
                    MeterStatusLabel(title: L10n.text("Automatic refresh paused"), symbol: "pause.circle")
                }
            }
            if let snapshot = result.snapshot {
                measurements(snapshot)
                if snapshot.isPartial {
                    MeterStatusLabel(title: L10n.text("Partial coverage"), symbol: "exclamationmark.triangle")
                }
                if let reset = snapshot.resetAt {
                    Text(L10n.text("Cycle resets \(reset.formatted(.dateTime.month().day().hour().minute().locale(L10n.locale)))"))
                        .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                }
                Text(L10n.text("Checked \(snapshot.sampledAt.formatted(.dateTime.hour().minute().locale(L10n.locale)))"))
                    .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                if !compact && !snapshot.sessions.isEmpty {
                    Divider()
                    Text(L10n.text("Recent local session checkpoints")).font(.system(size: 15, weight: .semibold))
                    LazyVStack(spacing: 0) {
                        ForEach(snapshot.sessions) { session in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L10n.text("Session \(String(session.id.prefix(8)))"))
                                    if let date = session.updatedAt {
                                        Text(date.formatted(.dateTime.month().day().hour().minute().locale(L10n.locale)))
                                            .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(TokenCountFormatter.compact(session.tokens) + " " + L10n.text("tokens"))
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 12)
                            Divider()
                        }
                    }
                }
            } else if result.status != .loading {
                Label(L10n.text("No verified usage data"), systemImage: "info.circle")
                    .font(MeterStyle.sectionFont)
                Button(L10n.text("Refresh")) { model.refresh() }.buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func measurements(_ snapshot: ProviderUsageSnapshot) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 145 : 180), spacing: 16)], spacing: 16) {
            if let percent = snapshot.usedPercent {
                measurement(L10n.text("Used allowance"), value: String(format: "%.1f%%", percent),
                    note: snapshot.periodLabel.map { L10n.lookup($0) })
            }
            if let amount = snapshot.costUSD {
                measurement(L10n.text("Used allowance (USD)"), value: amount.formatted(.currency(code: "USD")),
                    note: snapshot.limitUSD.map { L10n.text("Allowance \($0.formatted(.currency(code: "USD")))") })
            }
            if let total = snapshot.totalTokens {
                measurement(L10n.text("Local session tokens"), value: TokenCountFormatter.compact(total),
                    note: L10n.text("Cumulative · supported sessions"))
            }
            if let count = snapshot.sessionCount {
                measurement(L10n.text("Sessions"), value: count.formatted())
            }
            if !compact {
                if let input = snapshot.inputTokens { measurement(L10n.text("Input · including cache"), value: TokenCountFormatter.compact(input)) }
                if let output = snapshot.outputTokens { measurement(L10n.text("Output tokens"), value: TokenCountFormatter.compact(output)) }
                if let cached = snapshot.cachedInputTokens { measurement(L10n.text("Cache read tokens"), value: TokenCountFormatter.compact(cached)) }
                if let written = snapshot.cacheWriteTokens { measurement(L10n.text("Cache write tokens"), value: TokenCountFormatter.compact(written)) }
                if let count = snapshot.requestCount { measurement(L10n.text("Reported requests"), value: count.formatted()) }
                if let rate = snapshot.decodeTokensPerSecond {
                    measurement(L10n.text("Average decode speed"), value: String(format: "%.1f TPS", rate),
                        note: L10n.text("Weighted across supported sessions"))
                }
                if let seconds = snapshot.modelSeconds {
                    measurement(L10n.text("Cumulative model time"), value: String(format: "%.1f s", seconds))
                }
            }
        }
    }

    private func measurement(_ title: String, value: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(MeterStyle.captionFont).foregroundStyle(.secondary)
            Text(value).font(.system(size: compact ? 25 : 32, weight: .medium)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.75)
            if let note { Text(note).font(MeterStyle.captionFont).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(MeterStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
