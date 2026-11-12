import SwiftUI

struct WorkspaceNavigationRow: View {
    let destination: WorkspaceDestination

    var body: some View {
        Label {
            Text(destination.title)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: destination.symbol).accessibilityHidden(true)
        }
            .font(.system(size: 13))
            .accessibilityLabel(destination.title)
            .padding(.vertical, 5)
            .tag(destination)
    }
}
