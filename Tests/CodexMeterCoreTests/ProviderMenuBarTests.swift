import Foundation
import Testing
@testable import CodexMeterCore

struct ProviderMenuBarTests {
    private func usage(_ provider: AssistantProvider = .cursor) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(provider: provider, scope: provider == .cursor ? .accountPeriod : .localSessions,
            sampledAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func cursorShowsRemainingAllowanceAndClampsExhaustionWithoutInventingZero() {
        var snapshot = usage()
        snapshot.usedPercent = 63
        let ready = MenuBarFormatter.providerItem(.init(provider: .cursor, status: .ready, snapshot: snapshot, message: ""), autoRefresh: true)
        #expect(ready.title == "Cu 37%" && ready.metric == .focus)
        #expect(ready.accessibilityLabel == L10n.text("Cursor, \(37) percent of the current allowance remaining"))
        snapshot.usedPercent = 120
        #expect(MenuBarFormatter.providerItem(.init(provider: .cursor, status: .ready, snapshot: snapshot, message: ""), autoRefresh: true).title == "Cu 0%")
        snapshot.usedPercent = 0
        #expect(MenuBarFormatter.providerItem(.init(provider: .cursor, status: .ready, snapshot: snapshot, message: ""), autoRefresh: true).title == "Cu 100%")
        snapshot.usedPercent = nil
        #expect(MenuBarFormatter.providerItem(.init(provider: .cursor, status: .ready, snapshot: snapshot, message: ""), autoRefresh: true).title == "Cu —")
    }

    @Test func cursorCostFallbackNamesUsageRatherThanAnInvoiceCharge() {
        var snapshot = usage()
        snapshot.costUSD = 12.34
        let result = MenuBarFormatter.providerItem(.init(provider: .cursor, status: .ready, snapshot: snapshot, message: ""), autoRefresh: true)
        #expect(result.title == "Cu $12.3")
        let amount = "$12.3"
        #expect(result.accessibilityLabel == L10n.text("Cursor, \(amount) of reported allowance used, not an invoice or payment charge"))
        for invalid in [-1.0, .nan, .infinity] {
            snapshot.costUSD = invalid
            #expect(MenuBarFormatter.providerItem(.init(provider: .cursor, status: .ready, snapshot: snapshot, message: ""), autoRefresh: true).title == "Cu —")
        }
    }

    @Test func deepseekRetainsLocalNonForkedScopeAndPartialCheckpointMessage() {
        var snapshot = usage(.deepseekHarness)
        snapshot.totalTokens = 1_800_000
        snapshot.isPartial = true
        let message = "Partial local non-forked session totals, not today's usage or an account bill. Checkpoints may lag behind Harness."
        let result = MenuBarFormatter.providerItem(.init(provider: .deepseekHarness, status: .ready, snapshot: snapshot, message: message), autoRefresh: true)
        #expect(result.title == "DS " + TokenCountFormatter.compact(1_800_000))
        #expect(result.accessibilityLabel.contains(L10n.lookup(message)))
        #expect(result.accessibilityLabel.contains(L10n.text("Partial coverage")))
        snapshot.totalTokens = 0
        #expect(MenuBarFormatter.providerItem(.init(provider: .deepseekHarness, status: .ready, snapshot: snapshot, message: ""), autoRefresh: true).title == "DS 0")
        snapshot.totalTokens = nil
        #expect(MenuBarFormatter.providerItem(.init(provider: .deepseekHarness, status: .ready, snapshot: snapshot, message: ""), autoRefresh: true).title == "DS —")
    }

    @Test func statesUseStableIdentityAndDoNotDisplayFailedSnapshotsAsFreshReadings() {
        var snapshot = usage(.deepseekHarness)
        snapshot.totalTokens = 123
        for provider in [AssistantProvider.cursor, .deepseekHarness] {
            for status in [ProviderConnectionStatus.loading, .ready, .notFound, .signInRequired, .unavailable, .unsupported] {
                let item = MenuBarFormatter.providerItem(.init(provider: provider, status: status, snapshot: nil, message: "Fixture status"), autoRefresh: true)
                #expect(item.metric == .focus)
                #expect(item.title == (provider == .cursor ? "Cu" : "DS") + (status == .loading ? " …" : " —"))
                if status == .loading { #expect(item.symbolName == "clock") }
                else if status != .ready { #expect(item.symbolName == "exclamationmark.triangle") }
            }
        }
        let failed = MenuBarFormatter.providerItem(.init(provider: .deepseekHarness, status: .unavailable, snapshot: snapshot, message: ""), autoRefresh: true)
        #expect(failed.title == "DS —")
        let paused = MenuBarFormatter.providerItem(.init(provider: .deepseekHarness, status: .ready, snapshot: snapshot, message: ""), autoRefresh: false)
        #expect(paused.symbolName == "pause.fill" && paused.title == "DS 123")
        #expect(paused.accessibilityLabel.contains(L10n.text("Automatic refresh paused")))
    }
}
