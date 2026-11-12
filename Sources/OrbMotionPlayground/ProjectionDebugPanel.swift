import AppKit
import Combine
import OrbMotionKit
import ProjectionMotionKit
import PlaygroundLocalization
import SwiftUI

@MainActor
private final class ProjectionDebugOptions: ObservableObject {
    @Published var config: ProjectionConfig
    @Published var backdropConfig: ProjectionBackdropConfiguration
    @Published var pane = "Beam"
    @Published var reduceMotion = false
    private var subscription: AnyCancellable?
    private var backdropSubscription: AnyCancellable?
    init(controller: ProjectionAnimationController, pane: String? = nil) {
        config = controller.config
        backdropConfig = controller.backdropConfig
        if CommandLine.arguments.contains("--hud-demo") { self.pane = "HUD" }
        if let pane { self.pane = pane }
        subscription = controller.$config.removeDuplicates().sink { [weak self] in self?.config = $0 }
        backdropSubscription = controller.$backdropConfig.removeDuplicates().sink { [weak self] in self?.backdropConfig = $0 }
    }
}

struct ProjectionDebugPanel: View {
    let controller: ProjectionAnimationController
    @ObservedObject var desktop: ProjectionDesktopController
    @StateObject private var options: ProjectionDebugOptions
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.playgroundLanguage) private var language
    @Environment(\.playgroundSnapshot) private var isSnapshot

    init(controller: ProjectionAnimationController, desktop: ProjectionDesktopController, snapshotPane: String? = nil) {
        self.controller = controller; self.desktop = desktop
        _options = StateObject(wrappedValue: ProjectionDebugOptions(controller: controller, pane: snapshotPane))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.text("Projection Playground")).font(.system(size: 17, weight: .semibold))
                    Text(language.text("ORB → BEAM → FOCAL POINT → HUD"))
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(language.text("Defaults")) {
                    options.config = ProjectionConfig()
                    options.backdropConfig = ProjectionBackdropConfiguration()
                    controller.reset()
                }
                    .controlSize(.small).help(language.text("Restore projection parameters; preserve the approved orb"))
            }
            HStack {
                Toggle(language.text("Desktop projection"), isOn: Binding(get: { desktop.enabled }, set: { desktop.setEnabled($0) }))
                Spacer()
                if desktop.enabled {
                    Button(language.text("Hide window")) { Self.window?.orderOut(nil) }
                        .help(language.text("Keep the edge orb running. Reopen the app from the Dock to restore this window."))
                }
            }.font(.system(size: 12)).controlSize(.small)
            if desktop.enabled {
                Text(language.format("Hover the %@ screen-edge orb, then move into a HUD module to interact.", language.text(options.config.edge.title).lowercased()))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(language.format("Window state · Source %@ · HUD %@ · %@", language.text(desktop.sourceVisible ? "on" : "off"), language.text(desktop.projectionVisible ? "on" : "off"), language.text(desktop.onActiveSpace ? "active Space" : "other Space")))
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                    .help(language.text("Reads the app windows' actual visibility and Space state; does not measure occlusion or click-through."))
            } else if desktop.inspectionActive {
                Text(language.text("HUD is open in the inspection window."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ProjectionStage(controller: controller).frame(height: 228)
                    .background(Color(red: 0.02, green: 0.04, blue: 0.06))
                    .clipShape(.rect(cornerRadius: 8))
                    .accessibilityLabel(language.text("Interactive projection stage"))
            }
            HStack {
                Picker(language.text("Dock edge"), selection: $options.config.edge) {
                    ForEach(ProjectionEdge.allCases, id: \.self) { Text(language.text($0.title)).tag($0) }
                }.pickerStyle(.segmented).frame(width: 190)
                Picker(language.text("Display"), selection: Binding(get: { desktop.selectedDisplay }, set: { desktop.selectDisplay($0) })) {
                    Text(language.text("Current display")).tag("auto")
                    ForEach(desktop.displays) { Text($0.name).tag($0.id) }
                }.labelsHidden()
            }
            Divider()
            ProjectionTransport(controller: controller)
            Divider()
            Picker(language.text("Projection parameters"), selection: $options.pane) {
                Text(language.text("Beam")).tag("Beam")
                Text(language.text("HUD")).tag("HUD")
                Text(language.text("Backdrop")).tag("Backdrop")
                Text(language.text("Timing")).tag("Timing")
            }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                VStack(spacing: 13) {
                    if options.pane == "Beam" {
                        parameter("Volume length", value: $options.config.beamLength, range: 0.4...1, unit: "%", multiplier: 100)
                        Text(language.text("The fine connecting ray remains locked to the HUD center."))
                            .font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        parameter("Beam width", value: $options.config.beamWidth, range: 20...180, unit: "pt", step: 1)
                        parameter("Divergence", value: $options.config.divergence, range: 0...16, unit: "°", step: 1)
                        parameter("Brightness", value: $options.config.brightness, range: 0.1...1.2, unit: "%", multiplier: 100)
                        parameter("Edge glow", value: $options.config.edgeGlow, range: 0...1, unit: "%", multiplier: 100)
                        integer("Particle density", value: $options.config.particleCount, range: 0...24)
                        parameter("Particle speed", value: $options.config.particleSpeed, range: 0.1...2, unit: "×")
                        parameter("Scan lines", value: $options.config.scanVisibility, range: 0...1, unit: "%", multiplier: 100)
                        integer("Volume layers", value: $options.config.beamLayers, range: 1...5)
                    } else if options.pane == "HUD" {
                        HUDDebugControls(projection: controller, dashboard: controller.hud)
                    } else if options.pane == "Backdrop" {
                        ProjectionBackdropControls(configuration: $options.backdropConfig)
                    } else {
                        parameter("Expand duration", value: $options.config.openDuration, range: 0.8...3, unit: "ms", multiplier: 1000)
                        parameter("Retract duration", value: $options.config.closeDuration, range: 0.8...3, unit: "ms", multiplier: 1000)
                        parameter("Source height", value: $options.config.verticalPosition, range: 0.1...0.9, unit: "%", multiplier: 100)
                        Toggle(language.text("Preview Reduce Motion"), isOn: $options.reduceMotion).font(.system(size: 12))
                        Text(language.text(systemReduceMotion ? "System Reduce Motion is enabled." : "Stops ambient loops, particles and radar; keeps brief state feedback."))
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Text(language.text("A  0–15%   Source activation\nB  15–35%  Beam launch\nC  35–45%  Focal point\nD  45–65%  Core rings\nE  65–85%  Peripheral structures\nF  85–100% Steady projection"))
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }
                }.padding(.trailing, 4).padding(.bottom, 8)
            }
            Text(language.text("Native local metrics · AI / Activity marked Mock"))
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            guard !isSnapshot else { return }
            desktop.start()
            controller.setReduceMotion(systemReduceMotion || options.reduceMotion)
            positionWindow()
        }
        .onDisappear { if !isSnapshot { desktop.stop() } }
        .onChange(of: options.config) { _, value in
            if controller.config != value { controller.config = value }
        }
        .onChange(of: options.config.edge) { _, _ in positionWindow() }
        .onChange(of: options.backdropConfig) { _, value in
            if controller.backdropConfig != value { controller.backdropConfig = value }
        }
        .onChange(of: options.reduceMotion) { _, value in controller.setReduceMotion(value || systemReduceMotion) }
        .onChange(of: systemReduceMotion) { _, value in controller.setReduceMotion(value || options.reduceMotion) }
    }

    private static var window: NSWindow? {
        PlaygroundWindow.main
    }
    private func positionWindow() {
        DispatchQueue.main.async {
            guard let window = Self.window, let screen = window.screen ?? NSScreen.main else { return }
            window.title = language.text("Projection Playground")
            window.identifier = PlaygroundWindow.identifier
            window.setContentSize(NSSize(width: 440, height: min(820, screen.visibleFrame.height - 64)))
            let bounds = screen.visibleFrame
            let x = options.config.edge == .left ? bounds.maxX - window.frame.width - 18 : bounds.minX + 18
            window.setFrameOrigin(CGPoint(x: x, y: bounds.maxY - window.frame.height - 18))
        }
    }
    private func integer(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, step: Double = 1) -> some View {
        parameter(label, value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) }),
                  range: Double(range.lowerBound)...Double(range.upperBound), unit: "", step: step)
    }
    private func parameter(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                           unit: String, multiplier: Double = 1, step: Double = 0.01) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(language.text(title))
                Spacer()
                Text("\(value.wrappedValue * multiplier, specifier: multiplier == 1 && step < 1 ? "%.2f" : "%.0f") \(language.text(unit))")
                    .monospacedDigit().foregroundStyle(.secondary)
            }.font(.system(size: 12))
            Slider(value: value, in: range, step: step) { Text(language.text(title)) }.labelsHidden()
        }
    }
}

@MainActor
private final class ProjectionInspectorState: ObservableObject {
    @Published var timeline: ProjectionTimeline
    @Published var reducedMotion = false
    @Published var simulatedHover = false
    @Published var lastAction = "Started"
    private let controller: ProjectionAnimationController
    private var subscriptions = Set<AnyCancellable>()
    init(_ controller: ProjectionAnimationController) {
        self.controller = controller; timeline = controller.timeline
        controller.$timeline.removeDuplicates { a, b in
            a.progress == b.progress && a.direction == b.direction && a.isPlaying == b.isPlaying &&
            a.isLooping == b.isLooping && a.playbackRate == b.playbackRate
        }.throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] in self?.timeline = $0 }.store(in: &subscriptions)
        controller.$reduceMotion.sink { [weak self] in self?.reducedMotion = $0 }.store(in: &subscriptions)
        controller.$simulatedHover.sink { [weak self] in self?.simulatedHover = $0 }.store(in: &subscriptions)
        controller.$lastAction.sink { [weak self] in self?.lastAction = $0 }.store(in: &subscriptions)
    }
    func command(_ action: () -> Void) { action(); timeline = controller.timeline }
}

private struct ProjectionTransport: View {
    let controller: ProjectionAnimationController
    @StateObject private var state: ProjectionInspectorState
    @Environment(\.playgroundLanguage) private var language
    init(controller: ProjectionAnimationController) {
        self.controller = controller; _state = StateObject(wrappedValue: ProjectionInspectorState(controller))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(language.text(state.timeline.sample.phaseTitle)).font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(state.timeline.progress * 100, specifier: "%.1f")%")
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
            }
            Slider(value: Binding(get: { state.timeline.progress }, set: { value in
                state.command { controller.scrub(to: value) }
            }), in: 0...1) { Text(language.text("Projection progress")) }.labelsHidden()
            HStack {
                Text(language.text("0 · Standby"))
                Spacer()
                Text(language.text(state.timeline.stateTitle))
                Spacer()
                Text(language.text("100 · Projected"))
            }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button(language.text(state.timeline.isPlaying ? "Pause" : "Play")) {
                    state.command { controller.timeline.isPlaying ? controller.pause() : controller.play() }
                }
                Button(language.text("Reset")) { state.command { controller.reset() } }
                Spacer()
                Button(language.text("Retract")) { state.command { controller.retract() } }
                Button(language.text("Expand")) { state.command { controller.expand() } }.buttonStyle(.borderedProminent)
            }.controlSize(.small)
            HStack {
                Toggle(language.text("Loop"), isOn: Binding(get: { state.timeline.isLooping }, set: { value in
                    state.command { controller.loop(value) }
                })).disabled(state.reducedMotion)
                Toggle(language.text("Simulate Hover"), isOn: Binding(get: { state.simulatedHover }, set: { value in
                    state.command { controller.simulateHover(value) }
                }))
                Spacer()
                Picker(language.text("Projection speed"), selection: Binding(get: { state.timeline.playbackRate }, set: { value in
                    state.command { controller.speed(value) }
                })) {
                    ForEach([0.25, 0.5, 1.0, 2.0], id: \.self) { Text("\($0, specifier: "%g")×").tag($0) }
                }.labelsHidden().frame(width: 88)
            }.font(.system(size: 11)).toggleStyle(.checkbox)
            Text(language.format("Last input · %@", language.text(state.lastAction))).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
        }
    }
}
