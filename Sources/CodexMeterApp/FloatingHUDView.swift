import AppKit
import CodexMeterCore
import QuartzCore
import SwiftUI

private enum HUDStyle {
    static let cyan = Color(red: 0.13, green: 0.90, blue: 0.87)
    static let blue = Color(red: 0.05, green: 0.42, blue: 0.51)
    static let gold = Color(red: 0.96, green: 0.77, blue: 0.25)
    static let ink = Color(red: 0.008, green: 0.020, blue: 0.027)
    static let muted = Color(red: 0.64, green: 0.82, blue: 0.85)
    static let amber = Color(red: 1, green: 0.70, blue: 0.24)
}

private struct HUDReadout: Identifiable {
    let id: String
    let title: String
    let value: String
    let symbol: String
    let metric: MenuBarMetric
    var fraction: Double? = nil
    var warning = false
    var note: String? = nil
}

struct FloatingHUDView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var usage: AssistantUsageStore
    @ObservedObject var presentation: FloatingHUDPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onOpenMetric: (MenuBarMetric) -> Void
    let onOpenWorkspace: () -> Void
    let onOpenSettings: () -> Void
    let onHide: () -> Void
    let onCollapse: () -> Void

    private var summary: FocusSummary {
        FocusSummary(quota: model.quota, warning: model.quotaWarning,
            automaticRefresh: model.autoRefresh, now: model.now, refreshInterval: model.refreshOptions.quotaInterval)
    }

    private var providerResult: ProviderUsageResult { usage.result(for: model.provider) }
    private var hardware: SystemMetricsSnapshot? { model.currentSystemMetrics }

    var body: some View {
        Group {
            if presentation.visible && presentation.expanded {
                GeometryReader { geometry in
                    let scene = presentation.layout.composition ?? FloatingHUDComposition(size: geometry.size)
                    ZStack(alignment: .topLeading) {
                        technicalCore(compact: scene.isCompact)
                            .frame(width: scene.coreFrame.width, height: scene.coreFrame.height)
                            .position(x: scene.coreFrame.midX, y: scene.coreFrame.midY)
                        ForEach(0..<4) { index in
                            metricCard(index, compact: scene.isCompact)
                                .frame(width: scene.cardFrames[index].width, height: scene.cardFrames[index].height)
                                .position(x: scene.cardFrames[index].midX, y: scene.cardFrames[index].midY)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .frame(width: presentation.layout.dashboardFrame?.width ?? FloatingHUDGeometry.dashboardSize.width,
            height: presentation.layout.dashboardFrame?.height ?? FloatingHUDGeometry.dashboardSize.height)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, L10n.locale)
        .id(model.language)
    }

    private func technicalCore(compact: Bool) -> some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle().fill(HUDStyle.ink.opacity(0.98))
                HUDAnimatedReactor(animated: !reduceMotion, warning: statusWarning, showsCore: false, fraction: primaryFraction)
                VStack(spacing: compact ? 2 : 7) {
                    if !compact {
                        Text(model.provider.title).font(.system(size: 14, weight: .medium)).foregroundStyle(HUDStyle.muted)
                    }
                    Text(primaryValue).font(.system(size: compact ? 25 : 46, weight: .light, design: .monospaced))
                        .monospacedDigit().foregroundStyle(statusWarning ? HUDStyle.amber : .white)
                        .lineLimit(1).minimumScaleFactor(0.65)
                    Text(primaryLabel).font(.system(size: compact ? 10 : 14, weight: .medium))
                        .foregroundStyle(HUDStyle.muted).lineLimit(2).multilineTextAlignment(.center)
                }
                .frame(width: diameter * (compact ? 0.78 : 0.72))
                .position(x: diameter / 2, y: diameter * (compact ? 0.39 : 0.40))
                VStack(spacing: compact ? 0 : 6) {
                    HStack(spacing: 5) {
                        Image(systemName: statusSymbol).accessibilityHidden(true)
                        Text(statusText).lineLimit(compact ? 2 : 3).multilineTextAlignment(.center)
                    }
                    .font(.system(size: compact ? 9 : 12, weight: .medium))
                    .foregroundStyle(statusWarning ? HUDStyle.amber : HUDStyle.muted)
                    if !compact, let date = model.provider == .codex ? model.quota?.updatedAt : providerResult.snapshot?.sampledAt {
                        Text(L10n.text("Checked \(date.formatted(.dateTime.hour().minute().locale(L10n.locale)))"))
                            .font(.system(size: 11)).foregroundStyle(HUDStyle.muted.opacity(0.92))
                    }
                }
                .frame(width: diameter * 0.70)
                .position(x: diameter / 2, y: diameter * (compact ? 0.77 : 0.71))
            }
            .clipShape(Circle())
            .overlay {
                Circle().stroke(HUDStyle.cyan.opacity(0.42), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: HUDStyle.cyan.opacity(0.13), radius: 8)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func metricCard(_ index: Int, compact: Bool) -> some View {
        let padding: CGFloat = compact ? 8 : 12
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            HStack(spacing: 8) {
                Image(systemName: cardSymbol(index)).accessibilityHidden(true)
                Text(cardTitle(index)).font(.system(size: compact ? 12 : 14, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white.opacity(0.92))
            if index == 0 || index == 2 {
                let values = assistantReadouts
                let start = index == 0 ? 0 : 2
                if index == 0 {
                    HStack(alignment: .top, spacing: compact ? 8 : 14) {
                        quotaGauge(values[start], compact: compact)
                        quotaGauge(values[start + 1], compact: compact)
                    }
                } else {
                    HStack(alignment: .top, spacing: compact ? 8 : 14) {
                        technicalReadout(values[start], compact: compact)
                        technicalReadout(values[start + 1], compact: compact)
                    }
                    if !compact, !responseTrace.isEmpty {
                        HUDTraceShape(points: responseTrace, startTime: responseTrace.first?.time ?? 0,
                            endTime: responseTrace.last?.time ?? 1, upperBound: responseTrace.map(\.value).max() ?? 1)
                            .stroke(HUDStyle.cyan.opacity(0.9), lineWidth: 1)
                            .frame(height: 23).accessibilityHidden(true)
                    }
                }
            } else if index == 1 {
                VStack(spacing: compact ? 5 : 10) {
                    hardwareRow("CPU", value: hardware?.cpuUsagePercent, compact: compact)
                    hardwareRow("GPU", value: hardware?.gpuUsagePercent, compact: compact)
                    hardwareRow("RAM", value: hardware?.memoryUsagePercent, compact: compact)
                }
            } else {
                VStack(spacing: compact ? 6 : 8) {
                    networkRow(L10n.text("Upload"), symbol: "arrow.up", value: hardware?.networkUploadBytesPerSecond, compact: compact)
                    networkRow(L10n.text("Download"), symbol: "arrow.down", value: hardware?.networkDownloadBytesPerSecond, compact: compact)
                }
                if !compact, hardware != nil {
                    networkScope.frame(height: 26).accessibilityHidden(true)
                }
            }
        }
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: FloatingHUDComposition.cardCornerRadius).fill(HUDStyle.ink.opacity(0.98))
                .overlay {
                    RoundedRectangle(cornerRadius: FloatingHUDComposition.cardCornerRadius)
                        .fill(LinearGradient(colors: [HUDStyle.cyan.opacity(0.035), .clear, HUDStyle.gold.opacity(0.025)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: FloatingHUDComposition.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: FloatingHUDComposition.cardCornerRadius)
                .stroke(HUDStyle.cyan.opacity(0.44), lineWidth: 0.8)
                .overlay { HUDPanelMarkings().stroke(HUDStyle.cyan.opacity(0.85), lineWidth: 1) }
                .allowsHitTesting(false)
        }
        .shadow(color: HUDStyle.cyan.opacity(0.10), radius: 5)
    }

    private func cardTitle(_ index: Int) -> String {
        switch index {
        case 0: model.provider.title
        case 1: L10n.text("This Mac")
        case 2: model.provider == .codex ? L10n.text("Local activity") : L10n.text("Reported usage")
        default: L10n.text("Network")
        }
    }

    private func cardSymbol(_ index: Int) -> String {
        switch index {
        case 0: "chart.bar.xaxis"
        case 1: "cpu"
        case 2: "waveform.path"
        default: "arrow.up.arrow.down"
        }
    }

    private func technicalReadout(_ readout: HUDReadout, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            HStack(alignment: .top, spacing: 3) {
                Text(readout.title).lineLimit(2)
                if readout.warning { Image(systemName: "exclamationmark.circle").accessibilityHidden(true) }
            }
            .font(.system(size: compact ? 10 : 11)).foregroundStyle(HUDStyle.muted)
            Text(readout.value).font(.system(size: compact ? 17 : 24, weight: .medium, design: .monospaced)).monospacedDigit()
                .foregroundStyle(readout.warning ? HUDStyle.amber : .white).lineLimit(1).minimumScaleFactor(0.70)
            if let fraction = readout.fraction {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(LinearGradient(colors: [HUDStyle.blue, HUDStyle.cyan], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geometry.size.width * fraction)
                    }
                }.frame(height: 3)
            }
            if let note = readout.note {
                Text(note).font(.system(size: compact ? 9 : 10))
                    .foregroundStyle(readout.warning ? HUDStyle.amber : HUDStyle.muted).lineLimit(compact ? 1 : 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func hardwareRow(_ title: String, value: Double?, compact: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: compact ? 10 : 11, weight: .medium, design: .monospaced))
                .frame(width: 30, alignment: .leading)
            GeometryReader { geometry in
                let count = compact ? 12 : 20
                HStack(spacing: 2) {
                    ForEach(0..<count, id: \.self) { index in
                        let active = value.map { $0.isFinite && Double(index) / Double(count) < $0 / 100 } ?? false
                        Rectangle().fill(active ? ((value ?? 0) >= 90 ? HUDStyle.amber : HUDStyle.cyan) : HUDStyle.cyan.opacity(0.10))
                    }
                }
                .frame(width: geometry.size.width)
            }.frame(height: compact ? 4 : 7)
            Text(SystemMetricsFormatter.percent(value)).font(.system(size: compact ? 12 : 16, weight: .medium, design: .monospaced))
                .monospacedDigit().frame(width: compact ? 34 : 44, alignment: .trailing)
        }
        .foregroundStyle(HUDStyle.cyan).accessibilityElement(children: .combine)
    }

    private func networkRow(_ title: String, symbol: String, value: Double?, compact: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: compact ? 11 : 13)).foregroundStyle(symbol == "arrow.up" ? HUDStyle.gold : HUDStyle.cyan)
                .accessibilityHidden(true)
            Text(title).font(.system(size: compact ? 10 : 12)).foregroundStyle(HUDStyle.muted)
            Spacer(minLength: 3)
            Text(SystemMetricsFormatter.rate(value)).font(.system(size: compact ? 12 : 17, weight: .medium, design: .monospaced))
                .monospacedDigit().foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .combine)
    }

    private func quotaGauge(_ readout: HUDReadout, compact: Bool) -> some View {
        let diameter: CGFloat = compact ? (readout.note == nil ? 40 : 32) : (readout.note == nil ? 66 : 54)
        return VStack(spacing: compact ? 3 : 5) {
            ZStack {
                Circle().stroke(HUDStyle.cyan.opacity(0.12), lineWidth: compact ? 3 : 5)
                HUDGaugeTicks().stroke(HUDStyle.cyan.opacity(0.38), lineWidth: 0.8).padding(compact ? 5 : 7)
                if let fraction = readout.fraction {
                    Circle().trim(from: 0, to: min(1, max(0, fraction)))
                        .stroke(readout.warning ? HUDStyle.amber : HUDStyle.cyan,
                            style: StrokeStyle(lineWidth: compact ? 3 : 5, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
                Text(readout.value).font(.system(size: compact ? 12 : 17, weight: .medium, design: .monospaced))
                    .foregroundStyle(readout.warning ? HUDStyle.amber : .white)
                    .lineLimit(1).minimumScaleFactor(0.65).padding(compact ? 4 : 7)
            }
            .frame(width: diameter, height: diameter)
            Text(readout.title).font(.system(size: compact ? 9 : 10, weight: .medium, design: .monospaced))
                .foregroundStyle(HUDStyle.muted).lineLimit(2).multilineTextAlignment(.center)
            if let note = readout.note {
                Text(note).font(.system(size: compact ? 9 : 10)).foregroundStyle(readout.warning ? HUDStyle.amber : HUDStyle.muted)
                    .lineLimit(compact ? 1 : 2).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity).accessibilityElement(children: .combine)
    }

    private var primaryFraction: Double? {
        let value = model.provider == .codex ? summary.window?.remainingPercent
            : model.provider == .cursor ? providerResult.snapshot?.usedPercent : nil
        guard let value, value.isFinite else { return nil }
        return min(1, max(0, value / 100))
    }

    private var responseTrace: [HUDTracePoint] {
        guard model.provider == .codex, !model.tpsHistoryIsUnattributed else { return [] }
        var points: [HUDTracePoint] = []
        var segment = 0
        var previous: TPSHistoryPoint?
        for point in TPSHistory.points(model.recentTPSSamples).suffix(24) {
            if let previous, point.segment != previous.segment || point.sample.completedAt.timeIntervalSince(previous.sample.completedAt) > 300 {
                segment += 1
            }
            points.append(HUDTracePoint(time: point.sample.completedAt.timeIntervalSince1970,
                value: point.sample.tokensPerSecond, segment: segment))
            previous = point
        }
        return points
    }

    private func networkTrace(upload: Bool) -> [HUDTracePoint] {
        guard hardware != nil, let end = model.systemMetricsHistory.last?.sampledAt else { return [] }
        var points: [HUDTracePoint] = []
        var segment = 0
        var previous: Date?
        for snapshot in model.systemMetricsHistory.suffix(61) where snapshot.sampledAt >= end.addingTimeInterval(-120) {
            let value = upload ? snapshot.networkUploadBytesPerSecond : snapshot.networkDownloadBytesPerSecond
            guard let value, value.isFinite, value >= 0 else { segment += 1; previous = nil; continue }
            if let previous, snapshot.sampledAt.timeIntervalSince(previous) > 10 { segment += 1 }
            points.append(HUDTracePoint(time: snapshot.sampledAt.timeIntervalSince1970, value: value, segment: segment))
            previous = snapshot.sampledAt
        }
        return points
    }

    private var networkScope: some View {
        let upload = networkTrace(upload: true)
        let download = networkTrace(upload: false)
        let end = model.systemMetricsHistory.last?.sampledAt.timeIntervalSince1970 ?? 0
        let maximum = max(upload.map(\.value).max() ?? 0, download.map(\.value).max() ?? 0)
        return ZStack {
            HUDTraceShape(points: upload, startTime: end - 120, endTime: end, upperBound: maximum)
                .stroke(HUDStyle.gold.opacity(0.85), lineWidth: 1)
            HUDTraceShape(points: download, startTime: end - 120, endTime: end, upperBound: maximum)
                .stroke(HUDStyle.cyan.opacity(0.95), lineWidth: 1)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(HUDStyle.cyan.opacity(0.16)).frame(height: 0.5) }
    }

    private var primaryValue: String {
        if model.provider == .codex {
            return summary.window.map { $0.remainingPercent > 0 && $0.remainingPercent < 0.5
                ? "<1%" : String(format: "%.0f%%", $0.remainingPercent) } ?? "—"
        }
        if model.provider == .cursor {
            return providerResult.snapshot?.usedPercent.map { String(format: "%.1f%%", $0) } ?? "—"
        }
        return TokenCountFormatter.compact(providerResult.snapshot?.totalTokens)
    }

    private var primaryLabel: String {
        if model.provider == .codex { return L10n.text("Remaining quota") }
        return model.provider == .cursor ? L10n.text("Used allowance") : L10n.text("Local session tokens")
    }

    private var statusText: String {
        if !model.autoRefresh { return L10n.text("Automatic refresh paused") }
        if model.provider == .codex { return summary.title }
        if providerResult.snapshot?.isPartial == true { return L10n.text("Partial coverage") }
        if providerResult.status == .ready { return L10n.text("Reported usage") }
        return L10n.lookup(providerResult.message)
    }

    private var statusSymbol: String {
        model.provider == .codex ? summary.symbolName
            : providerResult.status == .ready ? "checkmark.circle" : "info.circle"
    }

    private var statusWarning: Bool {
        model.provider == .codex
            ? [.low, .exhausted, .cached, .paused].contains(summary.state)
            : providerResult.status != .ready || providerResult.snapshot?.isPartial == true || !model.autoRefresh
    }

    private var orbFraction: Double {
        let value = model.provider == .codex ? summary.window?.remainingPercent
            : providerResult.snapshot?.usedPercent.map { 100 - $0 }
        guard let value, value.isFinite else { return 0 }
        return min(1, max(0, value / 100))
    }

    private var assistantReadouts: [HUDReadout] {
        if model.provider == .codex {
            return [
                quotaReadout("fiveHour", title: L10n.text("5-hour quota"), window: model.quota?.fiveHour, metric: .fiveHour),
                quotaReadout("weekly", title: L10n.text("7-day quota"), window: model.quota?.weekly, metric: .weekly),
                HUDReadout(id: "today", title: L10n.text("Today · this Mac"),
                    value: TokenCountFormatter.compact(model.localDayUsage?.displayTotal(at: model.now)),
                    symbol: "square.stack.3d.up", metric: .todayTokens,
                    warning: model.localDayUsage?.isPartial == true || model.localDayUsage?.isBackfilling == true,
                    note: model.localDayUsage?.isBackfilling == true ? L10n.text("Backfilling today's logs…")
                        : model.localDayUsage?.isPartial == true ? L10n.text("Partial estimate") : nil),
                HUDReadout(id: "tps", title: L10n.text("Latest response"),
                    value: model.sample.map { String(format: "%.1f TPS", $0.tokensPerSecond) } ?? "—",
                    symbol: "bolt", metric: .tps, warning: model.latestUnmeasurable,
                    note: model.latestUnmeasurable ? L10n.text("Last valid response") : nil)
            ]
        }
        let snapshot = providerResult.snapshot
        if model.provider == .cursor {
            return [
                HUDReadout(id: "allowance", title: L10n.text("Used allowance"),
                    value: snapshot?.usedPercent.map { String(format: "%.1f%%", $0) } ?? "—",
                    symbol: "chart.bar", metric: .focus, fraction: snapshot?.usedPercent.map { min(1, max(0, $0 / 100)) }),
                HUDReadout(id: "cost", title: L10n.text("Used allowance (USD)"),
                    value: snapshot?.costUSD.map { $0.formatted(.currency(code: "USD")) } ?? "—",
                    symbol: "dollarsign.circle", metric: .focus),
                HUDReadout(id: "tokens", title: L10n.text("Reported tokens"),
                    value: TokenCountFormatter.compact(snapshot?.totalTokens), symbol: "number", metric: .focus),
                HUDReadout(id: "requests", title: L10n.text("Reported requests"),
                    value: snapshot?.requestCount.map { $0.formatted() } ?? "—", symbol: "arrow.triangle.2.circlepath", metric: .focus)
            ]
        }
        return [
            HUDReadout(id: "tokens", title: L10n.text("Local session tokens"),
                value: TokenCountFormatter.compact(snapshot?.totalTokens), symbol: "number", metric: .focus,
                note: L10n.text("Cumulative · supported sessions")),
            HUDReadout(id: "sessions", title: L10n.text("Sessions"),
                value: snapshot?.sessionCount.map { $0.formatted() } ?? "—", symbol: "square.stack", metric: .focus),
            HUDReadout(id: "decode", title: L10n.text("Average decode speed"),
                value: snapshot?.decodeTokensPerSecond.map { String(format: "%.1f TPS", $0) } ?? "—", symbol: "bolt", metric: .focus),
            HUDReadout(id: "modelTime", title: L10n.text("Cumulative model time"),
                value: snapshot?.modelSeconds.map { String(format: "%.1f s", $0) } ?? "—", symbol: "clock", metric: .focus)
        ]
    }

    private func quotaReadout(_ id: String, title: String, window: QuotaWindow?, metric: MenuBarMetric) -> HUDReadout {
        let remaining = window.flatMap { $0.usedPercent.isFinite ? $0.remainingPercent : nil }
        let value = remaining.map { $0 > 0 && $0 < 0.5 ? "<1%" : String(format: "%.0f%%", $0) } ?? (model.quota == nil ? "—" : "N/A")
        return HUDReadout(id: id, title: title, value: value, symbol: metric == .fiveHour ? "clock" : "calendar",
            metric: metric, fraction: remaining.map { min(1, max(0, $0 / 100)) },
            warning: remaining.map { $0 <= 10 } ?? false)
    }

}

private struct FloatingOrbInput: NSViewRepresentable {
    let onPress: () -> Void
    let onDragStart: () -> Void
    let onDrag: (NSSize) -> Void
    let onDragEnd: () -> Void
    let onOpenWorkspace: () -> Void
    let onOpenSettings: () -> Void
    let onRefresh: () -> Void
    let onHide: () -> Void
    let onMenuTrackingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> FloatingOrbInputView {
        let view = FloatingOrbInputView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: FloatingOrbInputView, context: Context) {
        view.onPress = onPress
        view.onDragStart = onDragStart
        view.onDrag = onDrag
        view.onDragEnd = onDragEnd
        view.onOpenWorkspace = onOpenWorkspace
        view.onOpenSettings = onOpenSettings
        view.onRefresh = onRefresh
        view.onHide = onHide
        view.onMenuTrackingChanged = onMenuTrackingChanged
        view.setAccessibilityLabel(L10n.text("Floating HUD"))
        view.setAccessibilityHelp(L10n.text("Hover to project. Left-click for an energy pulse, right-click for options. Hold and drag to move."))
    }
}

private final class FloatingOrbInputView: NSView {
    var onPress: (() -> Void)?
    var onDragStart: (() -> Void)?
    var onDrag: ((NSSize) -> Void)?
    var onDragEnd: (() -> Void)?
    var onOpenWorkspace: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onHide: (() -> Void)?
    var onMenuTrackingChanged: ((Bool) -> Void)?
    private var mouseOrigin: NSPoint?
    private var dragging = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool { onPress?(); return true }

    override func rightMouseDown(with event: NSEvent) {
        onMenuTrackingChanged?(true)
        defer { onMenuTrackingChanged?(false) }
        let menu = NSMenu(title: L10n.text("Floating HUD"))
        for (title, command) in [(L10n.text("Open workspace"), "workspace"),
                                 (L10n.text("Settings"), "settings"),
                                 (L10n.text("Refresh"), "refresh")] {
            let item = NSMenuItem(title: title, action: #selector(performMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = command
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let hide = NSMenuItem(title: L10n.text("Hide floating HUD"), action: #selector(performMenuAction(_:)), keyEquivalent: "")
        hide.target = self
        hide.representedObject = "hide"
        menu.addItem(hide)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func performMenuAction(_ sender: NSMenuItem) {
        switch sender.representedObject as? String {
        case "workspace": onOpenWorkspace?()
        case "settings": onOpenSettings?()
        case "refresh": onRefresh?()
        case "hide": onHide?()
        default: break
        }
    }

    override func mouseDown(with event: NSEvent) {
        mouseOrigin = NSEvent.mouseLocation
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseOrigin else { return }
        let pointer = NSEvent.mouseLocation
        let offset = NSSize(width: pointer.x - mouseOrigin.x, height: pointer.y - mouseOrigin.y)
        if !dragging, hypot(offset.width, offset.height) >= 3 {
            dragging = true
            onDragStart?()
        }
        if dragging { onDrag?(offset) }
    }

    override func mouseUp(with event: NSEvent) {
        if dragging { onDragEnd?() } else { onPress?() }
        mouseOrigin = nil
        dragging = false
    }
}

struct FloatingHUDOrbView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var presentation: FloatingHUDPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onExpand: () -> Void
    let onDragStart: () -> Void
    let onDrag: (NSSize) -> Void
    let onDragEnd: () -> Void
    let onOpenWorkspace: () -> Void
    let onOpenSettings: () -> Void
    let onRefresh: () -> Void
    let onHide: () -> Void
    let onMenuTrackingChanged: (Bool) -> Void

    private var warning: Bool {
        guard model.provider == .codex else { return !model.autoRefresh }
        let summary = FocusSummary(quota: model.quota, warning: model.quotaWarning,
            automaticRefresh: model.autoRefresh, now: model.now, refreshInterval: model.refreshOptions.quotaInterval)
        return [.low, .exhausted, .cached, .paused].contains(summary.state)
    }

    var body: some View {
        Group {
            if presentation.visible {
                ZStack {
                    HUDAnimatedReactor(animated: !reduceMotion, warning: warning, showsCore: true, impulse: presentation.clickSequence)
                }
                .overlay {
                    FloatingOrbInput(onPress: onExpand, onDragStart: onDragStart,
                        onDrag: onDrag, onDragEnd: onDragEnd,
                        onOpenWorkspace: onOpenWorkspace, onOpenSettings: onOpenSettings,
                        onRefresh: onRefresh, onHide: onHide, onMenuTrackingChanged: onMenuTrackingChanged)
                }
            }
        }
        .frame(width: presentation.layout.orbFrame.width, height: presentation.layout.orbFrame.height)
        .environment(\.locale, L10n.locale)
        .id(model.language)
    }
}

struct FloatingHUDBeamView: View {
    @ObservedObject var presentation: FloatingHUDPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if presentation.visible && presentation.expanded {
                HUDHolographicProjection(layout: presentation.layout, animated: !reduceMotion)
            }
        }
        .frame(width: presentation.layout.screenFrame.width, height: presentation.layout.screenFrame.height)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct HUDHolographicProjection: NSViewRepresentable {
    let layout: FloatingHUDLayout
    let animated: Bool

    func makeNSView(context: Context) -> HUDProjectionLayerView {
        let view = HUDProjectionLayerView()
        view.configure(layout: layout, animated: animated)
        return view
    }

    func updateNSView(_ view: HUDProjectionLayerView, context: Context) {
        view.configure(layout: layout, animated: animated)
    }

    static func dismantleNSView(_ view: HUDProjectionLayerView, coordinator: ()) { view.stopAnimations() }
}

private final class HUDProjectionLayerView: NSView {
    private let staticLight = CALayer()
    private let breathingLight = CALayer()
    private let energyStream = CALayer()
    private var projection: FloatingHUDLayout?
    private var builtProjection: FloatingHUDLayout?
    private var builtBounds = CGRect.zero
    private var animated = false
    private var waveLayers: [CALayer] = []
    private var particles: [(CALayer, CGPath, Double, Double)] = []

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        for group in [staticLight, breathingLight, energyStream] { layer?.addSublayer(group) }
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(layout: FloatingHUDLayout, animated: Bool) {
        let geometryChanged = projection != layout
        let motionChanged = self.animated != animated
        projection = layout
        self.animated = animated
        if geometryChanged { needsLayout = true }
        else if motionChanged { updateMotion() }
    }

    override func layout() {
        super.layout()
        guard let projection, bounds.width > 0, bounds.height > 0,
              builtProjection != projection || builtBounds != bounds else { return }
        stopAnimations()
        builtProjection = projection
        builtBounds = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for group in [staticLight, breathingLight, energyStream] {
            group.frame = bounds
            group.sublayers?.forEach { $0.removeFromSuperlayer() }
        }
        waveLayers.removeAll()
        particles.removeAll()
        let origin = CGPoint(x: projection.beamOrigin.x - projection.screenFrame.minX,
            y: projection.beamOrigin.y - projection.screenFrame.minY)
        let target = CGPoint(x: projection.beamTarget.x - projection.screenFrame.minX,
            y: projection.beamTarget.y - projection.screenFrame.minY)
        let delta = CGPoint(x: target.x - origin.x, y: target.y - origin.y)
        let length = max(1, hypot(delta.x, delta.y))
        let direction = CGPoint(x: delta.x / length, y: delta.y / length)
        let perpendicular = CGPoint(x: -direction.y, y: direction.x)
        let cyan = NSColor(calibratedRed: 0.13, green: 0.90, blue: 0.87, alpha: 1)
        let blue = NSColor(calibratedRed: 0.04, green: 0.35, blue: 0.44, alpha: 1)
        let gold = NSColor(calibratedRed: 0.98, green: 0.79, blue: 0.22, alpha: 1)
        let far = CGPoint(x: origin.x + delta.x * 1.7, y: origin.y + delta.y * 1.7)
        let fanWidth = min(bounds.width, bounds.height) * 0.31
        for (spread, colors, glow) in [
            (fanWidth, [gold.withAlphaComponent(0.32), cyan.withAlphaComponent(0.075), cyan.withAlphaComponent(0.006)], CGFloat(24)),
            (fanWidth * 0.55, [cyan.withAlphaComponent(0.30), cyan.withAlphaComponent(0.10), blue.withAlphaComponent(0.008)], CGFloat(15))
        ] {
            let cone = CGMutablePath()
            cone.move(to: origin)
            cone.addLine(to: CGPoint(x: far.x + perpendicular.x * spread, y: far.y + perpendicular.y * spread))
            cone.addLine(to: CGPoint(x: far.x - perpendicular.x * spread, y: far.y - perpendicular.y * spread))
            cone.closeSubpath()
            addCone(cone, colors: colors, from: origin, to: far, glow: glow)
        }
        let axisPath = CGMutablePath()
        axisPath.move(to: origin)
        axisPath.addLine(to: target)
        addStroke(axisPath, color: gold.withAlphaComponent(0.60), width: 1.2, glow: 7, to: breathingLight)
        for side in [CGFloat(-1), 1] {
            let ray = CGMutablePath()
            ray.move(to: origin)
            ray.addLine(to: CGPoint(x: far.x + perpendicular.x * fanWidth * side,
                y: far.y + perpendicular.y * fanWidth * side))
            addStroke(ray, color: cyan.withAlphaComponent(0.28), width: 0.6, glow: 4, to: staticLight)
        }
        for index in 1...3 {
            let t = CGFloat(index) / 4
            let center = CGPoint(x: origin.x + delta.x * t, y: origin.y + delta.y * t)
            let crossSection = ellipse(center: center, major: 10 + t * 170, minor: 4 + t * 11,
                axis: perpendicular, normal: direction)
            waveLayers.append(addStroke(crossSection, color: cyan.withAlphaComponent(0.18), width: 0.7, glow: 3, to: breathingLight))
        }
        let dashboard = projection.dashboardFrame
        let coreFrame = projection.composition?.coreFrame
        let coreCenter: CGPoint
        let coreRadius: CGFloat
        if let dashboard, let coreFrame {
            coreCenter = CGPoint(x: dashboard.minX + coreFrame.midX - projection.screenFrame.minX,
                y: dashboard.maxY - coreFrame.midY - projection.screenFrame.minY)
            coreRadius = coreFrame.width / 2
        } else {
            coreCenter = target
            coreRadius = 180
        }
        for multiplier in [CGFloat(1.06), 1.16] {
            let circle = CGPath(ellipseIn: CGRect(x: coreCenter.x - coreRadius * multiplier,
                y: coreCenter.y - coreRadius * multiplier, width: coreRadius * multiplier * 2,
                height: coreRadius * multiplier * 2), transform: nil)
            let ring = addStroke(circle, color: cyan.withAlphaComponent(multiplier == 1.06 ? 0.30 : 0.16),
                width: 0.7, glow: 3, to: staticLight)
            if multiplier > 1.1 { ring.lineDashPattern = [2, 7] }
        }
        if let dashboard, let composition = projection.composition {
            for (index, card) in composition.cardFrames.enumerated() {
                let end = CGPoint(x: dashboard.minX + (card.midX < composition.coreFrame.midX ? card.maxX : card.minX) - projection.screenFrame.minX,
                    y: dashboard.maxY - card.midY - projection.screenFrame.minY)
                let vector = CGPoint(x: end.x - coreCenter.x, y: end.y - coreCenter.y)
                let distance = max(1, hypot(vector.x, vector.y))
                let start = CGPoint(x: coreCenter.x + vector.x / distance * coreRadius * 1.04,
                    y: coreCenter.y + vector.y / distance * coreRadius * 1.04)
                let elbow = (start.x + end.x) / 2
                let circuit = CGMutablePath()
                circuit.move(to: start)
                circuit.addLines(between: [CGPoint(x: elbow, y: start.y), CGPoint(x: elbow, y: end.y), end])
                addStroke(circuit, color: cyan.withAlphaComponent(0.50), width: 0.8, glow: 3, to: staticLight)
                addStar(at: start, color: cyan, size: 3)
                addStar(at: end, color: index == 2 ? gold : cyan, size: 3)
                let detail = CGMutablePath()
                for step in 0..<5 {
                    let x = end.x + (end.x < coreCenter.x ? 1 : -1) * CGFloat(step * 4 + 4)
                    detail.move(to: CGPoint(x: x, y: end.y - 4))
                    detail.addLine(to: CGPoint(x: x, y: end.y + 4))
                }
                addStroke(detail, color: cyan.withAlphaComponent(0.25), width: 0.6, glow: 0, to: staticLight)
            }
        }
        for index in 0..<3 {
            let point = CALayer()
            point.bounds = CGRect(x: 0, y: 0, width: 3, height: 3)
            point.cornerRadius = 1.5
            point.backgroundColor = gold.cgColor
            point.shadowColor = gold.cgColor
            point.shadowRadius = 6
            point.shadowOpacity = 0.8
            point.opacity = 0
            energyStream.addSublayer(point)
            particles.append((point, axisPath, Double(index) * 1.1, 3.6))
        }
        CATransaction.commit()
        updateMotion()
    }

    private func addStar(at point: CGPoint, color: NSColor, size: CGFloat) {
        let star = CALayer()
        star.frame = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        star.cornerRadius = size / 2
        star.backgroundColor = color.cgColor
        star.shadowColor = color.cgColor
        star.shadowOpacity = 0.95
        star.shadowRadius = 6
        staticLight.addSublayer(star)
    }

    private func addCone(_ path: CGPath, colors: [NSColor], from origin: CGPoint, to target: CGPoint, glow: CGFloat) {
        let box = path.boundingBoxOfPath.insetBy(dx: -glow * 2, dy: -glow * 2)
        var transform = CGAffineTransform(translationX: -box.minX, y: -box.minY)
        guard let localPath = path.copy(using: &transform) else { return }
        let glowShape = CAShapeLayer()
        glowShape.frame = box
        glowShape.path = localPath
        glowShape.fillColor = colors[1].withAlphaComponent(0.12).cgColor
        glowShape.shadowPath = localPath
        glowShape.shadowColor = colors[0].cgColor
        glowShape.shadowOpacity = 0.9
        glowShape.shadowRadius = glow
        breathingLight.addSublayer(glowShape)
        let gradient = CAGradientLayer()
        gradient.frame = box
        gradient.colors = colors.map(\.cgColor)
        gradient.locations = [0, 0.42, 1]
        gradient.startPoint = CGPoint(x: (origin.x - box.minX) / box.width, y: (origin.y - box.minY) / box.height)
        gradient.endPoint = CGPoint(x: (target.x - box.minX) / box.width, y: (target.y - box.minY) / box.height)
        let mask = CAShapeLayer()
        mask.frame = CGRect(origin: .zero, size: box.size)
        mask.path = localPath
        gradient.mask = mask
        breathingLight.addSublayer(gradient)
    }

    @discardableResult private func addStroke(_ path: CGPath, color: NSColor, width: CGFloat,
                                               glow: CGFloat, to group: CALayer) -> CAShapeLayer {
        let box = path.boundingBoxOfPath.insetBy(dx: -glow * 2 - width, dy: -glow * 2 - width)
        var transform = CGAffineTransform(translationX: -box.minX, y: -box.minY)
        let shape = CAShapeLayer()
        shape.frame = box
        shape.path = path.copy(using: &transform)
        shape.fillColor = nil
        shape.strokeColor = color.cgColor
        shape.lineWidth = width
        shape.lineCap = .round
        shape.shadowPath = shape.path?.copy(strokingWithWidth: width + 1, lineCap: .round, lineJoin: .round, miterLimit: 1)
        shape.shadowColor = color.cgColor
        shape.shadowOpacity = 0.9
        shape.shadowRadius = glow
        group.addSublayer(shape)
        return shape
    }

    private func ellipse(center: CGPoint, major: CGFloat, minor: CGFloat, axis: CGPoint, normal: CGPoint) -> CGPath {
        let path = CGMutablePath()
        for index in 0...96 {
            let angle = CGFloat(index) / 96 * .pi * 2
            let point = CGPoint(x: center.x + axis.x * cos(angle) * major + normal.x * sin(angle) * minor,
                y: center.y + axis.y * cos(angle) * major + normal.y * sin(angle) * minor)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private func updateMotion() {
        stopAnimations()
        guard animated, builtProjection != nil else { return }
        let breath = CABasicAnimation(keyPath: "opacity")
        breath.fromValue = 0.72; breath.toValue = 1
        breath.duration = 5.5; breath.autoreverses = true; breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        breathingLight.add(breath, forKey: "projectionEnergy")
        for (index, ring) in waveLayers.enumerated() {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.65; pulse.toValue = 1
            pulse.duration = 4.8 + Double(index)
            pulse.autoreverses = true; pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ring.add(pulse, forKey: "instrumentLight")
        }
        for entry in particles {
            let travel = CAKeyframeAnimation(keyPath: "position")
            travel.path = entry.1
            travel.calculationMode = .paced
            travel.duration = entry.3
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0, 0.85, 0.85, 0]
            opacity.keyTimes = [0, 0.1, 0.9, 1]
            opacity.duration = entry.3
            let flow = CAAnimationGroup()
            flow.animations = [travel, opacity]
            flow.duration = entry.3
            flow.beginTime = CACurrentMediaTime() + entry.2
            flow.repeatCount = .infinity
            entry.0.add(flow, forKey: "reactorTransfer")
        }
        let reveal = CABasicAnimation(keyPath: "opacity")
        reveal.fromValue = 0; reveal.toValue = 1; reveal.duration = 0.55
        staticLight.add(reveal, forKey: "projectionReveal")
    }

    func stopAnimations() {
        func remove(_ current: CALayer) {
            current.removeAllAnimations()
            current.sublayers?.forEach(remove)
        }
        for group in [staticLight, breathingLight, energyStream] { remove(group) }
    }
}

private struct HUDAnimatedReactor: NSViewRepresentable {
    let animated: Bool
    let warning: Bool
    let showsCore: Bool
    var impulse = 0
    var fraction: Double? = nil

    func makeNSView(context: Context) -> HUDReactorLayerView {
        let view = HUDReactorLayerView()
        view.configure(animated: animated, warning: warning, showsCore: showsCore, impulse: impulse, fraction: fraction)
        return view
    }

    func updateNSView(_ view: HUDReactorLayerView, context: Context) {
        view.configure(animated: animated, warning: warning, showsCore: showsCore, impulse: impulse, fraction: fraction)
    }

    static func dismantleNSView(_ view: HUDReactorLayerView, coordinator: ()) { view.stopAnimations() }
}

private final class HUDReactorLayerView: NSView {
    private let backing = CAShapeLayer()
    private let rotor = CALayer()
    private let innerRotor = CALayer()
    private let coils = CAShapeLayer()
    private let spokes = CAShapeLayer()
    private let nucleus = CAGradientLayer()
    private let gauge = CAShapeLayer()
    private let clickRing = CAShapeLayer()
    private var builtBounds = CGRect.zero
    private var builtCore: Bool?
    private var lastImpulse = 0
    private var animated = false
    private var showsCore = true
    private var warning = false
    private var fraction: Double?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        for child in [backing, coils, rotor, innerRotor, spokes, nucleus, gauge, clickRing] { layer?.addSublayer(child) }
        clickRing.fillColor = nil
        clickRing.opacity = 0
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(animated: Bool, warning: Bool, showsCore: Bool, impulse: Int, fraction: Double?) {
        let motionChanged = self.animated != animated
        let shapeChanged = self.showsCore != showsCore || builtCore == nil
        self.animated = animated
        self.warning = warning
        self.showsCore = showsCore
        self.fraction = fraction
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gauge.strokeEnd = fraction.map { CGFloat(min(1, max(0, $0))) } ?? 0
        gauge.strokeColor = (warning ? NSColor.systemOrange : NSColor(calibratedRed: 0.13, green: 0.90, blue: 0.87, alpha: 1)).cgColor
        CATransaction.commit()
        if shapeChanged { needsLayout = true }
        else if motionChanged { updateMotion() }
        if impulse != lastImpulse {
            lastImpulse = impulse
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 1; opacity.toValue = 0; opacity.duration = 0.6
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.65; scale.toValue = 1.3; scale.duration = 0.6
            let pulse = CAAnimationGroup()
            pulse.animations = animated ? [opacity, scale] : [opacity]
            pulse.duration = 0.6
            clickRing.add(pulse, forKey: "reactorImpulse")
        }
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0,
              builtBounds != bounds || builtCore != showsCore else { return }
        stopAnimations()
        builtBounds = bounds
        builtCore = showsCore
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = max(1, min(bounds.width, bounds.height) / 2 - 2)
        let cyan = NSColor(calibratedRed: 0.13, green: 0.90, blue: 0.87, alpha: 1)
        let gold = NSColor(calibratedRed: 0.98, green: 0.79, blue: 0.22, alpha: 1)
        let white = NSColor(calibratedRed: 0.95, green: 0.99, blue: 1, alpha: 1)
        for child in [backing, coils, rotor, innerRotor, spokes, gauge, clickRing] { child.frame = bounds }
        for group in [rotor, innerRotor] { group.sublayers?.forEach { $0.removeFromSuperlayer() } }
        backing.path = CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2), transform: nil)
        backing.fillColor = NSColor(calibratedRed: 0.006, green: 0.014, blue: 0.020, alpha: 0.99).cgColor
        backing.strokeColor = (showsCore ? gold.withAlphaComponent(0.35) : cyan.withAlphaComponent(0.55)).cgColor
        backing.lineWidth = 1
        coils.fillColor = nil
        coils.strokeColor = (showsCore ? gold : cyan.withAlphaComponent(0.42)).cgColor
        coils.lineWidth = showsCore ? 1 : 0.8
        let ringPath = CGMutablePath()
        for ratio in showsCore ? [0.34, 0.41, 0.48, 0.55] : [0.54, 0.61, 0.73, 0.88, 0.98] {
            let r = radius * ratio
            ringPath.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        }
        coils.path = ringPath
        if showsCore {
            let blades = CGMutablePath()
            for index in 0..<10 {
                let angle = CGFloat(index) / 10 * .pi * 2
                addWedge(to: blades, center: center, inner: radius * 0.79, outer: radius,
                    angle: angle, innerHalf: 0.10, outerHalf: 0.15)
            }
            addMetal(path: blades, to: rotor, colors: [white, NSColor(calibratedRed: 0.57, green: 0.67, blue: 0.69, alpha: 1), white])
            let slots = CGMutablePath()
            for index in 0..<30 {
                addWedge(to: slots, center: center, inner: radius * 0.61, outer: radius * 0.73,
                    angle: CGFloat(index) / 30 * .pi * 2, innerHalf: 0.065, outerHalf: 0.055)
            }
            addMetal(path: slots, to: innerRotor, colors: [white, white.withAlphaComponent(0.85)])
            let wiring = CAShapeLayer()
            wiring.frame = bounds
            let wirePath = CGMutablePath()
            for index in 0..<10 {
                let angle = (CGFloat(index) + 0.5) / 10 * .pi * 2
                for offset in [-0.04, 0, 0.04] {
                    let r = radius * (0.82 + offset)
                    wirePath.move(to: CGPoint(x: center.x + cos(angle - 0.10) * r, y: center.y + sin(angle - 0.10) * r))
                    wirePath.addArc(center: center, radius: r, startAngle: angle - 0.10, endAngle: angle + 0.10, clockwise: false)
                }
            }
            wiring.path = wirePath
            wiring.fillColor = nil
            wiring.strokeColor = NSColor(calibratedRed: 0.83, green: 0.06, blue: 0.035, alpha: 0.9).cgColor
            wiring.lineWidth = 0.55
            rotor.addSublayer(wiring)
            let spokePath = CGMutablePath()
            for index in 0..<3 {
                addWedge(to: spokePath, center: center, inner: radius * 0.29, outer: radius * 0.88,
                    angle: CGFloat(index) / 3 * .pi * 2 + .pi / 2, innerHalf: 0.14, outerHalf: 0.055)
            }
            spokes.path = spokePath
            spokes.fillColor = NSColor.black.cgColor
            spokes.strokeColor = NSColor.black.cgColor
            spokes.lineWidth = 1
        } else {
            let ticks = CGMutablePath()
            for index in 0..<120 {
                let angle = CGFloat(index) / 120 * .pi * 2
                let inside = radius * (index.isMultiple(of: 5) ? 0.89 : 0.93)
                ticks.move(to: CGPoint(x: center.x + cos(angle) * inside, y: center.y + sin(angle) * inside))
                ticks.addLine(to: CGPoint(x: center.x + cos(angle) * radius * 0.97, y: center.y + sin(angle) * radius * 0.97))
            }
            addLine(path: ticks, to: innerRotor, color: cyan.withAlphaComponent(0.65), width: 1)
            let segments = CGMutablePath()
            for index in 0..<36 {
                let start = CGFloat(index) / 36 * .pi * 2
                let end = start + .pi / 36 * 1.3
                segments.move(to: CGPoint(x: center.x + cos(start) * radius * 0.84, y: center.y + sin(start) * radius * 0.84))
                segments.addArc(center: center, radius: radius * 0.84, startAngle: start, endAngle: end, clockwise: false)
            }
            addLine(path: segments, to: rotor, color: cyan.withAlphaComponent(0.75), width: radius * 0.035)
            let crosshair = CGMutablePath()
            for index in 0..<4 {
                let angle = CGFloat(index) / 4 * .pi * 2
                crosshair.move(to: CGPoint(x: center.x + cos(angle) * radius * 0.47, y: center.y + sin(angle) * radius * 0.47))
                crosshair.addLine(to: CGPoint(x: center.x + cos(angle) * radius * 0.64, y: center.y + sin(angle) * radius * 0.64))
            }
            spokes.path = crosshair
            spokes.fillColor = nil
            spokes.strokeColor = cyan.withAlphaComponent(0.3).cgColor
            spokes.lineWidth = 1
        }
        let coreRadius = radius * (showsCore ? 0.29 : 0.48)
        nucleus.frame = CGRect(x: center.x - coreRadius, y: center.y - coreRadius, width: coreRadius * 2, height: coreRadius * 2)
        nucleus.type = .radial
        nucleus.colors = showsCore ? [white.cgColor, white.cgColor, gold.withAlphaComponent(0.68).cgColor]
            : [NSColor(calibratedRed: 0.015, green: 0.07, blue: 0.09, alpha: 1).cgColor, NSColor.black.cgColor]
        nucleus.startPoint = CGPoint(x: 0.5, y: 0.5)
        nucleus.endPoint = CGPoint(x: 1, y: 1)
        let coreMask = CAShapeLayer()
        coreMask.frame = CGRect(origin: .zero, size: nucleus.frame.size)
        coreMask.path = CGPath(ellipseIn: coreMask.frame, transform: nil)
        nucleus.mask = coreMask
        nucleus.shadowColor = (showsCore ? gold : cyan).cgColor
        nucleus.shadowOpacity = showsCore ? 0.9 : 0.3
        nucleus.shadowRadius = showsCore ? 8 : 10
        gauge.path = CGPath(ellipseIn: CGRect(x: center.x - radius * 0.68, y: center.y - radius * 0.68,
            width: radius * 1.36, height: radius * 1.36), transform: nil)
        gauge.fillColor = nil
        gauge.lineWidth = max(2, radius * 0.026)
        gauge.strokeColor = (warning ? NSColor.systemOrange : cyan).cgColor
        gauge.strokeStart = 0
        gauge.strokeEnd = fraction.map { CGFloat(min(1, max(0, $0))) } ?? 0
        gauge.transform = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
        gauge.isHidden = showsCore
        clickRing.path = CGPath(ellipseIn: CGRect(x: center.x - radius * 0.73, y: center.y - radius * 0.73,
            width: radius * 1.46, height: radius * 1.46), transform: nil)
        clickRing.strokeColor = gold.cgColor
        clickRing.lineWidth = 2
        clickRing.shadowColor = white.cgColor
        clickRing.shadowOpacity = 0.8
        clickRing.shadowRadius = 6
        CATransaction.commit()
        updateMotion()
    }

    private func addWedge(to path: CGMutablePath, center: CGPoint, inner: CGFloat, outer: CGFloat,
                          angle: CGFloat, innerHalf: CGFloat, outerHalf: CGFloat) {
        path.move(to: CGPoint(x: center.x + cos(angle - innerHalf) * inner, y: center.y + sin(angle - innerHalf) * inner))
        path.addLine(to: CGPoint(x: center.x + cos(angle - outerHalf) * outer, y: center.y + sin(angle - outerHalf) * outer))
        path.addLine(to: CGPoint(x: center.x + cos(angle + outerHalf) * outer, y: center.y + sin(angle + outerHalf) * outer))
        path.addLine(to: CGPoint(x: center.x + cos(angle + innerHalf) * inner, y: center.y + sin(angle + innerHalf) * inner))
        path.closeSubpath()
    }

    private func addMetal(path: CGPath, to group: CALayer, colors: [NSColor]) {
        let metal = CAGradientLayer()
        metal.frame = bounds
        metal.colors = colors.map(\.cgColor)
        metal.startPoint = CGPoint(x: 0, y: 1)
        metal.endPoint = CGPoint(x: 1, y: 0)
        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.path = path
        mask.fillColor = NSColor.black.cgColor
        metal.mask = mask
        group.addSublayer(metal)
    }

    private func addLine(path: CGPath, to group: CALayer, color: NSColor, width: CGFloat) {
        let line = CAShapeLayer()
        line.frame = bounds
        line.path = path
        line.fillColor = nil
        line.strokeColor = color.cgColor
        line.lineWidth = width
        group.addSublayer(line)
    }

    private func updateMotion() {
        stopAnimations()
        guard animated, builtCore != nil else { return }
        for (index, group) in [rotor, innerRotor].enumerated() {
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0
            rotation.toValue = (index == 0 ? 1 : -1) * Double.pi * 2
            rotation.duration = showsCore ? (index == 0 ? 26 : 17) : (index == 0 ? 48 : 36)
            rotation.repeatCount = .infinity
            group.add(rotation, forKey: "mechanicalCounterRotation")
        }
        if showsCore {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.80; pulse.toValue = 1
            pulse.duration = 2.8; pulse.autoreverses = true; pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            nucleus.add(pulse, forKey: "hotCorePulse")
        }
    }

    func stopAnimations() {
        func remove(_ child: CALayer) {
            child.removeAllAnimations()
            child.sublayers?.forEach(remove)
        }
        for child in [backing, coils, rotor, innerRotor, spokes, nucleus, gauge, clickRing] { remove(child) }
    }
}

private struct HUDTracePoint {
    let time: Double
    let value: Double
    let segment: Int
}

private struct HUDTraceShape: Shape {
    let points: [HUDTracePoint]
    let startTime: Double
    let endTime: Double
    let upperBound: Double

    func path(in rect: CGRect) -> Path {
        func position(_ point: HUDTracePoint) -> CGPoint {
            let x = endTime > startTime ? (point.time - startTime) / (endTime - startTime) : 0.5
            return CGPoint(x: rect.minX + min(1, max(0, x)) * rect.width,
                y: rect.maxY - min(1, max(0, point.value / max(1, upperBound))) * rect.height)
        }
        return Path { path in
            var previous: HUDTracePoint?
            for point in points {
                let current = position(point)
                if previous?.segment == point.segment { path.addLine(to: current) }
                else { path.move(to: current) }
                previous = point
            }
            for point in points {
                let current = position(point)
                path.addEllipse(in: CGRect(x: current.x - 0.8, y: current.y - 0.8, width: 1.6, height: 1.6))
            }
        }
    }
}

private struct HUDGaugeTicks: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let radius = min(rect.width, rect.height) / 2
            for index in 0..<36 {
                let angle = CGFloat(index) / 36 * .pi * 2
                let inner = radius * (index.isMultiple(of: 3) ? 0.82 : 0.91)
                path.move(to: CGPoint(x: rect.midX + cos(angle) * inner, y: rect.midY + sin(angle) * inner))
                path.addLine(to: CGPoint(x: rect.midX + cos(angle) * radius, y: rect.midY + sin(angle) * radius))
            }
        }
    }
}

private struct HUDPanelMarkings: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let inset: CGFloat = 7
            let corner: CGFloat = 20
            for flipX in [false, true] {
                for flipY in [false, true] {
                    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                        CGPoint(x: flipX ? rect.maxX - x : rect.minX + x,
                            y: flipY ? rect.maxY - y : rect.minY + y)
                    }
                    path.move(to: point(inset, corner + 10))
                    path.addLine(to: point(inset, corner))
                    path.addLine(to: point(corner, inset))
                    path.addLine(to: point(corner + 15, inset))
                }
            }
            path.move(to: CGPoint(x: 14, y: 34))
            path.addLine(to: CGPoint(x: rect.width * 0.64, y: 34))
            path.addLine(to: CGPoint(x: rect.width * 0.64 + 5, y: 29))
        }
    }
}
