import AppKit
import CodexMeterCore
import ServiceManagement
import SwiftUI

fileprivate enum SettingsPane: String, CaseIterable, Identifiable {
    case general, sections, appearance, metrics, refresh, notifications
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: L10n.text("General")
        case .sections: L10n.text("Detail panel layout")
        case .appearance: L10n.text("Menu bar appearance")
        case .metrics: L10n.text("Labels & visible metrics")
        case .refresh: L10n.text("Refresh periods")
        case .notifications: L10n.text("Notifications")
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .sections: "rectangle.3.group"
        case .appearance: "paintbrush"
        case .metrics: "menubar.rectangle"
        case .refresh: "arrow.clockwise"
        case .notifications: "bell"
        }
    }
}

struct SettingsContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: AppUpdates
    @ObservedObject private var reminders: AppReminders
    @StateObject private var disclosure = SettingsDisclosureState()
    private let pane: SettingsPane?

    init(model: AppModel, updates: AppUpdates) {
        self.init(model: model, updates: updates, pane: nil)
    }

    fileprivate init(model: AppModel, updates: AppUpdates, pane: SettingsPane?) {
        self.model = model
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
                    detailLayoutSettings
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
        case .sections: detailLayoutSettings
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
            DisclosureGroup(target.title, isExpanded: Binding(
                get: { disclosure.expanded.contains(target) },
                set: { expanded in
                    if expanded { disclosure.expanded.insert(target) }
                    else { disclosure.expanded.remove(target) }
                })) {
                content().padding(.top, 12)
            }
            .font(MeterStyle.sectionFont)
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

    private var detailLayoutSettings: some View {
        settingsGroup(.sections) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.detailLayout.order) { section in
                    HStack(spacing: 8) {
                        Label {
                            Text(section.title).frame(maxWidth: .infinity, alignment: .leading)
                        } icon: {
                            Image(systemName: section.symbol).font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary).frame(width: 16).accessibilityHidden(true)
                        }
                        layoutArrow(section, step: -1)
                        layoutArrow(section, step: 1)
                        Toggle(section.title, isOn: Binding(
                            get: { !model.detailLayout.hidden.contains(section) },
                            set: { model.detailLayout.setVisible($0, for: section) }))
                            .labelsHidden().accessibilityLabel(L10n.text("Show \(section.title)"))
                            .padding(.leading, 6)
                    }
                    .frame(minHeight: 30)
                }
                Divider()
                note(L10n.text("Use arrows to reorder; switches show or hide sections."))
                HStack {
                    Spacer()
                    Button(L10n.text("Default layout")) { model.detailLayout = AppDefaults.detailLayout }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private func layoutArrow(_ section: DetailSection, step: Int) -> some View {
        let title = step < 0 ? L10n.text("Move \(section.title) up") : L10n.text("Move \(section.title) down")
        return Button { model.detailLayout.move(section, by: step) } label: {
            Image(systemName: step < 0 ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .medium)).frame(width: 12, height: 14)
        }
        .buttonStyle(.bordered)
        .frame(width: 26, height: 26)
        .disabled(!model.detailLayout.canMove(section, by: step))
        .help(title).accessibilityLabel(title)
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
                        MeterFontStepper(value: $model.options.fontSize)
                            .frame(width: 64, height: 28)
                    }.frame(width: controlWidth, alignment: .trailing)
                }
                segmentedPicker(L10n.text("Weight"), selection: $model.options.fontWeight) {
                    Text(L10n.text("Regular")).tag(MenuBarFontWeight.regular)
                    Text(L10n.text("Medium")).tag(MenuBarFontWeight.medium)
                    Text(L10n.text("Semibold")).tag(MenuBarFontWeight.semibold)
                }
                segmentedPicker(L10n.text("Typeface"), selection: $model.options.fontDesign) {
                    Text(L10n.text("System")).tag(MenuBarFontDesign.system)
                    Text(L10n.text("Rounded")).tag(MenuBarFontDesign.rounded)
                    Text(L10n.text("Mono")).tag(MenuBarFontDesign.monospaced)
                }
                menuPicker(L10n.text("Color"), selection: $model.options.colorStyle) {
                    ForEach(MenuBarColorStyle.allCases, id: \.self) { Text(L10n.lookup($0.rawValue.capitalized)).tag($0) }
                }
                segmentedPicker(L10n.text("Background"), selection: $model.options.itemStyle) {
                    Text(L10n.text("On open")).tag(MenuBarItemStyle.activeCapsule)
                    Text(L10n.text("Always")).tag(MenuBarItemStyle.capsule)
                    Text(L10n.text("None")).tag(MenuBarItemStyle.plain)
                }
                segmentedPicker(L10n.text("Spacing"), selection: $model.options.spacing) {
                    Text(L10n.text("Compact")).tag(MenuBarSpacing.compact)
                    Text(L10n.text("Comfortable")).tag(MenuBarSpacing.comfortable)
                }
            }
        }
    }

    private var layoutSettings: some View {
        settingsGroup(.metrics) {
            VStack(alignment: .leading, spacing: 12) {
                menuPicker(L10n.text("Quota labels"), selection: $model.options.quotaLabelStyle) {
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
                settingsToggle(L10n.text("Show 5-hour quota"), isOn: $model.options.showFiveHour)
                settingsToggle(L10n.text("Show 7-day quota"), isOn: $model.options.showWeekly)
                settingsToggle(L10n.text("Show percent sign"), isOn: $model.options.showPercentSign)
                settingsToggle(L10n.text("Show reset countdown"), isOn: $model.options.showCountdown)
                segmentedPicker(L10n.text("Countdown"), selection: $model.options.countdownStyle) {
                    Text("2h14m").tag(CountdownStyle.compact)
                    Text("02:14").tag(CountdownStyle.clock)
                }
                menuPicker(L10n.text("Countdown separator"), selection: $model.options.countdownSeparator) {
                    Text(L10n.text("Space")).tag(CountdownSeparator.space)
                    Text(L10n.text("Middle dot")).tag(CountdownSeparator.dot)
                    Text(L10n.text("Slash")).tag(CountdownSeparator.slash)
                    Text(L10n.text("Parentheses")).tag(CountdownSeparator.parentheses)
                }
                Divider()
                settingsToggle(L10n.text("Show TPS"), isOn: $model.options.showTPS)
                segmentedPicker(L10n.text("TPS layout"), selection: $model.options.tpsLayout) {
                    Text(L10n.text("Inline")).tag(MenuBarTPSLayout.inline)
                    Text(L10n.text("Stacked")).tag(MenuBarTPSLayout.stacked)
                }
                segmentedPicker(L10n.text("TPS decimals"), selection: $model.options.tpsDecimals) {
                    Text("0").tag(0)
                    Text("1").tag(1)
                }
                settingsToggle(L10n.text("Show TPS label"), isOn: $model.options.showTPSLabel)
            }
        }
    }

    private var refreshSettings: some View {
        settingsGroup(.refresh) {
            VStack(alignment: .leading, spacing: 12) {
                settingsToggle(L10n.text("Automatic Refresh"), isOn: $model.autoRefresh)
                note(L10n.text("Also refreshes after wake or network reconnection. Nearby requests are merged and rate-limited."))
                Divider()
                menuPicker(L10n.text("Quota"), selection: $model.refreshOptions.quotaSeconds) {
                    Text(L10n.text("1 minute")).tag(60)
                    Text(L10n.text("3 minutes")).tag(180)
                    Text(L10n.text("5 minutes")).tag(300)
                    Text(L10n.text("10 minutes")).tag(600)
                    Text(L10n.text("15 minutes")).tag(900)
                }
                menuPicker(L10n.text("Local response logs"), selection: $model.refreshOptions.logSeconds) {
                    ForEach([1.0, 2, 5, 10, 30], id: \.self) { Text(L10n.text("\(Int($0)) seconds")).tag($0) }
                }
                menuPicker(L10n.text("Countdown display"), selection: $model.refreshOptions.displaySeconds) {
                    Text(L10n.text("15 seconds")).tag(15)
                    Text(L10n.text("30 seconds")).tag(30)
                    Text(L10n.text("1 minute")).tag(60)
                }
                menuPicker(L10n.text("Account statistics"), selection: $model.refreshOptions.accountSeconds) {
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
                menuPicker(L10n.text("Language"), selection: $model.language) {
                    Text(L10n.text("Follow System")).tag(AppLanguage.system)
                    Text("简体中文").tag(AppLanguage.simplifiedChinese)
                    Text("English").tag(AppLanguage.english)
                }
                note(L10n.text("Language changes apply immediately. Existing scheduled notifications keep their original language."))
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
                    settingsToggle(L10n.text("Monitor 5-hour quota"), isOn: reminderBinding(\.fiveHourEnabled))
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

private final class SettingsDisclosureState: ObservableObject {
    @Published var expanded: Set<SettingsPane> = [.general, .sections]
}

private final class SettingsNavigationState: ObservableObject {
    @Published var selected: SettingsPane? = .general
}

struct SettingsWindowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: AppUpdates
    @StateObject private var navigation = SettingsNavigationState()

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $navigation.selected) {
                ForEach(SettingsPane.allCases) { pane in
                    Label {
                        Text(pane.title).lineLimit(2)
                    } icon: {
                        Image(systemName: pane.symbol).font(.system(size: 13, weight: .regular))
                            .foregroundStyle(navigation.selected == pane
                                ? Color(nsColor: .selectedControlTextColor) : Color.secondary)
                            .accessibilityHidden(true)
                    }
                    .tag(pane)
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 168)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text((navigation.selected ?? .general).title)
                    .font(MeterStyle.paneTitleFont)
                    .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 8)
                SettingsContent(model: model, updates: updates, pane: navigation.selected ?? .general)
                    .id(navigation.selected)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(MeterStyle.background)
        }
        .frame(minWidth: 680, idealWidth: 720, maxWidth: 960, minHeight: 440, idealHeight: 600)
        .environment(\.locale, L10n.locale)
        .onAppear { model.refreshLoginStatus() }
    }
}
