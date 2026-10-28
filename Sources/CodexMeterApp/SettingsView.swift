import AppKit
import CodexMeterCore
import ServiceManagement
import SwiftUI

struct SettingsContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: AppUpdates
    @StateObject private var disclosure = SettingsDisclosureState()

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            generalSettings
            Divider()
            appearanceSettings
            Divider()
            layoutSettings
            Divider()
            refreshSettings
        }
        .toggleStyle(.switch).controlSize(.small)
    }

    private var appearanceSettings: some View {
        DisclosureGroup("Menu bar appearance") {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 6) {
                    ForEach(DisplayPreset.allCases, id: \.self) { preset in
                        Button(preset.rawValue.capitalized) { model.options.applyPreset(preset) }
                            .buttonStyle(.bordered).frame(maxWidth: .infinity)
                    }
                }.help("Apply a style preset. Your visible metrics and refresh periods stay unchanged.")
                HStack {
                    Text("Font size")
                    Spacer()
                    Text(String(format: "%.0f pt", model.options.normalizedFontSize)).monospacedDigit()
                    Stepper("Font size", value: $model.options.fontSize, in: 9...16, step: 1).labelsHidden()
                }
                Picker("Weight", selection: $model.options.fontWeight) {
                    Text("Regular").tag(MenuBarFontWeight.regular)
                    Text("Medium").tag(MenuBarFontWeight.medium)
                    Text("Semibold").tag(MenuBarFontWeight.semibold)
                }.pickerStyle(.segmented)
                Picker("Typeface", selection: $model.options.fontDesign) {
                    Text("System").tag(MenuBarFontDesign.system)
                    Text("Rounded").tag(MenuBarFontDesign.rounded)
                    Text("Mono").tag(MenuBarFontDesign.monospaced)
                }.pickerStyle(.segmented)
                Picker("Color", selection: $model.options.colorStyle) {
                    ForEach(MenuBarColorStyle.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("Background", selection: $model.options.itemStyle) {
                    Text("On open").tag(MenuBarItemStyle.activeCapsule)
                    Text("Always").tag(MenuBarItemStyle.capsule)
                    Text("None").tag(MenuBarItemStyle.plain)
                }.pickerStyle(.segmented)
                Picker("Spacing", selection: $model.options.spacing) {
                    Text("Compact").tag(MenuBarSpacing.compact)
                    Text("Comfortable").tag(MenuBarSpacing.comfortable)
                }.pickerStyle(.segmented)
            }.font(.caption).padding(.top, 10)
        }
    }

    private var layoutSettings: some View {
        DisclosureGroup("Labels & visible metrics") {
            VStack(alignment: .leading, spacing: 11) {
                Picker("Quota labels", selection: $model.options.quotaLabelStyle) {
                    Text("AI").tag(QuotaLabelStyle.ai)
                    Text("5h / 7d").tag(QuotaLabelStyle.window)
                    Text("Window icons").tag(QuotaLabelStyle.icon)
                    Text("GPT icon").tag(QuotaLabelStyle.gpt)
                    Text("Custom").tag(QuotaLabelStyle.custom)
                    Text("None").tag(QuotaLabelStyle.none)
                }
                if model.options.quotaLabelStyle == .custom {
                    TextField("Custom label · up to 12 characters", text: Binding(
                        get: { model.options.customQuotaLabel },
                        set: { model.options.customQuotaLabel = DisplayOptions.sanitizeQuotaLabel($0) }))
                        .textFieldStyle(.roundedBorder)
                }
                settingsToggle("Show 5-hour quota", isOn: $model.options.showFiveHour)
                settingsToggle("Show 7-day quota", isOn: $model.options.showWeekly)
                settingsToggle("Show percent sign", isOn: $model.options.showPercentSign)
                settingsToggle("Show reset countdown", isOn: $model.options.showCountdown)
                Picker("Countdown", selection: $model.options.countdownStyle) {
                    Text("2h14m").tag(CountdownStyle.compact)
                    Text("02:14").tag(CountdownStyle.clock)
                }.pickerStyle(.segmented)
                Picker("Countdown separator", selection: $model.options.countdownSeparator) {
                    Text("Space").tag(CountdownSeparator.space)
                    Text("Middle dot").tag(CountdownSeparator.dot)
                    Text("Slash").tag(CountdownSeparator.slash)
                    Text("Parentheses").tag(CountdownSeparator.parentheses)
                }
                settingsToggle("Show TPS", isOn: $model.options.showTPS)
                Picker("TPS layout", selection: $model.options.tpsLayout) {
                    Text("Inline").tag(MenuBarTPSLayout.inline)
                    Text("Stacked").tag(MenuBarTPSLayout.stacked)
                }.pickerStyle(.segmented)
                Picker("TPS decimals", selection: $model.options.tpsDecimals) {
                    Text("0").tag(0)
                    Text("1").tag(1)
                }.pickerStyle(.segmented)
                settingsToggle("Show TPS label", isOn: $model.options.showTPSLabel)
            }.font(.caption).padding(.top, 10)
        }
    }

    private var refreshSettings: some View {
        DisclosureGroup("Refresh periods") {
            VStack(alignment: .leading, spacing: 11) {
                settingsToggle("Automatic Refresh", isOn: $model.autoRefresh)
                Picker("Quota", selection: $model.refreshOptions.quotaSeconds) {
                    Text("1 minute").tag(60)
                    Text("3 minutes").tag(180)
                    Text("5 minutes").tag(300)
                    Text("10 minutes").tag(600)
                    Text("15 minutes").tag(900)
                }
                Picker("Local response logs", selection: $model.refreshOptions.logSeconds) {
                    ForEach([1.0, 2, 5, 10, 30], id: \.self) { Text(String(format: "%.0f seconds", $0)).tag($0) }
                }
                Picker("Countdown display", selection: $model.refreshOptions.displaySeconds) {
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                }
                Picker("Account statistics", selection: $model.refreshOptions.accountSeconds) {
                    Text("5 minutes").tag(300)
                    Text("15 minutes").tag(900)
                    Text("30 minutes").tag(1800)
                    Text("1 hour").tag(3600)
                }
                Text("Response logs stay on this Mac. Account and quota reads use Codex App Server.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.font(.caption).padding(.top, 10)
        }
    }

    private var generalSettings: some View {
        DisclosureGroup("General", isExpanded: $disclosure.general) {
            VStack(alignment: .leading, spacing: 11) {
                settingsToggle("Launch at Login", isOn: Binding(get: { model.loginEnabled }, set: model.setLogin))
                if let warning = model.loginWarning {
                    Text(warning).font(.caption).foregroundStyle(.secondary)
                    Button("Open Login Items Settings…") { SMAppService.openSystemSettingsLoginItems() }
                }
                settingsToggle("Automatically Check for Updates", isOn: $updates.automaticallyChecks)
                Text("Checks GitHub about every 12 hours. Updates are installed manually.")
                    .font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Button(updates.checking ? "Checking…" : "Check for Updates…") { updates.check(force: true) }
                        .disabled(updates.checking)
                    if updates.checking { ProgressView().controlSize(.small) }
                }
                if let warning = updates.warning {
                    Text(warning).font(.caption2).foregroundStyle(.secondary)
                } else if updates.updateAvailable, let latest = updates.latestVersion {
                    Link("Version \(latest.description) Available — View on GitHub", destination: AppMetadata.projectURL)
                        .font(.caption)
                } else if updates.latestVersion != nil {
                    Text("CodexMeter is up to date.").font(.caption2).foregroundStyle(.secondary)
                }
                if let checked = updates.lastChecked {
                    Text("Last checked \(checked.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }.font(.caption).padding(.top, 10)
        }
    }

    private func settingsToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Toggle(title, isOn: isOn).labelsHidden().accessibilityLabel(title)
        }
    }
}

private final class SettingsDisclosureState: ObservableObject {
    @Published var general = true
}

struct SettingsWindowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: AppUpdates

    var body: some View {
        ScrollView {
            SettingsContent(model: model, updates: updates).padding(22)
        }
        .frame(minWidth: 440, idealWidth: 470, maxWidth: 620, minHeight: 280, idealHeight: 600)
        .onAppear { model.refreshLoginStatus() }
    }
}
