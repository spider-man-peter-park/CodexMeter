import Foundation
import Testing
import UserNotifications
@testable import CodexMeterApp
@testable import CodexMeterCore

actor TestReminderCenter: ReminderNotificationCenter {
    var status: ReminderAuthorization
    var prompts = 0
    var requests: [ReminderRequest] = []
    var pending: Set<String> = []
    var failNext = false
    init(_ status: ReminderAuthorization = .allowed) { self.status = status }
    func authorization() -> ReminderAuthorization { status }
    func requestPermission() -> Bool { prompts += 1; status = .allowed; return true }
    func pendingIdentifiers() -> Set<String> { pending }
    func add(_ request: ReminderRequest) throws {
        if failNext { failNext = false; throw URLError(.unknown) }
        requests.append(request)
        if request.deliveryAt != nil { pending.insert(request.id) }
    }
    func removePending(_ identifiers: [String]) { pending.subtract(identifiers) }
    func injectFailure() { failNext = true }
}

@Suite(.serialized) @MainActor struct ReminderIntegrationTests {
    private func defaults() throws -> UserDefaults {
        let suite = "io.github.codexmeter.reminder-tests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(suite, forKey: "testSuiteName")
        defaults.set(try JSONEncoder().encode(ReminderOptions()), forKey: "reminderOptions")
        return defaults
    }
    private func settle() async throws { try await Task.sleep(for: .milliseconds(80)) }
    private func snapshot(remaining: Double = 5, credits: ResetCreditSummary? = nil) -> QuotaSnapshot {
        QuotaSnapshot(fiveHour: nil,
            weekly: QuotaWindow(usedPercent: 100 - remaining, windowDurationMins: 10080, resetsAt: Date().addingTimeInterval(86400)),
            updatedAt: Date(), source: .appServer, resetCredits: credits)
    }

    @Test func noStartupPermissionPromptAndExplicitOptInPersists() async throws {
        let defaults = try defaults()
        defer { defaults.removePersistentDomain(forName: defaults.string(forKey: "testSuiteName")!) }
        let center = TestReminderCenter(.notDetermined)
        let reminders = AppReminders(defaults: defaults, scope: "test", center: center)
        reminders.start()
        try await settle()
        #expect(await center.prompts == 0)
        var options = reminders.options; options.lowQuotaEnabled = true
        reminders.setOptions(options)
        try await settle()
        #expect(await center.prompts == 1)
        #expect(reminders.authorization == .allowed)
        #expect(AppReminders(defaults: defaults, scope: "test", center: center).options.lowQuotaEnabled)
        reminders.stop()
    }

    @Test func unsupportedFiveHourWindowCancelsOnlyItsPendingAlertsWithoutPrompting() async throws {
        let defaults = try defaults()
        defer { defaults.removePersistentDomain(forName: defaults.string(forKey: "testSuiteName")!) }
        let center = TestReminderCenter()
        let reminders = AppReminders(defaults: defaults, scope: "test", center: center)
        var options = reminders.options
        options.lowQuotaEnabled = true
        reminders.setOptions(options)
        try await settle()
        let prefix = "io.github.codexmeter.reminders.test.quota."
        for window in ["fiveHour", "weekly"] {
            try await center.add(ReminderRequest(id: prefix + window + ".cycle.low.10", kind: .lowQuota,
                title: "Test", body: "Test", deliveryAt: Date().addingTimeInterval(3600), acknowledgementKeys: []))
        }
        reminders.start()
        reminders.setFiveHourAvailable(false)
        try await settle()
        #expect(await center.pending == [prefix + "weekly.cycle.low.10"])
        #expect(await center.prompts == 0)
        #expect(!reminders.options.fiveHourEnabled && reminders.options.weeklyEnabled)
        reminders.stop()
    }

    @Test func nativeCardTriggerPreservesAbsoluteDeadlineWithoutPrivatePayload() throws {
        let time = Date()
        let expiry = time.addingTimeInterval(5 * 86400)
        let credit = ResetCredit(id: "private-card-id", resetType: "full", status: "available", expiresAt: expiry)
        let data = QuotaSnapshot(fiveHour: nil, weekly: nil, updatedAt: time, source: .appServer,
            resetCredits: ResetCreditSummary(availableCount: 1, credits: [credit]))
        var options = ReminderOptions(); options.creditExpiryEnabled = true
        let request = try #require(ReminderEngine(scope: "test").creditRequests(data, options: options, now: time).first)
        let native = SystemReminderCenter.notificationRequest(for: request)
        let trigger = try #require(native.trigger as? UNCalendarNotificationTrigger)
        let target = try #require(trigger.nextTriggerDate())
        #expect(abs(target.timeIntervalSince(try #require(request.deliveryAt))) < 1)
        #expect(trigger.dateComponents.timeZone?.secondsFromGMT() == 0)
        #expect(!trigger.repeats)
        #expect(native.content.userInfo.isEmpty)
        #expect(!native.content.body.contains(credit.id))
    }

    @Test func cardSchedulesAreCancelledForUsedCardsAndWhenDisabled() async throws {
        let defaults = try defaults()
        defer { defaults.removePersistentDomain(forName: defaults.string(forKey: "testSuiteName")!) }
        let center = TestReminderCenter()
        let reminders = AppReminders(defaults: defaults, scope: "test", center: center)
        reminders.start()
        var options = reminders.options; options.creditExpiryEnabled = true
        reminders.setOptions(options)
        let credit = ResetCredit(id: "card", resetType: "full", status: "available", expiresAt: Date().addingTimeInterval(5 * 86400))
        reminders.receiveLiveQuota(snapshot(credits: ResetCreditSummary(availableCount: 1, credits: [credit])))
        try await settle()
        #expect(await center.pending.count == 2)
        reminders.receiveLiveQuota(snapshot(credits: ResetCreditSummary(availableCount: 0, credits: [])))
        try await settle()
        #expect(await center.pending.isEmpty)
        reminders.receiveLiveQuota(snapshot(credits: ResetCreditSummary(availableCount: 1, credits: [credit])))
        try await settle()
        #expect(await center.pending.count == 2)
        options.creditExpiryEnabled = false; reminders.setOptions(options)
        try await settle()
        #expect(await center.pending.isEmpty)
        reminders.stop()
    }

    @Test func scheduledCardsSurviveRestartUntilFreshAuthoritativeDataArrives() async throws {
        let defaults = try defaults()
        defer { defaults.removePersistentDomain(forName: defaults.string(forKey: "testSuiteName")!) }
        let center = TestReminderCenter()
        let first = AppReminders(defaults: defaults, scope: "test", center: center)
        var options = first.options; options.creditExpiryEnabled = true
        first.start(); first.setOptions(options)
        let credit = ResetCredit(id: "card", resetType: "full", status: "available", expiresAt: Date().addingTimeInterval(4 * 86400))
        first.receiveLiveQuota(snapshot(credits: ResetCreditSummary(availableCount: 1, credits: [credit])))
        try await settle()
        first.stop()
        let second = AppReminders(defaults: defaults, scope: "test", center: center)
        second.start()
        try await settle()
        #expect(await center.pending.count == 2)
        #expect(await center.requests.count == 2)
        second.stop()
    }

    @Test func failedLowAlertRetriesAndDeliveredAlertDoesNotRepeatAfterRestart() async throws {
        let defaults = try defaults()
        defer { defaults.removePersistentDomain(forName: defaults.string(forKey: "testSuiteName")!) }
        let center = TestReminderCenter()
        let first = AppReminders(defaults: defaults, scope: "test", center: center)
        var options = first.options; options.lowQuotaEnabled = true
        first.start(); first.setOptions(options)
        try await settle()
        await center.injectFailure()
        let data = snapshot()
        first.receiveLiveQuota(data)
        try await settle()
        #expect(first.warning != nil)
        first.receiveLiveQuota(data)
        try await settle()
        #expect(await center.requests.count == 1)
        first.stop()
        let second = AppReminders(defaults: defaults, scope: "test", center: center)
        second.start(); second.receiveLiveQuota(data)
        try await settle()
        #expect(await center.requests.count == 1)
        second.stop()
    }

    @Test func deniedPermissionNeverSchedulesNotifications() async throws {
        let defaults = try defaults()
        defer { defaults.removePersistentDomain(forName: defaults.string(forKey: "testSuiteName")!) }
        let center = TestReminderCenter(.denied)
        let reminders = AppReminders(defaults: defaults, scope: "test", center: center)
        var options = reminders.options; options.lowQuotaEnabled = true; options.creditExpiryEnabled = true
        reminders.start(); reminders.setOptions(options); reminders.receiveLiveQuota(snapshot())
        try await settle()
        #expect(reminders.authorization == .denied)
        #expect(await center.prompts == 0)
        #expect(await center.requests.isEmpty)
        reminders.stop()
    }

    @Test func recoveryRequestsMergeAndRespectAutomaticRefresh() async throws {
        let defaults = try defaults()
        defer { defaults.removePersistentDomain(forName: defaults.string(forKey: "testSuiteName")!) }
        defaults.set("/private/tmp/codexmeter-reminder-empty-" + UUID().uuidString, forKey: "codexHome")
        let reads = ReadCounter()
        let clock = RecoveryClock()
        let model = AppModel(defaults: defaults, notificationCenter: TestReminderCenter(),
            readQuota: { _ in await reads.quota() }, readAccount: { _ in await reads.account() },
            recoveryClock: { clock.now }, recoverySleep: { try await clock.sleep($0) })
        model.start()
        try await settle()
        #expect(await reads.quotaReads == 1)
        model.requestRecoveryRefresh(); model.requestRecoveryRefresh(); model.requestRecoveryRefresh()
        try await Task.sleep(for: .milliseconds(160))
        #expect(await reads.quotaReads == 2)
        #expect(await reads.accountReads == 2)
        #expect(clock.delays.contains { $0 >= 60 })
        model.autoRefresh = false
        model.systemWillSleep(); model.systemDidWake(canRefresh: true)
        model.networkPathChanged(available: false, recovered: false)
        model.networkPathChanged(available: true, recovered: true)
        try await settle()
        #expect(await reads.quotaReads == 2)
        model.refresh()
        try await settle()
        #expect(await reads.quotaReads == 3)
        model.stop()
    }

    @Test func inflightSuccessSatisfiesRecoveryAndSleepCancelsPendingWork() async throws {
        let defaults = try defaults()
        defer { defaults.removePersistentDomain(forName: defaults.string(forKey: "testSuiteName")!) }
        defaults.set("/private/tmp/codexmeter-reminder-empty-" + UUID().uuidString, forKey: "codexHome")
        let reads = ReadCounter()
        let clock = RecoveryClock()
        let model = AppModel(defaults: defaults, notificationCenter: TestReminderCenter(),
            readQuota: { _ in
                try await Task.sleep(for: .milliseconds(40))
                return await reads.quota()
            }, readAccount: { _ in await reads.account() },
            recoveryClock: { clock.now }, recoverySleep: { try await clock.sleep($0) })
        model.start()
        model.requestRecoveryRefresh()
        try await settle()
        #expect(await reads.quotaReads == 1)
        #expect(await reads.accountReads == 1)
        #expect(clock.delays.isEmpty)
        model.requestRecoveryRefresh()
        model.systemWillSleep()
        try await settle()
        #expect(await reads.quotaReads == 1)
        model.stop()
    }
}

private actor ReadCounter {
    var quotaReads = 0
    var accountReads = 0
    func quota() -> QuotaSnapshot {
        quotaReads += 1
        return QuotaSnapshot(fiveHour: nil, weekly: nil, updatedAt: Date(), source: .appServer)
    }
    func account() -> AccountInfoSnapshot { accountReads += 1; return AccountInfoSnapshot() }
}

@MainActor private final class RecoveryClock {
    var now = Date()
    var delays: [TimeInterval] = []
    func sleep(_ seconds: TimeInterval) async throws {
        delays.append(seconds)
        try await Task.sleep(for: .milliseconds(20))
        try Task.checkCancellation()
        now = now.addingTimeInterval(seconds)
    }
}
