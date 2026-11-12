import ProjectionMotionKit
import PlaygroundLocalization
import SwiftUI

@MainActor
private final class HUDInspectorOptions: ObservableObject {
    @Published var pane = "Layout"
    @Published var simulatedModule = HUDModule.performance
    var rapidTask: Task<Void, Never>?
    deinit { rapidTask?.cancel() }
}

struct HUDDebugControls: View {
    let projection: ProjectionAnimationController
    @ObservedObject var dashboard: HUDDashboardController
    @Environment(\.playgroundLanguage) private var language
    @Environment(\.openWindow) private var openWindow
    @StateObject private var options = HUDInspectorOptions()
    private var pane: String { options.pane }
    private var simulatedModule: HUDModule { options.simulatedModule }
    private var rapidTask: Task<Void, Never>? {
        get { options.rapidTask }
        nonmutating set { options.rapidTask = newValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Button(language.text("Open HUD inspection")) { openWindow(id: "hud-inspection") }
                .frame(maxWidth: .infinity)
            Picker(language.text("HUD inspector"), selection: $options.pane) {
                ForEach(["Layout", "Style", "Interaction", "Dynamics"], id: \.self) { Text(language.text($0)).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            if pane == "Layout" {
                Picker(language.text("Visual density"), selection: $dashboard.config.density) {
                    ForEach(HUDDensity.allCases, id: \.self) { Text(language.text($0.title)).tag($0) }
                }
                ForEach(HUDModule.allCases, id: \.self) { module in
                    Toggle(language.text(module.title), isOn: Binding(get: {
                        dashboard.config.enabledModules.contains(module)
                    }, set: { value in
                        if value { dashboard.config.enabledModules.insert(module) }
                        else { dashboard.config.enabledModules.remove(module) }
                    }))
                }
                metric("Core diameter", value: $dashboard.config.coreDiameter, in: 240...340, step: 1)
                metric("Module size", value: $dashboard.config.moduleScale, in: 0.85...1.15)
                metric("Module spacing", value: $dashboard.config.spacing, in: 12...48, step: 1)
                Picker(language.text("Arrangement"), selection: $dashboard.config.layoutVariant) {
                    Text(language.text("Balanced")).tag(0)
                    Text(language.text("Mirrored")).tag(1)
                }
            } else if pane == "Style" {
                metric("Primary hue", value: $dashboard.config.hue, in: 0...1)
                metric("Glass opacity", value: $dashboard.config.glassOpacity, in: 0.25...0.95)
                metric("Border brightness", value: $dashboard.config.borderBrightness, in: 0.2...1)
                metric("Glow intensity", value: $dashboard.config.glow, in: 0...1)
                metric("Connection intensity", value: $dashboard.config.connectorIntensity, in: 0...1)
                metric("Decoration density", value: $dashboard.config.decorationDensity, in: 0...1)
                metric("Text size", value: $dashboard.config.textScale, in: 0.9...1.2)
            } else if pane == "Interaction" {
                Picker(language.text("Target module"), selection: $options.simulatedModule) {
                    ForEach(HUDModule.allCases, id: \.self) { Text(language.text($0.title)).tag($0) }
                }
                Toggle(language.text("Disable target module"), isOn: Binding(get: {
                    dashboard.config.disabledModules.contains(simulatedModule)
                }, set: { value in
                    if value { dashboard.config.disabledModules.insert(simulatedModule) }
                    else { dashboard.config.disabledModules.remove(simulatedModule) }
                }))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                    Button(language.text("Idle")) { dashboard.overview(); projection.reset() }
                    Button(language.text("Previewing")) { projection.expand(); dashboard.overview() }
                    Button(language.text("Hover")) { projection.expand(); dashboard.hover(simulatedModule) }
                    Button(language.text("Selected")) { projection.expand(); dashboard.select(simulatedModule) }
                    Button(language.text("Expanded")) { projection.expand(); dashboard.select(simulatedModule); dashboard.expandSelection() }
                    Button(language.text("Closing")) { projection.retract() }
                }.controlSize(.small)
                Button(language.text("Back to overview")) { dashboard.overview() }
                metric("Exit delay", value: $dashboard.config.exitDelay, in: 0.15...1)
                metric("Transit grace", value: $dashboard.config.transitGrace, in: 0.4...2)
                Text(language.text("AI and Activity use an isolated Mock provider. System, CPU, memory and network use local native counters."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Toggle(language.text("Decorative motion"), isOn: Binding(get: {
                    dashboard.config.decorativeMotion
                }, set: { dashboard.setDecorativeMotion($0) }))
                metric("Clockwise rotation", value: $dashboard.config.clockwiseSpeed, in: 0...8)
                metric("Counter rotation", value: $dashboard.config.counterclockwiseSpeed, in: -8...0)
                metric("Scan speed", value: $dashboard.config.scanSpeed, in: 0...40)
                metric("Feedback duration", value: $dashboard.config.feedbackDuration, in: 0.15...0.5)
                metric("Feedback damping", value: $dashboard.config.feedbackDamping, in: 0.8...1.2)
                metric("Pulse amplitude", value: $dashboard.config.pulseAmplitude, in: 0...0.25)
                Button(language.text("Preview module transition")) {
                    dashboard.overview()
                    dashboard.select(simulatedModule)
                    dashboard.expandSelection()
                }
                Button(language.text("Rapid entry / reversal test")) {
                    rapidTask?.cancel()
                    rapidTask = Task { @MainActor in
                        for _ in 0..<4 {
                            projection.expand()
                            try? await Task.sleep(for: .milliseconds(180))
                            guard !Task.isCancelled else { return }
                            projection.retract()
                            try? await Task.sleep(for: .milliseconds(120))
                            guard !Task.isCancelled else { return }
                        }
                        projection.expand()
                    }
                }
                Text(language.text("The global playhead controls every generated border, connector, chart and label in both directions."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .toggleStyle(.checkbox)
        .onDisappear { rapidTask?.cancel(); rapidTask = nil }
    }

    private func metric(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double = 0.01) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(language.text(title))
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(step == 1 ? 0 : 2)))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step) { Text(language.text(title)) }.labelsHidden()
        }
    }
}

struct HUDInspectionWindow: View {
    let projection: ProjectionAnimationController
    let desktop: ProjectionDesktopController
    @ObservedObject var dashboard: HUDDashboardController
    @Environment(\.playgroundLanguage) private var language
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(language.text("JARVIS HUD · Native instrument study")).font(.system(size: 12, weight: .medium))
                Spacer()
                Button(language.text("Back to overview")) { dashboard.overview() }
                Button(language.text(dashboard.config.decorativeMotion ? "Pause decoration" : "Resume decoration")) {
                    dashboard.setDecorativeMotion(!dashboard.config.decorativeMotion)
                }
                Button(language.text("Expand")) { projection.expand() }
                Button(language.text("Retract")) { projection.retract() }
            }.padding(12).controlSize(.small)
            ProjectionStage(controller: projection)
                .background(Color(red: 0.018, green: 0.035, blue: 0.052))
        }.frame(minWidth: 900, minHeight: 630)
            .background(Color(nsColor: .windowBackgroundColor))
            .background(HUDInspectionLifecycle(projection: projection, desktop: desktop).frame(width: 0, height: 0))
            .onAppear { desktop.setInspectionActive(true); projection.start() }
            .onDisappear { projection.suspend(false); desktop.setInspectionActive(false) }
    }
}

private struct HUDInspectionLifecycle: NSViewRepresentable {
    let projection: ProjectionAnimationController
    let desktop: ProjectionDesktopController
    func makeNSView(context: Context) -> ObservationView {
        ObservationView(projection: projection, desktop: desktop)
    }
    func updateNSView(_ view: ObservationView, context: Context) {}
    @MainActor final class ObservationView: NSView {
        let projection: ProjectionAnimationController
        let desktop: ProjectionDesktopController
        private var observations: [NSObjectProtocol] = []
        init(projection: ProjectionAnimationController, desktop: ProjectionDesktopController) {
            self.projection = projection; self.desktop = desktop
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observations.forEach(NotificationCenter.default.removeObserver)
            observations.removeAll()
            guard let window else { return }
            for (name, suspended) in [(NSWindow.didMiniaturizeNotification, true), (NSWindow.didDeminiaturizeNotification, false)] {
                observations.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.projection.suspend(suspended)
                })
            }
        }
        deinit { observations.forEach(NotificationCenter.default.removeObserver) }
    }
}
