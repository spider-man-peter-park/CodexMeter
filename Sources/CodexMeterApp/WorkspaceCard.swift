import SwiftUI

struct WorkspaceCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(MeterStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(MeterStyle.rule.opacity(0.5)))
    }
}
