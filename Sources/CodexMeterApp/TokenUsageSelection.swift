import CodexMeterCore
import SwiftUI

@MainActor final class TokenUsageSelection: ObservableObject {
    @Published private(set) var dayID: String?

    func selectedDay(in series: TokenUsageSeries) -> TokenUsageDay? {
        series.days.first { $0.id == dayID }
    }

    func position(in series: TokenUsageSeries) -> Binding<Double?> {
        Binding(get: { [self] in selectedDay(in: series).map { Double($0.index) } },
                set: { [self] x in
            guard let x, x.isFinite else { setDay(nil); return }
            let index = Int(min(Double(series.days.count - 1), max(0, x.rounded())))
            setDay(series.days[index].id)
        })
    }

    func reconcile(with series: TokenUsageSeries) {
        if dayID != nil, selectedDay(in: series) == nil { setDay(nil) }
    }

    private func setDay(_ day: String?) {
        if dayID != day { dayID = day }
    }
}
