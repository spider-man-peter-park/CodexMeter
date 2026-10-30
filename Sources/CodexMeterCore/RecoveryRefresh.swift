import Foundation

public struct RecoveryRefreshGate: Sendable {
    public let minimumInterval: TimeInterval
    public let maximumBackoff: TimeInterval
    public private(set) var lastAttempt: Date?
    public private(set) var failures = 0
    public init(minimumInterval: TimeInterval, maximumBackoff: TimeInterval) {
        self.minimumInterval = minimumInterval
        self.maximumBackoff = maximumBackoff
    }
    public mutating func began(at date: Date) { lastAttempt = date }
    public mutating func finished(success: Bool) { failures = success ? 0 : min(6, failures + 1) }
    public func delay(at date: Date) -> TimeInterval {
        guard let lastAttempt else { return 0 }
        let interval = min(maximumBackoff, minimumInterval * pow(2, Double(max(0, failures - 1))))
        return max(0, interval - max(0, date.timeIntervalSince(lastAttempt)))
    }
}

public struct RecoveryEventPolicy: Sendable {
    public private(set) var pathAvailable: Bool?
    public private(set) var sleeping = false
    public init() {}
    public mutating func willSleep() { sleeping = true }
    public mutating func didWake() -> Bool { sleeping = false; return pathAvailable != false }
    public mutating func pathChanged(available: Bool) -> Bool {
        let recovered = pathAvailable == false && available && !sleeping
        pathAvailable = available
        return recovered
    }
}
