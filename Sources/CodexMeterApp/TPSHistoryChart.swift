import Charts
import CodexMeterCore
import SwiftUI

struct TPSHistoryChart: View {
    let samples: [TPSSample]
    let isBackfilling: Bool
    let isUnattributed: Bool
    @StateObject private var selection = TPSChartSelection()

    private var points: [TPSHistoryPoint] { TPSHistory.points(samples) }
    private var selected: TPSHistoryPoint? { points.first { $0.id == selection.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(L10n.text("Recent TPS · last 30 responses"), systemImage: "chart.xyaxis.line").font(MeterStyle.sectionFont)
                    .help(L10n.text("Response order, oldest → newest; timing is estimated. Lines break when the model changes."))
                Spacer()
                Text("\(points.count)/30").font(MeterStyle.captionFont).foregroundStyle(.secondary)
            }
            if points.isEmpty {
                Text(isBackfilling ? L10n.text("Loading previous responses…") : L10n.text("No responses with reliable timing yet."))
                    .font(MeterStyle.captionFont).foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(points) { point in
                        LineMark(x: .value(L10n.text("Response"), Double(point.index)), y: .value("TPS", point.sample.tokensPerSecond),
                                 series: .value(L10n.text("Model run"), point.segment))
                            .interpolationMethod(.linear).foregroundStyle(Color.accentColor)
                        PointMark(x: .value(L10n.text("Response"), Double(point.index)), y: .value("TPS", point.sample.tokensPerSecond))
                            .symbolSize(point.id == selection.id ? 45 : 16).foregroundStyle(Color.accentColor)
                            .accessibilityLabel("\(point.sample.model ?? L10n.text("Unknown model")), \(point.sample.completedAt.formatted(.dateTime.locale(L10n.locale)))")
                            .accessibilityValue(String(format: "%.1f TPS", point.sample.tokensPerSecond))
                    }
                    if let selected {
                        RuleMark(x: .value(L10n.text("Selected response"), Double(selected.index)))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(.secondary)
                    }
                }
                .chartXScale(domain: -0.4...Double(max(1, points.count - 1)) + 0.4)
                .chartYScale(domain: 0...max(10, (points.map { $0.sample.tokensPerSecond }.max() ?? 0) * 1.12))
                .chartXAxis {
                    AxisMarks(values: Array(Set([0, max(0, (points.count - 1) / 2), max(0, points.count - 1)])).sorted().map(Double.init)) { value in
                        AxisValueLabel { if let index = value.as(Double.self) { Text("\(Int(index) + 1)").font(MeterStyle.captionFont) } }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                        AxisValueLabel().font(MeterStyle.captionFont)
                    }
                }
                .chartLegend(.hidden)
                .chartXSelection(value: $selection.x)
                .frame(height: 116)
                .onChange(of: selection.x) { _, x in
                    guard let x, x.isFinite, !points.isEmpty else { selection.id = nil; return }
                    selection.id = points[Int(min(Double(points.count - 1), max(0, x.rounded())))].id
                }
                .onChange(of: points.map(\.id)) { _, _ in
                    if let index = points.firstIndex(where: { $0.id == selection.id }) { selection.x = Double(index) }
                    else { selection.id = nil; selection.x = nil }
                }
                VStack(alignment: .leading, spacing: 3) {
                if let point = selected {
                    HStack {
                        Text(point.sample.model ?? L10n.text("Unknown model")).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(String(format: "%.1f TPS", point.sample.tokensPerSecond)).monospacedDigit()
                    }.font(MeterStyle.captionFont)
                    Text(point.sample.completedAt.formatted(.dateTime.year().month().day().hour().minute().second().locale(L10n.locale)))
                        .font(MeterStyle.captionFont).foregroundStyle(.secondary)
                } else {
                    Text(L10n.text("Select a response")).font(MeterStyle.captionFont).foregroundStyle(.secondary)
                        .help(L10n.text("Select a response for its model, TPS and completion time."))
                }
                }.frame(height: 36, alignment: .topLeading)
                if isBackfilling { Text(L10n.text("Loading previous responses…")).font(MeterStyle.captionFont).foregroundStyle(.secondary) }
                if isUnattributed {
                    MeterStatusLabel(title: L10n.text("Unidentified source"), symbol: "questionmark.circle")
                        .help(L10n.text("Log source is unidentified; CLI responses may be included."))
                }
            }
        }
    }
}

private final class TPSChartSelection: ObservableObject {
    @Published var x: Double?
    @Published var id: String?
}
