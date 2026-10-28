import AppKit
import CodexMeterCore
import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
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
                resetCreditsSection
                Divider()
                DisclosureGroup("Settings", isExpanded: $model.settingsExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Launch at login", isOn: Binding(get: { model.loginEnabled }, set: model.setLogin))
                        if let warning = model.loginWarning {
                            Text(warning).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Picker("Quota labels", selection: $model.options.quotaLabelStyle) {
                            Text("AI").tag(QuotaLabelStyle.ai)
                            Text("5h / 7d").tag(QuotaLabelStyle.window)
                            Text("None").tag(QuotaLabelStyle.none)
                        }.pickerStyle(.segmented)
                        Toggle("Show 5-hour quota", isOn: $model.options.showFiveHour)
                        Toggle("Show 7-day quota", isOn: $model.options.showWeekly)
                        Toggle("Show reset countdown", isOn: $model.options.showCountdown)
                        Picker("Countdown", selection: $model.options.countdownStyle) {
                            Text("2h14m").tag(CountdownStyle.compact)
                            Text("02:14").tag(CountdownStyle.clock)
                        }.pickerStyle(.segmented)
                        Toggle("Show TPS", isOn: $model.options.showTPS)
                        Picker("TPS decimals", selection: $model.options.tpsDecimals) {
                            Text("0").tag(0)
                            Text("1").tag(1)
                        }.pickerStyle(.segmented)
                        Toggle("Show TPS label", isOn: $model.options.showTPSLabel)
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
        }
        .frame(width: 380, height: maximumHeight)
    }

    private var maximumHeight: CGFloat {
        min(700, max(300, (NSScreen.main?.visibleFrame.height ?? 800) - 100))
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
                    Text("Resets in \(MenuBarFormatter.countdown(until: window.resetsAt, now: model.now, style: model.options.countdownStyle))")
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

    private var resetCreditsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Quota reset credits").font(.subheadline)
                Spacer()
                Text(model.quota?.resetCredits.map { "\($0.availableCount) available" } ?? "—")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            if let summary = model.quota?.resetCredits {
                if let credits = summary.credits {
                    if credits.isEmpty {
                        Text(summary.availableCount == 0 ? "No reset credits are currently available." :
                                "The account reports available credits, but no credit details were returned.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(credits.enumerated()), id: \.offset) { _, credit in
                            resetCredit(credit)
                        }
                        if credits.count < summary.availableCount {
                            Text("Showing \(credits.count) credit details. The account reports \(summary.availableCount) available credits.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Only the available count was returned. Credit details and expiration dates are unavailable.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.quota?.source == .logCache || model.quota?.isStale == true || model.quotaWarning != nil {
                    Text("Credit information is cached and may be outdated.")
                        .font(.caption).foregroundStyle(.orange)
                }
            } else {
                Text("Reset credit information was not provided by Codex.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func resetCredit(_ credit: ResetCredit) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(credit.title ?? "Quota reset").font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                Text(credit.status).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(alignment: .top) {
                Text("Granted").foregroundStyle(.secondary)
                Spacer()
                Text(credit.grantedAt.map(Self.creditDate) ?? "Not provided")
                    .multilineTextAlignment(.trailing)
            }.font(.caption2)
            HStack(alignment: .top) {
                Text("Expires").foregroundStyle(.secondary)
                Spacer()
                Text(credit.expiresAt.map(Self.creditDate) ?? "Not provided")
                    .multilineTextAlignment(.trailing)
            }.font(.caption2)
            if let description = credit.description, !description.isEmpty {
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private static func creditDate(_ value: Date) -> String {
        value.formatted(.dateTime.year().month(.abbreviated).day().hour().minute())
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
