import AppKit
import CodexMeterCore
import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header.padding(18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    card { quotaSection }
                    card { speedSection }
                    card { accountSection }
                    card { resetCreditsSection }
                    card { settingsSection }
                    if model.quota == nil, model.quotaWarning != nil {
                        Text("Open Codex and sign in there, then refresh. CodexMeter never opens a login flow.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(18)
            }
            Divider()
            footer.padding(.horizontal, 18).padding(.vertical, 12)
        }
        .frame(width: 420, height: maximumHeight)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text("CodexMeter").font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Limits, tokens & response speed").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if model.refreshing || model.accountRefreshing { ProgressView().controlSize(.small) }
            Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).disabled(model.refreshing)
                .help("Refresh quota, account usage and local responses")
                .accessibilityLabel("Refresh")
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.quota?.source == .appServer && model.quota?.isStale == false && model.quotaWarning == nil ? "Live quota" : "Quota updated")
                Text(model.quota.map { Self.date($0.updatedAt) } ?? "No quota data yet")
            }.font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless).font(.caption)
        }
    }

    private var maximumHeight: CGFloat {
        min(740, max(350, (NSScreen.main?.visibleFrame.height ?? 840) - 100))
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Plan limits", symbol: "chart.bar.fill")
            if model.quota == nil || model.quota?.fiveHour != nil {
                quotaRow("5-hour limit", symbol: "clock", window: model.quota?.fiveHour)
                Divider()
            }
            quotaRow("7-day limit", symbol: "calendar", window: model.quota?.weekly)
            if model.quota?.source == .logCache || model.quota?.isStale == true || model.quotaWarning != nil {
                Label("Cached quota · may be outdated", systemImage: "clock.badge.exclamationmark")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    private func quotaRow(_ title: String, symbol: String, window: QuotaWindow?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: symbol).font(.subheadline)
                Spacer()
                Text(window.map { "\(Int($0.remainingPercent.rounded()))%" } ?? (model.quota == nil ? "—" : "N/A"))
                    .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(color(window))
                if window != nil { Text("left").font(.caption2).foregroundStyle(.secondary) }
            }
            if let window {
                ProgressView(value: window.remainingPercent, total: 100).tint(color(window))
                HStack {
                    Text("Resets in \(MenuBarFormatter.countdown(until: window.resetsAt, now: model.now, style: model.options.countdownStyle))")
                    Spacer()
                    if let reset = window.resetsAt { Text(reset, style: .time) }
                }.font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(model.quota == nil ? "Waiting for quota data" : "This account has no reported window")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    sectionTitle("Latest response", symbol: "bolt.fill")
                    Text(model.sample?.model ?? "Model unavailable")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Text(model.sample.map { String(format: "%.1f", $0.tokensPerSecond) } ?? "—")
                    .font(.system(size: 29, weight: .medium, design: .rounded)).monospacedDigit()
                Text("TPS").font(.caption).foregroundStyle(.secondary)
            }
            if let sample = model.sample {
                HStack {
                    metric("Output", value: TokenCountFormatter.compact(sample.outputTokens))
                    Spacer()
                    metric("Reasoning¹", value: TokenCountFormatter.compact(sample.reasoningTokens))
                    Spacer()
                    metric("Elapsed", value: String(format: "%.2fs", sample.elapsedSeconds))
                }
                Text("Completed \(Self.date(sample.completedAt))")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(sample.isEstimated ? "Effective rate · estimated from local event boundaries" : "Effective rate · measured response boundary")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("¹ Included in output tokens").font(.caption2).foregroundStyle(.tertiary)
                if model.latestUnmeasurable {
                    Text("The latest request has no reliable timing. Showing the last valid sample above.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("TPS is unavailable until a response has reliable timing and token usage.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("Account usage", symbol: "number.circle.fill")
                Spacer()
                if let plan = model.accountInfo?.planType { Text(plan).font(.caption).foregroundStyle(.secondary) }
            }
            HStack {
                metric("Lifetime tokens", value: TokenCountFormatter.compact(model.accountInfo?.summary?.lifetimeTokens))
                Spacer()
                metric("Peak daily tokens", value: TokenCountFormatter.compact(model.accountInfo?.summary?.peakDailyTokens))
            }
            Divider()
            HStack {
                metric("Current streak", value: model.accountInfo?.summary?.currentStreakDays.map { "\($0)d" } ?? "—")
                Spacer()
                metric("Longest streak", value: model.accountInfo?.summary?.longestStreakDays.map { "\($0)d" } ?? "—")
                Spacer()
                metric("Longest turn", value: model.accountInfo?.summary?.longestRunningTurnSec.map(Self.duration) ?? "—")
            }
            dailyUsageSection
            Divider()
            if let info = model.accountInfo {
                Text("Usage updated \(Self.date(info.updatedAt))")
                    .font(.caption2).foregroundStyle(.secondary)
                if info.isStale || model.accountWarning != nil {
                    Text("Account usage is cached and may be outdated.")
                        .font(.caption2).foregroundStyle(.orange)
                }
            } else {
                Text("Account token statistics are currently unavailable.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var dailyUsageSection: some View {
        if let buckets = model.accountInfo?.dailyUsageBuckets {
            if buckets.isEmpty {
                Text("No daily token totals were returned.").font(.caption).foregroundStyle(.secondary)
            } else {
                let sorted = buckets.sorted { $0.startDate > $1.startDate }
                if let latest = sorted.first {
                    HStack {
                        Text("Latest reported day · \(latest.startDate)")
                        Spacer()
                        Text(TokenCountFormatter.compact(latest.tokens)).monospacedDigit().fontWeight(.medium)
                    }.font(.caption)
                }
                if let series = model.recentTokenUsage {
                    TokenUsageChart(series: series)
                }
                DisclosureGroup("Daily tokens · \(sorted.count) dates") {
                    VStack(spacing: 7) {
                        ForEach(Array(sorted.prefix(14).enumerated()), id: \.offset) { _, day in dailyRow(day) }
                        if sorted.count > 14 {
                            DisclosureGroup("Earlier dates") {
                                VStack(spacing: 7) {
                                    ForEach(Array(sorted.dropFirst(14).enumerated()), id: \.offset) { _, day in dailyRow(day) }
                                }.padding(.top, 7)
                            }
                        }
                        Text("Dates and totals reported by Codex. A missing date is not treated as zero.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.padding(.top, 8)
                }.font(.caption)
            }
        } else {
            Text("Daily token totals were not provided.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func dailyRow(_ day: AccountDailyUsageBucket) -> some View {
        HStack {
            Text(day.startDate).foregroundStyle(.secondary)
            Spacer()
            Text(TokenCountFormatter.compact(day.tokens)).monospacedDigit()
        }.font(.caption)
    }

    private var settingsSection: some View {
        DisclosureGroup("Settings", isExpanded: $model.settingsExpanded) {
            VStack(alignment: .leading, spacing: 15) {
                appearanceSettings
                Divider()
                layoutSettings
                Divider()
                refreshSettings
                Divider()
                generalSettings
            }
            .toggleStyle(.switch).controlSize(.small).padding(.top, 14)
        }
    }

    private var appearanceSettings: some View {
        DisclosureGroup("Menu bar appearance") {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 6) {
                    ForEach(DisplayPreset.allCases, id: \.self) { preset in
                        Button(preset.rawValue.capitalized) { model.options.applyPreset(preset) }
                            .buttonStyle(.bordered).frame(maxWidth: .infinity)
                    }
                }.help("Apply a style preset. Your visible metrics and refresh periods stay unchanged.")
                HStack {
                    Text("Font size")
                    Spacer()
                    Text(String(format: "%.0f pt", model.options.normalizedFontSize)).monospacedDigit()
                    Stepper("Font size", value: $model.options.fontSize, in: 9...16, step: 1).labelsHidden()
                }
                Picker("Weight", selection: $model.options.fontWeight) {
                    Text("Regular").tag(MenuBarFontWeight.regular)
                    Text("Medium").tag(MenuBarFontWeight.medium)
                    Text("Semibold").tag(MenuBarFontWeight.semibold)
                }.pickerStyle(.segmented)
                Picker("Typeface", selection: $model.options.fontDesign) {
                    Text("System").tag(MenuBarFontDesign.system)
                    Text("Rounded").tag(MenuBarFontDesign.rounded)
                    Text("Mono").tag(MenuBarFontDesign.monospaced)
                }.pickerStyle(.segmented)
                Picker("Color", selection: $model.options.colorStyle) {
                    ForEach(MenuBarColorStyle.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("Background", selection: $model.options.itemStyle) {
                    Text("On open").tag(MenuBarItemStyle.activeCapsule)
                    Text("Always").tag(MenuBarItemStyle.capsule)
                    Text("None").tag(MenuBarItemStyle.plain)
                }.pickerStyle(.segmented)
                Picker("Spacing", selection: $model.options.spacing) {
                    Text("Compact").tag(MenuBarSpacing.compact)
                    Text("Comfortable").tag(MenuBarSpacing.comfortable)
                }.pickerStyle(.segmented)
            }.font(.caption).padding(.top, 10)
        }
    }

    private var layoutSettings: some View {
        DisclosureGroup("Labels & visible metrics") {
            VStack(alignment: .leading, spacing: 11) {
                Picker("Quota labels", selection: $model.options.quotaLabelStyle) {
                    Text("AI").tag(QuotaLabelStyle.ai)
                    Text("5h / 7d").tag(QuotaLabelStyle.window)
                    Text("Window icons").tag(QuotaLabelStyle.icon)
                    Text("GPT icon").tag(QuotaLabelStyle.gpt)
                    Text("Custom").tag(QuotaLabelStyle.custom)
                    Text("None").tag(QuotaLabelStyle.none)
                }
                if model.options.quotaLabelStyle == .custom {
                    TextField("Custom label · up to 12 characters", text: Binding(
                        get: { model.options.customQuotaLabel },
                        set: { model.options.customQuotaLabel = DisplayOptions.sanitizeQuotaLabel($0) }))
                        .textFieldStyle(.roundedBorder)
                }
                Toggle("Show 5-hour quota", isOn: $model.options.showFiveHour)
                Toggle("Show 7-day quota", isOn: $model.options.showWeekly)
                Toggle("Show percent sign", isOn: $model.options.showPercentSign)
                Toggle("Show reset countdown", isOn: $model.options.showCountdown)
                Picker("Countdown", selection: $model.options.countdownStyle) {
                    Text("2h14m").tag(CountdownStyle.compact)
                    Text("02:14").tag(CountdownStyle.clock)
                }.pickerStyle(.segmented)
                Picker("Countdown separator", selection: $model.options.countdownSeparator) {
                    Text("Space").tag(CountdownSeparator.space)
                    Text("Middle dot").tag(CountdownSeparator.dot)
                    Text("Slash").tag(CountdownSeparator.slash)
                    Text("Parentheses").tag(CountdownSeparator.parentheses)
                }
                Toggle("Show TPS", isOn: $model.options.showTPS)
                Picker("TPS layout", selection: $model.options.tpsLayout) {
                    Text("Inline").tag(MenuBarTPSLayout.inline)
                    Text("Stacked").tag(MenuBarTPSLayout.stacked)
                }.pickerStyle(.segmented)
                Picker("TPS decimals", selection: $model.options.tpsDecimals) {
                    Text("0").tag(0)
                    Text("1").tag(1)
                }.pickerStyle(.segmented)
                Toggle("Show TPS label", isOn: $model.options.showTPSLabel)
            }.font(.caption).padding(.top, 10)
        }
    }

    private var refreshSettings: some View {
        DisclosureGroup("Refresh periods") {
            VStack(alignment: .leading, spacing: 11) {
                Toggle("Automatic refresh", isOn: $model.autoRefresh)
                Picker("Quota", selection: $model.refreshOptions.quotaSeconds) {
                    Text("1 minute").tag(60)
                    Text("3 minutes").tag(180)
                    Text("5 minutes").tag(300)
                    Text("10 minutes").tag(600)
                    Text("15 minutes").tag(900)
                }
                Picker("Local response logs", selection: $model.refreshOptions.logSeconds) {
                    ForEach([1.0, 2, 5, 10, 30], id: \.self) { Text(String(format: "%.0f seconds", $0)).tag($0) }
                }
                Picker("Countdown display", selection: $model.refreshOptions.displaySeconds) {
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                }
                Picker("Account statistics", selection: $model.refreshOptions.accountSeconds) {
                    Text("5 minutes").tag(300)
                    Text("15 minutes").tag(900)
                    Text("30 minutes").tag(1800)
                    Text("1 hour").tag(3600)
                }
                Text("Response logs stay on this Mac. Account and quota reads use Codex App Server.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.font(.caption).padding(.top, 10)
        }
    }

    private var generalSettings: some View {
        DisclosureGroup("General") {
            VStack(alignment: .leading, spacing: 11) {
                Toggle("Launch at login", isOn: Binding(get: { model.loginEnabled }, set: model.setLogin))
                if let warning = model.loginWarning {
                    Text(warning).font(.caption).foregroundStyle(.secondary)
                }
            }.font(.caption).padding(.top, 10)
        }
    }

    private var resetCreditsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Quota reset credits", symbol: "arrow.counterclockwise.circle.fill")
                Spacer()
                Text(model.quota?.resetCredits.map { "\($0.availableCount) available" } ?? "—")
                    .font(.caption.weight(.semibold)).monospacedDigit()
            }
            if let summary = model.quota?.resetCredits {
                if let credits = summary.credits {
                    if credits.isEmpty {
                        Text(summary.availableCount == 0 ? "No reset credits are currently available." :
                                "The account reports available credits, but no credit details were returned.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(credits.enumerated()), id: \.offset) { _, credit in resetCredit(credit) }
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
                        .font(.caption2).foregroundStyle(.orange)
                }
            } else {
                Text("Reset credit information was not provided by Codex.").font(.caption).foregroundStyle(.secondary)
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
            detailRow("Granted", value: credit.grantedAt.map(Self.creditDate) ?? "Not provided")
            detailRow("Expires", value: credit.expiresAt.map(Self.creditDate) ?? "Not provided")
            if let description = credit.description, !description.isEmpty {
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }.font(.caption2)
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.caption.weight(.semibold))
    }

    private static func creditDate(_ value: Date) -> String {
        value.formatted(.dateTime.year().month(.abbreviated).day().hour().minute())
    }

    private static func duration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds % 60)s" }
        return "\(seconds)s"
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.caption, design: .rounded).weight(.semibold)).monospacedDigit()
        }
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
