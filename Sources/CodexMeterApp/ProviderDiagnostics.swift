import CodexMeterCore
import Foundation

enum ProviderDiagnostics {
    static func run(_ provider: AssistantProvider) async {
        let result: ProviderUsageResult
        switch provider {
        case .cursor: result = await CursorUsageReader().readUsage()
        case .deepseekHarness: result = await DeepSeekHarnessUsageReader().readUsage()
        case .codex: return
        }
        var output: [String: Any] = ["provider": provider.rawValue, "status": result.status.rawValue]
        if let snapshot = result.snapshot {
            output["scope"] = snapshot.scope.rawValue
            output["sampledAt"] = snapshot.sampledAt.ISO8601Format()
            output["period"] = snapshot.periodLabel
            output["totalTokens"] = snapshot.totalTokens
            output["sessionCount"] = snapshot.sessionCount
            output["usedPercent"] = snapshot.usedPercent
            output["allowanceUsedUSD"] = snapshot.costUSD
            output["allowanceLimitUSD"] = snapshot.limitUSD
            output["partial"] = snapshot.isPartial
        }
        if let bytes = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys, .prettyPrinted]) {
            print(String(decoding: bytes, as: UTF8.self))
        }
    }
}
