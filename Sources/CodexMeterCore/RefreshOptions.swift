import Foundation

public struct RefreshOptions: Codable, Equatable, Sendable {
    public var quotaSeconds: Int
    public var logSeconds: Double
    public var displaySeconds: Int
    public var accountSeconds: Int

    public init(quotaSeconds: Int = 180, logSeconds: Double = 2,
                displaySeconds: Int = 60, accountSeconds: Int = 900) {
        self.quotaSeconds = quotaSeconds
        self.logSeconds = logSeconds
        self.displaySeconds = displaySeconds
        self.accountSeconds = accountSeconds
    }

    // Network reads retain conservative minimum intervals even for externally edited preferences.
    public var quotaInterval: TimeInterval { TimeInterval(min(3600, max(60, quotaSeconds))) }
    public var accountInterval: TimeInterval { TimeInterval(min(86400, max(300, accountSeconds))) }
    public var logInterval: TimeInterval { logSeconds.isFinite ? min(30, max(1, logSeconds)) : 2 }
    public var displayInterval: TimeInterval { TimeInterval(min(300, max(5, displaySeconds))) }

    private enum CodingKeys: String, CodingKey {
        case quotaSeconds, logSeconds, displaySeconds, accountSeconds
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        quotaSeconds = try values.decodeIfPresent(Int.self, forKey: .quotaSeconds) ?? 180
        logSeconds = try values.decodeIfPresent(Double.self, forKey: .logSeconds) ?? 2
        displaySeconds = try values.decodeIfPresent(Int.self, forKey: .displaySeconds) ?? 60
        accountSeconds = try values.decodeIfPresent(Int.self, forKey: .accountSeconds) ?? 900
    }
}
