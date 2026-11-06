import Combine
import Foundation
import Testing
@testable import CodexMeterApp
@testable import CodexMeterCore

@MainActor struct SettingsObservationTests {
    private func defaults() throws -> UserDefaults {
        let name = "io.github.codexmeter.settings-observation." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.set(name, forKey: "testSuiteName")
        defaults.set("/private/tmp/codexmeter-settings-observation-empty", forKey: "codexHome")
        return defaults
    }

    @Test func liveMetricChangesDoNotInvalidateSettings() throws {
        let defaults = try defaults()
        defer { defaults.removePersistentDomain(forName: defaults.string(forKey: "testSuiteName")!) }
        let model = AppModel(defaults: defaults)
        let settings = AppSettingsObservation(model: model)
        var settingsChanges = 0
        let subscription = settings.objectWillChange.sink { settingsChanges += 1 }
        defer { subscription.cancel() }

        for index in 0..<100 {
            model.now = Date(timeIntervalSince1970: Double(index))
            model.sample = TPSSample(id: "sample-\(index)", model: "synthetic", outputTokens: index + 1,
                reasoningTokens: 0, elapsedSeconds: 1, completedAt: model.now, isEstimated: true)
            model.refreshing = index.isMultiple(of: 2)
            model.accountRefreshing = index.isMultiple(of: 3)
            model.latestUnmeasurable = index.isMultiple(of: 5)
            model.quotaWarning = "Synthetic warning \(index)"
            model.accountWarning = "Synthetic warning \(index)"
        }
        #expect(settingsChanges == 0)
        model.options.showTPS.toggle()
        #expect(settingsChanges == 1)
    }

    @Test func preferenceBindingsStillUpdateAndPersistNestedFields() throws {
        let defaults = try defaults()
        defer { defaults.removePersistentDomain(forName: defaults.string(forKey: "testSuiteName")!) }
        let model = AppModel(defaults: defaults)
        let settings = AppSettingsObservation(model: model)
        var changes = 0
        let subscription = settings.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }

        settings.binding(\.options.fontSize).wrappedValue = 15
        settings.binding(\.options.ramDisplay.showIcon).wrappedValue = false
        settings.binding(\.refreshOptions.logSeconds).wrappedValue = 3
        settings.binding(\.autoRefresh).wrappedValue = false
        settings.binding(\.appearance).wrappedValue = .dark
        #expect(changes == 5)
        let restored = AppModel(defaults: defaults)
        #expect(restored.options.fontSize == 15)
        #expect(!restored.options.ramDisplay.showIcon)
        #expect(restored.refreshOptions.logSeconds == 3)
        #expect(!restored.autoRefresh)
        #expect(restored.appearance == .dark)
    }

    @Test func capabilityAndLoginUpdatesRemainObservableWithoutDuplicateNotifications() throws {
        let defaults = try defaults()
        defer { defaults.removePersistentDomain(forName: defaults.string(forKey: "testSuiteName")!) }
        let model = AppModel(defaults: defaults)
        let settings = AppSettingsObservation(model: model)
        var changes = 0
        let subscription = settings.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }

        let weeklyOnly = QuotaSnapshot(fiveHour: nil,
            weekly: QuotaWindow(usedPercent: 20, windowDurationMins: 10_080, resetsAt: nil),
            updatedAt: Date(), source: .appServer)
        model.quota = weeklyOnly
        #expect(model.fiveHourAvailable == false)
        #expect(changes > 0)
        let capabilityChanges = changes
        model.quota = weeklyOnly
        #expect(changes == capabilityChanges)
        model.loginWarning = "Synthetic login warning"
        #expect(changes == capabilityChanges + 1)
        model.loginWarning = "Synthetic login warning"
        #expect(changes == capabilityChanges + 1)
    }

    @Test func unchangedLogSnapshotsDoNotPublishButFreshnessStillAdvances() throws {
        let defaults = try defaults()
        defer { defaults.removePersistentDomain(forName: defaults.string(forKey: "testSuiteName")!) }
        let model = AppModel(defaults: defaults)
        let time = Date()
        var today = LocalDayUsage(dayStart: Calendar.current.startOfDay(for: time),
            timeZoneIdentifier: Calendar.current.timeZone.identifier, updatedAt: time)
        var snapshot = LogSnapshot(latestSample: nil, cachedQuota: nil, latestResponseAt: nil,
            hasUnmeasurableResponse: false, todayUsage: today)
        model.apply(snapshot)
        var changes = 0
        let subscription = model.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }

        model.apply(snapshot)
        #expect(changes == 0)
        today.updatedAt = time.addingTimeInterval(2)
        snapshot.todayUsage = today
        model.apply(snapshot)
        #expect(changes == 1)
        #expect(model.localDayUsage?.updatedAt == today.updatedAt)
    }
}
