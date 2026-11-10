import CodexMeterCore
import Foundation

/// Deterministic local data for isolated UI previews; never starts a live monitor or login service.
enum UIPreviewFixtures {
    static func usage(for provider: AssistantProvider, at now: Date) -> ProviderUsageResult {
        var snapshot = ProviderUsageSnapshot(provider: provider,
            scope: provider == .cursor ? .accountPeriod : .localSessions, sampledAt: now)
        if provider == .cursor {
            snapshot.usedPercent = 42
            snapshot.periodLabel = "Weekly usage pool"
            snapshot.resetAt = now.addingTimeInterval(259_200)
            return ProviderUsageResult(provider: provider, status: .ready, snapshot: snapshot,
                message: "Cursor account usage for the reported cycle.")
        }
        snapshot.totalTokens = 4_200_000
        snapshot.inputTokens = 3_500_000
        snapshot.outputTokens = 700_000
        snapshot.cachedInputTokens = 2_100_000
        snapshot.cacheWriteTokens = 400_000
        snapshot.sessionCount = 12
        snapshot.decodeTokensPerSecond = 86.4
        snapshot.modelSeconds = 8_100
        snapshot.isPartial = true
        snapshot.sessions = (0..<6).map {
            ProviderSessionUsage(id: "sample-\($0 + 1)", tokens: 110_000 + $0 * 30_000,
                updatedAt: now.addingTimeInterval(Double(-$0) * 3_600))
        }
        return ProviderUsageResult(provider: provider, status: .ready, snapshot: snapshot,
            message: "Partial local non-forked session totals, not today's usage or an account bill. Checkpoints may lag behind Harness.")
    }

    static func quota(at date: Date) -> QuotaSnapshot {
        QuotaSnapshot(fiveHour: QuotaWindow(usedPercent: 23, windowDurationMins: 300,
                resetsAt: date.addingTimeInterval(8_100)),
            weekly: QuotaWindow(usedPercent: 62, windowDurationMins: 10_080,
                resetsAt: date.addingTimeInterval(172_800)),
            updatedAt: date, source: .appServer,
            resetCredits: ResetCreditSummary(availableCount: 1, credits: [
                ResetCredit(id: "preview-credit", resetType: "weekly", status: "available",
                    grantedAt: date.addingTimeInterval(-86_400), expiresAt: date.addingTimeInterval(259_200))
            ]))
    }

    static func account(at date: Date) -> AccountInfoSnapshot {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let values = [1_600_000, 3_200_000, 2_100_000, 4_800_000, 3_700_000, 6_200_000, 4_100_000]
        let buckets = values.enumerated().map { index, tokens in
            AccountDailyUsageBucket(startDate: formatter.string(from: date.addingTimeInterval(Double(index - 6) * 86_400)),
                tokens: tokens)
        }
        return AccountInfoSnapshot(planType: "pro", summary: AccountUsageSummary(lifetimeTokens: 124_600_000,
            peakDailyTokens: 8_200_000, longestRunningTurnSec: 420, currentStreakDays: 8, longestStreakDays: 21),
            dailyUsageBuckets: buckets, updatedAt: date)
    }

    @MainActor static func apply(to model: AppModel) {
        let time = Date()
        model.now = time
        model.quota = quota(at: time)
        model.accountInfo = account(at: time)
        var today = LocalDayUsage(dayStart: Calendar.current.startOfDay(for: time),
            timeZoneIdentifier: Calendar.current.timeZone.identifier, updatedAt: time)
        today.input = 1_420_000
        today.output = 380_000
        today.responses = 42
        today.hasDesktopLogs = true
        let samples = (0..<30).map { index in
            TPSSample(id: "preview-response-\(index)", model: "gpt-5.4", outputTokens: 220 + index * 5,
                reasoningTokens: 40, elapsedSeconds: 3 + Double(index % 4),
                completedAt: time.addingTimeInterval(Double(index - 29) * 50), isEstimated: true)
        }
        model.apply(LogSnapshot(latestSample: samples.last, cachedQuota: nil, latestResponseAt: time,
            hasUnmeasurableResponse: false, todayUsage: today, recentSamples: samples))
        for seconds in stride(from: -120, through: 0, by: 2) {
            let value = 30 + sin(Double(seconds) / 15) * 16
            let sample = SystemMetricsSnapshot(sampledAt: time.addingTimeInterval(Double(seconds)),
                cpuUsagePercent: value, gpuUsagePercent: 18 + sin(Double(seconds) / 20) * 10,
                memoryUsedBytes: 12_400_000_000, memoryTotalBytes: 24_000_000_000,
                networkUploadBytesPerSecond: 124_000, networkDownloadBytesPerSecond: 2_800_000,
                cpuTopProcesses: [SystemProcessUsage(pid: 100, name: "Codex", memoryBytes: 1_200_000_000, cpuUsagePercent: 16)],
                memoryTopProcesses: [SystemProcessUsage(pid: 100, name: "Codex", memoryBytes: 1_200_000_000, cpuUsagePercent: 16)],
                gpuDeviceNames: ["Apple GPU"], gpuHasUnifiedMemory: true)
            model.applySystemMetrics(sample, at: time)
        }
        if CommandLine.arguments.contains("--ui-preview-empty") {
            model.quota = nil
            model.accountInfo = nil
            model.quotaWarning = "Live quota unavailable. Showing the last valid data, which may be outdated."
        } else if CommandLine.arguments.contains("--ui-preview-cached") {
            var cached = quota(at: time.addingTimeInterval(-3_600))
            cached.isStale = true
            model.quota = cached
        }
        if CommandLine.arguments.contains("--ui-preview-individual") { model.menuBarMode = .individual }
    }
}
