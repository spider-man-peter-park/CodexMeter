import CodexMeterCore
import Foundation

@MainActor final class AssistantUsageStore: ObservableObject {
    @Published private(set) var results: [AssistantProvider: ProviderUsageResult] = [:]
    var changed: (() -> Void)?
    private let read: @Sendable (AssistantProvider, Date) async -> ProviderUsageResult
    private var task: Task<Void, Never>?
    private var polling: AssistantProvider?
    private var generation = 0

    init(preview: Bool = false,
         read: (@Sendable (AssistantProvider, Date) async -> ProviderUsageResult)? = nil) {
        if let read { self.read = read; return }
        let cursor = CursorUsageReader()
        let deepseek = DeepSeekHarnessUsageReader()
        self.read = { provider, now in
            if preview { return UIPreviewFixtures.usage(for: provider, at: now) }
            switch provider {
            case .cursor: return await cursor.readUsage(now: now)
            case .deepseekHarness: return await deepseek.readUsage(now: now)
            case .codex: return ProviderUsageResult(provider: .codex, status: .unavailable, message: "")
            }
        }
    }

    func result(for provider: AssistantProvider) -> ProviderUsageResult {
        results[provider] ?? ProviderUsageResult(provider: provider, status: .loading,
            message: "Waiting for usage data.")
    }

    func refresh(_ provider: AssistantProvider) {
        guard provider != .codex else { stop(); return }
        guard task == nil || polling != provider else { return }
        stop()
        let currentGeneration = generation
        polling = provider
        results[provider] = ProviderUsageResult(provider: provider, status: .loading,
            message: "Reading usage data…")
        changed?()
        let reader = read
        task = Task { [weak self] in
            let result = await reader(provider, Date())
            guard let self, !Task.isCancelled, self.generation == currentGeneration else { return }
            self.results[provider] = result
            self.task = nil
            self.polling = nil
            self.changed?()
        }
    }

    func stop() {
        generation &+= 1
        task?.cancel()
        task = nil
        polling = nil
    }
}
