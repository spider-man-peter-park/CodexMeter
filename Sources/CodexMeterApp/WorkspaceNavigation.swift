import SwiftUI

@MainActor final class WorkspaceNavigation: ObservableObject {
    @Published private(set) var destination: WorkspaceDestination = .overview
    private var lastSettingsPane: SettingsPane = .general

    var settingsDestination: WorkspaceDestination { .settings(lastSettingsPane) }

    func select(_ destination: WorkspaceDestination) {
        let next = destination.canonical
        if case .settings(let pane) = next { lastSettingsPane = pane }
        self.destination = next
    }
}
