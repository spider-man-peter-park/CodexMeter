import AppKit
import CodexMeterCore
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var quota: QuotaSnapshot? {
        didSet { store(quota, forKey: quotaCacheKey) }
    }
    @Published var accountInfo: AccountInfoSnapshot? {
        didSet {
            store(accountInfo, forKey: accountCacheKey)
            recentTokenUsage = accountInfo.flatMap { $0.dailyUsageBuckets }
                .flatMap { TokenUsageSeries(buckets: $0) }
        }
    }
    @Published private(set) var recentTokenUsage: TokenUsageSeries?
    @Published private(set) var localDayUsage: LocalDayUsage?
    @Published private(set) var recentTPSSamples: [TPSSample] = []
    @Published private(set) var tpsHistoryBackfilling = true
    @Published private(set) var tpsHistoryIsUnattributed = false
    @Published var sample: TPSSample?
    @Published var now = Date()
    @Published var refreshing = false
    @Published var accountRefreshing = false
    @Published var settingsExpanded = false
    @Published var quotaWarning: String?
    @Published var accountWarning: String?
    @Published var latestUnmeasurable = false
    @Published var loginWarning: String?
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var options: DisplayOptions {
        didSet { saveDisplayOptions(); changed?() }
    }
    @Published var detailLayout: DetailLayout {
        didSet { store(detailLayout, forKey: "detailLayout"); changed?() }
    }
    @Published var refreshOptions: RefreshOptions {
        didSet {
            store(refreshOptions, forKey: "refreshOptions")
            if started { configureTimers() }
        }
    }
    @Published var autoRefresh: Bool {
        didSet {
            defaults.set(autoRefresh, forKey: "autoRefresh")
            if !autoRefresh { cancelRecoveryRefresh() }
        }
    }
    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: "appLanguage"); changed?() }
    }
    var changed: (() -> Void)?
    let reminders: AppReminders
    let initialLoginPreference: Bool?

    private let defaults: UserDefaults
    private let homeKey: String
    private let quotaCacheKey: String
    private let accountCacheKey: String
    private let monitor: LogMonitor
    private var timers: [Timer] = []
    private var quotaTask: Task<Void, Never>?
    private var accountTask: Task<Void, Never>?
    private var logTask: Task<Void, Never>?
    private var polling = false
    private var started = false
    private var sleeping = false
    private var pathAvailable = true
    private var recoveryQuotaPending = false
    private var recoveryAccountPending = false
    private var recoveryDebounceUntil = Date.distantPast
    private var recoveryTask: Task<Void, Never>?
    private var quotaGate = RecoveryRefreshGate(minimumInterval: 60, maximumBackoff: 900)
    private var accountGate = RecoveryRefreshGate(minimumInterval: 300, maximumBackoff: 1800)
    private let readQuota: @Sendable (URL) async throws -> QuotaSnapshot
    private let readAccount: @Sendable (URL) async throws -> AccountInfoSnapshot
    private let recoveryClock: @MainActor () -> Date
    private let recoverySleep: @MainActor (TimeInterval) async throws -> Void

    static func codexHome(defaults: UserDefaults = .standard) -> URL {
        let path = defaults.string(forKey: "codexHome")
            ?? ProcessInfo.processInfo.environment["CODEX_HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
    }

    init(defaults: UserDefaults = .standard,
         notificationCenter: any ReminderNotificationCenter = SystemReminderCenter(),
         readQuota: @escaping @Sendable (URL) async throws -> QuotaSnapshot = { try await AppServerClient().readQuota(codexHome: $0) },
         readAccount: @escaping @Sendable (URL) async throws -> AccountInfoSnapshot = { try await AppServerClient().readAccountInfo(codexHome: $0) },
         recoveryClock: @escaping @MainActor () -> Date = { Date() },
         recoverySleep: @escaping @MainActor (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.defaults = defaults
        let legacyDisplayKeys = ["fullMode", "showFiveHour", "showWeekly", "showCountdown", "showTPS",
                                 "quotaLabelStyle", "countdownStyle", "tpsDecimals", "showTPSLabel"]
        let hasLegacyDisplay = legacyDisplayKeys.contains { defaults.object(forKey: $0) != nil }
        let hasSavedPreferences = (legacyDisplayKeys + ["displaySchemaVersion", "displayOptions", "detailLayout",
            "refreshOptions", "reminderOptions", "appLanguage", "autoRefresh", "automaticallyCheckForUpdates"])
            .contains { defaults.object(forKey: $0) != nil }
        initialLoginPreference = hasSavedPreferences ? nil : AppDefaults.launchAtLogin
        language = AppLanguage(rawValue: defaults.string(forKey: "appLanguage") ?? "") ?? AppDefaults.language
        detailLayout = defaults.data(forKey: "detailLayout")
            .flatMap { try? JSONDecoder().decode(DetailLayout.self, from: $0) } ?? AppDefaults.detailLayout
        self.readQuota = readQuota
        self.readAccount = readAccount
        self.recoveryClock = recoveryClock
        self.recoverySleep = recoverySleep
        let home = Self.codexHome(defaults: defaults)
        let hash = home.standardizedFileURL.path.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        homeKey = String(hash, radix: 16)
        reminders = AppReminders(defaults: defaults, scope: homeKey, center: notificationCenter)
        quotaCacheKey = "lastValidQuota." + homeKey
        accountCacheKey = "lastValidAccountInfo." + homeKey
        let display = AppDefaults.display
        defaults.register(defaults: ["showFiveHour": display.showFiveHour, "showWeekly": display.showWeekly,
                                     "showCountdown": display.showCountdown, "showTPS": display.showTPS,
                                     "fullMode": display.fullMode, "autoRefresh": AppDefaults.autoRefresh,
                                     "quotaLabelStyle": display.quotaLabelStyle.rawValue,
                                     "countdownStyle": display.countdownStyle.rawValue,
                                     "tpsDecimals": display.tpsDecimals, "showTPSLabel": display.showTPSLabel])
        if hasLegacyDisplay && defaults.integer(forKey: "displaySchemaVersion") < 2 {
            defaults.set("ai", forKey: "quotaLabelStyle")
            defaults.set(true, forKey: "showCountdown")
        }
        if defaults.integer(forKey: "displaySchemaVersion") < 2 {
            defaults.set(2, forKey: "displaySchemaVersion")
        }
        if let bytes = defaults.data(forKey: "displayOptions"),
           let saved = try? JSONDecoder().decode(DisplayOptions.self, from: bytes) {
            options = saved
        } else {
            var migrated = display
            migrated.fullMode = defaults.bool(forKey: "fullMode")
            migrated.showFiveHour = defaults.bool(forKey: "showFiveHour")
            migrated.showWeekly = defaults.bool(forKey: "showWeekly")
            migrated.showCountdown = defaults.bool(forKey: "showCountdown")
            migrated.showTPS = defaults.bool(forKey: "showTPS")
            migrated.quotaLabelStyle = QuotaLabelStyle(rawValue: defaults.string(forKey: "quotaLabelStyle") ?? "") ?? display.quotaLabelStyle
            migrated.countdownStyle = CountdownStyle(rawValue: defaults.string(forKey: "countdownStyle") ?? "") ?? display.countdownStyle
            migrated.tpsDecimals = defaults.integer(forKey: "tpsDecimals")
            migrated.showTPSLabel = defaults.bool(forKey: "showTPSLabel")
            options = migrated
        }
        if let bytes = defaults.data(forKey: "refreshOptions"),
           let saved = try? JSONDecoder().decode(RefreshOptions.self, from: bytes) {
            refreshOptions = saved
        } else { refreshOptions = AppDefaults.refresh }
        autoRefresh = defaults.bool(forKey: "autoRefresh")
        monitor = LogMonitor(home: home)
        if let bytes = defaults.data(forKey: quotaCacheKey),
           var saved = try? JSONDecoder().decode(QuotaSnapshot.self, from: bytes) {
            saved.isStale = true
            quota = saved
        }
        if let bytes = defaults.data(forKey: accountCacheKey),
           var saved = try? JSONDecoder().decode(AccountInfoSnapshot.self, from: bytes) {
            saved.isStale = true
            accountInfo = saved
            recentTokenUsage = saved.dailyUsageBuckets.flatMap { TokenUsageSeries(buckets: $0) }
            accountWarning = "Showing saved account statistics until the next successful refresh."
        }
    }

    func start() {
        guard !started else { return }
        started = true
        reminders.start()
        refresh()
        configureTimers()
    }

    func stop() {
        started = false
        cancelRecoveryRefresh()
        reminders.stop()
        timers.forEach { $0.invalidate() }
        timers.removeAll()
        quotaTask?.cancel()
        accountTask?.cancel()
        logTask?.cancel()
    }

    private func configureTimers() {
        timers.forEach { $0.invalidate() }
        timers.removeAll()
        timer(every: refreshOptions.logInterval) { [weak self] in
            guard let self, self.autoRefresh, !self.sleeping else { return }
            self.pollLogs()
        }
        timer(every: refreshOptions.quotaInterval) { [weak self] in
            guard let self, self.autoRefresh, !self.sleeping else { return }
            self.refreshQuota()
        }
        timer(every: refreshOptions.accountInterval) { [weak self] in
            guard let self, self.autoRefresh, !self.sleeping else { return }
            self.refreshAccountInfo()
        }
        timer(every: refreshOptions.displayInterval) { [weak self] in
            self?.now = Date()
            self?.changed?()
        }
    }

    private func timer(every interval: TimeInterval, action: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor in action() }
        }
        timer.tolerance = min(5, interval * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }

    func refresh() {
        now = Date()
        pollLogs()
        refreshQuota()
        refreshAccountInfo()
    }

    private func refreshQuota() {
        guard !refreshing else { return }
        recoveryQuotaPending = false
        quotaGate.began(at: recoveryClock())
        refreshing = true
        quotaTask = Task { [weak self] in
            guard let self else { return }
            defer { self.refreshing = false; self.changed?(); self.scheduleRecoveryRefresh() }
            do {
                let fresh = try await self.readQuota(Self.codexHome(defaults: self.defaults))
                guard !Task.isCancelled else { return }
                self.quotaGate.finished(success: true)
                self.recoveryQuotaPending = false
                self.quota = fresh
                self.quotaWarning = nil
                self.reminders.receiveLiveQuota(fresh)
            } catch {
                guard !Task.isCancelled else { return }
                self.quotaGate.finished(success: false)
                let logs = await self.monitor.poll()
                if self.quota == nil || (logs.cachedQuota?.updatedAt ?? .distantPast) > (self.quota?.updatedAt ?? .distantPast) {
                    self.quota = logs.cachedQuota ?? self.quota
                }
                self.quotaWarning = "Live quota unavailable. Showing the last valid data, which may be outdated."
                self.apply(logs)
            }
        }
    }

    private func refreshAccountInfo() {
        guard !accountRefreshing else { return }
        recoveryAccountPending = false
        accountGate.began(at: recoveryClock())
        accountRefreshing = true
        accountTask = Task { [weak self] in
            guard let self else { return }
            defer { self.accountRefreshing = false; self.scheduleRecoveryRefresh() }
            do {
                let fresh = try await self.readAccount(Self.codexHome(defaults: self.defaults))
                guard !Task.isCancelled else { return }
                self.accountGate.finished(success: true)
                self.recoveryAccountPending = false
                self.accountInfo = fresh
                self.accountWarning = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.accountGate.finished(success: false)
                if var previous = self.accountInfo { previous.isStale = true; self.accountInfo = previous }
                self.accountWarning = (error as? LocalizedError)?.errorDescription ?? L10n.text("Account statistics are temporarily unavailable.")
            }
        }
    }

    private func pollLogs() {
        guard !polling else { return }
        polling = true
        logTask = Task { [weak self] in
            guard let self else { return }
            let snapshot = await self.monitor.poll()
            guard !Task.isCancelled else { self.polling = false; return }
            self.apply(snapshot)
            self.polling = false
        }
    }

    private func apply(_ snapshot: LogSnapshot) {
        if let latest = snapshot.latestSample { sample = latest }
        localDayUsage = snapshot.todayUsage
        recentTPSSamples = snapshot.recentSamples
        tpsHistoryBackfilling = snapshot.historyBackfilling
        tpsHistoryIsUnattributed = snapshot.historyIsUnattributed
        latestUnmeasurable = snapshot.hasUnmeasurableResponse
        if quota == nil { quota = snapshot.cachedQuota }
        changed?()
    }

    func systemWillSleep() {
        sleeping = true
        cancelRecoveryRefresh()
    }

    func systemDidWake(canRefresh: Bool) {
        sleeping = false
        now = Date()
        changed?()
        if canRefresh { requestRecoveryRefresh() }
    }

    func networkPathChanged(available: Bool, recovered: Bool) {
        pathAvailable = available
        if !available { recoveryTask?.cancel(); recoveryTask = nil }
        if recovered { requestRecoveryRefresh() }
    }

    func requestRecoveryRefresh() {
        guard started, autoRefresh, !sleeping, pathAvailable else { return }
        recoveryQuotaPending = true
        recoveryAccountPending = true
        recoveryDebounceUntil = recoveryClock().addingTimeInterval(3)
        pollLogs()
        scheduleRecoveryRefresh()
    }

    private func cancelRecoveryRefresh() {
        recoveryTask?.cancel(); recoveryTask = nil
        recoveryQuotaPending = false; recoveryAccountPending = false
    }

    private func scheduleRecoveryRefresh() {
        recoveryTask?.cancel(); recoveryTask = nil
        guard started, autoRefresh, !sleeping, pathAvailable else { return }
        let time = recoveryClock()
        var delays: [TimeInterval] = []
        if recoveryQuotaPending && !refreshing { delays.append(quotaGate.delay(at: time)) }
        if recoveryAccountPending && !accountRefreshing { delays.append(accountGate.delay(at: time)) }
        guard let minimum = delays.min() else { return }
        let delay = max(minimum, recoveryDebounceUntil.timeIntervalSince(time), 0)
        recoveryTask = Task { [weak self] in
            guard let self else { return }
            do { try await self.recoverySleep(delay) } catch { return }
            guard !Task.isCancelled, self.started, self.autoRefresh, !self.sleeping, self.pathAvailable else { return }
            self.recoveryTask = nil
            let time = self.recoveryClock()
            if self.recoveryQuotaPending && !self.refreshing && self.quotaGate.delay(at: time) <= 0 { self.refreshQuota() }
            if self.recoveryAccountPending && !self.accountRefreshing && self.accountGate.delay(at: time) <= 0 { self.refreshAccountInfo() }
            self.scheduleRecoveryRefresh()
        }
    }

    func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        loginEnabled = status == .enabled
        loginWarning = status == .requiresApproval
            ? "Allow CodexMeter in System Settings → General → Login Items." : nil
    }

    func applyInitialLoginPreference() {
        guard let initialLoginPreference, !defaults.bool(forKey: "initialLoginPreferenceHandled") else { return }
        defaults.set(true, forKey: "initialLoginPreferenceHandled")
        setLogin(initialLoginPreference)
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLoginStatus()
        } catch {
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginWarning = "Login item could not be changed. Install CodexMeter in Applications and try again."
        }
    }

    private func store<Value: Encodable>(_ value: Value?, forKey key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func saveDisplayOptions() {
        store(options, forKey: "displayOptions")
        defaults.set(options.fullMode, forKey: "fullMode")
        defaults.set(options.showFiveHour, forKey: "showFiveHour")
        defaults.set(options.showWeekly, forKey: "showWeekly")
        defaults.set(options.showCountdown, forKey: "showCountdown")
        defaults.set(options.showTPS, forKey: "showTPS")
        defaults.set(options.quotaLabelStyle.rawValue, forKey: "quotaLabelStyle")
        defaults.set(options.countdownStyle.rawValue, forKey: "countdownStyle")
        defaults.set(options.tpsDecimals, forKey: "tpsDecimals")
        defaults.set(options.showTPSLabel, forKey: "showTPSLabel")
    }
}
