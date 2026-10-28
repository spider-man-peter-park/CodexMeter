import Foundation
import Testing
@testable import CodexMeterCore

@Suite struct DisplayTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func quota(source: QuotaSource = .appServer) -> QuotaSnapshot {
        QuotaSnapshot(fiveHour: QuotaWindow(usedPercent: 18, windowDurationMins: 300,
                                           resetsAt: now.addingTimeInterval(134 * 60)),
                      weekly: QuotaWindow(usedPercent: 39, windowDurationMins: 10_080,
                                         resetsAt: now.addingTimeInterval((4 * 24 + 8) * 3600)),
                      updatedAt: now, source: source)
    }

    private var sample: TPSSample {
        TPSSample(id: "response", model: "test-model", outputTokens: 734,
                  reasoningTokens: 300, elapsedSeconds: 10, completedAt: now)
    }

    @Test func eachMetricHasSeparateIdentityAndNoCombinedText() {
        let items = MenuBarFormatter.items(quota: quota(), sample: sample, options: DisplayOptions(), now: now)
        #expect(items.map(\.metric) == [.fiveHour, .weekly, .tps])
        #expect(Set(items.map(\.id)).count == 3)
        #expect(items.map(\.title) == ["AI 82% 2h14m", "AI 61% 4d8h", "73 TPS"])
        #expect(items.allSatisfy { !$0.title.contains("|") })
        #expect(items[0].accessibilityLabel.contains("5-hour"))
        #expect(items[1].accessibilityLabel.contains("7-day"))
    }

    @Test func noDataUsesDashesInsteadOfZero() {
        let items = MenuBarFormatter.items(quota: nil, sample: nil, options: DisplayOptions(), now: now)
        #expect(items.map(\.title) == ["AI —", "AI —", "— TPS"])
        #expect(items.allSatisfy { !$0.title.contains("0%") })
    }

    @Test func windowLabelsRemainAnIndependentChoice() {
        let options = DisplayOptions(quotaLabelStyle: .window)
        let items = MenuBarFormatter.items(quota: quota(), sample: nil, options: options, now: now)
        #expect(items.map(\.title) == ["5h 82% 2h14m", "7d 61% 4d8h", "— TPS"])
    }

    @Test func labelsCanBeHiddenWithoutChangingMetricIdentity() {
        let items = MenuBarFormatter.items(quota: quota(), sample: nil,
                                           options: DisplayOptions(quotaLabelStyle: .none), now: now)
        #expect(items[0].title == "82% 2h14m")
        #expect(items[0].metric == .fiveHour)
        #expect(items[1].title == "61% 4d8h")
        #expect(items[1].accessibilityLabel.contains("7-day quota"))
    }

    @Test func countdownVisibilityDoesNotDependOnLegacyFullMode() {
        let visible = MenuBarFormatter.items(quota: quota(), sample: nil,
                                             options: DisplayOptions(fullMode: false, showTPS: false), now: now)
        #expect(visible.map(\.title) == ["AI 82% 2h14m", "AI 61% 4d8h"])
        let hidden = MenuBarFormatter.items(quota: quota(), sample: nil,
                                            options: DisplayOptions(fullMode: true, showCountdown: false, showTPS: false), now: now)
        #expect(hidden.map(\.title) == ["AI 82%", "AI 61%"])
    }

    @Test func clockCountdownStyleFormatsHoursMinutesAndDays() {
        let items = MenuBarFormatter.items(quota: quota(), sample: nil,
                                           options: DisplayOptions(countdownStyle: .clock), now: now)
        #expect(items[0].title == "AI 82% 02:14")
        #expect(items[1].title == "AI 61% 4d08:00")
        #expect(MenuBarFormatter.countdown(until: now.addingTimeInterval(314 * 60), now: now, style: .clock) == "05:14")
    }

    @Test func metricVisibilityDoesNotCombineRemainingItems() {
        let options = DisplayOptions(showFiveHour: false, showCountdown: false, showTPS: false)
        let items = MenuBarFormatter.items(quota: quota(), sample: nil, options: options, now: now)
        #expect(items.count == 1)
        #expect(items[0].metric == .weekly)
        #expect(items[0].title == "AI 61%")
    }

    @Test func missingWindowIsNAOnlyAfterValidSnapshot() {
        let weekly = QuotaSnapshot(fiveHour: nil, weekly: quota().weekly, updatedAt: now, source: .appServer)
        let items = MenuBarFormatter.items(quota: weekly, sample: nil, options: DisplayOptions(), now: now)
        #expect(items[0].title == "AI N/A")
        #expect(items[1].title == "AI 61% 4d8h")
    }

    @Test func eachCachedQuotaHasMarkerButTPSDoesNot() {
        let items = MenuBarFormatter.items(quota: quota(source: .logCache), sample: sample,
                                           options: DisplayOptions(), now: now)
        #expect(items[0].title.hasSuffix(" *"))
        #expect(items[1].title.hasSuffix(" *"))
        #expect(!items[2].title.hasSuffix(" *"))
        #expect(items[0].accessibilityLabel.contains("cached"))
        let failed = MenuBarFormatter.items(quota: quota(), sample: nil,
                                            options: DisplayOptions(), now: now, stale: true)
        #expect(failed[0].title.hasSuffix(" *"))
    }

    @Test func tpsPrecisionAndSuffixAreIndependent() {
        let options = DisplayOptions(showFiveHour: false, showWeekly: false, tpsDecimals: 1, showTPSLabel: false)
        let items = MenuBarFormatter.items(quota: nil, sample: sample, options: options, now: now)
        #expect(items.count == 1)
        #expect(items[0].title == "73.4")
        #expect(items[0].metric == .tps)
        #expect(items[0].accessibilityLabel.contains("effective tokens per second"))
        let labeled = MenuBarFormatter.items(quota: nil, sample: sample,
                                             options: DisplayOptions(showFiveHour: false, showWeekly: false, tpsDecimals: 1), now: now)
        #expect(labeled[0].title == "73.4 TPS")
    }

    @Test func tpsPrecisionIsBoundedToSupportedChoices() {
        var options = DisplayOptions(showFiveHour: false, showWeekly: false, tpsDecimals: 99)
        #expect(MenuBarFormatter.items(quota: nil, sample: sample, options: options, now: now)[0].title == "73.4 TPS")
        options.tpsDecimals = -5
        #expect(MenuBarFormatter.items(quota: nil, sample: sample, options: options, now: now)[0].title == "73 TPS")
    }

    @Test func allHiddenKeepsOneClickableAIItem() {
        let options = DisplayOptions(showFiveHour: false, showWeekly: false, showTPS: false)
        let items = MenuBarFormatter.items(quota: nil, sample: nil, options: options, now: now)
        #expect(items.count == 1)
        #expect(items[0].metric == .fallback)
        #expect(items[0].title == "AI")
    }

    @Test func resetCountdownHandlesPastMissingAndMinuteRounding() {
        #expect(MenuBarFormatter.countdown(until: nil, now: now) == "—")
        #expect(MenuBarFormatter.countdown(until: now.addingTimeInterval(-300), now: now) == "now")
        #expect(MenuBarFormatter.countdown(until: now.addingTimeInterval(1), now: now) == "1m")
        #expect(MenuBarFormatter.countdown(until: now.addingTimeInterval(-300), now: now, style: .clock) == "00:00")
    }

    @Test func oldEncodedDisplayOptionsGainNewStyleDefaults() throws {
        let legacy = Data("{\"fullMode\":false,\"showFiveHour\":true,\"showWeekly\":false,\"showCountdown\":false,\"showTPS\":true}".utf8)
        let options = try JSONDecoder().decode(DisplayOptions.self, from: legacy)
        #expect(options.quotaLabelStyle == .ai)
        #expect(options.countdownStyle == .compact)
        #expect(options.tpsDecimals == 0)
        #expect(options.showTPSLabel)
        #expect(!options.showWeekly)
        #expect(!options.showCountdown)
    }
    @Test func iconLabelsAreNativeSymbolsWithIndependentWindowIdentity() {
        let items = MenuBarFormatter.items(quota: quota(), sample: sample,
                                           options: DisplayOptions(quotaLabelStyle: .icon), now: now)
        #expect(items[0].title == "82% 2h14m")
        #expect(items[0].symbolName == "clock")
        #expect(items[1].symbolName == "calendar")
        #expect(items[0].accessibilityLabel.contains("5-hour quota"))
        #expect(items[2].symbolName == nil)
    }

    @Test func customLabelsAreBoundedAndRemoveControlCharacters() {
        let options = DisplayOptions(quotaLabelStyle: .custom, customQuotaLabel: "  My  AI\n\tlabeltoolong  ")
        let items = MenuBarFormatter.items(quota: quota(), sample: nil, options: options, now: now)
        #expect(options.normalizedCustomQuotaLabel.count <= 12)
        #expect(!items[0].title.contains("\n"))
        #expect(!items[0].title.contains("\t"))
        #expect(!items[0].title.hasPrefix(" "))
        #expect(items[0].title.hasPrefix(options.normalizedCustomQuotaLabel + " "))
        #expect(DisplayOptions(quotaLabelStyle: .custom, customQuotaLabel: "  ").normalizedCustomQuotaLabel == "AI")
    }

    @Test func customLabelLimitCountsCharactersWithoutSplittingEmoji() {
        let emoji = String(repeating: "👩‍💻", count: 20)
        #expect(DisplayOptions.sanitizeQuotaLabel(emoji).count == 12)
        #expect(DisplayOptions.sanitizeQuotaLabel(emoji) == String(repeating: "👩‍💻", count: 12))
    }

    @Test func percentSignCanBeHiddenWithoutChangingAccessibleMeaning() {
        let items = MenuBarFormatter.items(quota: quota(), sample: nil,
                                           options: DisplayOptions(showPercentSign: false), now: now)
        #expect(items[0].title == "AI 82 2h14m")
        #expect(items[0].accessibilityLabel.contains("82 percent remaining"))
        #expect(MenuBarFormatter.items(quota: nil, sample: nil,
                                      options: DisplayOptions(showPercentSign: false), now: now)[0].title == "AI —")
    }

    @Test func countdownSeparatorsChangePresentationOnly() {
        let expected: [CountdownSeparator: String] = [.space: "AI 82% 2h14m", .dot: "AI 82% · 2h14m",
                                                      .slash: "AI 82% / 2h14m", .parentheses: "AI 82% (2h14m)"]
        for separator in CountdownSeparator.allCases {
            let items = MenuBarFormatter.items(quota: quota(), sample: nil,
                                               options: DisplayOptions(countdownSeparator: separator), now: now)
            #expect(items[0].title == expected[separator])
            #expect(items[0].accessibilityLabel.contains("resets in 2h14m"))
        }
    }

    @Test func fontSizeAndSpacingStayWithinMenuBarBounds() {
        #expect(DisplayOptions(fontSize: 2).normalizedFontSize == 9)
        #expect(DisplayOptions(fontSize: 50).normalizedFontSize == 16)
        #expect(DisplayOptions(fontSize: .nan).normalizedFontSize == 11)
        #expect(DisplayOptions(fontSize: .infinity).normalizedFontSize == 11)
        #expect(DisplayOptions(spacing: .comfortable).itemHorizontalPadding > DisplayOptions(spacing: .compact).itemHorizontalPadding)
    }

    @Test func applyingPresetsPreservesIndependentMetricVisibility() {
        for preset in DisplayPreset.allCases {
            var options = DisplayOptions(showFiveHour: false, showWeekly: true, showCountdown: false, showTPS: false)
            options.applyPreset(preset)
            #expect(!options.showFiveHour)
            #expect(options.showWeekly)
            #expect(!options.showCountdown)
            #expect(!options.showTPS)
            #expect(MenuBarFormatter.items(quota: quota(), sample: nil, options: options, now: now).map(\.metric) == [.weekly])
        }
    }

    @Test func elegantPresetSpecifiesVisibleNativeStyling() {
        var options = DisplayOptions()
        options.applyPreset(.elegant)
        #expect(options.fontDesign == .rounded)
        #expect(options.fontWeight == .semibold)
        #expect(options.colorStyle == .teal)
        #expect(options.itemStyle == .capsule)
        #expect(options.spacing == .comfortable)
        #expect(options.quotaLabelStyle == .icon)
        #expect(options.tpsDecimals == 1)
    }

    @Test func richStyleOptionsRoundTripWithoutLosingIndependentFlags() throws {
        let options = DisplayOptions(showWeekly: false, quotaLabelStyle: .custom, countdownStyle: .clock,
                                     tpsDecimals: 1, showTPSLabel: false, fontSize: 13, fontWeight: .semibold,
                                     fontDesign: .rounded, colorStyle: .purple, itemStyle: .capsule,
                                     spacing: .comfortable, customQuotaLabel: "My AI", showPercentSign: false,
                                     countdownSeparator: .parentheses)
        #expect(try JSONDecoder().decode(DisplayOptions.self, from: JSONEncoder().encode(options)) == options)
    }

}
