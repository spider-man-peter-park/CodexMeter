import CodexMeterCore
import SwiftUI

struct MetricDetailContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: AppUpdates
    let section: DetailSection
    var quotaMetric: MenuBarMetric? = nil

    var body: some View {
        Group {
            switch section {
            case .quota: quotaSection
            case .today, .account: usageSection
            case .speed: speedSection
            case .cpu, .gpu, .ram:
                SystemMetricsDetailView(section: section,
                    snapshot: model.currentSystemMetrics, history: model.systemMetricsHistory)
            case .network: networkSection
            case .settings: settingsSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(L10n.text("Plan limits"), symbol: "chart.bar.fill")
            if quotaSummary.state == .cached || quotaSummary.state == .paused {
                MeterStatusLabel(title: quotaSummary.title, symbol: quotaSummary.symbolName)
                Text(quotaSummary.message).font(MeterStyle.captionFont).foregroundStyle(.secondary)
            }
            subscriptionBadge
            if quotaMetric != .weekly && (model.quota == nil || model.quota?.fiveHour != nil) {
                quotaRow(L10n.text("5-hour limit"), symbol: "clock", window: model.quota?.fiveHour)
                if quotaMetric != .fiveHour { Divider() }
            }
            if quotaMetric != .fiveHour {
                quotaRow(L10n.text("7-day limit"), symbol: "calendar", window: model.quota?.weekly)
            }
            if quotaIsCached {
                MeterStatusLabel(title: L10n.text("Cached quota · may be outdated"), symbol: "clock.badge.exclamationmark")
            }
            Divider()
            resetCreditsSection
        }
    }

    private var subscriptionBadge: some View {
        HStack(spacing: 12) {
            Text(L10n.text("Subscription")).font(MeterStyle.captionFont).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Link(destination: AppMetadata.plansURL) {
                HStack(spacing: 8) {
                    Label {
                        Text(SubscriptionPlanLabel.title(for: model.accountInfo?.planType))
                            .font(.system(size: 16, weight: .semibold)).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "crown").font(.system(size: 12)).accessibilityHidden(true)
                    }
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary).accessibilityHidden(true)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor.opacity(0.18)))
                .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help(L10n.text("View official plans"))
            .accessibilityElement(children: .combine)
            .accessibilityHint(L10n.text("View official plans"))
        }
    }

    private func quotaRow(_ title: String, symbol: String, window: QuotaWindow?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(MeterStyle.sectionFont)
            primaryValue(window.map { $0.remainingPercent > 0 && $0.remainingPercent < 0.5
                ? "<1%" : "\(Int($0.remainingPercent.rounded()))%" } ?? (model.quota == nil ? "—" : "N/A"),
                         unit: window == nil ? nil : L10n.text("left"), tint: color(window))
            if let window {
                ProgressView(value: window.remainingPercent, total: 100).tint(color(window))
                HStack {
                    Text(L10n.text("Resets in \(MenuBarFormatter.countdown(until: window.resetsAt, now: model.now, style: model.options.countdownStyle))"))
                    Spacer()
                    if let reset = window.resetsAt { Text(reset, style: .time) }
                }.font(MeterStyle.captionFont).foregroundStyle(.secondary)
            } else {
                Text(model.quota == nil ? L10n.text("Waiting for quota data") : L10n.text("This account has no reported window"))
                    .font(MeterStyle.captionFont).foregroundStyle(.secondary)
            }
        }
    }

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle(L10n.text("Latest response"), symbol: "bolt.fill")
            primaryValue(model.sample.map { String(format: "%.1f", $0.tokensPerSecond) } ?? "—", unit: "TPS")
            HStack(spacing: 12) {
                Text(L10n.text("Tokens per second")).fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                Text(model.sample?.model ?? L10n.text("Model unavailable"))
                    .lineLimit(1).truncationMode(.middle)
            }
            .font(MeterStyle.captionFont).foregroundStyle(.secondary)
            if let sample = model.sample {
                Text(L10n.text("Estimated · completed \(Self.date(sample.completedAt))"))
                    .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                if model.latestUnmeasurable {
                    Label(L10n.text("Last valid response"), systemImage: "clock")
                        .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                        .help(L10n.text("The latest request has no reliable timing. Showing the last valid sample above."))
                }
                Divider()
                TPSHistoryChart(samples: model.recentTPSSamples, isBackfilling: model.tpsHistoryBackfilling,
                    isUnattributed: model.tpsHistoryIsUnattributed)
            } else {
                Text(L10n.text("TPS is unavailable until a response has reliable timing and token usage."))
                    .font(MeterStyle.captionFont).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            localTodaySection
            Divider()
            accountSection
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle(L10n.text("Account usage"), symbol: "number.circle.fill")
                Spacer()
            }
            if let info = model.accountInfo {
                Text(L10n.text("Usage updated \(Self.date(info.updatedAt))"))
                    .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                if info.isStale || model.accountWarning != nil {
                    MeterStatusLabel(title: L10n.text("Cached account data"), symbol: "clock.badge.exclamationmark")
                        .help(L10n.text("Account usage is cached and may be outdated."))
                }
            }
            if let series = model.recentTokenUsage {
                TokenUsageChart(series: series)
            } else {
                Text(L10n.text("Daily token totals were not provided."))
                    .font(MeterStyle.captionFont).foregroundStyle(.secondary)
            }
            Text(L10n.text("Account dates are reported by Codex and may lag behind today. These totals are not added to the local estimate."))
                .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                metric(L10n.text("Lifetime tokens"), value: TokenCountFormatter.compact(model.accountInfo?.summary?.lifetimeTokens))
                Spacer()
                metric(L10n.text("Peak daily tokens"), value: TokenCountFormatter.compact(model.accountInfo?.summary?.peakDailyTokens))
            }
            Divider()
            HStack {
                metric(L10n.text("Current streak"), value: model.accountInfo?.summary?.currentStreakDays.map { L10n.text("\($0)d") } ?? "—")
                Spacer()
                metric(L10n.text("Longest streak"), value: model.accountInfo?.summary?.longestStreakDays.map { L10n.text("\($0)d") } ?? "—")
                Spacer()
                metric(L10n.text("Longest turn"), value: model.accountInfo?.summary?.longestRunningTurnSec.map(Self.duration) ?? "—")
            }
            if let buckets = model.accountInfo?.dailyUsageBuckets, !buckets.isEmpty {
                Divider()
                dailyHistorySection(buckets)
            }
            if model.accountInfo == nil {
                Text(L10n.text("Account token statistics are currently unavailable."))
                    .font(MeterStyle.captionFont).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var localTodaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L10n.text("Today · this Mac"), symbol: DetailSection.today.symbol)
                .help(model.localDayUsage?.isPartial == true
                    ? L10n.text("Partial estimate: some usage records could not be counted safely.")
                    : L10n.text("Desktop logs and linked subagents, by usage-record time. Other-device or cloud activity without local records is not covered. Separate from account daily totals."))
            if let usage = model.localDayUsage, usage.matches(model.now) {
                if usage.hasDesktopLogs && (usage.logsAvailable || usage.responses > 0) {
                    HStack(alignment: .firstTextBaseline) {
                        primaryValue(TokenCountFormatter.compact(usage.displayTotal(at: model.now)), unit: L10n.text("tokens"))
                        Spacer()
                        Text(L10n.text("\(usage.responses) usage records")).font(MeterStyle.captionFont).foregroundStyle(.secondary)
                    }
                } else {
                    Text(usage.isBackfilling ? L10n.text("Counting today's local usage…") : L10n.text("No readable, supported Desktop usage is available."))
                        .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                }
                if usage.isBackfilling { Label(L10n.text("Backfilling today's logs…"), systemImage: "clock").font(MeterStyle.captionFont).foregroundStyle(.secondary) }
            } else {
                Text(L10n.text("Waiting for today's local log refresh…")).font(MeterStyle.captionFont).foregroundStyle(.secondary)
            }
            Text(L10n.text("Local Desktop records and linked subagents. Account history is shown separately."))
                .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let usage = model.localDayUsage, usage.matches(model.now), usage.displayTotal(at: model.now) != nil {
                Divider()
                HStack(spacing: 24) {
                    metric(L10n.text("Input"), value: TokenCountFormatter.compact(usage.input))
                    metric(L10n.text("Output"), value: TokenCountFormatter.compact(usage.output))
                    Spacer(minLength: 0)
                }
                if usage.isPartial {
                    MeterStatusLabel(title: L10n.text("Partial estimate: some usage records could not be counted safely."),
                        symbol: "exclamationmark.triangle")
                }
            }
        }
    }

    private func dailyHistorySection(_ buckets: [AccountDailyUsageBucket]) -> some View {
        let sorted = buckets.sorted { $0.startDate > $1.startDate }
        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("Daily tokens · \(sorted.count) dates")).font(MeterStyle.sectionFont)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                ForEach(Array(sorted.enumerated()), id: \.offset) { index, day in
                    dailyRow(day).padding(.leading, index.isMultiple(of: 2) ? 0 : 12)
                }
            }
        }
        .help(L10n.text("Dates and totals reported by Codex. A missing date is not treated as zero."))
    }

    private func dailyRow(_ day: AccountDailyUsageBucket) -> some View {
        HStack {
            Text(day.startDate).foregroundStyle(.secondary)
            Spacer()
            Text(TokenCountFormatter.compact(day.tokens)).monospacedDigit()
        }.font(MeterStyle.captionFont)
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(DetailSection.network.title, symbol: DetailSection.network.symbol)
            HStack {
                metric(L10n.text("Upload"), value: SystemMetricsFormatter.rate(model.currentSystemMetrics?.networkUploadBytesPerSecond))
                Spacer()
                metric(L10n.text("Download"), value: SystemMetricsFormatter.rate(model.currentSystemMetrics?.networkDownloadBytesPerSecond))
            }
            Text(L10n.text("Physical network interfaces · bytes per second"))
                .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            NetworkProcessList(processes: model.currentSystemMetrics?.networkTopProcesses ?? [],
                updatedAt: model.currentSystemMetrics?.networkProcessesUpdatedAt)
        }
    }

    private var settingsSection: some View {
        SettingsContent(model: model, updates: updates)
    }

    private var resetCreditsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(L10n.text("Reset credits"), systemImage: "arrow.counterclockwise.circle")
                    .font(MeterStyle.sectionFont)
                Spacer(minLength: 4)
                Text(resetCreditSummary).fontWeight(.medium).monospacedDigit()
                    .multilineTextAlignment(.trailing).foregroundStyle(.secondary)
            }
            resetCreditDetails
        }
        .font(MeterStyle.captionFont)
    }

    private var quotaIsCached: Bool {
        quotaSummary.state == .cached || quotaSummary.state == .paused
    }

    private var quotaSummary: FocusSummary {
        FocusSummary(quota: model.quota, warning: model.quotaWarning, automaticRefresh: model.autoRefresh,
            now: model.now, refreshInterval: model.refreshOptions.quotaInterval)
    }

    private var resetCreditSummary: String {
        guard let summary = model.quota?.resetCredits else { return L10n.text("Unavailable") }
        if quotaIsCached { return L10n.text("Cached · \(summary.availableCount) reported") }
        if summary.availableCount > 0, let expiry = summary.credits?
            .filter({ $0.status.lowercased() == "available" })
            .compactMap(\.expiresAt).filter({ $0 > model.now }).min() {
            let date = expiry.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))
            return L10n.text("\(summary.availableCount) available · expires \(date)")
        }
        return L10n.text("\(summary.availableCount) available")
    }

    private var resetCreditDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let summary = model.quota?.resetCredits {
                if let credits = summary.credits {
                    if credits.isEmpty {
                        Text(summary.availableCount == 0 ? L10n.text("No reset credits are currently available.") :
                                L10n.text("Details not provided"))
                            .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(credits.enumerated()), id: \.offset) { _, credit in resetCredit(credit) }
                        if credits.count < summary.availableCount {
                            Text(L10n.text("\(credits.count) details returned"))
                                .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text(L10n.text("Details not provided"))
                        .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                        .help(L10n.text("Only the available count was returned. Credit details and expiration dates are unavailable."))
                }
            } else {
                Text(L10n.text("Reset credit information was not provided by Codex.")).font(MeterStyle.captionFont).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func resetCredit(_ credit: ResetCredit) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(credit.title.map { L10n.lookup($0) } ?? L10n.text("Quota reset")).font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                Text(L10n.lookup(credit.status)).font(MeterStyle.captionFont).foregroundStyle(.secondary)
            }
            detailRow(L10n.text("Granted"), value: credit.grantedAt.map(Self.creditDate) ?? L10n.text("Not provided"))
            detailRow(L10n.text("Expires"), value: credit.expiresAt.map(Self.creditDate) ?? L10n.text("Not provided"))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MeterStyle.surface, in: RoundedRectangle(cornerRadius: 6))
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }.font(MeterStyle.captionFont)
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol.replacingOccurrences(of: ".fill", with: ""))
            .font(MeterStyle.sectionFont).foregroundStyle(.primary)
    }

    private func primaryValue(_ value: String, unit: String? = nil, tint: Color = .primary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value).font(MeterStyle.numberFont).monospacedDigit().foregroundStyle(tint)
            if let unit { Text(unit).font(MeterStyle.captionFont).foregroundStyle(.secondary) }
        }
    }

    private static func creditDate(_ value: Date) -> String {
        value.formatted(.dateTime.year().month(.abbreviated).day().hour().minute().locale(L10n.locale))
    }

    private static func duration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return L10n.text("\(hours)h \(minutes)m") }
        if minutes > 0 { return L10n.text("\(minutes)m \(seconds % 60)s") }
        return L10n.text("\(seconds)s")
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(MeterStyle.captionFont).foregroundStyle(.secondary)
            Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit()
        }
    }

    private func color(_ window: QuotaWindow?) -> Color {
        guard let window else { return .secondary }
        if window.remainingPercent <= 10 { return .red }
        if window.remainingPercent <= 20 { return .orange }
        return .accentColor
    }

    private static func date(_ value: Date) -> String {
        value.formatted(.dateTime.month(.abbreviated).day().hour().minute().second().locale(L10n.locale))
    }
}
