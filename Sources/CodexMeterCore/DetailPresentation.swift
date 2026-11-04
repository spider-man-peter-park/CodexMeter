public extension MenuBarMetric {
    var detailSection: DetailSection {
        switch self {
        case .fiveHour, .weekly, .fallback: .quota
        case .todayTokens: .today
        case .tps: .speed
        case .cpu: .cpu
        case .gpu: .gpu
        case .ram: .ram
        case .network: .network
        }
    }
}
