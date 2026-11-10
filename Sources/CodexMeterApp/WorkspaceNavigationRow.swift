import SwiftUI

struct WorkspaceNavigationRow: View {
    let destination: WorkspaceDestination

    var body: some View {
        Label(destination.title, systemImage: destination.symbol)
            .font(.system(size: 13))
            .accessibilityLabel(destination.title)
            .padding(.vertical, 5)
            .tag(destination)
    }
}
