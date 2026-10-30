import Foundation

public enum QuotaAlertThresholds: String, Codable, CaseIterable, Sendable {
    case twentyAndTen, ten, five
    public var values: [Int] {
        switch self { case .twentyAndTen: [20, 10]; case .ten: [10]; case .five: [5] }
    }
}

public enum CreditExpiryLeadTime: String, Codable, CaseIterable, Sendable {
    case threeDaysAndOneDay, threeDays, oneDay
    public var days: [Int] {
        switch self { case .threeDaysAndOneDay: [3, 1]; case .threeDays: [3]; case .oneDay: [1] }
    }
}

public struct ReminderOptions: Codable, Equatable, Sendable {
    public var lowQuotaEnabled = false
    public var recoveryEnabled = false
    public var fiveHourEnabled = true
    public var weeklyEnabled = true
    public var thresholds = QuotaAlertThresholds.twentyAndTen
    public var creditExpiryEnabled = false
    public var creditLeadTime = CreditExpiryLeadTime.threeDaysAndOneDay
    public var quotaEnabled: Bool { (lowQuotaEnabled || recoveryEnabled) && (fiveHourEnabled || weeklyEnabled) }
    public var anyEnabled: Bool { quotaEnabled || creditExpiryEnabled }
    public init() {}
}

public struct ReminderRequest: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case lowQuota, recoveredQuota, creditExpiry }
    public let id: String
    public let kind: Kind
    public let title: String
    public let body: String
    public let deliveryAt: Date?
    public let acknowledgementKeys: [String]
}

public struct ReminderState: Codable, Sendable {
    fileprivate struct Window: Codable, Sendable {
        var cycle = UUID().uuidString
        var resetAt: Date?
        var recoveryArmed = false
        var pendingRecovery: ReminderRequest?
    }
    fileprivate var windows: [String: Window] = [:]
    fileprivate var acknowledgements: [String: Date] = [:]
    public init() {}
}

public struct ReminderEngine: Sendable {
    public private(set) var state: ReminderState
    public let prefix: String
    public var creditPrefix: String { prefix + "credit." }

    public init(state: ReminderState = ReminderState(), scope: String) {
        self.state = state
        prefix = "io.github.codexmeter.reminders." + scope + "."
    }

    public mutating func resetRecoveryTracking() {
        for key in state.windows.keys {
            state.windows[key]?.recoveryArmed = false
            state.windows[key]?.pendingRecovery = nil
        }
    }

    public static func isFresh(_ snapshot: QuotaSnapshot, now: Date) -> Bool {
        snapshot.source == .appServer && !snapshot.isStale
            && (-60...300).contains(now.timeIntervalSince(snapshot.updatedAt))
    }

    public mutating func quotaRequests(_ snapshot: QuotaSnapshot, options: ReminderOptions, now: Date) -> [ReminderRequest] {
        guard Self.isFresh(snapshot, now: now) else { return [] }
        var requests: [ReminderRequest] = []
        for (key, title, window, enabled) in [
            ("fiveHour", L10n.text("5-hour"), snapshot.fiveHour, options.fiveHourEnabled),
            ("weekly", L10n.text("7-day"), snapshot.weekly, options.weeklyEnabled)
        ] {
            guard enabled, options.quotaEnabled, let window, window.usedPercent.isFinite else {
                state.windows[key]?.recoveryArmed = false
                continue
            }
            var previous = state.windows[key] ?? ReminderState.Window()
            let remaining = window.remainingPercent
            let warning = options.thresholds.values.max() ?? 20
            let recovered = previous.recoveryArmed && remaining >= Double(warning + 5)
            var pendingRecovery = previous.pendingRecovery
            let confirmedNewWindow = previous.resetAt.map { old in
                old <= snapshot.updatedAt && window.resetsAt.map { $0 > old } == true
            } ?? false
            if recovered {
                if options.recoveryEnabled {
                    let id = prefix + "quota." + key + "." + previous.cycle + ".recovered"
                    if state.acknowledgements[id] == nil {
                        pendingRecovery = ReminderRequest(id: id, kind: .recoveredQuota,
                            title: L10n.text("Codex quota recovered"),
                            body: L10n.text("The \(title) window now has \(Int(remaining.rounded()))% remaining."),
                            deliveryAt: nil, acknowledgementKeys: [id])
                    }
                }
            }
            if recovered || confirmedNewWindow {
                previous = ReminderState.Window()
            }
            if remaining < Double(warning + 5) || !options.recoveryEnabled { pendingRecovery = nil }
            previous.pendingRecovery = pendingRecovery
            if let pendingRecovery { requests.append(pendingRecovery) }
            previous.resetAt = window.resetsAt ?? previous.resetAt
            if remaining <= Double(warning) { previous.recoveryArmed = true }
            let crossed = options.thresholds.values.filter { remaining <= Double($0) }
            if options.lowQuotaEnabled, let threshold = crossed.min() {
                let keys = crossed.map { prefix + "quota." + key + "." + previous.cycle + ".low.\($0)" }
                let id = prefix + "quota." + key + "." + previous.cycle + ".low.\(threshold)"
                if state.acknowledgements[id] == nil {
                    requests.append(ReminderRequest(id: id, kind: .lowQuota,
                        title: L10n.text("Codex quota running low"),
                        body: L10n.text("The \(title) window has \(Int(remaining.rounded()))% remaining (\(threshold)% alert)."),
                        deliveryAt: nil, acknowledgementKeys: keys))
                }
            }
            state.windows[key] = previous
        }
        return requests
    }

    public func creditRequests(_ snapshot: QuotaSnapshot, options: ReminderOptions, now: Date,
                               pendingIdentifiers: Set<String> = []) -> [ReminderRequest] {
        guard options.creditExpiryEnabled, Self.isFresh(snapshot, now: now),
              let summary = snapshot.resetCredits, summary.availableCount > 0, let credits = summary.credits else { return [] }
        var result: [ReminderRequest] = []
        let eligible = credits.filter { $0.status.lowercased() == "available" && ($0.expiresAt ?? .distantPast) > now }
            .sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
        for credit in eligible.prefix(32) {
            guard let expiry = credit.expiresAt else { continue }
            let identity = Self.fingerprint(credit.id + ":" + String(expiry.timeIntervalSince1970))
            let due = options.creditLeadTime.days.filter { expiry.timeIntervalSince(now) <= Double($0) * 86_400 }.min()
            for days in options.creditLeadTime.days {
                let id = creditPrefix + identity + ".\(days)d"
                let target = expiry.addingTimeInterval(-Double(days) * 86_400)
                // A more urgent overdue reminder replaces older missed lead times.
                if target <= now, days != due { continue }
                if let acknowledged = state.acknowledgements[id], acknowledged <= now, !pendingIdentifiers.contains(id) { continue }
                let date = expiry.formatted(.dateTime.year().month().day().hour().minute().locale(L10n.locale))
                result.append(ReminderRequest(id: id, kind: .creditExpiry,
                    title: L10n.text("Codex reset credit expiry"),
                    body: L10n.text("A reset credit last reported as available expires on \(date). Check its current status in Codex."),
                    deliveryAt: target > now ? target : nil, acknowledgementKeys: [id]))
            }
        }
        return result
    }

    public mutating func acknowledge(_ request: ReminderRequest, now: Date) {
        for key in request.acknowledgementKeys { state.acknowledgements[key] = request.deliveryAt ?? now }
        for key in state.windows.keys where state.windows[key]?.pendingRecovery?.id == request.id {
            state.windows[key]?.pendingRecovery = nil
        }
        state.acknowledgements = state.acknowledgements.filter { now.timeIntervalSince($0.value) < 90 * 86_400 }
        if state.acknowledgements.count > 512 {
            state.acknowledgements = Dictionary(uniqueKeysWithValues: state.acknowledgements.sorted { $0.value > $1.value }.prefix(512).map { ($0.key, $0.value) })
        }
    }

    private static func fingerprint(_ text: String) -> String {
        String(text.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }, radix: 16)
    }
}
