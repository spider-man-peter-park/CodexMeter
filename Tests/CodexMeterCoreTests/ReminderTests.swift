import Foundation
import Testing
@testable import CodexMeterCore

@Suite struct ReminderTests {
    private let time = Date(timeIntervalSince1970: 1_800_000_000)
    private func snapshot(_ remaining: Double, at date: Date, reset: Date? = nil,
                          source: QuotaSource = .appServer, stale: Bool = false,
                          credits: ResetCreditSummary? = nil) -> QuotaSnapshot {
        QuotaSnapshot(fiveHour: QuotaWindow(usedPercent: 100 - remaining, windowDurationMins: 300, resetsAt: reset),
                      weekly: nil, updatedAt: date, source: source, isStale: stale, resetCredits: credits)
    }
    private var enabled: ReminderOptions {
        var value = ReminderOptions(); value.lowQuotaEnabled = true; value.recoveryEnabled = true
        return value
    }

    @Test func defaultsAndCachedOrExpiredSnapshotsNeverNotify() {
        var engine = ReminderEngine(scope: "test")
        let condition1 = engine.quotaRequests(snapshot(5, at: time), options: ReminderOptions(), now: time).isEmpty
        #expect(condition1)
        let condition2 = engine.quotaRequests(snapshot(5, at: time, source: .logCache), options: enabled, now: time).isEmpty
        #expect(condition2)
        let condition3 = engine.quotaRequests(snapshot(5, at: time, stale: true), options: enabled, now: time).isEmpty
        #expect(condition3)
        let condition4 = engine.quotaRequests(snapshot(5, at: time.addingTimeInterval(-301)), options: enabled, now: time).isEmpty
        #expect(condition4)
        let condition5 = engine.quotaRequests(snapshot(5, at: time.addingTimeInterval(61)), options: enabled, now: time).isEmpty
        #expect(condition5)
    }

    @Test func thresholdsDeduplicateAcrossRestartAndDoNotRepeatOnSmallFluctuations() throws {
        var engine = ReminderEngine(scope: "test")
        let first = try #require(engine.quotaRequests(snapshot(19, at: time), options: enabled, now: time).first)
        #expect(first.kind == .lowQuota)
        engine.acknowledge(first, now: time)
        let condition6 = engine.quotaRequests(snapshot(21, at: time), options: enabled, now: time).isEmpty
        #expect(condition6)
        let condition7 = engine.quotaRequests(snapshot(19, at: time), options: enabled, now: time).isEmpty
        #expect(condition7)
        let second = try #require(engine.quotaRequests(snapshot(9, at: time), options: enabled, now: time).first)
        #expect(second.id != first.id)
        engine.acknowledge(second, now: time)
        let restored = try JSONDecoder().decode(ReminderState.self, from: JSONEncoder().encode(engine.state))
        var restarted = ReminderEngine(state: restored, scope: "test")
        let condition8 = restarted.quotaRequests(snapshot(8, at: time), options: enabled, now: time).isEmpty
        #expect(condition8)
    }

    @Test func skippedThresholdsProduceOneUrgentAlertAndRecoveryRequiresNewReading() throws {
        var engine = ReminderEngine(scope: "test")
        let low = engine.quotaRequests(snapshot(5, at: time, reset: time), options: enabled, now: time)
        #expect(low.count == 1)
        engine.acknowledge(try #require(low.first), now: time)
        let condition9 = engine.quotaRequests(snapshot(15, at: time), options: enabled, now: time).isEmpty
        #expect(condition9)
        let condition10 = engine.quotaRequests(snapshot(100, at: time, source: .logCache), options: enabled, now: time).isEmpty
        #expect(condition10)
        let recovery = engine.quotaRequests(snapshot(25, at: time), options: enabled, now: time)
        #expect(recovery.count == 1)
        #expect(recovery.first?.kind == .recoveredQuota)
        // Failed deliveries remain eligible until they are acknowledged.
        let retry = engine.quotaRequests(snapshot(30, at: time), options: enabled, now: time)
        #expect(retry.first?.id == recovery.first?.id)
        engine.acknowledge(try #require(retry.first), now: time)
        let condition11 = engine.quotaRequests(snapshot(31, at: time), options: enabled, now: time).isEmpty
        #expect(condition11)
        let condition12 = engine.quotaRequests(snapshot(19, at: time), options: enabled, now: time).first?.kind == .lowQuota
        #expect(condition12)
    }

    @Test func resetTimeAloneDoesNotClaimRecoveryAndConfirmedNewCycleRearms() throws {
        var engine = ReminderEngine(scope: "test")
        let first = try #require(engine.quotaRequests(snapshot(5, at: time, reset: time.addingTimeInterval(5)), options: enabled, now: time).first)
        engine.acknowledge(first, now: time)
        let later = time.addingTimeInterval(10)
        let condition13 = engine.quotaRequests(snapshot(5, at: later, reset: time.addingTimeInterval(5)), options: enabled, now: later).isEmpty
        #expect(condition13)
        let events = engine.quotaRequests(snapshot(5, at: later, reset: later.addingTimeInterval(18000)), options: enabled, now: later)
        #expect(events.count == 1)
        #expect(events.first?.kind == .lowQuota)
    }

    @Test func lowAlertsRearmAfterRefillEvenWithRecoveryNotificationsDisabled() throws {
        var options = ReminderOptions(); options.lowQuotaEnabled = true
        var engine = ReminderEngine(scope: "test")
        let first = try #require(engine.quotaRequests(snapshot(5, at: time), options: options, now: time).first)
        engine.acknowledge(first, now: time)
        let refill = engine.quotaRequests(snapshot(90, at: time), options: options, now: time)
        #expect(refill.isEmpty)
        let next = engine.quotaRequests(snapshot(5, at: time), options: options, now: time)
        #expect(next.count == 1)
        #expect(next.first?.id != first.id)
    }

    @Test func weeklyOnlyAndDisabledWindowsAreRespected() {
        let week = QuotaSnapshot(fiveHour: nil, weekly: QuotaWindow(usedPercent: 95, windowDurationMins: 10080, resetsAt: nil), updatedAt: time, source: .appServer)
        var engine = ReminderEngine(scope: "test")
        let condition14 = engine.quotaRequests(week, options: enabled, now: time).count == 1
        #expect(condition14)
        var options = enabled; options.weeklyEnabled = false
        let condition15 = engine.quotaRequests(week, options: options, now: time).isEmpty
        #expect(condition15)
    }

    @Test func cardSchedulesLeadTimesAndDeduplicatesDueReminders() throws {
        var options = enabled; options.creditExpiryEnabled = true
        var engine = ReminderEngine(scope: "test")
        let expiry = time.addingTimeInterval(4 * 86400)
        let credit = ResetCredit(id: "private-card-id", resetType: "full", status: "available", expiresAt: expiry)
        let data = snapshot(90, at: time, credits: ResetCreditSummary(availableCount: 1, credits: [credit]))
        let requests = engine.creditRequests(data, options: options, now: time)
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { !$0.id.contains(credit.id) })
        for request in requests { engine.acknowledge(request, now: time) }
        let near = time.addingTimeInterval(3.5 * 86400)
        let fresh = snapshot(90, at: near, credits: data.resetCredits)
        #expect(engine.creditRequests(fresh, options: options, now: near).isEmpty)
        var firstUse = ReminderEngine(scope: "new")
        let overdue = firstUse.creditRequests(fresh, options: options, now: near)
        #expect(overdue.count == 1)
        #expect(overdue.first?.deliveryAt == nil)
        firstUse.acknowledge(try #require(overdue.first), now: near)
        #expect(firstUse.creditRequests(fresh, options: options, now: near).isEmpty)
    }

    @Test func cardsRequireAuthoritativeAvailabilityAndKnownFutureExpiry() {
        var options = ReminderOptions(); options.creditExpiryEnabled = true
        let engine = ReminderEngine(scope: "test")
        for credit in [
            ResetCredit(id: "used", resetType: "full", status: "used", expiresAt: time.addingTimeInterval(100)),
            ResetCredit(id: "unknown", resetType: "full", status: "new_status", expiresAt: time.addingTimeInterval(100)),
            ResetCredit(id: "expired", resetType: "full", status: "available", expiresAt: time),
            ResetCredit(id: "no-expiry", resetType: "full", status: "available")
        ] {
            let data = snapshot(90, at: time, credits: ResetCreditSummary(availableCount: 1, credits: [credit]))
            #expect(engine.creditRequests(data, options: options, now: time).isEmpty)
        }
        #expect(engine.creditRequests(snapshot(90, at: time, credits: ResetCreditSummary(availableCount: 2)), options: options, now: time).isEmpty)
    }

    @Test func recoveryEventsIgnoreInitialConnectionAndWaitForNetworkAfterWake() {
        var policy = RecoveryEventPolicy()
        let condition16 = !policy.pathChanged(available: true)
        #expect(condition16)
        let condition17 = !policy.pathChanged(available: true)
        #expect(condition17)
        let condition18 = !policy.pathChanged(available: false)
        #expect(condition18)
        policy.willSleep()
        let condition19 = !policy.didWake()
        #expect(condition19)
        let condition20 = policy.pathChanged(available: true)
        #expect(condition20)
        let condition21 = !policy.pathChanged(available: true)
        #expect(condition21)
    }

    @Test func recoveryGateRateLimitsAndBacksOffFailuresWithoutChangingManualRefresh() {
        var gate = RecoveryRefreshGate(minimumInterval: 60, maximumBackoff: 900)
        #expect(gate.delay(at: time) == 0)
        gate.began(at: time); gate.finished(success: false)
        #expect(gate.delay(at: time.addingTimeInterval(10)) == 50)
        gate.began(at: time.addingTimeInterval(60)); gate.finished(success: false)
        #expect(gate.delay(at: time.addingTimeInterval(60)) == 120)
        for _ in 0..<10 { gate.finished(success: false) }
        #expect(gate.delay(at: time.addingTimeInterval(60)) == 900)
        gate.finished(success: true)
        #expect(gate.delay(at: time.addingTimeInterval(120)) == 0)
    }
}
