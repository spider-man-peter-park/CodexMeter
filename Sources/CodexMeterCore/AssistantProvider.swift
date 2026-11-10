import Foundation

public enum AssistantProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case codex, cursor, deepseekHarness
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .deepseekHarness: "DeepSeek Harness"
        }
    }
}

public enum ProviderConnectionStatus: String, Equatable, Sendable {
    case loading, ready, notFound, signInRequired, unavailable, unsupported
}

public enum ProviderUsageScope: String, Equatable, Sendable {
    case accountPeriod, localSessions
}

public struct ProviderSessionUsage: Identifiable, Equatable, Sendable {
    public let id: String
    public var tokens: Int?
    public var modelSeconds: Double?
    public var decodeTokensPerSecond: Double?
    public var updatedAt: Date?

    public init(id: String, tokens: Int? = nil, modelSeconds: Double? = nil,
                decodeTokensPerSecond: Double? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.tokens = tokens
        self.modelSeconds = modelSeconds
        self.decodeTokensPerSecond = decodeTokensPerSecond
        self.updatedAt = updatedAt
    }
}

/// Provider-native measurements; absent fields never imply zero or a Codex quota window.
public struct ProviderUsageSnapshot: Equatable, Sendable {
    public let provider: AssistantProvider
    public let scope: ProviderUsageScope
    public let sampledAt: Date
    public var periodLabel: String?
    public var periodStart: Date?
    public var resetAt: Date?
    public var usedPercent: Double?
    public var costUSD: Double?
    public var limitUSD: Double?
    public var totalTokens: Int?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var cachedInputTokens: Int?
    public var cacheWriteTokens: Int?
    public var requestCount: Int?
    public var sessionCount: Int?
    public var decodeTokensPerSecond: Double?
    public var modelSeconds: Double?
    public var isPartial = false
    public var sessions: [ProviderSessionUsage] = []

    public init(provider: AssistantProvider, scope: ProviderUsageScope, sampledAt: Date) {
        self.provider = provider
        self.scope = scope
        self.sampledAt = sampledAt
    }
}

public struct ProviderUsageResult: Equatable, Sendable {
    public let provider: AssistantProvider
    public let status: ProviderConnectionStatus
    public let snapshot: ProviderUsageSnapshot?
    public let message: String

    public init(provider: AssistantProvider, status: ProviderConnectionStatus,
                snapshot: ProviderUsageSnapshot? = nil, message: String) {
        self.provider = provider
        self.status = status
        self.snapshot = snapshot
        self.message = message
    }
}
