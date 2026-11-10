import Foundation

public enum MenuBarMetric: String, Codable, CaseIterable, Hashable, Sendable {
    case fiveHour, weekly, tps, todayTokens, cpu, gpu, ram, network, fallback, focus

    public var isSystemMetric: Bool {
        switch self {
        case .cpu, .gpu, .ram, .network: true
        default: false
        }
    }
}

public enum QuotaLabelStyle: String, Codable, CaseIterable, Sendable {
    case ai, window, none, icon, gpt, custom
}

public enum CountdownStyle: String, Codable, CaseIterable, Sendable {
    case compact, clock
}

public enum MenuBarTPSLayout: String, Codable, CaseIterable, Sendable { case inline, stacked }

public enum MenuBarLabelPosition: String, Codable, CaseIterable, Sendable { case above, leading }

public struct SystemMetricDisplayOptions: Equatable, Codable, Sendable {
    public var showIcon: Bool
    public var showLabel: Bool
    public var labelPosition: MenuBarLabelPosition

    public init(showIcon: Bool = true, showLabel: Bool = true, labelPosition: MenuBarLabelPosition = .leading) {
        self.showIcon = showIcon
        self.showLabel = showLabel
        self.labelPosition = labelPosition
    }

    private enum CodingKeys: String, CodingKey { case showIcon, showLabel, labelPosition }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        showIcon = try values.decodeIfPresent(Bool.self, forKey: .showIcon) ?? true
        showLabel = try values.decodeIfPresent(Bool.self, forKey: .showLabel) ?? true
        labelPosition = (try? values.decode(MenuBarLabelPosition.self, forKey: .labelPosition)) ?? .leading
    }
}

public enum MenuBarFontWeight: String, Codable, CaseIterable, Sendable { case regular, medium, semibold }
public enum MenuBarFontDesign: String, Codable, CaseIterable, Sendable { case system, rounded, monospaced }
public enum MenuBarColorStyle: String, Codable, CaseIterable, Sendable { case adaptive, monochrome, blue, teal, purple }
public enum MenuBarItemStyle: String, Codable, CaseIterable, Sendable { case plain, capsule, activeCapsule }
public enum MenuBarSpacing: String, Codable, CaseIterable, Sendable { case compact, comfortable }
public enum CountdownSeparator: String, Codable, CaseIterable, Sendable { case space, dot, slash, parentheses }
public enum DisplayPreset: String, Codable, CaseIterable, Sendable { case minimal, balanced, elegant }

public struct MenuBarItem: Equatable, Sendable, Identifiable {
    public let metric: MenuBarMetric
    public let title: String
    public let accessibilityLabel: String
    public let symbolName: String?
    public let usesGPTLogo: Bool
    public let tpsValue: String?
    public let systemValue: String?
    public let systemLabel: String?
    public let networkUploadValue: String?
    public let networkDownloadValue: String?
    public let quotaPrimary: String?
    public let quotaCountdown: String?
    public var id: MenuBarMetric { metric }

    public init(metric: MenuBarMetric, title: String, accessibilityLabel: String, symbolName: String? = nil,
                usesGPTLogo: Bool = false, tpsValue: String? = nil, systemValue: String? = nil,
                systemLabel: String? = nil, networkUploadValue: String? = nil, networkDownloadValue: String? = nil,
                quotaPrimary: String? = nil, quotaCountdown: String? = nil) {
        self.metric = metric
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self.symbolName = symbolName
        self.usesGPTLogo = usesGPTLogo
        self.tpsValue = tpsValue
        self.systemValue = systemValue
        self.systemLabel = systemLabel
        self.networkUploadValue = networkUploadValue
        self.networkDownloadValue = networkDownloadValue
        self.quotaPrimary = quotaPrimary
        self.quotaCountdown = quotaCountdown
    }
}

public struct DisplayOptions: Equatable, Codable, Sendable {
    // Retained for preference migration; countdown visibility is now independent.
    public var fullMode: Bool
    public var showFiveHour: Bool
    public var showWeekly: Bool
    public var showCountdown: Bool
    public var showTPS: Bool
    public var showTodayTokens: Bool
    public var showTodayTokensLabel: Bool
    public var showCPU: Bool
    public var showGPU: Bool
    public var showRAM: Bool
    public var showNetworkUpload: Bool
    public var showNetworkDownload: Bool
    public var cpuDisplay: SystemMetricDisplayOptions
    public var gpuDisplay: SystemMetricDisplayOptions
    public var ramDisplay: SystemMetricDisplayOptions
    public var quotaLabelStyle: QuotaLabelStyle
    public var countdownStyle: CountdownStyle
    public var tpsDecimals: Int
    public var showTPSLabel: Bool
    public var showTPSIcon: Bool
    public var tpsLayout: MenuBarTPSLayout
    public var fontSize: Double
    public var fontWeight: MenuBarFontWeight
    public var fontDesign: MenuBarFontDesign
    public var colorStyle: MenuBarColorStyle
    public var itemStyle: MenuBarItemStyle
    public var spacing: MenuBarSpacing
    public var customQuotaLabel: String
    public var showPercentSign: Bool
    public var countdownSeparator: CountdownSeparator

    public var normalizedFontSize: Double { fontSize.isFinite ? max(9, min(16, fontSize)) : 12 }
    public var normalizedCustomQuotaLabel: String {
        let label = Self.sanitizeQuotaLabel(customQuotaLabel)
        return label.isEmpty ? "AI" : label
    }
    public var itemHorizontalPadding: Double { spacing == .compact ? 3 : 5 }

    public static func sanitizeQuotaLabel(_ value: String) -> String {
        let safe = value.unicodeScalars.filter {
            // Joiners are required for intact emoji and script grapheme clusters.
            !CharacterSet.controlCharacters.contains($0) || $0.value == 0x200C || $0.value == 0x200D
        }
        return String(String.UnicodeScalarView(safe)).split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ").prefix(12).description
    }

    public init(fullMode: Bool = false, showFiveHour: Bool = true, showWeekly: Bool = true,
                showCountdown: Bool = true, showTPS: Bool = true, showTodayTokens: Bool = true,
                showTodayTokensLabel: Bool = true,
                showCPU: Bool = true, showGPU: Bool = true, showRAM: Bool = true,
                showNetworkUpload: Bool = true, showNetworkDownload: Bool = true,
                cpuDisplay: SystemMetricDisplayOptions = .init(), gpuDisplay: SystemMetricDisplayOptions = .init(),
                ramDisplay: SystemMetricDisplayOptions = .init(),
                quotaLabelStyle: QuotaLabelStyle = .ai, countdownStyle: CountdownStyle = .compact,
                tpsDecimals: Int = 0, showTPSLabel: Bool = true, showTPSIcon: Bool = true,
                tpsLayout: MenuBarTPSLayout = .inline,
                fontSize: Double = 12, fontWeight: MenuBarFontWeight = .semibold,
                fontDesign: MenuBarFontDesign = .system, colorStyle: MenuBarColorStyle = .adaptive,
                itemStyle: MenuBarItemStyle = .activeCapsule, spacing: MenuBarSpacing = .comfortable,
                customQuotaLabel: String = "AI", showPercentSign: Bool = true,
                countdownSeparator: CountdownSeparator = .space) {
        self.fullMode = fullMode
        self.showFiveHour = showFiveHour
        self.showWeekly = showWeekly
        self.showCountdown = showCountdown
        self.showTPS = showTPS
        self.showTodayTokens = showTodayTokens
        self.showTodayTokensLabel = showTodayTokensLabel
        self.showCPU = showCPU
        self.showGPU = showGPU
        self.showRAM = showRAM
        self.showNetworkUpload = showNetworkUpload
        self.showNetworkDownload = showNetworkDownload
        self.cpuDisplay = cpuDisplay
        self.gpuDisplay = gpuDisplay
        self.ramDisplay = ramDisplay
        self.quotaLabelStyle = quotaLabelStyle
        self.countdownStyle = countdownStyle
        self.tpsDecimals = tpsDecimals
        self.showTPSLabel = showTPSLabel
        self.showTPSIcon = showTPSIcon
        self.tpsLayout = tpsLayout
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.fontDesign = fontDesign
        self.colorStyle = colorStyle
        self.itemStyle = itemStyle
        self.spacing = spacing
        self.customQuotaLabel = customQuotaLabel
        self.showPercentSign = showPercentSign
        self.countdownSeparator = countdownSeparator
    }

    private enum CodingKeys: String, CodingKey {
        case fullMode, showFiveHour, showWeekly, showCountdown, showTPS, showTodayTokens, showTodayTokensLabel
        case showCPU, showGPU, showRAM, showNetworkUpload, showNetworkDownload
        case cpuDisplay, gpuDisplay, ramDisplay
        case quotaLabelStyle, countdownStyle, tpsDecimals, showTPSLabel, showTPSIcon, tpsLayout
        case fontSize, fontWeight, fontDesign, colorStyle, itemStyle, spacing
        case customQuotaLabel, showPercentSign, countdownSeparator
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fullMode = try values.decodeIfPresent(Bool.self, forKey: .fullMode) ?? false
        showFiveHour = try values.decodeIfPresent(Bool.self, forKey: .showFiveHour) ?? true
        showWeekly = try values.decodeIfPresent(Bool.self, forKey: .showWeekly) ?? true
        showCountdown = try values.decodeIfPresent(Bool.self, forKey: .showCountdown) ?? true
        showTPS = try values.decodeIfPresent(Bool.self, forKey: .showTPS) ?? true
        showTodayTokens = try values.decodeIfPresent(Bool.self, forKey: .showTodayTokens) ?? true
        showTodayTokensLabel = try values.decodeIfPresent(Bool.self, forKey: .showTodayTokensLabel) ?? true
        showCPU = try values.decodeIfPresent(Bool.self, forKey: .showCPU) ?? true
        showGPU = try values.decodeIfPresent(Bool.self, forKey: .showGPU) ?? true
        showRAM = try values.decodeIfPresent(Bool.self, forKey: .showRAM) ?? true
        showNetworkUpload = try values.decodeIfPresent(Bool.self, forKey: .showNetworkUpload) ?? true
        showNetworkDownload = try values.decodeIfPresent(Bool.self, forKey: .showNetworkDownload) ?? true
        cpuDisplay = (try? values.decode(SystemMetricDisplayOptions.self, forKey: .cpuDisplay)) ?? .init()
        gpuDisplay = (try? values.decode(SystemMetricDisplayOptions.self, forKey: .gpuDisplay)) ?? .init()
        ramDisplay = (try? values.decode(SystemMetricDisplayOptions.self, forKey: .ramDisplay)) ?? .init()
        quotaLabelStyle = try values.decodeIfPresent(QuotaLabelStyle.self, forKey: .quotaLabelStyle) ?? .ai
        countdownStyle = try values.decodeIfPresent(CountdownStyle.self, forKey: .countdownStyle) ?? .compact
        tpsDecimals = try values.decodeIfPresent(Int.self, forKey: .tpsDecimals) ?? 0
        showTPSLabel = try values.decodeIfPresent(Bool.self, forKey: .showTPSLabel) ?? true
        showTPSIcon = try values.decodeIfPresent(Bool.self, forKey: .showTPSIcon) ?? true
        tpsLayout = try values.decodeIfPresent(MenuBarTPSLayout.self, forKey: .tpsLayout) ?? .inline
        fontSize = try values.decodeIfPresent(Double.self, forKey: .fontSize) ?? 12
        fontWeight = try values.decodeIfPresent(MenuBarFontWeight.self, forKey: .fontWeight) ?? .semibold
        fontDesign = try values.decodeIfPresent(MenuBarFontDesign.self, forKey: .fontDesign) ?? .system
        colorStyle = try values.decodeIfPresent(MenuBarColorStyle.self, forKey: .colorStyle) ?? .adaptive
        itemStyle = try values.decodeIfPresent(MenuBarItemStyle.self, forKey: .itemStyle) ?? .activeCapsule
        spacing = try values.decodeIfPresent(MenuBarSpacing.self, forKey: .spacing) ?? .comfortable
        customQuotaLabel = try values.decodeIfPresent(String.self, forKey: .customQuotaLabel) ?? "AI"
        showPercentSign = try values.decodeIfPresent(Bool.self, forKey: .showPercentSign) ?? true
        countdownSeparator = try values.decodeIfPresent(CountdownSeparator.self, forKey: .countdownSeparator) ?? .space
    }

    public mutating func applyPreset(_ preset: DisplayPreset) {
        showPercentSign = true
        countdownStyle = .compact
        switch preset {
        case .minimal:
            fontSize = 10
            fontWeight = .regular
            fontDesign = .system
            colorStyle = .monochrome
            itemStyle = .plain
            spacing = .compact
            quotaLabelStyle = .none
            countdownSeparator = .space
            tpsDecimals = 0
            showTPSLabel = false
        case .balanced:
            fontSize = 12
            fontWeight = .semibold
            fontDesign = .system
            colorStyle = .adaptive
            itemStyle = .activeCapsule
            spacing = .comfortable
            quotaLabelStyle = .ai
            countdownSeparator = .dot
            tpsDecimals = 0
            showTPSLabel = true
        case .elegant:
            fontSize = 11
            fontWeight = .semibold
            fontDesign = .rounded
            colorStyle = .teal
            itemStyle = .capsule
            spacing = .comfortable
            quotaLabelStyle = .icon
            countdownSeparator = .dot
            tpsDecimals = 1
            showTPSLabel = true
        }
    }
}

public enum MenuBarFormatter {
    public static func items(quota: QuotaSnapshot?, sample: TPSSample?, options: DisplayOptions,
                             todayUsage: LocalDayUsage? = nil, now: Date = Date(), stale: Bool = false,
                             calendar: Calendar = .current, systemMetrics: SystemMetricsSnapshot? = nil,
                             systemNow: Date? = nil) -> [MenuBarItem] {
        var result: [MenuBarItem] = []
        let isCached = quota.map { stale || $0.source == .logCache || $0.isStale } ?? false
        func window(_ metric: MenuBarMetric, _ value: QuotaWindow?) -> MenuBarItem {
            let windowLabel = metric == .fiveHour ? "5h" : "7d"
            let accessibleWindow = metric == .fiveHour ? L10n.text("5-hour quota") : L10n.text("7-day quota")
            let label: String
            switch options.quotaLabelStyle {
            case .ai: label = "AI "
            case .window: label = windowLabel + " "
            case .none, .icon, .gpt: label = ""
            case .custom: label = options.normalizedCustomQuotaLabel + " "
            }
            let primary = label + (value.map { "\(Int($0.remainingPercent.rounded()))" + (options.showPercentSign ? "%" : "") } ?? (quota == nil ? "—" : "N/A"))
            var title = primary
            var resetCountdown: String?
            var accessibility = accessibleWindow
            if let value {
                accessibility += L10n.text(", \(Int(value.remainingPercent.rounded())) percent remaining")
                if options.showCountdown {
                    let remaining = countdown(until: value.resetsAt, now: now, style: options.countdownStyle)
                    resetCountdown = remaining
                    switch options.countdownSeparator {
                    case .space: title += " " + remaining
                    case .dot: title += " · " + remaining
                    case .slash: title += " / " + remaining
                    case .parentheses: title += " (" + remaining + ")"
                    }
                    accessibility += L10n.text(", resets in ") + remaining
                }
            } else {
                accessibility += quota == nil ? L10n.text(", data unavailable") : L10n.text(", window not reported by this account")
            }
            if isCached {
                accessibility += L10n.text(", cached data, may be outdated")
            }
            return MenuBarItem(metric: metric, title: title, accessibilityLabel: accessibility,
                               symbolName: options.quotaLabelStyle == .icon ? (metric == .fiveHour ? "clock" : "calendar") : nil,
                               usesGPTLogo: options.quotaLabelStyle == .gpt,
                               quotaPrimary: primary, quotaCountdown: resetCountdown)
        }
        if options.showFiveHour { result.append(window(.fiveHour, quota?.fiveHour)) }
        if options.showWeekly { result.append(window(.weekly, quota?.weekly)) }
        if options.showTPS {
            let precision = options.tpsDecimals > 0 ? 1 : 0
            let value = sample.map { String(format: "%.*f", precision, $0.tokensPerSecond) } ?? "—"
            result.append(MenuBarItem(metric: .tps, title: value + (options.showTPSLabel ? " TPS" : ""),
                                      accessibilityLabel: sample == nil ? L10n.text("Latest response speed unavailable") :
                                        L10n.text("Latest completed response, \(value) effective tokens per second"),
                                      symbolName: options.showTPSIcon ? "bolt.fill" : nil, tpsValue: value))
        }
        if options.showTodayTokens {
            let total = todayUsage?.displayTotal(at: now, calendar: calendar)
            var accessibility = L10n.text("Today · this Mac")
            if let total {
                accessibility += L10n.text(", \(total.formatted(.number.locale(L10n.locale))) tokens, local estimate")
                if todayUsage?.isPartial == true {
                    accessibility += ". " + L10n.text("Partial estimate: some usage records could not be counted safely.")
                }
            } else {
                accessibility += L10n.text(", data unavailable")
            }
            if todayUsage?.matches(now, calendar: calendar) == true, todayUsage?.isBackfilling == true {
                accessibility += ". " + L10n.text("Backfilling today's logs…")
            }
            result.append(MenuBarItem(metric: .todayTokens,
                                      title: (options.showTodayTokensLabel ? "tok " : "") + TokenCountFormatter.compact(total),
                                      accessibilityLabel: accessibility, symbolName: DetailSection.today.symbol))
        }
        let freshSystem = systemMetrics?.fresh(at: systemNow ?? now)
        let metrics: [(Bool, MenuBarMetric, String, String, Double?, SystemMetricDisplayOptions)] = [
            (options.showCPU, .cpu, "CPU", "cpu", freshSystem?.cpuUsagePercent, options.cpuDisplay),
            (options.showGPU, .gpu, "GPU", "display", freshSystem?.gpuUsagePercent, options.gpuDisplay),
            (options.showRAM, .ram, "RAM", "memorychip", freshSystem?.memoryUsagePercent, options.ramDisplay)
        ]
        for (visible, metric, label, symbol, value, display) in metrics where visible {
            let formatted = SystemMetricsFormatter.percent(value)
            let title = display.showLabel ? label + " " + formatted : formatted
            let accessibility = label + ", " + (formatted == "—" ? L10n.text("System reading unavailable") : formatted)
            result.append(MenuBarItem(metric: metric, title: title, accessibilityLabel: accessibility,
                symbolName: display.showIcon ? symbol : nil, systemValue: formatted, systemLabel: display.showLabel ? label : nil))
        }
        if options.showNetworkUpload || options.showNetworkDownload {
            let upload = options.showNetworkUpload ? SystemMetricsFormatter.rate(freshSystem?.networkUploadBytesPerSecond) : nil
            let download = options.showNetworkDownload ? SystemMetricsFormatter.rate(freshSystem?.networkDownloadBytesPerSecond) : nil
            var titles: [String] = []
            var accessibility: [String] = []
            if let upload {
                titles.append("↑ " + upload)
                accessibility.append(L10n.text("Upload") + ", " + (upload == "—" ? L10n.text("System reading unavailable") : upload))
            }
            if let download {
                titles.append("↓ " + download)
                accessibility.append(L10n.text("Download") + ", " + (download == "—" ? L10n.text("System reading unavailable") : download))
            }
            result.append(MenuBarItem(metric: .network, title: titles.joined(separator: " "),
                accessibilityLabel: accessibility.joined(separator: "; "), networkUploadValue: upload, networkDownloadValue: download))
        }
        return result.isEmpty ? [MenuBarItem(metric: .fallback, title: "AI", accessibilityLabel: L10n.text("CodexMeter, open details"),
                                            symbolName: options.quotaLabelStyle == .icon ? "sparkles" : nil,
                                            usesGPTLogo: options.quotaLabelStyle == .gpt)] : result
    }

    public static func title(quota: QuotaSnapshot?, sample: TPSSample?, options: DisplayOptions,
                             todayUsage: LocalDayUsage? = nil, now: Date = Date(), stale: Bool = false,
                             systemMetrics: SystemMetricsSnapshot? = nil, systemNow: Date? = nil) -> String {
        items(quota: quota, sample: sample, options: options, todayUsage: todayUsage, now: now, stale: stale,
              systemMetrics: systemMetrics, systemNow: systemNow)
            .map(\.title).joined(separator: " | ")
    }

    public static func countdown(until reset: Date?, now: Date = Date(), style: CountdownStyle = .compact) -> String {
        guard let reset else { return "—" }
        let remaining = max(0, Int(ceil(reset.timeIntervalSince(now) / 60)))
        let days = remaining / 1440
        let hours = (remaining % 1440) / 60
        let minutes = remaining % 60
        if style == .clock {
            let time = String(format: "%02d:%02d", hours, minutes)
            return days > 0 ? "\(days)d" + time : time
        }
        if remaining == 0 { return "now" }
        if days > 0 { return "\(days)d\(hours)h" }
        if hours > 0 { return "\(hours)h\(minutes)m" }
        return "\(minutes)m"
    }
}
