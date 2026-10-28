import AppKit
import CodexMeterCore
import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.title2).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("CodexMeter").font(.headline)
                    Text("Codex, at a glance").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.refreshing { ProgressView().controlSize(.small) }
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(model.refreshing)
                    .help("Refresh quota and local responses")
                    .accessibilityLabel("Refresh")
            }
            VStack(spacing: 14) {
                quotaRow("5-hour limit", window: model.quota?.fiveHour)
                quotaRow("7-day limit", window: model.quota?.weekly)
            }
            if model.quota?.source == .logCache || model.quota?.isStale == true || model.quotaWarning != nil {
                Label("Cached quota · may be outdated", systemImage: "clock.badge.exclamationmark")
                    .font(.caption).foregroundStyle(.orange)
            }
            Divider()
            speedSection
            Divider()
            DisclosureGroup("Settings", isExpanded: $model.settingsExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Launch at login", isOn: Binding(get: { model.loginEnabled }, set: model.setLogin))
                    if let warning = model.loginWarning {
                        Text(warning).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Picker("Menu bar", selection: $model.options.fullMode) {
                        Text("Compact").tag(false)
                        Text("Full").tag(true)
                    }.pickerStyle(.segmented)
                    Toggle("Show 5-hour quota", isOn: $model.options.showFiveHour)
                    Toggle("Show 7-day quota", isOn: $model.options.showWeekly)
                    Toggle("Show countdown in full mode", isOn: $model.options.showCountdown)
                    Toggle("Show TPS", isOn: $model.options.showTPS)
                    Toggle("Automatic refresh", isOn: $model.autoRefresh)
                }
                .toggleStyle(.switch).controlSize(.small).padding(.top, 10)
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.quota?.source == .appServer && model.quota?.isStale == false && model.quotaWarning == nil ? "Live quota" : "Quota updated")
                    Text(model.quota.map { Self.date($0.updatedAt) } ?? "No quota data yet")
                }.font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless).font(.caption)
            }
            if model.quota == nil, model.quotaWarning != nil {
                Text("Open Codex and sign in there, then refresh. CodexMeter never opens a login flow.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func quotaRow(_ title: String, window: QuotaWindow?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(window.map { "\(Int($0.remainingPercent.rounded()))% left" } ?? (model.quota == nil ? "—" : "N/A"))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(color(window))
            }
            if let window {
                ProgressView(value: window.remainingPercent, total: 100)
                    .tint(color(window))
                HStack {
                    Text("Resets in \(MenuBarFormatter.countdown(until: window.resetsAt, now: model.now))")
                    Spacer()
                    if let reset = window.resetsAt { Text(reset, style: .time) }
                }.font(.caption2).foregroundStyle(.secondary)
            } else {
                ProgressView(value: 0, total: 100).opacity(0.2)
                Text(model.quota == nil ? "Waiting for quota data" : "This account has no reported window")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Latest completed response").font(.subheadline)
                    Text(model.sample?.model ?? "Model unavailable")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Text(model.sample.map { String(format: "%.1f", $0.tokensPerSecond) } ?? "—")
                    .font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit()
                Text("TPS").font(.caption).foregroundStyle(.secondary)
            }
            if let sample = model.sample {
                HStack(spacing: 0) {
                    metric("Output", value: sample.outputTokens.formatted())
                    Spacer()
                    metric("Reasoning¹", value: sample.reasoningTokens.formatted())
                    Spacer()
                    metric("Elapsed", value: String(format: "%.2fs", sample.elapsedSeconds))
                }
                Text("Completed \(Self.date(sample.completedAt))")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(sample.isEstimated ? "Effective rate · estimated from local event boundaries" : "Effective rate · measured response boundary")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("¹ Included in output tokens")
                    .font(.caption2).foregroundStyle(.tertiary)
                if model.latestUnmeasurable {
                    Text("The latest request has no reliable timing. Showing the last valid sample above.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("TPS is unavailable until a response has a reliable time window and token usage.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }.font(.caption)
    }

    private func color(_ window: QuotaWindow?) -> Color {
        guard let window else { return .secondary }
        if window.remainingPercent <= 10 { return .red }
        if window.remainingPercent <= 20 { return .orange }
        return .accentColor
    }

    private static func date(_ value: Date) -> String {
        value.formatted(.dateTime.month(.abbreviated).day().hour().minute().second())
    }
}
