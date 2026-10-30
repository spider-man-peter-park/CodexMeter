import Foundation
import Testing
@testable import CodexMeterCore

struct LocalizationTests {
    @Test func languageResolutionHasAnEnglishFallback() {
        #expect(AppLanguage.system.resolvedCode(preferredLanguages: ["zh-Hans-CN", "en"]) == "zh-Hans")
        #expect(AppLanguage.system.resolvedCode(preferredLanguages: ["en-GB", "zh-Hans"]) == "en")
        #expect(AppLanguage.system.resolvedCode(preferredLanguages: ["fr-FR"]) == "en")
        #expect(AppLanguage.system.resolvedCode(preferredLanguages: []) == "en")
        #expect(AppLanguage.english.resolvedCode(preferredLanguages: ["zh-CN"]) == "en")
        #expect(AppLanguage.simplifiedChinese.resolvedCode(preferredLanguages: ["en"]) == "zh-Hans")
    }

    @Test func shippedCatalogsHaveMatchingKeysAndPlaceholders() throws {
        func catalog(_ language: String) throws -> [String: String] {
            let bundle = try #require(L10n.localizedBundle(language))
            let path = try #require(bundle.url(forResource: "Localizable", withExtension: "strings"))
            return try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: path), format: nil) as? [String: String])
        }
        let english = try catalog("en"), chinese = try catalog("zh-Hans")
        #expect(english.count > 250)
        #expect(Set(english.keys) == Set(chinese.keys))
        let regex = try NSRegularExpression(pattern: #"\{\d+\}"#)
        func placeholders(_ text: String) -> [String] {
            regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .compactMap { Range($0.range, in: text).map { String(text[$0]) } }.sorted()
        }
        for key in english.keys {
            let translated = try #require(chinese[key])
            #expect(!translated.isEmpty)
            #expect(placeholders(key) == placeholders(translated))
        }
    }

    @Test func chineseResourcesAndEnglishFallbackLoadFromTheBundle() {
        #expect(L10n.text("Settings", language: .simplifiedChinese) == "设置")
        #expect(L10n.lookup("Full reset", language: .simplifiedChinese) == "完整重置")
        #expect(L10n.text("Settings", language: .english) == "Settings")
        #expect(L10n.lookup("future-model-name", language: .simplifiedChinese) == "future-model-name")
        #expect(L10n.text("\(3) available", language: .simplifiedChinese) == "3 张可用")
    }

    @Test func interpolationKeepsArgumentsLiteralAndPreservesPercentSigns() {
        let adversarial = "模型 {1} %@ 中文"
        #expect(L10n.text("Showing \(adversarial) credit details. The account reports \(2) available credits.",
                         language: .simplifiedChinese) == "显示 模型 {1} %@ 中文 张卡片的明细，账户报告共有 2 张可用。")
        #expect(L10n.text("The \("5 小时") window now has \(25)% remaining.", language: .simplifiedChinese)
                == "5 小时额度已恢复，当前剩余 25%。")
    }

    @Test func translatedNotificationsKeepTheirIdentityAndDeadlines() {
        let now = Date()
        let expiry = now.addingTimeInterval(5 * 86400)
        let snapshot = QuotaSnapshot(fiveHour: nil, weekly: nil, updatedAt: now, source: .appServer,
            resetCredits: ResetCreditSummary(availableCount: 1, credits: [
                ResetCredit(id: "card", resetType: "full", status: "available", expiresAt: expiry)]))
        var options = ReminderOptions(); options.creditExpiryEnabled = true
        let engine = ReminderEngine(scope: "localization")
        let en = L10n.$languageOverride.withValue(.english) { engine.creditRequests(snapshot, options: options, now: now) }
        let zh = L10n.$languageOverride.withValue(.simplifiedChinese) { engine.creditRequests(snapshot, options: options, now: now) }
        #expect(en.map(\.id) == zh.map(\.id))
        #expect(en.map(\.deliveryAt) == zh.map(\.deliveryAt))
        #expect(zh.first?.title == "Codex 重置卡即将到期")
        #expect(zh.first?.body.contains("上次报告为可用") == true)
    }

    @Test func chineseLanguageNeverChangesServerFieldNamesOrMenuBarUnits() {
        L10n.$languageOverride.withValue(.simplifiedChinese) {
            let account = AccountInfoParser.parse(account: ["account": ["planType": "plus"]],
                usage: ["dailyUsageBuckets": [["startDate": "2026-10-28", "tokens": 22000]]])
            #expect(account?.dailyUsageBuckets?.first?.tokens == 22000)
            let now = Date()
            #expect(MenuBarFormatter.countdown(until: now.addingTimeInterval(4 * 86400 + 8 * 3600), now: now) == "4d8h")
            #expect(AppServerError.timeout.errorDescription == "Codex App Server 请求超时。")
        }
    }
}
