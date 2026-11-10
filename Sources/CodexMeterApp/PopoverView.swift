import AppKit
import CodexMeterCore
import SwiftUI

struct PopoverView: View {
    private static let appIcon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        .flatMap { NSImage(contentsOf: $0) }
        ?? NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: nil)!
    @ObservedObject var model: AppModel
    @ObservedObject var updates: AppUpdates
    @StateObject private var measurement = DetailPanelMeasurement()
    var onOpenSettings: () -> Void = {}
    var onOpenAbout: () -> Void = {}
    var panelHeight: CGFloat = 980

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, MeterStyle.pageInset).padding(.vertical, 12)
                .measurePanelPart(.header)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if updates.updateAvailable, let latest = updates.latestVersion {
                        Link(L10n.text("CodexMeter \(latest.description) is available"), destination: AppMetadata.projectURL)
                            .font(.caption.weight(.medium))
                    }
                    sectionContainer {
                        MetricDetailContent(model: model, updates: updates,
                            section: model.selectedDetailSection, quotaMetric: model.selectedQuotaMetric)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .measurePanelPart(.content)
            }
            .frame(height: measurement.viewportHeight(maximum: panelHeight))
            .scrollDisabled(!measurement.needsScrolling(maximum: panelHeight))
            .scrollIndicators(measurement.needsScrolling(maximum: panelHeight) ? .automatic : .hidden)
            .id(model.selectedDetailSection.rawValue + "." + (model.selectedQuotaMetric?.rawValue ?? "all"))
            .background(MeterStyle.background)
            Divider()
            footer.padding(.horizontal, MeterStyle.pageInset).padding(.vertical, 10)
                .background(MeterStyle.surface)
                .measurePanelPart(.footer)
        }
        .frame(width: 480)
        .onPreferenceChange(DetailPanelSizeKey.self) { measurement.update($0) }
        .environment(\.locale, L10n.locale)
        .id(model.language)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(nsImage: Self.appIcon)
                .resizable().interpolation(.high).frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(AppMetadata.name).font(MeterStyle.titleFont)
                Text(L10n.text("Know your limits. Keep your focus.")).font(MeterStyle.captionFont).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(model.detailLayout.visibleSections) { section in
                    Button {
                        model.selectedDetailSection = section
                        model.selectedQuotaMetric = nil
                    } label: {
                        Label(section.title, systemImage: section.symbol)
                    }
                }
            } label: {
                Image(systemName: "rectangle.stack").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .disabled(model.detailLayout.visibleSections.isEmpty)
            .frame(width: 20).help(L10n.text("Other details")).accessibilityLabel(L10n.text("Other details"))
            Group {
                if model.refreshing || model.accountRefreshing { ProgressView().controlSize(.small) }
                else { Color.clear }
            }.frame(width: 16, height: 16)
            MeterIconButton(symbol: "arrow.clockwise", title: L10n.text("Refresh")) { model.refresh() }
                .disabled(model.refreshing)
                .help(model.quota == nil && model.quotaWarning != nil
                    ? L10n.text("Open Codex and sign in there, then refresh. CodexMeter never opens a login flow.")
                    : L10n.text("Refresh quota, account usage and local responses"))
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(footerStatus.title)
                Text(footerStatus.value)
            }.font(MeterStyle.captionFont).foregroundStyle(.secondary)
            Spacer()
            MeterIconButton(symbol: "gearshape", title: L10n.text("Settings"), action: onOpenSettings)
            MeterIconButton(symbol: "info.circle", title: L10n.text("About CodexMeter"), action: onOpenAbout)
            Button(L10n.text("Quit")) { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless).font(MeterStyle.captionFont)
                .help(L10n.text("Quit CodexMeter")).accessibilityLabel(L10n.text("Quit CodexMeter"))
        }
    }

    private var footerStatus: (title: String, value: String) {
        switch model.selectedDetailSection {
        case .cpu, .gpu, .ram, .network:
            (L10n.text("System updated"), model.currentSystemMetrics.map { Self.date($0.sampledAt) } ?? L10n.text("Waiting for system data"))
        case .speed:
            (L10n.text("Latest response"), model.sample.map { Self.date($0.completedAt) } ?? "—")
        case .today:
            (L10n.text("Today · this Mac"), model.localDayUsage.map { Self.date($0.updatedAt) } ?? "—")
        case .account:
            (L10n.text("Account usage"), model.accountInfo.map { Self.date($0.updatedAt) } ?? "—")
        case .settings:
            (AppMetadata.name, L10n.text("Settings"))
        case .quota:
            (model.quota?.source == .appServer && model.quota?.isStale == false && model.quotaWarning == nil ? L10n.text("Live quota") : L10n.text("Quota updated"),
             model.quota.map { Self.date($0.updatedAt) } ?? L10n.text("No quota data yet"))
        }
    }

    private func sectionContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, MeterStyle.pageInset)
            .padding(.vertical, MeterStyle.sectionGap)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func date(_ value: Date) -> String {
        value.formatted(.dateTime.month(.abbreviated).day().hour().minute().second().locale(L10n.locale))
    }


}

enum DetailPanelPart: Hashable { case header, content, footer }

private struct DetailPanelSizeKey: PreferenceKey {
    static let defaultValue: [DetailPanelPart: CGFloat] = [:]
    static func reduce(value: inout [DetailPanelPart: CGFloat], nextValue: () -> [DetailPanelPart: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension View {
    func measurePanelPart(_ part: DetailPanelPart) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: DetailPanelSizeKey.self, value: [part: geometry.size.height])
        })
    }
}

final class DetailPanelMeasurement: ObservableObject {
    @Published private var heights: [DetailPanelPart: CGFloat] = [:]

    func update(_ values: [DetailPanelPart: CGFloat]) {
        let valid = values.filter { $0.value.isFinite && $0.value > 0 }
        guard valid.contains(where: { abs((heights[$0.key] ?? 0) - $0.value) > 0.5 }) else { return }
        heights.merge(valid, uniquingKeysWith: { _, new in new })
    }

    func viewportHeight(maximum: CGFloat) -> CGFloat {
        let chrome = (heights[.header] ?? 62) + (heights[.footer] ?? 50) + 2
        return max(0, min(heights[.content] ?? 280, maximum - chrome))
    }

    func needsScrolling(maximum: CGFloat) -> Bool {
        (heights[.content] ?? 280) > viewportHeight(maximum: maximum) + 0.5
    }
}

@MainActor final class PopoverContentHost {
    private let popover: NSPopover
    private let model: AppModel
    private let updates: AppUpdates
    private let onOpenSettings: () -> Void
    private let onOpenAbout: () -> Void
    private(set) var controller: NSHostingController<PopoverView>?

    init(popover: NSPopover, model: AppModel, updates: AppUpdates,
         onOpenSettings: @escaping () -> Void = {}, onOpenAbout: @escaping () -> Void = {}) {
        self.popover = popover
        self.model = model
        self.updates = updates
        self.onOpenSettings = onOpenSettings
        self.onOpenAbout = onOpenAbout
    }

    @discardableResult
    func prepare(panelHeight: CGFloat) -> NSHostingController<PopoverView> {
        if let controller {
            if controller.rootView.panelHeight != panelHeight { controller.rootView.panelHeight = panelHeight }
            return controller
        }
        let controller = NSHostingController(rootView: PopoverView(model: model, updates: updates,
            onOpenSettings: onOpenSettings, onOpenAbout: onOpenAbout, panelHeight: panelHeight))
        controller.sizingOptions = [.preferredContentSize]
        self.controller = controller
        popover.contentViewController = controller
        return controller
    }

    @discardableResult
    func releaseIfHidden() -> Bool {
        guard !popover.isShown else { return false }
        let hadContent = controller != nil || popover.contentViewController != nil
        // Detach both owners so hidden details stop observing live model updates.
        popover.contentViewController = nil
        controller = nil
        return hadContent
    }
}
