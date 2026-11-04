import Foundation

public enum SystemMetricsFormatter {
    public static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite, (0...100).contains(value) else { return "—" }
        return String(format: "%.0f%%", value)
    }

    public static func bytes(_ value: UInt64?) -> String {
        guard let value else { return "—" }
        return scaledBytes(Double(value))
    }

    public static func rate(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        return scaledBytes(value) + "/s"
    }

    private static func scaledBytes(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB", "EB"]
        var number = value
        var index = 0
        while number >= 1_000 && index < units.count - 1 {
            number /= 1_000
            index += 1
        }
        // Round before selecting the unit so 999.99 KB never renders as 1000 KB.
        let rounded = number >= 100 ? number.rounded() : (number * 10).rounded() / 10
        if index < units.count - 1 && rounded >= 1_000 {
            number /= 1_000
            index += 1
        } else {
            number = rounded
        }
        return String(format: index == 0 || number >= 100 ? "%.0f %@" : "%.1f %@", number, units[index])
    }
}
