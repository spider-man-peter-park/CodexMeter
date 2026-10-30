import CodexMeterCore
import Foundation
import SwiftUI

@MainActor final class AppUpdates: ObservableObject {
    @Published var automaticallyChecks: Bool {
        didSet {
            defaults.set(automaticallyChecks, forKey: "automaticallyCheckForUpdates")
            if automaticallyChecks && started { check() }
            if !automaticallyChecks { task?.cancel() }
            configureTimer()
        }
    }
    @Published private(set) var checking = false
    @Published private(set) var latestVersion: AppReleaseVersion?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var warning: String?
    private let defaults: UserDefaults
    private let client: AppUpdateClient
    private let currentVersion: AppReleaseVersion?
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var started = false

    var updateAvailable: Bool {
        guard let currentVersion, let latestVersion else { return false }
        return latestVersion > currentVersion
    }

    init(defaults: UserDefaults = .standard, client: AppUpdateClient = AppUpdateClient(), version: String = AppMetadata.version) {
        self.defaults = defaults
        self.client = client
        currentVersion = AppReleaseVersion(version)
        automaticallyChecks = defaults.object(forKey: "automaticallyCheckForUpdates") as? Bool ?? AppDefaults.automaticallyCheckForUpdates
        lastChecked = defaults.object(forKey: "lastUpdateCheck") as? Date
        latestVersion = defaults.string(forKey: "latestAppVersion").flatMap(AppReleaseVersion.init)
    }

    func start() {
        guard !started else { return }
        started = true
        if automaticallyChecks { check() }
        configureTimer()
    }

    private func configureTimer() {
        timer?.invalidate()
        timer = nil
        guard started && automaticallyChecks else { return }
        timer = Timer(timeInterval: 3_600, repeats: true) { [weak self] _ in
            Task { @MainActor in guard let self, self.automaticallyChecks else { return }; self.check() }
        }
        timer?.tolerance = 60
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func stop() { started = false; timer?.invalidate(); timer = nil; task?.cancel() }

    func check(force: Bool = false, now: Date = Date()) {
        guard !checking else { return }
        if !force, let lastChecked {
            let age = now.timeIntervalSince(lastChecked)
            if age >= 0 && age < 43_200 { return }
        }
        checking = true
        warning = nil
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.checking = false }
            do {
                let latest = try await self.client.latestVersion()
                guard !Task.isCancelled else { return }
                self.latestVersion = latest
                self.lastChecked = Date()
                self.defaults.set(latest.description, forKey: "latestAppVersion")
                self.defaults.set(self.lastChecked, forKey: "lastUpdateCheck")
            } catch {
                guard !Task.isCancelled else { return }
                self.warning = "Unable to check for updates. Try again later."
                // Failed automatic checks back off too; a manual check is always available.
                self.lastChecked = Date()
                self.defaults.set(self.lastChecked, forKey: "lastUpdateCheck")
            }
        }
    }
}
