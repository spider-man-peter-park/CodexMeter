import CodexMeterCore
import Foundation
import SwiftUI
import UserNotifications

enum ReminderAuthorization: Sendable { case notDetermined, denied, allowed }

protocol ReminderNotificationCenter: Sendable {
    func authorization() async -> ReminderAuthorization
    func requestPermission() async throws -> Bool
    func pendingIdentifiers() async -> Set<String>
    func add(_ request: ReminderRequest) async throws
    func removePending(_ identifiers: [String]) async
}

final class SystemReminderCenter: NSObject, ReminderNotificationCenter, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }
    var openDetails: (@Sendable () -> Void)?
    func activate() { center.delegate = self }
    func authorization() async -> ReminderAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .allowed
        case .denied: return .denied
        default: return .notDetermined
        }
    }
    func requestPermission() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func pendingIdentifiers() async -> Set<String> { Set(await center.pendingNotificationRequests().map(\.identifier)) }
    func add(_ request: ReminderRequest) async throws {
        try await center.add(Self.notificationRequest(for: request))
    }
    static func notificationRequest(for request: ReminderRequest) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.threadIdentifier = "CodexMeter." + request.kind.rawValue
        var trigger: UNNotificationTrigger?
        if let date = request.deliveryAt {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let components = calendar.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second], from: date)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }
        return UNNotificationRequest(identifier: request.id, content: content, trigger: trigger)
    }
    func removePending(_ identifiers: [String]) async { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.list])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        openDetails?()
        completionHandler()
    }
}

@MainActor final class AppReminders: ObservableObject {
    @Published private(set) var options: ReminderOptions
    @Published private(set) var authorization = ReminderAuthorization.notDetermined
    @Published private(set) var warning: String?
    @Published private(set) var requestingPermission = false
    private let defaults: UserDefaults
    private let center: any ReminderNotificationCenter
    private let stateKey: String
    private var engine: ReminderEngine
    private var latest: QuotaSnapshot?
    private var observations: [QuotaSnapshot] = []
    private var task: Task<Void, Never>?
    private var permissionTask: Task<Void, Never>?
    private var revision = 0
    private var generation = 0
    private var processedRevision = -1
    private var started = false

    init(defaults: UserDefaults = .standard, scope: String, center: any ReminderNotificationCenter = SystemReminderCenter()) {
        self.defaults = defaults
        self.center = center
        stateKey = "reminderState." + scope
        options = defaults.data(forKey: "reminderOptions").flatMap { try? JSONDecoder().decode(ReminderOptions.self, from: $0) } ?? AppDefaults.reminders
        let saved = defaults.data(forKey: stateKey).flatMap { try? JSONDecoder().decode(ReminderState.self, from: $0) } ?? ReminderState()
        engine = ReminderEngine(state: saved, scope: scope)
    }

    func start() { guard !started else { return }; started = true; reconcile() }
    func activateSystemNotifications(openDetails: @escaping @Sendable () -> Void) {
        if let system = center as? SystemReminderCenter { system.openDetails = openDetails; system.activate() }
    }
    func stop() {
        started = false
        task?.cancel(); task = nil
        permissionTask?.cancel(); permissionTask = nil
        observations.removeAll()
    }
    func refreshAuthorization() { reconcile() }

    func setOptions(_ value: ReminderOptions) {
        generation += 1
        if (!options.recoveryEnabled && value.recoveryEnabled)
            || options.fiveHourEnabled != value.fiveHourEnabled || options.weeklyEnabled != value.weeklyEnabled
            || options.thresholds != value.thresholds { engine.resetRecoveryTracking() }
        options = value
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: "reminderOptions") }
        saveState()
        if value.anyEnabled { requestPermissionIfNeeded() }
        reconcile()
    }

    // Only an explicit settings action can enter the authorization prompt path.
    func requestPermissionIfNeeded() {
        guard permissionTask == nil else { return }
        requestingPermission = true
        permissionTask = Task { [weak self] in
            guard let self else { return }
            defer { self.requestingPermission = false; self.permissionTask = nil; self.reconcile() }
            let status = await self.center.authorization()
            guard !Task.isCancelled, self.options.anyEnabled else { return }
            self.authorization = status
            guard status == .notDetermined else { return }
            do {
                self.authorization = try await self.center.requestPermission() ? .allowed : .denied
            } catch {
                self.warning = "Notifications could not be enabled. Check System Settings → Notifications → CodexMeter."
            }
        }
    }

    func receiveLiveQuota(_ snapshot: QuotaSnapshot) {
        guard ReminderEngine.isFresh(snapshot, now: Date()) else { return }
        latest = snapshot
        observations.append(snapshot)
        if observations.count > 16 { observations.removeFirst(observations.count - 16) }
        reconcile()
    }

    private func reconcile() {
        revision += 1
        guard started, task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }
            while !Task.isCancelled && self.started && self.processedRevision != self.revision {
                let revision = self.revision
                self.authorization = await self.center.authorization()
                let pending = await self.center.pendingIdentifiers()
                guard !Task.isCancelled, self.started else { return }
                let generation = self.generation
                let now = Date()
                let currentOptions = self.options
                let active = self.authorization == .allowed && currentOptions.anyEnabled
                var immediate: [ReminderRequest] = []
                var samples = self.observations
                self.observations.removeAll()
                if samples.isEmpty, let latest = self.latest { samples = [latest] }
                if active {
                    for sample in samples {
                        immediate += self.engine.quotaRequests(sample, options: currentOptions, now: now)
                    }
                }
                let hasFreshCredits = self.latest.map { ReminderEngine.isFresh($0, now: now) } == true
                let credits = active ? self.latest.map { self.engine.creditRequests($0, options: currentOptions, now: now,
                    pendingIdentifiers: pending) } ?? [] : []
                let desired = Set(credits.map(\.id))
                let obsolete = pending.filter { id in
                    if id.hasPrefix("io.github.codexmeter.reminders."), !id.hasPrefix(self.engine.prefix) { return true }
                    guard id.hasPrefix(self.engine.prefix) else { return false }
                    if !active { return true }
                    if !id.hasPrefix(self.engine.creditPrefix) {
                        return (id.contains(".low.") && !currentOptions.lowQuotaEnabled)
                            || (id.hasSuffix(".recovered") && !currentOptions.recoveryEnabled)
                            || (id.contains(".fiveHour.") && !currentOptions.fiveHourEnabled)
                            || (id.contains(".weekly.") && !currentOptions.weeklyEnabled)
                    }
                    let selectedLead = currentOptions.creditLeadTime.days.contains { id.hasSuffix(".\($0)d") }
                    return !active || !currentOptions.creditExpiryEnabled || !selectedLead || (hasFreshCredits && !desired.contains(id))
                }
                await self.center.removePending(Array(obsolete))
                var submitted: Set<String> = []
                for request in immediate + credits {
                    guard !Task.isCancelled, self.started, generation == self.generation else { break }
                    guard submitted.insert(request.id).inserted else { continue }
                    if request.kind == .creditExpiry && pending.contains(request.id) { continue }
                    do {
                        try await self.center.add(request)
                        self.engine.acknowledge(request, now: now)
                        if generation != self.generation { await self.center.removePending([request.id]) }
                        self.warning = nil
                    } catch {
                        self.warning = "A reminder could not be scheduled. CodexMeter will try again after a fresh quota read."
                    }
                }
                self.saveState()
                self.processedRevision = revision
            }
        }
    }

    private func saveState() {
        if let data = try? JSONEncoder().encode(engine.state) { defaults.set(data, forKey: stateKey) }
    }
}
