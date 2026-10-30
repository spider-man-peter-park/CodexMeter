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
        #expect(items.map(\.metric) == [.fiveHour, .weekly, .tps, .todayTokens])
        #expect(Set(items.map(\.id)).count == 4)
        #expect(items.map(\.title) == ["AI 82% 2h14m", "AI 61% 4d8h", "73 TPS", "—"])
        #expect(items.allSatisfy { !$0.title.contains("|") })
        #expect(items[0].accessibilityLabel.contains(L10n.text("5-hour quota")))
        #expect(items[1].accessibilityLabel.contains(L10n.text("7-day quota")))
    }

    @Test func noDataUsesDashesInsteadOfZero() {
        let items = MenuBarFormatter.items(quota: nil, sample: nil, options: DisplayOptions(), now: now)
        #expect(items.map(\.title) == ["AI —", "AI —", "— TPS", "—"])
        #expect(items.allSatisfy { !$0.title.contains("0%") })
    }

    @Test func windowLabelsRemainAnIndependentChoice() {
        let options = DisplayOptions(quotaLabelStyle: .window)
        let items = MenuBarFormatter.items(quota: quota(), sample: nil, options: options, now: now)
        #expect(items.map(\.title) == ["5h 82% 2h14m", "7d 61% 4d8h", "— TPS", "—"])
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
        #expect(visible.map(\.title) == ["AI 82% 2h14m", "AI 61% 4d8h", "—"])
        let hidden = MenuBarFormatter.items(quota: quota(), sample: nil,
                                            options: DisplayOptions(fullMode: true, showCountdown: false, showTPS: false), now: now)
        #expect(hidden.map(\.title) == ["AI 82%", "AI 61%", "—"])
    }

    @Test func clockCountdownStyleFormatsHoursMinutesAndDays() {
        let items = MenuBarFormatter.items(quota: quota(), sample: nil,
                                           options: DisplayOptions(countdownStyle: .clock), now: now)
        #expect(items[0].title == "AI 82% 02:14")
        #expect(items[1].title == "AI 61% 4d08:00")
        #expect(MenuBarFormatter.countdown(until: now.addingTimeInterval(314 * 60), now: now, style: .clock) == "05:14")
    }

    @Test func metricVisibilityDoesNotCombineRemainingItems() {
        let options = DisplayOptions(showFiveHour: false, showCountdown: false, showTPS: false, showTodayTokens: false)
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
        #expect(items[0].accessibilityLabel.contains(L10n.text(", cached data, may be outdated")))
        let failed = MenuBarFormatter.items(quota: quota(), sample: nil,
                                            options: DisplayOptions(), now: now, stale: true)
        #expect(failed[0].title.hasSuffix(" *"))
    }

    @Test func tpsPrecisionAndSuffixAreIndependent() {
        let options = DisplayOptions(showFiveHour: false, showWeekly: false, showTodayTokens: false,
                                     tpsDecimals: 1, showTPSLabel: false)
        let items = MenuBarFormatter.items(quota: nil, sample: sample, options: options, now: now)
        #expect(items.count == 1)
        #expect(items[0].title == "73.4")
        #expect(items[0].metric == .tps)
        #expect(items[0].accessibilityLabel.contains(L10n.text("Latest completed response, \("73.4") effective tokens per second")))
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
        let options = DisplayOptions(showFiveHour: false, showWeekly: false, showTPS: false, showTodayTokens: false)
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
        #expect(options.tpsLayout == .inline)
        #expect(!options.showWeekly)
        #expect(!options.showCountdown)
        #expect(options.showTodayTokens)
    }
    @Test func iconLabelsAreNativeSymbolsWithIndependentWindowIdentity() {
        let items = MenuBarFormatter.items(quota: quota(), sample: sample,
                                           options: DisplayOptions(quotaLabelStyle: .icon), now: now)
        #expect(items[0].title == "82% 2h14m")
        #expect(items[0].symbolName == "clock")
        #expect(items[1].symbolName == "calendar")
        #expect(items[0].accessibilityLabel.contains(L10n.text("5-hour quota")))
        #expect(items[2].symbolName == "bolt.fill")
    }

    @Test func gptLogoLabelsPreserveIndependentQuotaMetricsAndSurvivePreferences() throws {
        let options = DisplayOptions(quotaLabelStyle: .gpt)
        let restored = try JSONDecoder().decode(DisplayOptions.self, from: JSONEncoder().encode(options))
        let items = MenuBarFormatter.items(quota: quota(), sample: sample, options: restored, now: now)
        #expect(items.map(\.metric) == [.fiveHour, .weekly, .tps, .todayTokens])
        #expect(items.map(\.title) == ["82% 2h14m", "61% 4d8h", "73 TPS", "—"])
        #expect(items.map(\.usesGPTLogo) == [true, true, false, false])
        #expect(items.prefix(2).allSatisfy { $0.symbolName == nil })
        #expect(items[2].symbolName == "bolt.fill")
        #expect(items[0].accessibilityLabel.contains(L10n.text("5-hour quota")))
        #expect(items[1].accessibilityLabel.contains(L10n.text("7-day quota")))
    }

    @Test func gptLogoWorksWithoutQuotaDataAndKeepsHiddenMetricsAccessible() {
        var options = DisplayOptions(quotaLabelStyle: .gpt)
        let missing = MenuBarFormatter.items(quota: nil, sample: nil, options: options, now: now)
        #expect(missing.map(\.title) == ["—", "—", "— TPS", "—"])
        #expect(missing.map(\.usesGPTLogo) == [true, true, false, false])
        options.showFiveHour = false
        options.showWeekly = false
        options.showTPS = false
        options.showTodayTokens = false
        let fallback = MenuBarFormatter.items(quota: nil, sample: nil, options: options, now: now)
        #expect(fallback.count == 1)
        #expect(fallback[0].metric == .fallback)
        #expect(fallback[0].usesGPTLogo)
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
        #expect(items[0].accessibilityLabel.contains(L10n.text(", \(82) percent remaining")))
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
            #expect(items[0].accessibilityLabel.contains(L10n.text(", resets in ") + "2h14m"))
        }
    }

    @Test func fontSizeAndSpacingStayWithinMenuBarBounds() {
        #expect(DisplayOptions(fontSize: 2).normalizedFontSize == 9)
        #expect(DisplayOptions(fontSize: 50).normalizedFontSize == 16)
        #expect(DisplayOptions(fontSize: .nan).normalizedFontSize == 12)
        #expect(DisplayOptions(fontSize: .infinity).normalizedFontSize == 12)
        #expect(DisplayOptions(spacing: .comfortable).itemHorizontalPadding > DisplayOptions(spacing: .compact).itemHorizontalPadding)
    }

    @Test func applyingPresetsPreservesIndependentMetricVisibility() {
        for preset in DisplayPreset.allCases {
            var options = DisplayOptions(showFiveHour: false, showWeekly: true, showCountdown: false,
                                         showTPS: false, showTodayTokens: false)
            options.applyPreset(preset)
            #expect(!options.showFiveHour)
            #expect(options.showWeekly)
            #expect(!options.showCountdown)
            #expect(!options.showTPS)
            #expect(!options.showTodayTokens)
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

    @Test func stackedTPSRetainsPrecisionVisibilityAndPreferenceIndependently() throws {
        let options = DisplayOptions(showFiveHour: false, showWeekly: false, showTodayTokens: false, tpsDecimals: 1,
                                     tpsLayout: .stacked)
        let saved = try JSONDecoder().decode(DisplayOptions.self, from: JSONEncoder().encode(options))
        #expect(saved.tpsLayout == .stacked)
        let items = MenuBarFormatter.items(quota: nil, sample: sample, options: saved, now: now)
        #expect(items.count == 1)
        #expect(items[0].metric == .tps)
        #expect(items[0].tpsValue == "73.4")
        #expect(items[0].title == "73.4 TPS")
        let missing = MenuBarFormatter.items(quota: nil, sample: nil, options: saved, now: now)
        #expect(missing[0].tpsValue == "—")
        var hidden = saved
        hidden.showTPS = false
        #expect(MenuBarFormatter.items(quota: nil, sample: sample, options: hidden, now: now)[0].metric == .fallback)
    }

    @Test func backgroundDefaultsToOpenPanelAndRetainsExplicitPreferences() throws {
        #expect(DisplayOptions().itemStyle == .activeCapsule)
        let legacy = try JSONDecoder().decode(DisplayOptions.self, from: Data("{}".utf8))
        #expect(legacy.itemStyle == .activeCapsule)
        for style in MenuBarItemStyle.allCases {
            let options = DisplayOptions(itemStyle: style)
            #expect(try JSONDecoder().decode(DisplayOptions.self, from: JSONEncoder().encode(options)).itemStyle == style)
        }
    }

    @Test func tpsLightningVisibilityIsIndependentOfLabelsLayoutAndPresets() throws {
        let legacy = try JSONDecoder().decode(DisplayOptions.self, from: Data("{}".utf8))
        #expect(legacy.showTPSIcon)
        for showIcon in [false, true] {
            for showLabel in [false, true] {
                for layout in MenuBarTPSLayout.allCases {
                    var options = DisplayOptions(showFiveHour: false, showWeekly: false, showTodayTokens: false,
                        showTPSLabel: showLabel, showTPSIcon: showIcon, tpsLayout: layout)
                    let item = try #require(MenuBarFormatter.items(quota: nil, sample: sample,
                        options: options, now: now).first)
                    #expect(item.symbolName == (showIcon ? "bolt.fill" : nil))
                    #expect(item.title == (showLabel ? "73 TPS" : "73"))
                    #expect(item.tpsValue == "73")
                    #expect(try JSONDecoder().decode(DisplayOptions.self, from: JSONEncoder().encode(options)) == options)
                    for preset in DisplayPreset.allCases {
                        options.applyPreset(preset)
                        #expect(options.showTPSIcon == showIcon)
                    }
                    options.showTPS = false
                    #expect(MenuBarFormatter.items(quota: nil, sample: sample, options: options, now: now)
                        .map(\.metric) == [.fallback])
                }
            }
        }
    }

    @Test func todayTokensUseOnlyTheLocalTotalAndHaveIndependentVisibility() throws {
        let calendar = Calendar.current
        let usage = LocalDayUsage(dayStart: calendar.startOfDay(for: now), timeZoneIdentifier: calendar.timeZone.identifier,
            input: 12_345, output: 655, cachedInput: 9_000, reasoningOutput: 100, responses: 1,
            updatedAt: now, hasDesktopLogs: true)
        var options = DisplayOptions(showFiveHour: false, showWeekly: false, showTPS: false)
        let item = try #require(MenuBarFormatter.items(quota: quota(source: .logCache), sample: sample,
            options: options, todayUsage: usage, now: now, stale: true).first)
        #expect(item.metric == .todayTokens)
        #expect(item.title == "13K")
        #expect(item.symbolName == "square.stack.3d.up.fill")
        #expect(!item.usesGPTLogo && item.tpsValue == nil)
        #expect(item.accessibilityLabel.contains(L10n.text("Today · this Mac")))
        #expect(item.accessibilityLabel.contains("13"))
        #expect(!item.title.contains("*"))
        options.showTodayTokens = false
        #expect(MenuBarFormatter.items(quota: quota(), sample: sample, options: options,
            todayUsage: usage, now: now).map(\.metric) == [.fallback])
        #expect(try JSONDecoder().decode(DisplayOptions.self, from: JSONEncoder().encode(options)) == options)
    }

    @Test func todayTokensDistinguishMissingPartialAndBackfillingDataFromARealZero() throws {
        let options = DisplayOptions(showFiveHour: false, showWeekly: false, showTPS: false)
        func item(_ usage: LocalDayUsage?) throws -> MenuBarItem {
            try #require(MenuBarFormatter.items(quota: nil, sample: nil, options: options,
                todayUsage: usage, now: now).first)
        }
        #expect(try item(nil).title == "—")
        var usage = LocalDayUsage(dayStart: Calendar.current.startOfDay(for: now),
            timeZoneIdentifier: Calendar.current.timeZone.identifier, updatedAt: now, hasDesktopLogs: true)
        #expect(try item(usage).title == "0")
        usage.isBackfilling = true
        #expect(try item(usage).title == "—")
        usage.input = 1_000
        usage.responses = 1
        #expect(try item(usage).title == "1K")
        #expect(try item(usage).accessibilityLabel.contains(L10n.text("Backfilling today's logs…")))
        usage.isPartial = true
        #expect(try item(usage).accessibilityLabel.contains(L10n.text("Partial estimate: some usage records could not be counted safely.")))
        usage.dayStart = usage.dayStart.addingTimeInterval(-86_400)
        #expect(try item(usage).title == "—")
    }

}
