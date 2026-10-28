import Foundation

public struct TokenUsageDay: Identifiable, Equatable, Sendable {
    public let day: String
    public let index: Int
    public let tokens: Int?
    public let segment: Int
    public var id: String { day }
    public var shortLabel: String { day.suffix(5).replacingOccurrences(of: "-", with: "/") }
}

public struct TokenUsageSeries: Equatable, Sendable {
    public let days: [TokenUsageDay]
    public var startDay: String { days[0].day }
    public var endDay: String { days[6].day }
    public var hasMissingDays: Bool { days.contains { $0.tokens == nil } }
    public var maximumTokens: Int? { days.compactMap(\.tokens).max() }

    public init?(buckets: [AccountDailyUsageBucket]) {
        let valid = buckets.filter { AccountInfoParser.validDay($0.startDate) }
        guard let latest = valid.map(\.startDate).max() else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let end = formatter.date(from: latest) else { return nil }
        let grouped = Dictionary(grouping: valid, by: \.startDate)
        var points: [TokenUsageDay] = []
        var segment = 0
        for offset in -6...0 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: end) else { return nil }
            let label = formatter.string(from: date)
            let counts = grouped[label]?.map(\.tokens) ?? []
            let tokens: Int?
            if let first = counts.first, first >= 0, counts.allSatisfy({ $0 == first }) {
                tokens = first
            } else {
                tokens = nil
                segment += 1
            }
            // Separate runs prevent a line from bridging dates with unknown usage.
            points.append(TokenUsageDay(day: label, index: offset + 6, tokens: tokens, segment: segment))
        }
        days = points
    }
}
