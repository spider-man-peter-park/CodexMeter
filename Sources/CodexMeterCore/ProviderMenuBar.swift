import Foundation

public extension MenuBarFormatter {
    /// Keeps the native status-item identity stable while its selected provider or reading changes.
    static func providerItem(_ result: ProviderUsageResult, autoRefresh: Bool) -> MenuBarItem {
        let prefix: String
        let normalSymbol: String
        switch result.provider {
        case .codex: prefix = "AI"; normalSymbol = "circle.hexagongrid.fill"
        case .cursor: prefix = "Cu"; normalSymbol = "cursorarrow"
        case .deepseekHarness: prefix = "DS"; normalSymbol = "circle.hexagongrid.fill"
        }
        let mayShowSnapshot = result.status == .ready || result.status == .loading
        let snapshot = mayShowSnapshot ? result.snapshot : nil
        var title = prefix + (result.status == .loading && snapshot == nil ? " …" : " —")
        var label = result.provider.title + ", " + L10n.text("Usage unavailable")
        if let snapshot {
            switch result.provider {
            case .cursor:
                if let used = snapshot.usedPercent, used.isFinite, used >= 0 {
                    let remaining = max(0, min(100, 100 - used))
                    let percentage = remaining > 0 && remaining < 0.5 ? "<1" : String(Int(remaining.rounded()))
                    title = prefix + " " + percentage + "%"
                    label = remaining > 0 && remaining < 0.5
                        ? L10n.text("Cursor, less than 1 percent of the current allowance remaining")
                        : L10n.text("Cursor, \(Int(remaining.rounded())) percent of the current allowance remaining")
                } else if let cost = snapshot.costUSD, cost.isFinite, cost >= 0 {
                    let amount = String(format: "$%.1f", locale: Locale(identifier: "en_US_POSIX"), cost)
                    title = prefix + " " + amount
                    label = L10n.text("Cursor, \(amount) of reported allowance used, not an invoice or payment charge")
                }
            case .deepseekHarness:
                if let tokens = snapshot.totalTokens, tokens >= 0 {
                    title = prefix + " " + TokenCountFormatter.compact(tokens)
                    label = L10n.text("DeepSeek Harness, \(tokens.formatted(.number.locale(L10n.locale))) tokens in local non-forked sessions, not today's usage or an account bill")
                }
            case .codex:
                break
            }
            if snapshot.isPartial { label += ". " + L10n.text("Partial coverage") }
        }
        if !result.message.isEmpty { label += ". " + L10n.lookup(result.message) }
        let symbol: String
        if !autoRefresh {
            symbol = "pause.fill"
            label += ". " + L10n.text("Automatic refresh paused")
        } else if result.status == .loading {
            symbol = "clock"
            label += ". " + L10n.text("Updating")
        } else if result.status != .ready {
            symbol = "exclamationmark.triangle"
        } else {
            symbol = normalSymbol
        }
        return MenuBarItem(metric: .focus, title: title, accessibilityLabel: label, symbolName: symbol)
    }
}
