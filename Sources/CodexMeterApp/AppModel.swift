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
        didSet { store(accountInfo, forKey: accountCacheKey) }
    }
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
    @Published var refreshOptions: RefreshOptions {
        didSet {
            store(refreshOptions, forKey: "refreshOptions")
            if started { configureTimers() }
        }
    }
    @Published var autoRefresh: Bool {
        didSet { defaults.set(autoRefresh, forKey: "autoRefresh") }
    }
    var changed: (() -> Void)?

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

    static func codexHome(defaults: UserDefaults = .standard) -> URL {
        let path = defaults.string(forKey: "codexHome")
            ?? ProcessInfo.processInfo.environment["CODEX_HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let home = Self.codexHome(defaults: defaults)
        let hash = home.standardizedFileURL.path.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        homeKey = String(hash, radix: 16)
        quotaCacheKey = "lastValidQuota." + homeKey
        accountCacheKey = "lastValidAccountInfo." + homeKey
        defaults.register(defaults: ["showFiveHour": true, "showWeekly": true, "showCountdown": true,
                                     "showTPS": true, "fullMode": false, "autoRefresh": true,
                                     "quotaLabelStyle": "ai", "countdownStyle": "compact",
                                     "tpsDecimals": 0, "showTPSLabel": true])
        if defaults.integer(forKey: "displaySchemaVersion") < 2 {
            defaults.set("ai", forKey: "quotaLabelStyle")
            defaults.set(true, forKey: "showCountdown")
            defaults.set(2, forKey: "displaySchemaVersion")
        }
        if let bytes = defaults.data(forKey: "displayOptions"),
           let saved = try? JSONDecoder().decode(DisplayOptions.self, from: bytes) {
            options = saved
        } else {
            options = DisplayOptions(fullMode: defaults.bool(forKey: "fullMode"),
                showFiveHour: defaults.bool(forKey: "showFiveHour"),
                showWeekly: defaults.bool(forKey: "showWeekly"),
                showCountdown: defaults.bool(forKey: "showCountdown"),
                showTPS: defaults.bool(forKey: "showTPS"),
                quotaLabelStyle: QuotaLabelStyle(rawValue: defaults.string(forKey: "quotaLabelStyle") ?? "") ?? .ai,
                countdownStyle: CountdownStyle(rawValue: defaults.string(forKey: "countdownStyle") ?? "") ?? .compact,
                tpsDecimals: defaults.integer(forKey: "tpsDecimals"),
                showTPSLabel: defaults.bool(forKey: "showTPSLabel"))
        }
        if let bytes = defaults.data(forKey: "refreshOptions"),
           let saved = try? JSONDecoder().decode(RefreshOptions.self, from: bytes) {
            refreshOptions = saved
        } else { refreshOptions = RefreshOptions() }
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
            accountWarning = "Showing saved account statistics until the next successful refresh."
        }
    }

    func start() {
        guard !started else { return }
        started = true
        refresh()
        configureTimers()
    }

    func stop() {
        started = false
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
            guard let self, self.autoRefresh else { return }
            self.pollLogs()
        }
        timer(every: refreshOptions.quotaInterval) { [weak self] in
            guard let self, self.autoRefresh else { return }
            self.refreshQuota()
        }
        timer(every: refreshOptions.accountInterval) { [weak self] in
            guard let self, self.autoRefresh else { return }
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
        refreshing = true
        quotaTask = Task { [weak self] in
            guard let self else { return }
            defer { self.refreshing = false; self.changed?() }
            do {
                let fresh = try await AppServerClient().readQuota(codexHome: Self.codexHome(defaults: self.defaults))
                guard !Task.isCancelled else { return }
                self.quota = fresh
                self.quotaWarning = nil
            } catch {
                guard !Task.isCancelled else { return }
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
        accountRefreshing = true
        accountTask = Task { [weak self] in
            guard let self else { return }
            defer { self.accountRefreshing = false }
            do {
                let fresh = try await AppServerClient().readAccountInfo(codexHome: Self.codexHome(defaults: self.defaults))
                guard !Task.isCancelled else { return }
                self.accountInfo = fresh
                self.accountWarning = nil
            } catch {
                guard !Task.isCancelled else { return }
                if var previous = self.accountInfo { previous.isStale = true; self.accountInfo = previous }
                self.accountWarning = (error as? LocalizedError)?.errorDescription ?? "Account statistics are temporarily unavailable."
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
        latestUnmeasurable = snapshot.hasUnmeasurableResponse
        if quota == nil { quota = snapshot.cachedQuota }
        changed?()
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginWarning = SMAppService.mainApp.status == .requiresApproval
                ? "Allow CodexMeter in System Settings → General → Login Items." : nil
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
