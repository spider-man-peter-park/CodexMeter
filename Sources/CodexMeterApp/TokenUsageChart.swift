import Charts
import CodexMeterCore
import SwiftUI

struct TokenUsageChart: View {
    let series: TokenUsageSeries
    @StateObject private var selection = TokenUsageSelection()

    private var selectedDay: TokenUsageDay? {
        guard let selectedX = selection.x, selectedX.isFinite else { return nil }
        return series.days[min(6, max(0, Int(selectedX.rounded())))]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Token usage · 7 days", systemImage: "chart.xyaxis.line")
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            Text("\(series.startDay) – \(series.endDay)")
                .font(.caption2).foregroundStyle(.secondary)
            Chart {
                ForEach(series.days) { day in
                    if let tokens = day.tokens {
                        LineMark(x: .value("Day", Double(day.index)), y: .value("Tokens", Double(tokens)),
                                 series: .value("Run", day.segment))
                            .interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .foregroundStyle(.blue)
                        PointMark(x: .value("Day", Double(day.index)), y: .value("Tokens", Double(tokens)))
                            .symbolSize(24).foregroundStyle(.blue)
                            .accessibilityLabel(day.day)
                            .accessibilityValue("\(TokenCountFormatter.compact(tokens)) tokens")
                    }
                }
                if let selectedDay {
                    RuleMark(x: .value("Selected day", Double(selectedDay.index)))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                }
            }
            .chartXScale(domain: -0.35...6.35)
            .chartYScale(domain: 0...max(10, Double(series.maximumTokens ?? 0) * 1.12))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel(anchor: .trailing, collisionResolution: .disabled) {
                        if let y = value.as(Double.self), let count = Int(exactly: y.rounded()) {
                            Text(TokenCountFormatter.compact(count)).font(.system(size: 9))
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .chartXSelection(value: $selection.x)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let frame = proxy.plotFrame {
                        let plot = geometry[frame]
                        ForEach(series.days) { day in
                            if let x = proxy.position(forX: Double(day.index)) {
                                Text(day.shortLabel).font(.system(size: 9)).foregroundStyle(.secondary)
                                    .fixedSize()
                                    .position(x: plot.minX + x, y: plot.maxY + 9)
                            }
                        }
                    }
                }.allowsHitTesting(false)
            }
            .frame(height: 140)
            .padding(.bottom, 18)
            HStack {
                Text(selectedDay?.day ?? "Select a day for details")
                Spacer()
                if let selectedDay {
                    Text(selectedDay.tokens.map { TokenCountFormatter.compact($0) + " tokens" } ?? "Not reported")
                        .monospacedDigit()
                }
            }.font(.caption2).foregroundStyle(.secondary)
            if series.hasMissingDays {
                Text("Gaps are dates not reported by Codex, not zero usage.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private final class TokenUsageSelection: ObservableObject {
    @Published var x: Double?
}
