import PlaygroundLocalization
import ProjectionMotionKit
import SwiftUI

struct ProjectionBackdropControls: View {
    @Binding var configuration: ProjectionBackdropConfiguration
    @Environment(\.playgroundLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(language.text("Show projection backdrop"), isOn: $configuration.isEnabled)
                .toggleStyle(.checkbox)
            VStack(spacing: 14) {
                percentage("Backdrop opacity", value: $configuration.opacity)
                Text(language.text("0% is transparent; 100% uses the full configured backdrop."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                percentage("Black tint", value: $configuration.tintOpacity)
                percentage("Background blur", value: $configuration.blurIntensity)
            }
            .disabled(!configuration.isEnabled)
            Button(language.text("Backdrop defaults")) { configuration = ProjectionBackdropConfiguration() }
                .controlSize(.small)
            Text(language.text("Applies to the current projection display. Changes are saved automatically."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
    }

    private func percentage(_ title: String, value: Binding<Double>) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(language.text(title))
                Spacer()
                Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...1, step: 0.01) { Text(language.text(title)) }
                .labelsHidden()
                .accessibilityValue(Text(value.wrappedValue, format: .percent.precision(.fractionLength(0))))
        }
    }
}
