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
                Label(L10n.text("Account tokens · 7 days"), systemImage: "chart.xyaxis.line")
                    .font(MeterStyle.sectionFont)
                    .help(L10n.text("Account dates are reported by Codex and may lag behind today. These totals are not added to the local estimate."))
                Spacer()
                if series.hasMissingDays {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(L10n.text("Some dates not reported"))
                        .help(L10n.text("Gaps are dates not reported by Codex, not zero usage."))
                }
            }
            Text("\(series.startDay) – \(series.endDay)")
                .font(MeterStyle.captionFont).foregroundStyle(.secondary)
            Chart {
                ForEach(series.days) { day in
                    if let tokens = day.tokens {
                        LineMark(x: .value(L10n.text("Day"), Double(day.index)), y: .value(L10n.text("Tokens"), Double(tokens)),
                                 series: .value("Run", day.segment))
                            .interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .foregroundStyle(.blue)
                        PointMark(x: .value(L10n.text("Day"), Double(day.index)), y: .value(L10n.text("Tokens"), Double(tokens)))
                            .symbolSize(18).foregroundStyle(.blue)
                            .accessibilityLabel(day.day)
                            .accessibilityValue(L10n.text("\(TokenCountFormatter.compact(tokens)) tokens"))
                    }
                }
                if let selectedDay {
                    RuleMark(x: .value(L10n.text("Selected day"), Double(selectedDay.index)))
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
                            Text(TokenCountFormatter.compact(count)).font(MeterStyle.captionFont)
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
                                Text(day.shortLabel).font(MeterStyle.captionFont).foregroundStyle(.secondary)
                                    .fixedSize()
                                    .position(x: plot.minX + x, y: plot.maxY + 9)
                            }
                        }
                    }
                }.allowsHitTesting(false)
            }
            .frame(height: 116)
            .padding(.bottom, 20)
            HStack {
                Text(selectedDay?.day ?? L10n.text("Select a day"))
                Spacer()
                if let selectedDay {
                    Text(selectedDay.tokens.map { TokenCountFormatter.compact($0) + L10n.text(" tokens") } ?? L10n.text("Not reported"))
                        .monospacedDigit()
                }
            }.font(MeterStyle.captionFont).foregroundStyle(.secondary)
                .frame(height: 18, alignment: .leading).lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

private final class TokenUsageSelection: ObservableObject {
    @Published var x: Double?
}
