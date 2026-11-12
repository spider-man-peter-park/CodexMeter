import CodexMeterCore
import Foundation
import ProjectionMotionKit

@MainActor
final class FloatingHUDDataProvider: HUDDataProviding {
    private let model: AppModel
    private let usage: AssistantUsageStore

    init(model: AppModel, usage: AssistantUsageStore) { self.model = model; self.usage = usage }

    func sample(modules: Set<HUDModule>, now: Date) -> HUDDataSnapshot {
        L10n.$languageOverride.withValue(model.language) { makeSnapshot(now: now) }
    }

    private func makeSnapshot(now: Date) -> HUDDataSnapshot {
        var snapshot = HUDDataSnapshot()
        let hardware = model.systemMetrics?.fresh(at: now)
        snapshot.date = now
        snapshot.deviceName = Host.current().localizedName ?? "Mac"
        let version = ProcessInfo.processInfo.operatingSystemVersion
        snapshot.osVersion = "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        snapshot.uptime = ProcessInfo.processInfo.systemUptime
        snapshot.cpuUsage = hardware?.cpuUsagePercent.map { $0 / 100 }
        snapshot.gpuUsage = hardware?.gpuUsagePercent.map { $0 / 100 }
        snapshot.memoryUsedBytes = hardware?.memoryUsedBytes
        snapshot.memoryTotalBytes = hardware?.memoryTotalBytes
        snapshot.uploadBytesPerSecond = hardware?.networkUploadBytesPerSecond
        snapshot.downloadBytesPerSecond = hardware?.networkDownloadBytesPerSecond
        let history = hardware == nil ? [] : Array(model.systemMetricsHistory.suffix(60))
        snapshot.cpuHistory = continuousHistory(history, value: \.cpuUsagePercent).map { $0 / 100 }
        snapshot.uploadHistory = continuousHistory(history, value: \.networkUploadBytesPerSecond)
        snapshot.downloadHistory = continuousHistory(history, value: \.networkDownloadBytesPerSecond)
        snapshot.activities = []
        snapshot.isFixture = CommandLine.arguments.contains("--ui-preview-fixtures")

        let summary = FocusSummary(quota: model.quota, warning: model.quotaWarning,
            automaticRefresh: model.autoRefresh, now: now, refreshInterval: model.refreshOptions.quotaInterval)
        let result = usage.result(for: model.provider)
        let reported = result.snapshot
        let badge = !model.autoRefresh ? L10n.text("Refresh paused") : model.provider == .codex ? summary.title :
            reported?.isPartial == true ? L10n.text("Partial coverage") :
            result.status == .ready ? L10n.text("Reported usage") : L10n.text("Unavailable")
        let warning = !model.autoRefresh || (model.provider == .codex ? summary.state != .ready : result.status != .ready || reported?.isPartial == true)
        let primary: String
        let primaryLabel: String
        if model.provider == .codex {
            primary = quota(summary.window)
            primaryLabel = L10n.text("Remaining quota")
        } else if model.provider == .cursor {
            primary = reported?.usedPercent.map { String(format: "%.1f%%", $0) } ?? "—"
            primaryLabel = L10n.text("Used allowance")
        } else {
            primary = TokenCountFormatter.compact(reported?.totalTokens)
            primaryLabel = L10n.text("Local session tokens")
        }
        snapshot.coreContent = HUDTextContent(title: model.provider.title, value: primary,
            subtitle: primaryLabel, detail: badge, warning: warning)
        let fractionBadge = model.provider == .codex ? summary.title : badge
        let quotaDetail = model.provider == .codex ? "5h  \(quota(model.quota?.fiveHour))   ·   7d  \(quota(model.quota?.weekly))" :
            reported?.periodLabel.map { L10n.lookup($0) } ??
                (model.provider == .cursor ? L10n.text("Reported usage") : L10n.text("Cumulative · supported sessions"))
        snapshot.moduleContent[.ai] = HUDTextContent(title: model.provider.title, value: primary,
            subtitle: primaryLabel, detail: quotaDetail, footnote: fractionBadge, warning: warning)

        let os = snapshot.osVersion
        let hours = Int(snapshot.uptime / 3600)
        snapshot.moduleContent[.system] = HUDTextContent(title: L10n.text("This Mac"), value: snapshot.deviceName,
            subtitle: os, detail: "\(hours / 24)d \(hours % 24)h", footnote: now.formatted(.dateTime.hour().minute().locale(L10n.locale)))
        snapshot.moduleContent[.performance] = HUDTextContent(title: L10n.text("Hardware"),
            value: "CPU  " + SystemMetricsFormatter.percent(hardware?.cpuUsagePercent),
            subtitle: "GPU \(SystemMetricsFormatter.percent(hardware?.gpuUsagePercent))   RAM \(SystemMetricsFormatter.percent(hardware?.memoryUsagePercent))",
            detail: memory(hardware))
        snapshot.moduleContent[.network] = HUDTextContent(title: L10n.text("Network"),
            value: "↓ " + SystemMetricsFormatter.rate(hardware?.networkDownloadBytesPerSecond),
            subtitle: "↑ " + SystemMetricsFormatter.rate(hardware?.networkUploadBytesPerSecond),
            detail: L10n.text("This Mac"))
        if model.provider == .codex {
            let activity = model.localDayUsage
            let note = activity?.isBackfilling == true ? L10n.text("Backfilling today's logs…") :
                activity?.isPartial == true ? L10n.text("Partial estimate") : L10n.text("Local activity")
            snapshot.moduleContent[.activity] = HUDTextContent(title: L10n.text("Today · this Mac"),
                value: TokenCountFormatter.compact(activity?.displayTotal(at: now)), subtitle: note,
                warning: activity?.isPartial == true || activity?.isBackfilling == true)
            snapshot.moduleContent[.controls] = HUDTextContent(title: L10n.text("Latest response"),
                value: model.sample.map { String(format: "%.1f TPS", $0.tokensPerSecond) } ?? "—",
                subtitle: model.latestUnmeasurable ? L10n.text("Last valid response") : "TPS", warning: model.latestUnmeasurable)
        } else if model.provider == .cursor {
            snapshot.moduleContent[.activity] = HUDTextContent(title: L10n.text("Reported tokens"),
                value: TokenCountFormatter.compact(reported?.totalTokens), subtitle: L10n.text("Reported usage"))
            snapshot.moduleContent[.controls] = HUDTextContent(title: L10n.text("Reported requests"),
                value: reported?.requestCount.map { $0.formatted() } ?? "—",
                subtitle: reported?.costUSD.map { L10n.text("Used allowance") + "  " + $0.formatted(.currency(code: "USD")) } ?? "—")
        } else {
            snapshot.moduleContent[.activity] = HUDTextContent(title: L10n.text("Sessions"),
                value: reported?.sessionCount.map { $0.formatted() } ?? "—",
                subtitle: L10n.text("Cumulative · supported sessions"), warning: reported?.isPartial == true)
            snapshot.moduleContent[.controls] = HUDTextContent(title: L10n.text("Average decode speed"),
                value: reported?.decodeTokensPerSecond.map { String(format: "%.1f TPS", $0) } ?? "—",
                subtitle: L10n.text("Cumulative model time") + "  " + (reported?.modelSeconds.map { String(format: "%.1f s", $0) } ?? "—"))
        }
        return snapshot
    }

    private func quota(_ window: QuotaWindow?) -> String {
        guard let window, window.usedPercent.isFinite else { return "—" }
        return window.remainingPercent > 0 && window.remainingPercent < 0.5 ? "<1%" : String(format: "%.0f%%", window.remainingPercent)
    }

    private func continuousHistory(_ history: [SystemMetricsSnapshot],
                                   value: KeyPath<SystemMetricsSnapshot, Double?>) -> [Double] {
        var result: [Double] = []
        var previous: Date?
        for sample in history {
            if let previous, !(0...10).contains(sample.sampledAt.timeIntervalSince(previous)) { result.removeAll() }
            guard let number = sample[keyPath: value], number.isFinite, number >= 0 else {
                result.removeAll(); previous = nil
                continue
            }
            result.append(number)
            previous = sample.sampledAt
        }
        return result
    }

    private func memory(_ hardware: SystemMetricsSnapshot?) -> String {
        guard let used = hardware?.memoryUsedBytes, let total = hardware?.memoryTotalBytes, total > 0 else { return "—" }
        return String(format: "%.1f / %.0f GiB", Double(used) / 1_073_741_824, Double(total) / 1_073_741_824)
    }
}
