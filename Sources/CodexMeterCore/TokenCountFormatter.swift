public enum TokenCountFormatter {
    public static func compact(_ count: Int?) -> String {
        guard let count, count >= 0 else { return "—" }
        guard count >= 1_000 else { return String(count) }
        let units: [(divisor: Int, suffix: String)] = [
            (1_000, "K"), (1_000_000, "M"), (1_000_000_000, "B"), (1_000_000_000_000, "T")
        ]
        var index = units.count - 1
        while count < units[index].divisor { index -= 1 }
        while true {
            let (divisor, suffix) = units[index]
            // Round using integer parts to preserve large counters without overflowing.
            let tenths = (count / divisor) * 10 + ((count % divisor) * 10 + divisor / 2) / divisor
            if tenths >= 10_000, index < units.count - 1 {
                index += 1
                continue
            }
            let fraction = tenths % 10
            return String(tenths / 10) + (fraction == 0 ? "" : ".\(fraction)") + suffix
        }
    }
}
