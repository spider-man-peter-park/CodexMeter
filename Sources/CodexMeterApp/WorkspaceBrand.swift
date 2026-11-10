import CodexMeterCore
import SwiftUI

struct WorkspaceBrand: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text(AppMetadata.name).font(.system(size: 16, weight: .semibold))
            }
            Text(L10n.text("Your focus, in view."))
                .font(MeterStyle.captionFont).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 12)
    }
}
