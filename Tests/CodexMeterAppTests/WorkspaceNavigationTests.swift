import CodexMeterCore
import Testing
@testable import CodexMeterApp

@MainActor struct WorkspaceNavigationTests {
    @Test func localAndAccountRoutesConvergeOnUsage() {
        let navigation = WorkspaceNavigation()
        for destination in [WorkspaceDestination.detail(.today), .detail(.account), .usage] {
            navigation.select(destination)
            #expect(navigation.destination == .usage)
        }
        navigation.select(.detail(MenuBarMetric.todayTokens.detailSection))
        #expect(navigation.destination == .usage)
        #expect(WorkspaceDestination.codexDestinations == [.detail(.quota), .usage, .detail(.speed)])
    }

    @Test func otherDestinationsRetainTheirOwnNavigation() {
        let navigation = WorkspaceNavigation()
        for destination in [WorkspaceDestination.overview, .detail(.quota), .detail(.speed), .detail(.cpu)] {
            navigation.select(destination)
            #expect(navigation.destination == destination)
        }
    }

    @Test func settingsRoutesRemainInsideWorkspaceAndRememberTheirCategory() {
        let navigation = WorkspaceNavigation()
        navigation.select(.detail(.settings))
        #expect(navigation.destination == .settings(.general))
        navigation.select(.settings(.metrics))
        navigation.select(.usage)
        #expect(navigation.settingsDestination == .settings(.metrics))
        navigation.select(navigation.settingsDestination)
        #expect(navigation.destination == .settings(.metrics))
        #expect(navigation.destination.detailSection == .settings)
        navigation.select(.overview)
        #expect(navigation.destination == .overview)
        #expect(navigation.settingsDestination == .settings(.metrics))
    }
}
