import Foundation
import Testing
@testable import CodexMeterApp

@MainActor struct DetailPanelSizingTests {
    @Test func panelFitsItsContentAndShrinksWhenSwitchingToAShorterModule() {
        let sizing = DetailPanelMeasurement()
        sizing.update([.header: 60, .footer: 48, .content: 650])
        #expect(sizing.viewportHeight(maximum: 1000) == 650)
        #expect(!sizing.needsScrolling(maximum: 1000))
        sizing.update([.content: 180])
        #expect(sizing.viewportHeight(maximum: 1000) == 180)
        #expect(!sizing.needsScrolling(maximum: 1000))
    }

    @Test func onlyContentExceedingTheScreenLimitNeedsScrolling() {
        let sizing = DetailPanelMeasurement()
        sizing.update([.header: 60, .footer: 48, .content: 1000])
        #expect(sizing.viewportHeight(maximum: 700) == 590)
        #expect(sizing.needsScrolling(maximum: 700))
        sizing.update([.content: .infinity, .header: .nan, .footer: -100])
        #expect(sizing.viewportHeight(maximum: 700) == 590)
        #expect(sizing.viewportHeight(maximum: 100) == 0)
    }
}
