import Combine
import Foundation
import Testing
@testable import CodexMeterApp
@testable import CodexMeterCore

@MainActor struct MultiProviderIntegrationTests {
    private func preferences() throws -> (UserDefaults, String) {
        let suite = "io.github.codexmeter.multi-provider." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("/private/tmp/" + suite, forKey: "codexHome")
        return (defaults, suite)
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while !(await condition()) {
            try #require(clock.now < deadline, "Timed out waiting for the injected provider reader")
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func ready(_ provider: AssistantProvider, tokens: Int) -> ProviderUsageResult {
        var value = ProviderUsageSnapshot(provider: provider, scope: .localSessions,
            sampledAt: Date(timeIntervalSince1970: 1_800_000_000))
        value.totalTokens = tokens
        return ProviderUsageResult(provider: provider, status: .ready, snapshot: value, message: "Fixture usage")
    }

    @Test func providerDefaultsAndSelectionPersistWithoutRewritingDisplayPreferences() throws {
        let (defaults, suite) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        #expect(model.provider == .codex)
        var display = model.options
        display.fontSize = 15
        display.showTPS = false
        model.options = display
        let savedDisplay = try #require(defaults.data(forKey: "displayOptions"))
        for provider in [AssistantProvider.cursor, .deepseekHarness, .codex] {
            model.provider = provider
            #expect(defaults.string(forKey: "assistantProvider") == provider.rawValue)
            #expect(defaults.data(forKey: "displayOptions") == savedDisplay)
            let restored = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
            #expect(restored.provider == provider && restored.options == display)
        }
    }

    @Test func manualExternalRefreshRoutesOnlyToTheSelectedProvider() async throws {
        let (defaults, suite) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let reads = CodexReadCounts()
        let model = AppModel(defaults: defaults, notificationCenter: TestReminderCenter(),
            readQuota: { _ in await reads.quotaRead(); throw AppServerError.queryFailed },
            readAccount: { _ in await reads.accountRead(); throw AppServerError.queryFailed })
        var requested: [AssistantProvider] = []
        model.externalRefreshRequested = { requested.append($0) }
        for provider in [AssistantProvider.cursor, .deepseekHarness] {
            model.provider = provider
            model.refresh()
        }
        for _ in 0..<10 { await Task.yield() }
        #expect(requested == [.cursor, .deepseekHarness])
        #expect(await reads.counts == [0, 0])
        #expect(!model.refreshing && !model.accountRefreshing)
        // The model is deliberately never started: no timer, hardware, log or login operation runs.
    }

    @Test func externalProvidersIgnoreOldHardwareItemsButVisibleWorkspaceModulesKeepDemand() throws {
        let (defaults, suite) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        model.menuBarMode = .individual
        #expect(model.options.showCPU && model.options.showGPU && model.options.showRAM)
        for provider in [AssistantProvider.cursor, .deepseekHarness] {
            model.provider = provider
            model.selectedDetailSection = .quota
            #expect(!model.needsSystemMetrics)
            #expect(model.systemDetailDemand == SystemMetricsDetailDemand())
            model.selectedDetailSection = .cpu
            model.setDetailPresented(true, on: .workspace)
            #expect(model.needsSystemMetrics)
            #expect(model.systemDetailDemand == SystemMetricsDetailDemand(processes: true))
            model.selectedDetailSection = .network
            #expect(model.systemDetailDemand == SystemMetricsDetailDemand(networkProcesses: true))
            model.setDetailPresented(false, on: .workspace)
            #expect(!model.needsSystemMetrics && model.systemDetailDemand == SystemMetricsDetailDemand())
        }
        model.provider = .codex
        #expect(model.needsSystemMetrics)
    }

    @Test func providerBindingNotifiesSettingsWhileLiveMetricsRemainIsolated() throws {
        let (defaults, suite) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, notificationCenter: TestReminderCenter())
        let observation = AppSettingsObservation(model: model)
        var publications = 0
        let subscription = observation.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }
        let original = model.options
        observation.binding(\.provider).wrappedValue = .cursor
        #expect(publications == 1 && model.provider == .cursor)
        observation.binding(\.provider).wrappedValue = .cursor
        #expect(publications == 1)
        for index in 0..<20 {
            model.now = Date(timeIntervalSince1970: Double(index))
            model.sample = TPSSample(id: "fixture-\(index)", model: "Fixture", outputTokens: index + 1,
                reasoningTokens: 0, elapsedSeconds: 1, completedAt: model.now, isEstimated: true)
        }
        #expect(publications == 1)
        observation.binding(\.provider).wrappedValue = .deepseekHarness
        observation.binding(\.provider).wrappedValue = .codex
        #expect(publications == 3 && model.options == original)
    }

    @Test func externalRefreshPublishesLoadingAndFailureWithoutKeepingAnOldSnapshot() async throws {
        let gate = ProviderReadGate()
        let store = AssistantUsageStore(read: { provider, _ in await gate.read(provider) })
        defer { store.stop(); Task { await gate.finishAll() } }
        var changes = 0
        store.changed = { changes += 1 }
        store.refresh(.cursor)
        #expect(store.result(for: .cursor).status == .loading && store.result(for: .cursor).snapshot == nil)
        try await waitUntil { await gate.count(.cursor) == 1 }
        await gate.complete(.cursor, with: ready(.cursor, tokens: 100))
        try await waitUntil { store.result(for: .cursor).status == .ready }
        #expect(store.result(for: .cursor).snapshot?.totalTokens == 100)
        store.refresh(.cursor)
        #expect(store.result(for: .cursor).status == .loading && store.result(for: .cursor).snapshot == nil)
        try await waitUntil { await gate.count(.cursor) == 2 }
        await gate.complete(.cursor, with: .init(provider: .cursor, status: .unavailable, message: "Fixture failure"))
        try await waitUntil { store.result(for: .cursor).status == .unavailable }
        #expect(store.result(for: .cursor).snapshot == nil && changes == 4)
    }

    @Test func returningToAProviderCannotPublishItsEarlierCancelledGeneration() async throws {
        let gate = ProviderReadGate()
        let store = AssistantUsageStore(read: { provider, _ in await gate.read(provider) })
        defer { store.stop(); Task { await gate.finishAll() } }
        var published: [Int] = []
        store.changed = { [weak store] in
            if let value = store?.result(for: .cursor), value.status == .ready,
               let count = value.snapshot?.totalTokens { published.append(count) }
        }
        store.refresh(.cursor)
        try await waitUntil { await gate.count(.cursor) == 1 }
        store.refresh(.deepseekHarness)
        try await waitUntil { await gate.count(.deepseekHarness) == 1 }
        store.refresh(.cursor)
        try await waitUntil { await gate.count(.cursor) == 2 }
        // The injected reader ignores cancellation, proving that publication is independently fenced.
        await gate.complete(.cursor, with: ready(.cursor, tokens: 111))
        await gate.complete(.deepseekHarness, with: ready(.deepseekHarness, tokens: 222))
        await gate.complete(.cursor, with: ready(.cursor, tokens: 333))
        try await waitUntil { store.result(for: .cursor).status == .ready }
        for _ in 0..<10 { await Task.yield() }
        #expect(published == [333])
        #expect(store.result(for: .cursor).snapshot?.totalTokens == 333)
        #expect(store.result(for: .deepseekHarness).status == .loading)
    }
}

private actor CodexReadCounts {
    private var quota = 0
    private var account = 0
    var counts: [Int] { [quota, account] }
    func quotaRead() { quota += 1 }
    func accountRead() { account += 1 }
}

private actor ProviderReadGate {
    private var calls: [AssistantProvider: Int] = [:]
    private var pending: [AssistantProvider: [CheckedContinuation<ProviderUsageResult, Never>]] = [:]

    func read(_ provider: AssistantProvider) async -> ProviderUsageResult {
        calls[provider, default: 0] += 1
        return await withCheckedContinuation { pending[provider, default: []].append($0) }
    }

    func count(_ provider: AssistantProvider) -> Int { calls[provider, default: 0] }

    func complete(_ provider: AssistantProvider, with value: ProviderUsageResult) {
        guard var queue = pending[provider], !queue.isEmpty else { return }
        let continuation = queue.removeFirst()
        pending[provider] = queue
        continuation.resume(returning: value)
    }

    func finishAll() {
        for (provider, queue) in pending {
            for continuation in queue {
                continuation.resume(returning: .init(provider: provider, status: .unavailable, message: "Fixture closed"))
            }
        }
        pending.removeAll()
    }
}
