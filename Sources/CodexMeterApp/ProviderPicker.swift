import CodexMeterCore
import SwiftUI

struct ProviderPicker: View {
    @Binding var selection: AssistantProvider

    var body: some View {
        Picker(L10n.text("Assistant"), selection: $selection) {
            ForEach(AssistantProvider.allCases) { provider in
                Text(provider.title).tag(provider)
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel(L10n.text("Assistant"))
    }
}
