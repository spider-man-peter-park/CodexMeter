import AppKit
import CodexMeterCore
import Combine
import ServiceManagement
import SwiftUI

final class AppSettingsObservation: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    let model: AppModel
    private var subscription: AnyCancellable?

    @MainActor init(model: AppModel) {
        self.model = model
        // Settings observe preference changes, independently of live metric refreshes.
        let changes: [AnyPublisher<Void, Never>] = [
            model.$provider.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$menuBarMode.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$showFloatingHUD.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$options.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$detailLayout.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$refreshOptions.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$autoRefresh.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$language.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$appearance.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$fiveHourAvailable.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$loginEnabled.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            model.$loginWarning.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher()
        ]
        subscription = Publishers.MergeMany(changes).sink { [weak self] in self?.objectWillChange.send() }
    }

    @MainActor func binding<Value>(_ keyPath: ReferenceWritableKeyPath<AppModel, Value>) -> Binding<Value> {
        Binding(get: { self.model[keyPath: keyPath] }, set: { self.model[keyPath: keyPath] = $0 })
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, metrics, refresh, notifications
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: L10n.text("General")
        case .appearance: L10n.text("Menu bar appearance")
        case .metrics: L10n.text("Labels & visible metrics")
        case .refresh: L10n.text("Refresh periods")
        case .notifications: L10n.text("Notifications")
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .metrics: "menubar.rectangle"
        case .refresh: "arrow.clockwise"
        case .notifications: "bell"
        }
    }
}

struct SettingsContent: View {
    @StateObject private var settings: AppSettingsObservation
    private var model: AppModel { settings.model }
    @ObservedObject var updates: AppUpdates
    @ObservedObject private var reminders: AppReminders
    private let pane: SettingsPane?

    init(model: AppModel, updates: AppUpdates) {
        self.init(model: model, updates: updates, pane: nil)
    }

    init(model: AppModel, updates: AppUpdates, pane: SettingsPane?) {
        _settings = StateObject(wrappedValue: AppSettingsObservation(model: model))
        self.updates = updates
        self.reminders = model.reminders
        self.pane = pane
    }

    var body: some View {
        Group {
            if let pane {
                Form {
                    Section {
                        contents(for: pane)
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    generalSettings
                    Divider()
                    reminderSettings
                    Divider()
                    appearanceSettings
                    Divider()
                    layoutSettings
                    Divider()
                    refreshSettings
                }
            }
        }
        .font(MeterStyle.bodyFont)
        .toggleStyle(.switch)
        .controlSize(.small)
        .environment(\.locale, L10n.locale)
        .id(model.language)
    }

    @ViewBuilder private func contents(for pane: SettingsPane) -> some View {
        switch pane {
        case .general: generalSettings
        case .appearance: appearanceSettings
        case .metrics: layoutSettings
        case .refresh: refreshSettings
        case .notifications: reminderSettings
        }
    }

    @ViewBuilder private func settingsGroup<Content: View>(_ target: SettingsPane,
                                                          @ViewBuilder content: @escaping () -> Content) -> some View {
        if pane != nil {
            content()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(target.title).font(MeterStyle.sectionFont)
                content()
            }
        }
    }

    private var controlWidth: CGFloat { pane == nil ? 192 : 220 }

    private func settingsRow<Control: View>(_ title: String,
                                           @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
        .font(MeterStyle.bodyFont)
        .frame(minHeight: MeterStyle.controlHeight)
    }

    private func menuPicker<Value: Hashable, Choices: View>(_ title: String, selection: Binding<Value>,
                                                           @ViewBuilder choices: () -> Choices) -> some View {
        settingsRow(title) {
            Picker(title, selection: selection, content: choices)
                .labelsHidden().pickerStyle(.menu)
                .frame(width: controlWidth, alignment: .trailing)
                .accessibilityLabel(title)
        }
    }

    private func segmentedPicker<Value: Hashable, Choices: View>(_ title: String, selection: Binding<Value>,
                                                                @ViewBuilder choices: () -> Choices) -> some View {
        settingsRow(title) {
            Picker(title, selection: selection, content: choices)
                .labelsHidden().pickerStyle(.segmented)
                .frame(width: controlWidth)
                .accessibilityLabel(title)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(MeterStyle.captionFont).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appearanceSettings: some View {
        settingsGroup(.appearance) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(DisplayPreset.allCases, id: \.self) { preset in
                        Button(L10n.lookup(preset.rawValue.capitalized)) { model.options.applyPreset(preset) }
                            .buttonStyle(.bordered).frame(maxWidth: .infinity)
                    }
                }.help(L10n.text("Apply a style preset. Your visible metrics and refresh periods stay unchanged."))
                Divider()
                settingsRow(L10n.text("Font size")) {
                    HStack(spacing: 8) {
                        Text(String(format: "%.0f pt", model.options.normalizedFontSize)).monospacedDigit()
                        MeterFontStepper(value: settings.binding(\.options.fontSize))
                            .frame(width: 64, height: 28)
                    }.frame(width: controlWidth, alignment: .trailing)
                }
                segmentedPicker(L10n.text("Weight"), selection: settings.binding(\.options.fontWeight)) {
                    Text(L10n.text("Regular")).tag(MenuBarFontWeight.regular)
                    Text(L10n.text("Medium")).tag(MenuBarFontWeight.medium)
                    Text(L10n.text("Semibold")).tag(MenuBarFontWeight.semibold)
                }
                segmentedPicker(L10n.text("Typeface"), selection: settings.binding(\.options.fontDesign)) {
                    Text(L10n.text("System")).tag(MenuBarFontDesign.system)
                    Text(L10n.text("Rounded")).tag(MenuBarFontDesign.rounded)
                    Text(L10n.text("Mono")).tag(MenuBarFontDesign.monospaced)
                }
                menuPicker(L10n.text("Color"), selection: settings.binding(\.options.colorStyle)) {
                    ForEach(MenuBarColorStyle.allCases, id: \.self) { Text(L10n.lookup($0.rawValue.capitalized)).tag($0) }
                }
                segmentedPicker(L10n.text("Background"), selection: settings.binding(\.options.itemStyle)) {
                    Text(L10n.text("On open")).tag(MenuBarItemStyle.activeCapsule)
                    Text(L10n.text("Always")).tag(MenuBarItemStyle.capsule)
                    Text(L10n.text("None")).tag(MenuBarItemStyle.plain)
                }
                segmentedPicker(L10n.text("Spacing"), selection: settings.binding(\.options.spacing)) {
                    Text(L10n.text("Compact")).tag(MenuBarSpacing.compact)
                    Text(L10n.text("Comfortable")).tag(MenuBarSpacing.comfortable)
                }
            }
        }
    }

    private var layoutSettings: some View {
        settingsGroup(.metrics) {
            VStack(alignment: .leading, spacing: 12) {
                if model.fiveHourAvailable != false {
                    metricSettings(L10n.text("Show 5-hour quota"), isOn: settings.binding(\.options.showFiveHour),
                                   detailsTitle: L10n.text("Quota display options")) {
                        quotaDisplaySettings
                    }
                    Divider()
                }
                metricSettings(L10n.text("Show 7-day quota"), isOn: settings.binding(\.options.showWeekly),
                               detailsTitle: L10n.text("Quota display options")) {
                    quotaDisplaySettings
                }
                Divider()
                metricSettings(L10n.text("Show TPS"), isOn: settings.binding(\.options.showTPS),
                               detailsTitle: L10n.text("TPS display options")) {
                    segmentedPicker(L10n.text("TPS layout"), selection: settings.binding(\.options.tpsLayout)) {
                        Text(L10n.text("Inline")).tag(MenuBarTPSLayout.inline)
                        Text(L10n.text("Stacked")).tag(MenuBarTPSLayout.stacked)
                    }
                    segmentedPicker(L10n.text("TPS decimals"), selection: settings.binding(\.options.tpsDecimals)) {
                        Text("0").tag(0)
                        Text("1").tag(1)
                    }
                    settingsToggle(L10n.text("Show TPS label"), isOn: settings.binding(\.options.showTPSLabel))
                    settingsToggle(L10n.text("Show TPS lightning icon"), isOn: settings.binding(\.options.showTPSIcon))
                }
                Divider()
                metricSettings(L10n.text("Show today's tokens"), isOn: settings.binding(\.options.showTodayTokens),
                               detailsTitle: L10n.text("Today's tokens display options")) {
                    settingsToggle(L10n.text("Show tok label"), isOn: settings.binding(\.options.showTodayTokensLabel))
                }
                Divider()
                metricSettings(L10n.text("Show CPU usage"), isOn: settings.binding(\.options.showCPU),
                               detailsTitle: L10n.text("CPU display options")) {
                    systemMetricDisplaySettings(settings.binding(\.options.cpuDisplay))
                }
                Divider()
                metricSettings(L10n.text("Show GPU usage"), isOn: settings.binding(\.options.showGPU),
                               detailsTitle: L10n.text("GPU display options")) {
                    systemMetricDisplaySettings(settings.binding(\.options.gpuDisplay))
                }
                Divider()
                metricSettings(L10n.text("Show RAM usage"), isOn: settings.binding(\.options.showRAM),
                               detailsTitle: L10n.text("RAM display options")) {
                    systemMetricDisplaySettings(settings.binding(\.options.ramDisplay))
                }
                Divider()
                settingsToggle(L10n.text("Show upload speed"), isOn: settings.binding(\.options.showNetworkUpload))
                settingsToggle(L10n.text("Show download speed"), isOn: settings.binding(\.options.showNetworkDownload))
                note(L10n.text("Network directions share one menu item: upload above, download below."))
            }
        }
    }

    private func metricSettings<Content: View>(_ title: String, isOn: Binding<Bool>, detailsTitle: String,
                                              @ViewBuilder details: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsToggle(title, isOn: isOn)
            if isOn.wrappedValue {
                VStack(alignment: .leading, spacing: 12) {
                    Text(detailsTitle).font(MeterStyle.sectionFont)
                    details()
                }
                .padding(.leading, 12)
            }
        }
    }

    private func systemMetricDisplaySettings(_ display: Binding<SystemMetricDisplayOptions>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsToggle(L10n.text("Show icon"), isOn: display.showIcon)
            settingsToggle(L10n.text("Show label"), isOn: display.showLabel)
            if display.wrappedValue.showLabel {
                segmentedPicker(L10n.text("Label position"), selection: display.labelPosition) {
                    Text(L10n.text("Above")).tag(MenuBarLabelPosition.above)
                    Text(L10n.text("Left")).tag(MenuBarLabelPosition.leading)
                }
            }
        }
    }

    private var quotaDisplaySettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            note(L10n.text("Applies to visible 5-hour and 7-day quota labels."))
            menuPicker(L10n.text("Quota labels"), selection: settings.binding(\.options.quotaLabelStyle)) {
                Text("AI").tag(QuotaLabelStyle.ai)
                Text("5h / 7d").tag(QuotaLabelStyle.window)
                Text(L10n.text("Window icons")).tag(QuotaLabelStyle.icon)
                Text(L10n.text("GPT icon")).tag(QuotaLabelStyle.gpt)
                Text(L10n.text("Custom")).tag(QuotaLabelStyle.custom)
                Text(L10n.text("None")).tag(QuotaLabelStyle.none)
            }
            if model.options.quotaLabelStyle == .custom {
                TextField(L10n.text("Custom label · up to 12 characters"), text: Binding(
                    get: { model.options.customQuotaLabel },
                    set: { model.options.customQuotaLabel = DisplayOptions.sanitizeQuotaLabel($0) }))
                    .textFieldStyle(.roundedBorder)
            }
            settingsToggle(L10n.text("Show percent sign"), isOn: settings.binding(\.options.showPercentSign))
            settingsToggle(L10n.text("Show reset countdown"), isOn: settings.binding(\.options.showCountdown))
            if model.options.showCountdown {
                segmentedPicker(L10n.text("Countdown"), selection: settings.binding(\.options.countdownStyle)) {
                    Text("2h14m").tag(CountdownStyle.compact)
                    Text("02:14").tag(CountdownStyle.clock)
                }
                menuPicker(L10n.text("Countdown separator"), selection: settings.binding(\.options.countdownSeparator)) {
                    Text(L10n.text("Space")).tag(CountdownSeparator.space)
                    Text(L10n.text("Middle dot")).tag(CountdownSeparator.dot)
                    Text(L10n.text("Slash")).tag(CountdownSeparator.slash)
                    Text(L10n.text("Parentheses")).tag(CountdownSeparator.parentheses)
                }
            }
        }
    }

    private var refreshSettings: some View {
        settingsGroup(.refresh) {
            VStack(alignment: .leading, spacing: 12) {
                settingsToggle(L10n.text("Automatic Refresh"), isOn: settings.binding(\.autoRefresh))
                note(L10n.text("Also refreshes after wake or network reconnection. Nearby requests are merged and rate-limited."))
                Divider()
                menuPicker(L10n.text("Quota"), selection: settings.binding(\.refreshOptions.quotaSeconds)) {
                    Text(L10n.text("1 minute")).tag(60)
                    Text(L10n.text("3 minutes")).tag(180)
                    Text(L10n.text("5 minutes")).tag(300)
                    Text(L10n.text("10 minutes")).tag(600)
                    Text(L10n.text("15 minutes")).tag(900)
                }
                menuPicker(L10n.text("Local response logs"), selection: settings.binding(\.refreshOptions.logSeconds)) {
                    ForEach([1.0, 2, 5, 10, 30], id: \.self) { Text(L10n.text("\(Int($0)) seconds")).tag($0) }
                }
                menuPicker(L10n.text("Countdown display"), selection: settings.binding(\.refreshOptions.displaySeconds)) {
                    Text(L10n.text("15 seconds")).tag(15)
                    Text(L10n.text("30 seconds")).tag(30)
                    Text(L10n.text("1 minute")).tag(60)
                }
                menuPicker(L10n.text("Account statistics"), selection: settings.binding(\.refreshOptions.accountSeconds)) {
                    Text(L10n.text("5 minutes")).tag(300)
                    Text(L10n.text("15 minutes")).tag(900)
                    Text(L10n.text("30 minutes")).tag(1800)
                    Text(L10n.text("1 hour")).tag(3600)
                }
                note(L10n.text("Response logs stay on this Mac. Account and quota reads use Codex App Server."))
            }
        }
    }

    private var generalSettings: some View {
        settingsGroup(.general) {
            VStack(alignment: .leading, spacing: 12) {
                menuPicker(L10n.text("Theme"), selection: settings.binding(\.appearance)) {
                    Text(L10n.text("Follow System")).tag(AppAppearance.system)
                    Text(L10n.text("Light")).tag(AppAppearance.light)
                    Text(L10n.text("Dark")).tag(AppAppearance.dark)
                }
                menuPicker(L10n.text("Language"), selection: settings.binding(\.language)) {
                    Text(L10n.text("Follow System")).tag(AppLanguage.system)
                    Text("简体中文").tag(AppLanguage.simplifiedChinese)
                    Text("English").tag(AppLanguage.english)
                }
                note(L10n.text("Language changes apply immediately. Existing scheduled notifications keep their original language."))
                Divider()
                settingsToggle(L10n.text("Show floating HUD"), isOn: settings.binding(\.showFloatingHUD))
                Divider()
                settingsToggle(L10n.text("Launch at Login"), isOn: Binding(get: { model.loginEnabled }, set: model.setLogin))
                if let warning = model.loginWarning {
                    note(L10n.lookup(warning))
                    Button(L10n.text("Open Login Items Settings…")) { SMAppService.openSystemSettingsLoginItems() }
                        .buttonStyle(.bordered)
                }
                Divider()
                settingsToggle(L10n.text("Automatically Check for Updates"), isOn: $updates.automaticallyChecks)
                note(L10n.text("Checks GitHub about every 12 hours. Updates are installed manually."))
                HStack(spacing: 8) {
                    Button(updates.checking ? L10n.text("Checking…") : L10n.text("Check for Updates…")) { updates.check(force: true) }
                        .buttonStyle(.bordered).disabled(updates.checking)
                    if updates.checking { ProgressView().controlSize(.small) }
                }
                if let warning = updates.warning {
                    note(L10n.lookup(warning))
                } else if updates.updateAvailable, let latest = updates.latestVersion {
                    Link(L10n.text("Version \(latest.description) Available — View on GitHub"), destination: AppMetadata.projectURL)
                } else if updates.latestVersion != nil {
                    note(L10n.text("CodexMeter is up to date."))
                }
                if let checked = updates.lastChecked {
                    note(L10n.text("Last checked \(checked.formatted(.dateTime.year().month().day().hour().minute().locale(L10n.locale)))"))
                }
            }
        }
    }

    private func settingsToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        settingsRow(title) {
            Toggle(title, isOn: isOn).labelsHidden().accessibilityLabel(title)
        }
    }

    private func reminderBinding<Value>(_ keyPath: WritableKeyPath<ReminderOptions, Value>) -> Binding<Value> {
        Binding(get: { reminders.options[keyPath: keyPath] }, set: { value in
            var options = reminders.options; options[keyPath: keyPath] = value; reminders.setOptions(options)
        })
    }

    private var reminderSettings: some View {
        settingsGroup(.notifications) {
            VStack(alignment: .leading, spacing: 12) {
                settingsToggle(L10n.text("Low quota alerts"), isOn: reminderBinding(\.lowQuotaEnabled))
                settingsToggle(L10n.text("Quota recovery alerts"), isOn: reminderBinding(\.recoveryEnabled))
                Group {
                    if model.fiveHourAvailable != false {
                        settingsToggle(L10n.text("Monitor 5-hour quota"), isOn: reminderBinding(\.fiveHourEnabled))
                    }
                    settingsToggle(L10n.text("Monitor 7-day quota"), isOn: reminderBinding(\.weeklyEnabled))
                    menuPicker(L10n.text("Low quota thresholds"), selection: reminderBinding(\.thresholds)) {
                        Text(L10n.text("20% and 10%")).tag(QuotaAlertThresholds.twentyAndTen)
                        Text("10%").tag(QuotaAlertThresholds.ten)
                        Text("5%").tag(QuotaAlertThresholds.five)
                    }
                }.disabled(!reminders.options.lowQuotaEnabled && !reminders.options.recoveryEnabled)
                note(L10n.text("Recovery is confirmed by a fresh reading at least 5 points above the highest low-quota threshold."))
                Divider()
                settingsToggle(L10n.text("Reset credit expiry reminders"), isOn: reminderBinding(\.creditExpiryEnabled))
                menuPicker(L10n.text("Remind before expiry"), selection: reminderBinding(\.creditLeadTime)) {
                    Text(L10n.text("3 days and 1 day")).tag(CreditExpiryLeadTime.threeDaysAndOneDay)
                    Text(L10n.text("3 days")).tag(CreditExpiryLeadTime.threeDays)
                    Text(L10n.text("1 day")).tag(CreditExpiryLeadTime.oneDay)
                }.disabled(!reminders.options.creditExpiryEnabled)
                note(L10n.text("Only cards reported as available with a known expiry are scheduled. New readings cancel reminders for used or expired cards."))
                if reminders.options.anyEnabled {
                    switch reminders.authorization {
                    case .notDetermined:
                        Button(L10n.text("Enable Notifications…")) { reminders.requestPermissionIfNeeded() }
                            .buttonStyle(.bordered).disabled(reminders.requestingPermission)
                    case .denied:
                        note(L10n.text("Allow CodexMeter in System Settings → Notifications. Permission status updates when you return."))
                    case .allowed:
                        note(L10n.text("Notifications are allowed by macOS."))
                    }
                }
                if let warning = reminders.warning { note(L10n.lookup(warning)) }
                note(L10n.text("Alerts use fresh quota readings. Turn on Automatic Refresh for background monitoring. Previously scheduled card reminders can arrive while the app is closed; their status reflects the last successful read."))
            }
        }
    }
}
