import SwiftUI

@MainActor final class WorkspaceNavigation: ObservableObject {
    @Published var destination: WorkspaceDestination = .overview
}
