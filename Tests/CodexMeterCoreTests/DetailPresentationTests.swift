import Testing
@testable import CodexMeterCore

struct DetailPresentationTests {
    @Test func everyMenuBarMetricOpensItsCorrespondingDetailSection() {
        let expected: [MenuBarMetric: DetailSection] = [
            .fiveHour: .quota,
            .weekly: .quota,
            .fallback: .quota,
            .todayTokens: .today,
            .tps: .speed,
            .cpu: .cpu,
            .gpu: .gpu,
            .ram: .ram,
            .network: .network
        ]
        #expect(Set(expected.keys) == Set(MenuBarMetric.allCases))
        for metric in MenuBarMetric.allCases {
            #expect(metric.detailSection == expected[metric])
        }
    }
}
