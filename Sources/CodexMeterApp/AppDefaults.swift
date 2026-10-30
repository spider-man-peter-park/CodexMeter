import CodexMeterCore

enum AppDefaults {
    static let display = DisplayOptions(
        fullMode: true, quotaLabelStyle: .gpt, tpsLayout: .stacked,
        fontSize: 12, fontWeight: .medium, spacing: .compact,
        customQuotaLabel: "", countdownSeparator: .dot)
    static let detailLayout = DetailLayout(hidden: [.account, .settings])
    static let refresh = RefreshOptions(quotaSeconds: 180, logSeconds: 2, displaySeconds: 60, accountSeconds: 900)
    static let language = AppLanguage.system
    static let autoRefresh = true
    static let launchAtLogin = true
    static let automaticallyCheckForUpdates = false
    static let reminders: ReminderOptions = {
        var options = ReminderOptions()
        options.lowQuotaEnabled = true
        options.recoveryEnabled = true
        options.thresholds = .ten
        options.creditExpiryEnabled = true
        options.creditLeadTime = .threeDays
        return options
    }()
}
