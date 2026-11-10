import CodexMeterCore
import SwiftUI

struct WorkspaceSystemStrip: View {
    let snapshot: SystemMetricsSnapshot?
    let navigate: (WorkspaceDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("This Mac")).font(.system(size: 15, weight: .semibold))
            HStack(spacing: 12) {
                ForEach(WorkspaceDestination.systemSections) { section in
                    Button {
                        navigate(.detail(section))
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(shortTitle(section), systemImage: section.symbol)
                                .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                                .accessibilityLabel(shortTitle(section))
                            Text(value(section)).font(.system(size: 16, weight: .medium)).monospacedDigit()
                                .foregroundStyle(.primary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.borderless)
                    .background(MeterStyle.surface, in: RoundedRectangle(cornerRadius: 8))
                    .help(section.title)
                }
            }
            Text(snapshot == nil
                 ? L10n.text("Open a system module for live readings. Hardware sampling stays off when it is not needed.")
                 : L10n.text("Local readings · every 2 seconds"))
                .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func shortTitle(_ section: DetailSection) -> String {
        switch section {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .ram: "RAM"
        default: L10n.text("Network")
        }
    }

    private func value(_ section: DetailSection) -> String {
        switch section {
        case .cpu: SystemMetricsFormatter.percent(snapshot?.cpuUsagePercent)
        case .gpu: SystemMetricsFormatter.percent(snapshot?.gpuUsagePercent)
        case .ram: SystemMetricsFormatter.percent(snapshot?.memoryUsagePercent)
        default: SystemMetricsFormatter.rate(snapshot?.networkDownloadBytesPerSecond)
        }
    }
}
