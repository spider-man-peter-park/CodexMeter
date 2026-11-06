import AppKit
import CodexMeterCore
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum DetailSurface: Hashable { case popover, preview }

    @Published var quota: QuotaSnapshot? {
        didSet {
            store(quota, forKey: quotaCacheKey)
            updateFiveHourAvailability(from: quota)
        }
    }
    @Published private(set) var fiveHourAvailable: Bool?
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
    @Published private(set) var systemMetrics: SystemMetricsSnapshot?
    @Published private(set) var systemMetricsHistory: [SystemMetricsSnapshot] = []
    @Published var selectedDetailSection: DetailSection = .quota {
        didSet { if selectedDetailSection != oldValue { reconcileSystemDetailDemand() } }
    }
    @Published var selectedQuotaMetric: MenuBarMetric?
    @Published private(set) var systemMetricsNow = Date()
    var currentSystemMetrics: SystemMetricsSnapshot? { systemMetrics?.fresh(at: systemMetricsNow) }
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
        didSet {
            if fiveHourAvailable == false && options.showFiveHour { options.showFiveHour = false }
            saveDisplayOptions()
            reconcileSystemDetailDemand()
            changed?()
        }
    }
    @Published var detailLayout: DetailLayout {
        didSet { store(detailLayout, forKey: "detailLayout"); reconcileSystemDetailDemand(); changed?() }
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
    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: "appAppearance"); appearanceChanged?() }
    }
    var changed: (() -> Void)?
    var appearanceChanged: (() -> Void)?
    let reminders: AppReminders
    let initialLoginPreference: Bool?

    private let defaults: UserDefaults
    private let homeKey: String
    private let quotaCacheKey: String
    private let fiveHourAvailabilityKey: String
    private let accountCacheKey: String
    private let monitor: LogMonitor
    private let systemMonitor = SystemMetricsMonitor()
    private var timers: [Timer] = []
    private var quotaTask: Task<Void, Never>?
    private var accountTask: Task<Void, Never>?
    private var logTask: Task<Void, Never>?
    private var systemMetricsTask: Task<Void, Never>?
    private var systemMetricsGeneration = 0
    private var visibleDetailSurfaces: Set<DetailSurface> = []
    private var requestedDetailDemand = SystemMetricsDetailDemand()
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
            "refreshOptions", "reminderOptions", "appLanguage", "appAppearance", "autoRefresh", "automaticallyCheckForUpdates"])
            .contains { defaults.object(forKey: $0) != nil }
        initialLoginPreference = hasSavedPreferences ? nil : AppDefaults.launchAtLogin
        language = AppLanguage(rawValue: defaults.string(forKey: "appLanguage") ?? "") ?? AppDefaults.language
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appAppearance") ?? "") ?? .system
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
        fiveHourAvailabilityKey = "fiveHourAvailable." + homeKey
        accountCacheKey = "lastValidAccountInfo." + homeKey
        let display = AppDefaults.display
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
            migrated.fullMode = defaults.object(forKey: "fullMode") as? Bool ?? display.fullMode
            migrated.showFiveHour = defaults.object(forKey: "showFiveHour") as? Bool ?? display.showFiveHour
            migrated.showWeekly = defaults.object(forKey: "showWeekly") as? Bool ?? display.showWeekly
            migrated.showCountdown = defaults.object(forKey: "showCountdown") as? Bool ?? display.showCountdown
            migrated.showTPS = defaults.object(forKey: "showTPS") as? Bool ?? display.showTPS
            migrated.quotaLabelStyle = QuotaLabelStyle(rawValue: defaults.string(forKey: "quotaLabelStyle") ?? "") ?? display.quotaLabelStyle
            migrated.countdownStyle = CountdownStyle(rawValue: defaults.string(forKey: "countdownStyle") ?? "") ?? display.countdownStyle
            migrated.tpsDecimals = defaults.object(forKey: "tpsDecimals") as? Int ?? display.tpsDecimals
            migrated.showTPSLabel = defaults.object(forKey: "showTPSLabel") as? Bool ?? display.showTPSLabel
            options = migrated
        }
        if let bytes = defaults.data(forKey: "refreshOptions"),
           let saved = try? JSONDecoder().decode(RefreshOptions.self, from: bytes) {
            refreshOptions = saved
        } else { refreshOptions = AppDefaults.refresh }
        autoRefresh = defaults.object(forKey: "autoRefresh") as? Bool ?? AppDefaults.autoRefresh
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
        if let available = defaults.object(forKey: fiveHourAvailabilityKey) as? Bool {
            applyFiveHourAvailability(available)
        } else {
            updateFiveHourAvailability(from: quota, allowSavedSnapshot: true)
        }
    }

    private func updateFiveHourAvailability(from snapshot: QuotaSnapshot?, allowSavedSnapshot: Bool = false) {
        // A failed read, a log fallback or a credits-only response cannot establish plan windows.
        guard let snapshot, snapshot.source == .appServer,
              allowSavedSnapshot || !snapshot.isStale,
              snapshot.fiveHour != nil || snapshot.weekly != nil else { return }
        applyFiveHourAvailability(snapshot.fiveHour != nil)
    }

    private func applyFiveHourAvailability(_ available: Bool) {
        fiveHourAvailable = available
        defaults.set(available, forKey: fiveHourAvailabilityKey)
        reminders.setFiveHourAvailable(available)
        if !available && options.showFiveHour { options.showFiveHour = false }
        changed?()
    }

    func start() {
        guard !started else { return }
        started = true
        reminders.start()
        refresh()
        pollSystemMetrics(reset: true)
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
        cancelSystemMetrics()
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
        // Local hardware sampling is independent of Codex account refresh intervals.
        timer(every: 2) { [weak self] in
            guard let self, !self.sleeping, self.needsSystemMetrics else { return }
            let time = Date()
            self.expireSystemMetrics(at: time)
            self.pollSystemMetrics()
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

    var needsSystemMetrics: Bool {
        options.showCPU || options.showGPU || options.showRAM || options.showNetworkUpload || options.showNetworkDownload
            || (!visibleDetailSurfaces.isEmpty && [.cpu, .gpu, .ram, .network].contains(selectedDetailSection))
    }

    var systemDetailDemand: SystemMetricsDetailDemand {
        guard !visibleDetailSurfaces.isEmpty else { return SystemMetricsDetailDemand() }
        return SystemMetricsDetailDemand(processes: [.cpu, .ram].contains(selectedDetailSection),
            networkProcesses: selectedDetailSection == .network, gpuHardware: selectedDetailSection == .gpu)
    }

    func setDetailPresented(_ presented: Bool, on surface: DetailSurface) {
        if presented { visibleDetailSurfaces.insert(surface) }
        else { visibleDetailSurfaces.remove(surface) }
        reconcileSystemDetailDemand()
    }

    private func reconcileSystemDetailDemand() {
        let next = systemDetailDemand
        let changed = next != requestedDetailDemand
        requestedDetailDemand = next
        guard started, !sleeping else { return }
        guard needsSystemMetrics else { cancelSystemMetrics(); return }
        if changed || systemMetrics == nil { pollSystemMetrics() }
    }

    private func pollSystemMetrics(reset: Bool = false) {
        guard started, !sleeping, systemMetricsTask == nil else { return }
        guard needsSystemMetrics else {
            if systemMetrics != nil { cancelSystemMetrics() }
            return
        }
        let generation = systemMetricsGeneration
        let demand = systemDetailDemand
        let shouldReset = reset || systemMetrics == nil
        systemMetricsTask = Task { [weak self] in
            guard let self else { return }
            if shouldReset { await self.systemMonitor.reset() }
            let snapshot = await self.systemMonitor.sample(demand: demand)
            guard !Task.isCancelled, generation == self.systemMetricsGeneration, self.started, !self.sleeping else { return }
            if self.systemDetailDemand != demand {
                self.systemMetricsTask = nil
                self.pollSystemMetrics()
                return
            }
            self.systemMetricsTask = nil
            self.applySystemMetrics(snapshot)
        }
    }

    func applySystemMetrics(_ snapshot: SystemMetricsSnapshot, at time: Date = Date()) {
        systemMetrics = snapshot
        let chronological = systemMetricsHistory.last.map { snapshot.sampledAt >= $0.sampledAt } ?? true
        var history = chronological ? systemMetricsHistory : []
        // Construct the chart window locally so observers receive one history update per sample.
        history.append(Self.historySnapshot(snapshot))
        systemMetricsHistory = Array(history.filter {
            snapshot.sampledAt.timeIntervalSince($0.sampledAt) <= 120
        }.suffix(61))
        systemMetricsNow = time
        changed?()
    }

    func expireSystemMetrics(at time: Date) {
        guard let snapshot = systemMetrics, snapshot.fresh(at: time) == nil else { return }
        let history = systemMetricsHistory.filter {
            let age = time.timeIntervalSince($0.sampledAt)
            return age >= 0 && age <= 120
        }
        if history.count != systemMetricsHistory.count { systemMetricsHistory = history }
        guard currentSystemMetrics != nil else { return }
        // A delayed sampler still expires displayed readings without publishing every timer tick.
        systemMetricsNow = time
        changed?()
    }

    static func historySnapshot(_ snapshot: SystemMetricsSnapshot) -> SystemMetricsSnapshot {
        SystemMetricsSnapshot(sampledAt: snapshot.sampledAt, cpuUsagePercent: snapshot.cpuUsagePercent,
            gpuUsagePercent: snapshot.gpuUsagePercent, memoryUsedBytes: snapshot.memoryUsedBytes,
            memoryTotalBytes: snapshot.memoryTotalBytes)
    }

    private func cancelSystemMetrics() {
        systemMetricsGeneration += 1
        let generation = systemMetricsGeneration
        let previous = systemMetricsTask
        previous?.cancel()
        let monitor = systemMonitor
        // Serialize cleanup with any in-flight sample before a wake or visibility change resumes it.
        systemMetricsTask = Task { [weak self] in
            await previous?.value
            await monitor.reset()
            guard let self, generation == self.systemMetricsGeneration else { return }
            self.systemMetricsTask = nil
            if self.started && !self.sleeping && self.needsSystemMetrics { self.pollSystemMetrics(reset: true) }
        }
        systemMetrics = nil
        systemMetricsHistory.removeAll()
        changed?()
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

    func apply(_ snapshot: LogSnapshot) {
        var menuChanged = false
        if let latest = snapshot.latestSample, latest != sample {
            sample = latest
            menuChanged = true
        }
        if localDayUsage != snapshot.todayUsage {
            var previous = localDayUsage
            if let time = snapshot.todayUsage?.updatedAt { previous?.updatedAt = time }
            // Freshness belongs to the detail view; the menu displays totals and availability.
            menuChanged = menuChanged || previous != snapshot.todayUsage
            localDayUsage = snapshot.todayUsage
        }
        if recentTPSSamples != snapshot.recentSamples { recentTPSSamples = snapshot.recentSamples }
        if tpsHistoryBackfilling != snapshot.historyBackfilling { tpsHistoryBackfilling = snapshot.historyBackfilling }
        if tpsHistoryIsUnattributed != snapshot.historyIsUnattributed { tpsHistoryIsUnattributed = snapshot.historyIsUnattributed }
        if latestUnmeasurable != snapshot.hasUnmeasurableResponse {
            latestUnmeasurable = snapshot.hasUnmeasurableResponse
            menuChanged = true
        }
        if quota == nil, let cached = snapshot.cachedQuota {
            quota = cached
            menuChanged = true
        }
        if menuChanged { changed?() }
    }

    func systemWillSleep() {
        sleeping = true
        cancelSystemMetrics()
        cancelRecoveryRefresh()
    }

    func systemDidWake(canRefresh: Bool) {
        sleeping = false
        now = Date()
        changed?()
        pollSystemMetrics(reset: true)
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
