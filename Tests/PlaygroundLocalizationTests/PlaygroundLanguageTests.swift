import Foundation
import PlaygroundLocalization
import Testing

struct PlaygroundLanguageTests {
    @Test func savedLanguageWinsAndMissingPreferencesFollowTheSystem() {
        #expect(PlaygroundLanguage.resolve(saved: "en", preferredLanguages: ["zh-Hans-CN"]) == .english)
        #expect(PlaygroundLanguage.resolve(saved: "zh-Hans", preferredLanguages: ["en-US"]) == .simplifiedChinese)
        #expect(PlaygroundLanguage.resolve(saved: nil, preferredLanguages: ["zh-Hant-TW", "en"]) == .simplifiedChinese)
        #expect(PlaygroundLanguage.resolve(saved: "invalid", preferredLanguages: ["en-GB"]) == .english)
        #expect(PlaygroundLanguage.resolve(saved: nil, preferredLanguages: []) == .english)
    }

    @Test func allDeclaredTranslationsHaveContentAndEnglishRemainsUnchanged() {
        for (key, translation) in PlaygroundLanguage.chinese {
            #expect(!translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty translation: \(key)")
            #expect(PlaygroundLanguage.english.text(key) == key)
            #expect(PlaygroundLanguage.simplifiedChinese.text(key) == translation)
        }
        #expect(PlaygroundLanguage.english.displayName == "English")
        #expect(PlaygroundLanguage.simplifiedChinese.displayName == "简体中文")
    }

    @Test func translatedFormatsPreserveTheirArguments() throws {
        let expression = try NSRegularExpression(pattern: "%[0-9.]*[@dfg]")
        func arguments(_ text: String) -> [String] {
            let source = text.replacingOccurrences(of: "%%", with: "")
            return expression.matches(in: source, range: NSRange(source.startIndex..., in: source)).map {
                String(source[Range($0.range, in: source)!])
            }
        }
        for (key, translation) in PlaygroundLanguage.chinese {
            #expect(arguments(key) == arguments(translation), "Format arguments changed: \(key)")
        }
        #expect(PlaygroundLanguage.simplifiedChinese.format("%d percent activated", 42) == "激活进度 42%")
        #expect(PlaygroundLanguage.english.format("%d percent activated", 42) == "42 percent activated")
        #expect(PlaygroundLanguage.simplifiedChinese.format("Last input · %@", "展开") == "最近操作 · 展开")
    }

    @Test func bothModesAndEveryConstructionPhaseHaveChineseLabels() {
        let language = PlaygroundLanguage.simplifiedChinese
        for key in ["Orb", "Projection", "Orb Motion Playground", "Projection Playground", "Beam", "Timing",
                    "A · Orb activation", "B · Beam launch", "C · Focal point", "D · Core construction",
                    "E · Peripheral structures", "F · Steady projection", "Expanding", "Retracting", "Projected",
                    "SIGNAL TRACE", "SPECTRUM", "PHASE STUDY", "LINK STRUCTURE", "Source entered", "Source exited"] {
            #expect(language.text(key) != key, "Missing user-facing translation: \(key)")
        }
        #expect(language.text("HUD") == "HUD")
    }
}
