import AppKit
import Charts
import CodexMeterCore
import SwiftUI

struct SystemMetricsDetailView: View {
    let section: DetailSection
    let snapshot: SystemMetricsSnapshot?
    let history: [SystemMetricsSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch section {
            case .cpu: cpuDetails
            case .gpu: gpuDetails
            case .ram: memoryDetails
            default: EmptyView()
            }
        }
        .font(MeterStyle.bodyFont)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cpuDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(DetailSection.cpu.title, symbol: DetailSection.cpu.symbol)
            HStack(alignment: .firstTextBaseline) {
                primaryValue(snapshot?.cpuUsagePercent)
                Spacer()
                Text(L10n.text("All cores")).font(MeterStyle.captionFont).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                smallMetric(L10n.text("User"), value: SystemMetricsFormatter.percent(snapshot?.cpuUserPercent))
                smallMetric(L10n.text("System"), value: SystemMetricsFormatter.percent(snapshot?.cpuSystemPercent))
                smallMetric(L10n.text("Idle"), value: SystemMetricsFormatter.percent(snapshot?.cpuIdlePercent))
            }
            SystemUsageHistoryChart(history: history, value: { $0.cpuUsagePercent })
            Divider()
            heading(L10n.text("Processor"), symbol: "cpu")
            valueRow(L10n.text("Physical cores"), value: snapshot?.physicalCoreCount.map(String.init) ?? "—")
            valueRow(L10n.text("Logical cores"), value: snapshot?.logicalCoreCount.map(String.init) ?? "—")
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("Load average")).font(MeterStyle.sectionFont)
                HStack(spacing: 12) {
                    smallMetric(L10n.text("1 min"), value: loadAverage(0))
                    smallMetric(L10n.text("5 min"), value: loadAverage(1))
                    smallMetric(L10n.text("15 min"), value: loadAverage(2))
                }
            }
            Divider()
            SystemProcessList(processes: snapshot?.cpuTopProcesses ?? [], mode: .cpu)
        }
    }

    private var memoryDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(DetailSection.ram.title, symbol: DetailSection.ram.symbol)
            valueRow(L10n.text("Memory pressure"), value: memoryPressureTitle)
            valueRow(L10n.text("RAM usage"), value: SystemMetricsFormatter.percent(snapshot?.memoryUsagePercent), prominent: true)
            SystemUsageHistoryChart(history: history, value: { $0.memoryUsagePercent })
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                valueRow(L10n.text("Memory used"), value: SystemMemoryUnits.format(snapshot?.memoryUsedBytes) + " / " + SystemMemoryUnits.format(snapshot?.memoryTotalBytes), prominent: true)
                MemoryCompositionBar(segments: memorySegments, total: snapshot?.memoryTotalBytes)
                ForEach(memorySegments) { segment in
                    HStack(spacing: 8) {
                        Circle().fill(segment.color).frame(width: 8, height: 8).accessibilityHidden(true)
                        Text(segment.title).foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        Text(SystemMemoryUnits.format(segment.bytes)).monospacedDigit()
                    }
                }
                valueRow(L10n.text("Swap used"), value: SystemMemoryUnits.format(snapshot?.memorySwapUsedBytes))
                Text(L10n.text("Available includes free memory and reclaimable cache."))
                    .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            SystemProcessList(processes: snapshot?.memoryTopProcesses ?? [], mode: .memory)
        }
    }

    private var gpuDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(DetailSection.gpu.title, symbol: DetailSection.gpu.symbol)
            primaryValue(snapshot?.gpuUsagePercent)
            Text(snapshot?.gpuUsagePercent == nil ? L10n.text("GPU utilization is unavailable on this Mac.") :
                L10n.text("Utilization is for the busiest reporting GPU."))
                .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SystemUsageHistoryChart(history: history, value: { $0.gpuUsagePercent })
            Divider()
            heading(L10n.text("Graphics hardware"), symbol: "display")
            if let names = snapshot?.gpuDeviceNames, !names.isEmpty {
                ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                    Text(name).font(.system(size: 15, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(L10n.text("GPU name unavailable")).foregroundStyle(.secondary)
            }
            valueRow(L10n.text("Default GPU unified memory"), value: snapshot?.gpuHasUnifiedMemory.map {
                $0 ? L10n.text("Yes") : L10n.text("No")
            } ?? "—")
            valueRow(L10n.text("Default GPU memory budget"), value: SystemMemoryUnits.format(snapshot?.gpuRecommendedWorkingSetBytes))
                .help(L10n.text("Recommended working-set limit, not current GPU memory usage."))
            HStack(spacing: 12) {
                smallMetric(L10n.text("Renderer"), value: SystemMetricsFormatter.percent(snapshot?.gpuRendererUsagePercent))
                smallMetric(L10n.text("Tiler"), value: SystemMetricsFormatter.percent(snapshot?.gpuTilerUsagePercent))
            }
            Text(L10n.text("Some GPU statistics may be unavailable. Per-process GPU usage is not reported."))
                .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var memoryPressureTitle: String {
        switch snapshot?.memoryPressure {
        case .some(.normal): L10n.text("Normal")
        case .some(.warning): L10n.text("Warning")
        case .some(.critical): L10n.text("Critical")
        case nil: L10n.text("Unavailable")
        }
    }

    private var memorySegments: [MemoryUsageSegment] {
        [MemoryUsageSegment(id: "app", title: L10n.text("App memory"), bytes: snapshot?.memoryAppBytes, color: .accentColor),
         MemoryUsageSegment(id: "wired", title: L10n.text("Wired"), bytes: snapshot?.memoryWiredBytes, color: .purple),
         MemoryUsageSegment(id: "compressed", title: L10n.text("Compressed"), bytes: snapshot?.memoryCompressedBytes, color: .teal),
         MemoryUsageSegment(id: "free", title: L10n.text("Available"), bytes: snapshot?.memoryFreeBytes, color: .secondary)]
    }

    private func loadAverage(_ index: Int) -> String {
        guard let loads = snapshot?.loadAverages, loads.indices.contains(index), loads[index].isFinite else { return "—" }
        return String(format: "%.2f", loads[index])
    }

    private func heading(_ title: String, symbol: String) -> some View {
        Label { Text(title) } icon: { Image(systemName: symbol).accessibilityHidden(true) }
            .font(MeterStyle.sectionFont)
    }

    private func primaryValue(_ value: Double?) -> some View {
        Text(SystemMetricsFormatter.percent(value)).font(MeterStyle.numberFont).monospacedDigit()
    }

    private func smallMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(MeterStyle.captionFont).foregroundStyle(.secondary)
            Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func valueRow(_ title: String, value: String, prominent: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).foregroundStyle(prominent ? .primary : .secondary)
            Spacer(minLength: 8)
            Text(value).fontWeight(prominent ? .semibold : .regular).monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MemoryUsageSegment: Identifiable {
    let id: String
    let title: String
    let bytes: UInt64?
    let color: Color
}

private struct MemoryCompositionBar: View {
    let segments: [MemoryUsageSegment]
    let total: UInt64?

    private var valid: Bool {
        guard let total, total > 0, segments.allSatisfy({ $0.bytes != nil && ($0.bytes ?? 0) <= total }) else { return false }
        return segments.reduce(0.0) { $0 + Double($1.bytes ?? 0) } <= Double(total)
    }

    var body: some View {
        if valid, let total {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(segments) { segment in
                        Rectangle().fill(segment.color)
                            .frame(width: geometry.size.width * CGFloat(Double(segment.bytes ?? 0) / Double(total)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        }
    }
}

struct SystemUsageHistoryData {
    static let duration: TimeInterval = 120
    static let axisValues: [Double] = [-120, -60, 0]

    struct Point: Identifiable, Equatable {
        let id: Int
        let time: Date
        let secondsFromEnd: TimeInterval
        let value: Double
        let segment: Int
    }

    let end: Date
    let hasHistory: Bool
    let points: [Point]

    init(history: [SystemMetricsSnapshot], value: (SystemMetricsSnapshot) -> Double?) {
        end = history.last?.sampledAt ?? .distantPast
        hasHistory = !history.isEmpty
        let windowEnd = end
        let start = windowEnd.addingTimeInterval(-Self.duration)
        var segment = 0
        var previous: Date?
        // Chart closures hold only scalar points, never complete hardware/process snapshots.
        points = history.suffix(61).enumerated().compactMap { index, snapshot in
            guard snapshot.sampledAt >= start, snapshot.sampledAt <= windowEnd,
                  let number = value(snapshot), number.isFinite, (0...100).contains(number) else {
                segment += 1
                return nil
            }
            if let previous, snapshot.sampledAt.timeIntervalSince(previous) > 10 { segment += 1 }
            previous = snapshot.sampledAt
            return Point(id: index, time: snapshot.sampledAt,
                         secondsFromEnd: snapshot.sampledAt.timeIntervalSince(windowEnd), value: number, segment: segment)
        }
    }

    func nearest(to selectedDate: Date?) -> Point? {
        guard let selectedDate else { return nil }
        let offset = selectedDate.timeIntervalSince(end)
        guard offset.isFinite, (-Self.duration...0).contains(offset) else { return nil }
        return points.min { abs($0.time.timeIntervalSince(selectedDate)) < abs($1.time.timeIntervalSince(selectedDate)) }
    }

    static func axisLabel(for seconds: Double) -> String {
        seconds == 0 ? L10n.text("Now") : seconds == -duration ? "−2m" : "−1m"
    }
}

private struct SystemUsageHistoryChart: View {
    private let data: SystemUsageHistoryData
    @StateObject private var selection = SystemUsageHistorySelection()

    init(history: [SystemMetricsSnapshot], value: (SystemMetricsSnapshot) -> Double?) {
        data = SystemUsageHistoryData(history: history, value: value)
    }

    var body: some View {
        let points = data.points
        let selected = selection.selectedPoint(in: data)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.text("Usage history")).font(MeterStyle.sectionFont)
                Spacer()
                Text(L10n.text("Last 2 minutes")).font(MeterStyle.captionFont).foregroundStyle(.secondary)
            }
            if points.isEmpty {
                Text(!data.hasHistory ? L10n.text("Waiting for usage history…") : L10n.text("No valid readings in the last 2 minutes."))
                    .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .center)
            } else {
                Chart {
                    ForEach(points) { point in
                        let accessibilityTime = Text(point.time.formatted(.dateTime.hour().minute().second().locale(L10n.locale)))
                        let accessibilityUsage = Text(SystemMetricsFormatter.percent(point.value))
                        AreaMark(x: .value(L10n.text("Time"), point.secondsFromEnd), yStart: .value("", 0.0),
                            yEnd: .value(L10n.text("Usage"), point.value), series: .value("Run", point.segment))
                            .foregroundStyle(Color.accentColor.opacity(0.1))
                            .accessibilityLabel(accessibilityTime)
                            .accessibilityValue(accessibilityUsage)
                        LineMark(x: .value(L10n.text("Time"), point.secondsFromEnd), y: .value(L10n.text("Usage"), point.value),
                            series: .value("Run", point.segment))
                            .foregroundStyle(Color.accentColor).lineStyle(StrokeStyle(lineWidth: 1.5))
                            .accessibilityLabel(accessibilityTime)
                            .accessibilityValue(accessibilityUsage)
                        if points.count == 1 {
                            PointMark(x: .value(L10n.text("Time"), point.secondsFromEnd), y: .value(L10n.text("Usage"), point.value))
                                .foregroundStyle(Color.accentColor).symbolSize(20)
                                .accessibilityLabel(accessibilityTime)
                                .accessibilityValue(accessibilityUsage)
                        }
                    }
                    if let selected {
                        RuleMark(x: .value(L10n.text("Time"), selected.secondsFromEnd))
                            .foregroundStyle(Color.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .chartXScale(domain: -SystemUsageHistoryData.duration...0)
                .chartYScale(domain: 0.0...100.0)
                .chartLegend(.hidden)
                .chartXAxis {
                    // Fixed relative ticks let Charts reuse axis labels across samples.
                    AxisMarks(values: SystemUsageHistoryData.axisValues) { tick in
                        AxisValueLabel {
                            if let seconds = tick.as(Double.self) {
                                Text(SystemUsageHistoryData.axisLabel(for: seconds))
                                    .font(MeterStyle.captionFont)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [0.0, 50.0, 100.0]) { tick in
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                        AxisValueLabel {
                            if let number = tick.as(Double.self) { Text("\(Int(number))%").font(MeterStyle.captionFont) }
                        }
                    }
                }
                .chartXSelection(value: selection.relativeSeconds(in: data))
                .frame(height: 72)
                .accessibilityLabel(L10n.text("Usage history"))
            }
            HStack {
                if let selected {
                    Text(selected.time.formatted(.dateTime.hour().minute().second().locale(L10n.locale)))
                    Spacer()
                    Text(SystemMetricsFormatter.percent(selected.value)).monospacedDigit()
                } else if let minimum = points.map(\.value).min(), let maximum = points.map(\.value).max() {
                    Text(L10n.text("Range \(SystemMetricsFormatter.percent(minimum)) – \(SystemMetricsFormatter.percent(maximum))"))
                } else {
                    Text(L10n.text("Local readings · every 2 seconds"))
                }
            }
            .font(MeterStyle.captionFont).foregroundStyle(.secondary)
            .frame(minHeight: 14)
        }
        .onChange(of: data.points) { _, _ in selection.reconcile(with: data) }
    }
}

@MainActor final class SystemUsageHistorySelection: ObservableObject {
    @Published private(set) var date: Date?

    func selectedPoint(in data: SystemUsageHistoryData) -> SystemUsageHistoryData.Point? {
        guard let date else { return nil }
        return data.points.first { $0.time == date }
    }

    func relativeSeconds(in data: SystemUsageHistoryData) -> Binding<Double?> {
        Binding(get: { [self] in selectedPoint(in: data)?.secondsFromEnd }, set: { [self] seconds in
            guard let seconds, seconds.isFinite,
                  (-SystemUsageHistoryData.duration...0).contains(seconds) else { select(nil); return }
            select(data.nearest(to: data.end.addingTimeInterval(seconds))?.time)
        })
    }

    func reconcile(with data: SystemUsageHistoryData) {
        if date != nil, selectedPoint(in: data) == nil { select(nil) }
    }

    private func select(_ time: Date?) {
        if date != time { date = time }
    }
}

private struct SystemProcessList: View {
    enum Mode { case cpu, memory }
    let processes: [SystemProcessUsage]
    let mode: Mode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("Top processes")).font(MeterStyle.sectionFont)
            HStack {
                Text(L10n.text("Process"))
                Spacer()
                Text(mode == .memory ? L10n.text("Memory") : "CPU")
            }
            .font(MeterStyle.captionFont).foregroundStyle(.secondary)
            if processes.isEmpty {
                Text(L10n.text("Process statistics unavailable")).font(MeterStyle.captionFont).foregroundStyle(.secondary)
            } else {
                ForEach(Array(processes.prefix(8))) { process in
                    HStack(spacing: 8) {
                        processIcon(process.pid).frame(width: 16, height: 16).accessibilityHidden(true)
                        Text(process.name).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 12)
                        Text(processValue(process)).monospacedDigit().fixedSize()
                    }
                    .frame(minHeight: 20)
                    .help(process.name + "\n" + L10n.text("PID \(process.pid)"))
                    .accessibilityElement(children: .combine)
                }
            }
            Text(mode == .memory ? L10n.text("Physical footprint · accessible processes only.") :
                L10n.text("100% equals one logical core · accessible processes only."))
                .font(MeterStyle.captionFont).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func processIcon(_ pid: Int32) -> some View {
        if let icon = NSRunningApplication(processIdentifier: pid)?.icon {
            Image(nsImage: icon).resizable().interpolation(.high)
        } else {
            Image(systemName: "app").font(.system(size: 14)).foregroundStyle(.secondary)
        }
    }

    private func processValue(_ process: SystemProcessUsage) -> String {
        if mode == .memory { return SystemMemoryUnits.format(process.memoryBytes) }
        guard let value = process.cpuUsagePercent, value.isFinite, value >= 0 else { return "—" }
        return String(format: "%.1f%%", value)
    }
}

private enum SystemMemoryUnits {
    static func format(_ bytes: UInt64?) -> String {
        guard let bytes else { return "—" }
        let units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB"]
        var number = Double(bytes)
        var index = 0
        while number >= 1024, index < units.count - 1 {
            number /= 1024
            index += 1
        }
        return String(format: index == 0 ? "%.0f %@" : "%.1f %@", number, units[index])
    }
}

struct NetworkProcessList: View {
    let processes: [SystemNetworkProcessUsage]
    let updatedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("Top network processes")).font(MeterStyle.sectionFont)
            HStack(spacing: 8) {
                Text(L10n.text("Process")).frame(maxWidth: .infinity, alignment: .leading)
                Text("↑ " + L10n.text("Upload")).frame(width: 88, alignment: .trailing)
                Text("↓ " + L10n.text("Download")).frame(width: 88, alignment: .trailing)
            }
            .font(MeterStyle.captionFont).foregroundStyle(.secondary)
            if updatedAt == nil {
                Text(L10n.text("Collecting process rates; unavailable if macOS denies access."))
                    .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if processes.isEmpty {
                Text(L10n.text("No active network processes in this sample."))
                    .font(MeterStyle.captionFont).foregroundStyle(.secondary)
            } else {
                ForEach(processes) { process in
                    HStack(spacing: 8) {
                        Group {
                            if let icon = NSRunningApplication(processIdentifier: process.pid)?.icon {
                                Image(nsImage: icon).resizable().interpolation(.high)
                            } else {
                                Image(systemName: "app").foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 16, height: 16).accessibilityHidden(true)
                        Text(process.name).lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(SystemMetricsFormatter.rate(process.uploadBytesPerSecond))
                            .frame(width: 88, alignment: .trailing).monospacedDigit()
                        Text(SystemMetricsFormatter.rate(process.downloadBytesPerSecond))
                            .frame(width: 88, alignment: .trailing).monospacedDigit()
                    }
                    .frame(minHeight: 20)
                    .help(process.name + "\n" + L10n.text("PID \(process.pid)"))
                    .accessibilityElement(children: .combine)
                }
            }
            Text(L10n.text("Non-loopback process traffic · refreshed every few seconds. VPN forwarding may differ from physical interface totals."))
                .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(MeterStyle.bodyFont)
    }
}
