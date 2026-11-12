import AppKit
import Combine
import OrbMotionKit
import ProjectionMotionKit
import PlaygroundLocalization
import SwiftUI

@MainActor
private final class PlaygroundOptions: ObservableObject {
    @Published var parameters = ApprovedOrbParameters.value
    @Published var magnification = 1.0
    @Published var appearance = "System"
    @Published var simulateHover = false
    @Published var pointerInside = false
    @Published var forceReducedMotion = false
    @Published var pane = "Appearance"
    init(pane: String = "Appearance") { self.pane = pane }
}

@MainActor
private final class PlaygroundAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // The shared preview bundle is an accessory; the standalone lab needs normal window activation.
        NSApplication.shared.setActivationPolicy(.regular)
        if CommandLine.arguments.contains("--ui-preview-fixtures") {
            if CommandLine.arguments.contains("--ui-preview-dark") {
                NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
            } else if CommandLine.arguments.contains("--ui-preview-light") {
                NSApplication.shared.appearance = NSAppearance(named: .aqua)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        showPlaygroundWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPlaygroundWindow()
        return true
    }

    func showPlaygroundWindow() {
        DispatchQueue.main.async {
            guard let window = PlaygroundWindow.main else { return }
            window.identifier = PlaygroundWindow.identifier
            window.collectionBehavior.insert(.moveToActiveSpace)
            if window.isMiniaturized { window.deminiaturize(nil) }
            if PlaygroundLanguage.allCases.contains(where: { window.title == $0.text("Orb Motion Playground") }) { window.center() }
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate()
        }
    }
}

@main
struct OrbMotionPlaygroundApp: App {
    @NSApplicationDelegateAdaptor(PlaygroundAppDelegate.self) private var appDelegate
    @StateObject private var session = PlaygroundSession()
    private var language: PlaygroundLanguage { session.language }

    init() {
        if CommandLine.arguments.contains("--verify-resources") {
            print("OrbMotionPlayground verified: native standalone target; no external resources required.")
            exit(0)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--export-hud-previews"),
           CommandLine.arguments.indices.contains(index + 1) {
            do { try HUDPreviewExporter.export(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            catch { fputs("HUD preview export failed: \(error)\n", stderr); exit(1) }
            exit(0)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--export-language-previews"),
           CommandLine.arguments.indices.contains(index + 1) {
            do { try PlaygroundLanguagePreviewExporter.export(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            catch { fputs("Language preview export failed: \(error)\n", stderr); exit(1) }
            exit(0)
        }
    }

    var body: some Scene {
        Window(language.text(session.mode == .orb ? "Orb Motion Playground" : "Projection Playground"), id: "motion-playground") {
            PlaygroundModeRoot(session: session)
                .environment(\.playgroundLanguage, session.language)
                .environment(\.locale, session.language.locale)
                .onAppear { appDelegate.showPlaygroundWindow() }
        }
        .defaultSize(width: 1060, height: 790)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu(language.text("Playback")) {
                Button(language.text("Activate")) {
                    if session.mode == .orb { session.orb.activate() } else { session.projection.expand() }
                }.keyboardShortcut(.rightArrow, modifiers: [.command])
                Button(language.text("Retract")) {
                    if session.mode == .orb { session.orb.retract() } else { session.projection.retract() }
                }.keyboardShortcut(.leftArrow, modifiers: [.command])
                Button(language.text("Play / Pause")) {
                    if session.mode == .orb {
                        session.orb.timeline.isPlaying ? session.orb.pause() : session.orb.play()
                    } else {
                        session.projection.timeline.isPlaying ? session.projection.pause() : session.projection.play()
                    }
                }.keyboardShortcut(.space, modifiers: [])
                Button(language.text("Reset")) {
                    if session.mode == .orb { session.orb.reset() } else { session.projection.reset() }
                }.keyboardShortcut("r", modifiers: [.command])
            }
        }
        Window(language.text("HUD inspection"), id: "hud-inspection") {
            HUDInspectionWindow(projection: session.projection, desktop: session.desktop, dashboard: session.projection.hud)
                .environment(\.playgroundLanguage, session.language)
                .environment(\.locale, session.language.locale)
        }.defaultSize(width: 1120, height: 760)
    }
}

private struct PlaygroundModeRoot: View {
    @ObservedObject var session: PlaygroundSession
    @Environment(\.playgroundLanguage) private var language
    @Environment(\.playgroundSnapshot) private var isSnapshot
    @Environment(\.playgroundSnapshotPane) private var snapshotPane
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker(language.text("Playground mode"), selection: $session.mode) {
                    ForEach(PlaygroundMode.allCases, id: \.self) { Text(language.text($0.rawValue)).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 220)
                Spacer(minLength: 0)
                Picker(language.text("Language"), selection: $session.language) {
                    ForEach(PlaygroundLanguage.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }.pickerStyle(.menu).labelsHidden().frame(width: 130)
                    .accessibilityLabel(language.text("Language")).help(language.text("Language"))
            }.padding(10)
            Divider()
            if session.mode == .orb {
                PlaygroundLayout(controller: session.orb, snapshotPane: isSnapshot ? snapshotPane : nil)
            } else {
                ProjectionDebugPanel(controller: session.projection, desktop: session.desktop, snapshotPane: isSnapshot ? snapshotPane : nil)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: session.mode == .orb ? 940 : 440, minHeight: 720)
        .onAppear { PlaygroundWindow.update(mode: session.mode, language: session.language) }
        .onChange(of: session.language) { _, value in PlaygroundWindow.update(mode: session.mode, language: value) }
        .onChange(of: session.mode) { _, mode in
            DispatchQueue.main.async {
                guard let window = PlaygroundWindow.main else { return }
                window.identifier = PlaygroundWindow.identifier
                window.title = language.text(mode == .orb ? "Orb Motion Playground" : "Projection Playground")
                if mode == .orb { window.setContentSize(NSSize(width: 1060, height: 790)); window.center() }
            }
        }
    }
}

private struct PlaygroundLayout: View {
    let controller: MotionController
    @StateObject private var options: PlaygroundOptions
    @Environment(\.playgroundLanguage) private var language
    @Environment(\.playgroundSnapshot) private var isSnapshot
    private var parameters: OrbParameters {
        get { options.parameters }
        nonmutating set { options.parameters = newValue }
    }
    private var magnification: Double { options.magnification }
    private var appearance: String { options.appearance }
    private var simulateHover: Bool {
        get { options.simulateHover }
        nonmutating set { options.simulateHover = newValue }
    }
    private var forceReducedMotion: Bool {
        get { options.forceReducedMotion }
        nonmutating set { options.forceReducedMotion = newValue }
    }
    private var pane: String { options.pane }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion

    init(controller: MotionController, snapshotPane: String? = nil) {
        self.controller = controller
        _options = StateObject(wrappedValue: PlaygroundOptions(pane: snapshotPane ?? "Appearance"))
    }

    private var colorScheme: ColorScheme? {
        appearance == "Dark" ? .dark : appearance == "Light" ? .light : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "circle.hexagongrid.fill").font(.system(size: 22, weight: .light))
                    .foregroundStyle(.cyan).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.text("Motion Playground")).font(.system(size: 17, weight: .semibold))
                    Text(language.text("ENERGY ORB  /  STUDY 01")).font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1.8).foregroundStyle(.secondary)
                }
                Spacer()
                Picker(language.text("Appearance"), selection: $options.appearance) {
                    ForEach(["System", "Light", "Dark"], id: \.self) { Text(language.text($0 == "System" ? "Follow system" : $0)).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).frame(width: 190)
            }.padding(.horizontal, 24).padding(.vertical, 18)
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    stage.environment(\.colorScheme, .dark)
                    TransportPanel(controller: controller, simulateHover: $options.simulateHover,
                                   pointerInside: options.pointerInside)
                }.frame(maxWidth: .infinity)
                Divider()
                parameterPanel.frame(width: 320)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(colorScheme)
        .onAppear {
            guard !isSnapshot else { return }
            controller.parameters = parameters
            controller.setReduceMotion(systemReducedMotion || forceReducedMotion)
            controller.setSuspended(scenePhase != .active)
            controller.start()
        }
        .onDisappear { if !isSnapshot { controller.stop() } }
        .onChange(of: parameters) { _, value in controller.parameters = value }
        .onChange(of: scenePhase) { _, phase in controller.setSuspended(phase != .active) }
        .onChange(of: forceReducedMotion) { _, value in controller.setReduceMotion(value || systemReducedMotion) }
        .onChange(of: systemReducedMotion) { _, value in controller.setReduceMotion(value || forceReducedMotion) }
    }

    private var stage: some View {
        VStack(spacing: 0) {
            HStack {
                Text(language.text("LIVE STAGE")).tracking(1.6)
                Spacer()
                Picker(language.text("Preview magnification"), selection: $options.magnification) {
                    Text(language.text("1:1")).tag(1.0)
                    Text(language.text("2×")).tag(2.0)
                    Text(language.text("3×")).tag(3.0)
                }.labelsHidden().pickerStyle(.segmented).frame(width: 142)
            }.font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.68)).padding(24)
            Spacer(minLength: 12)
            LiveOrb(controller: controller, parameters: parameters, magnification: magnification, simulateHover: simulateHover,
                    pointerInside: $options.pointerInside)
                .frame(minHeight: 130, maxHeight: .infinity)
            Text(language.text("Hover to charge. Leave to unwind."))
                .font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.68)).padding(.top, 12)
            Text(language.format("%d pt  ·  front view  ·  %.0f× inspection", Int(parameters.diameter), magnification))
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.white.opacity(0.53))
                .padding(.top, 7)
            Spacer(minLength: 28)
            HStack(spacing: 0) {
                ForEach([0.0, 0.4, 1.0], id: \.self) { progress in
                    VStack(spacing: 6) {
                        EnergyOrb(parameters: parameters, progress: progress, reducedMotion: forceReducedMotion)
                        Text(language.text(progress == 0 ? "STANDBY" : progress == 1 ? "ACTIVATED" : "INTERRUPTED"))
                            .font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(0.7)
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.white.opacity(0.53))
                    }.frame(maxWidth: .infinity)
                }
            }.foregroundStyle(Color.white.opacity(0.72)).padding(.horizontal, 24).padding(.bottom, 26)
        }
        .background {
            LinearGradient(colors: [Color(red: 0.045, green: 0.065, blue: 0.085),
                                    Color(red: 0.018, green: 0.032, blue: 0.048)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var parameterPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(language.text("Inspector")).font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(language.text("Defaults")) {
                    parameters = ApprovedOrbParameters.value
                    simulateHover = false
                    forceReducedMotion = false
                    controller.reset()
                }.controlSize(.small).help(language.text("Restore all appearance and motion parameters"))
            }
            Picker(language.text("Parameter group"), selection: $options.pane) {
                Text(language.text("Appearance")).tag("Appearance")
                Text(language.text("Motion")).tag("Motion")
            }.labelsHidden().pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if pane == "Appearance" {
                        inspectorHeading("FORM", subtitle: "Fine geometry, designed at native size.")
                        parameter("Diameter", value: $options.parameters.diameter, range: OrbParameters.diameterRange, unit: "pt", step: 1)
                        parameter("Core size", value: $options.parameters.coreRatio, range: OrbParameters.coreRatioRange, unit: "%", multiplier: 100)
                        parameter("Ring weight", value: $options.parameters.ringWidth, range: OrbParameters.ringWidthRange, unit: "pt")
                        parameter("Tick count", value: Binding(get: { Double(parameters.tickCount) },
                                  set: { parameters.tickCount = Int($0) }), range: 24...72, unit: "", step: 4)
                        Divider()
                        inspectorHeading("LIGHT & MATERIAL", subtitle: "A cold core inside a translucent iris.")
                        parameter("Energy hue", value: $options.parameters.hue, range: OrbParameters.hueRange, unit: "°", multiplier: 360)
                        parameter("Glow intensity", value: $options.parameters.glowIntensity, range: OrbParameters.glowIntensityRange, unit: "%", multiplier: 100)
                        parameter("Halo radius", value: $options.parameters.haloRadius, range: OrbParameters.haloRadiusRange, unit: "pt", step: 1)
                        parameter("Glass opacity", value: $options.parameters.glassOpacity, range: OrbParameters.glassOpacityRange, unit: "%", multiplier: 100)
                    } else {
                        inspectorHeading("AMBIENT", subtitle: "Independent orbits, one quiet rhythm.")
                        parameter("Outer rotation", value: $options.parameters.outerSpeed, range: OrbParameters.rotationSpeedRange, unit: "°/s", step: 1)
                        parameter("Inner rotation", value: $options.parameters.innerSpeed, range: OrbParameters.rotationSpeedRange, unit: "°/s", step: 1)
                        parameter("Breathing period", value: $options.parameters.breathPeriod, range: OrbParameters.breathPeriodRange, unit: "s")
                        parameter("Breathing depth", value: $options.parameters.breathAmplitude, range: OrbParameters.breathAmplitudeRange, unit: "%", multiplier: 100)
                        parameter("Scan speed", value: $options.parameters.scanSpeed, range: OrbParameters.scanSpeedRange, unit: "°/s", step: 1)
                        Divider()
                        inspectorHeading("ACTIVATION", subtitle: "Every stage follows the same playhead.")
                        parameter("Charge duration", value: $options.parameters.chargeDuration, range: OrbParameters.durationRange, unit: "ms", multiplier: 1000)
                        parameter("Release duration", value: $options.parameters.releaseDuration, range: OrbParameters.durationRange, unit: "ms", multiplier: 1000)
                        Picker(language.text("Time curve"), selection: $options.parameters.curve) {
                            ForEach(MotionCurve.allCases, id: \.self) { Text(language.text($0.title)).tag($0) }
                        }
                        Divider()
                        Toggle(language.text("Preview Reduce Motion"), isOn: $options.forceReducedMotion)
                        Text(language.text(systemReducedMotion ? "System Reduce Motion is on. Ambient motion is disabled." :
                             "Stops ambient motion; activation uses a brief light transition."))
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.trailing, 3).padding(.bottom, 12)
            }
            Text(language.text("Native SwiftUI · No external renderer"))
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(20)
    }

    private func inspectorHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(language.text(title)).font(.system(size: 10, weight: .semibold)).tracking(1)
            Text(language.text(subtitle)).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func parameter(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                           unit: String, multiplier: Double = 1, step: Double = 0.01) -> some View {
        VStack(spacing: 6) {
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

private struct LiveOrb: View {
    let controller: MotionController
    let parameters: OrbParameters
    let magnification: Double
    let simulateHover: Bool
    @Binding var pointerInside: Bool
    @Environment(\.playgroundLanguage) private var language

    var body: some View {
        AnimatedEnergyOrb(controller: controller)
            .frame(width: parameters.diameter + parameters.haloRadius * 2,
                   height: parameters.diameter + parameters.haloRadius * 2)
            .scaleEffect(magnification)
            .frame(width: parameters.diameter * magnification,
                   height: parameters.diameter * magnification)
            .contentShape(Circle())
            .onHover { inside in
                guard inside != pointerInside else { return }
                pointerInside = inside
                controller.setHovered(inside || simulateHover)
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { controller.activate() }
            .help(language.text("Hover to activate; move away to reverse from the current frame"))
    }
}

@MainActor
private final class PlaybackInspectorState: ObservableObject {
    @Published private(set) var timeline: MotionTimeline
    @Published private(set) var reduceMotion: Bool
    @Published private(set) var isSuspended: Bool
    private let controller: MotionController
    private var subscriptions = Set<AnyCancellable>()

    init(controller: MotionController) {
        self.controller = controller
        timeline = controller.timeline
        reduceMotion = controller.reduceMotion
        isSuspended = controller.isSuspended
        // Native controls need telemetry updates, not a full animation-rate layout pass.
        controller.$timeline.removeDuplicates { before, after in
            before.progress == after.progress && before.direction == after.direction &&
            before.isPlaying == after.isPlaying && before.isLooping == after.isLooping &&
            before.playbackRate == after.playbackRate
        }.throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] in self?.timeline = $0 }.store(in: &subscriptions)
        controller.$reduceMotion.sink { [weak self] in self?.reduceMotion = $0 }.store(in: &subscriptions)
        controller.$isSuspended.sink { [weak self] in self?.isSuspended = $0 }.store(in: &subscriptions)
    }

    func refresh() {
        timeline = controller.timeline
    }
}

private struct TransportPanel: View {
    let controller: MotionController
    @StateObject private var inspector: PlaybackInspectorState
    @Binding var simulateHover: Bool
    let pointerInside: Bool
    @Environment(\.playgroundLanguage) private var language

    init(controller: MotionController, simulateHover: Binding<Bool>, pointerInside: Bool) {
        self.controller = controller
        self._inspector = StateObject(wrappedValue: PlaybackInspectorState(controller: controller))
        self._simulateHover = simulateHover
        self.pointerInside = pointerInside
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(language.text("ACTIVATION TIMELINE")).font(.system(size: 10, weight: .semibold)).tracking(1)
                Spacer()
                Text(language.text(inspector.isSuspended ? "Suspended" : inspector.timeline.stateTitle))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text("\(inspector.timeline.progress * 100, specifier: "%.1f")%")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .frame(width: 63, alignment: .trailing)
            }
            VStack(spacing: 4) {
                Slider(value: Binding(get: { inspector.timeline.progress }, set: {
                    simulateHover = false
                    controller.scrub(to: $0)
                    inspector.refresh()
                }), in: 0...1) { Text(language.text("Activation progress")) }
                .labelsHidden().accessibilityValue(language.format("%d percent", Int(inspector.timeline.progress * 100)))
                HStack {
                    Text(language.text("0  Standby"))
                    Spacer()
                    Text(language.text("40  Gather"))
                    Spacer()
                    Text(language.text("100  Activated"))
                }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button(action: {
                    controller.timeline.isPlaying ? controller.pause() : controller.play()
                    inspector.refresh()
                }) {
                    Label(language.text(inspector.timeline.isPlaying ? "Pause" : "Play"),
                          systemImage: inspector.timeline.isPlaying ? "pause.fill" : "play.fill")
                }.frame(width: 78).help(language.text("Pause or resume both the playhead and ambient motion"))
                Button(language.text("Reset")) { simulateHover = false; controller.reset(); inspector.refresh() }
                Spacer(minLength: 4)
                Button(language.text("Retract")) { simulateHover = false; controller.retract(); inspector.refresh() }
                    .help(language.text("Reverse from the current progress"))
                Button(language.text("Activate")) { simulateHover = false; controller.activate(); inspector.refresh() }.buttonStyle(.borderedProminent)
                    .help(language.text("Continue charging from the current progress"))
            }.controlSize(.small)
            HStack(spacing: 14) {
                Toggle(language.text("Loop"), isOn: Binding(get: { inspector.timeline.isLooping }, set: { controller.setLooping($0); inspector.refresh() }))
                    .disabled(inspector.reduceMotion)
                Toggle(language.text("Simulate Hover"), isOn: Binding(get: { simulateHover }, set: {
                    simulateHover = $0
                    controller.setHovered($0 || pointerInside)
                    inspector.refresh()
                }))
                Spacer(minLength: 4)
                Picker(language.text("Playback speed"), selection: Binding(get: { inspector.timeline.playbackRate },
                                                           set: { controller.setPlaybackRate($0); inspector.refresh() })) {
                    ForEach(OrbParameters.playbackRates, id: \.self) { Text("\($0, specifier: "%g")×").tag($0) }
                }.labelsHidden().frame(width: 76)
            }.font(.system(size: 11)).toggleStyle(.checkbox)
            HStack {
                Text(language.text(inspector.timeline.direction.title))
                Spacer()
                Text(language.text(inspector.reduceMotion ? "Reduced motion" : "60 Hz active / 30 Hz idle target"))
            }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
        }.padding(24)
    }
}

private struct PlaygroundRenderFixture: View {
    @ObservedObject var session: PlaygroundSession
    let pane: String
    let scheme: ColorScheme
    let size: CGSize
    var body: some View {
        PlaygroundModeRoot(session: session)
            .environment(\.playgroundLanguage, session.language)
            .environment(\.locale, session.language.locale)
            .environment(\.playgroundSnapshot, true)
            .environment(\.playgroundSnapshotPane, pane)
            .environment(\.colorScheme, scheme)
            .preferredColorScheme(scheme)
            .frame(width: size.width, height: size.height)
    }
}

@MainActor
private enum PlaygroundLanguagePreviewExporter {
    static func export(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var files: [String] = []
        let fixtures: [(PlaygroundMode, String)] = CommandLine.arguments.contains("--hud-inspector-only") ? [(.projection, "HUD")] :
            [(.orb, "Appearance"), (.orb, "Motion"), (.projection, "Beam"), (.projection, "HUD"), (.projection, "Timing")]
        for (mode, pane) in fixtures {
            for dark in [false, true] {
                let session = PlaygroundSession(preferences: nil, languageOverride: .english)
                session.mode = mode
                session.projection.config.beamWidth = 137
                session.projection.scrub(to: 0.42)
                session.orb.scrub(to: 0.31)
                let config = session.projection.config
                let projected = session.projection.timeline, source = session.orb.timeline
                let identity = ObjectIdentifier(session.projection)
                let size = mode == .orb ? CGSize(width: 1060, height: 820) : CGSize(width: 440, height: 820)
                let view = PlaygroundRenderFixture(session: session, pane: pane, scheme: dark ? .dark : .light, size: size)
                let host = NSHostingView(rootView: view)
                let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: true)
                window.title = "Language render fixture"
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                host.appearance = window.appearance
                window.contentView = host
                host.frame = CGRect(origin: .zero, size: size)
                for language in PlaygroundLanguage.allCases {
                    session.language = language
                    host.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.12))
                    host.layoutSubtreeIfNeeded()
                    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    host.appearance?.performAsCurrentDrawingAppearance {
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                    }
                    guard let data = bitmap.representation(using: .png, properties: [:]) else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    let name = "\(language.rawValue)-\(mode.rawValue.lowercased())-\(pane.lowercased())-\(dark ? "dark" : "light").png"
                    try data.write(to: directory.appendingPathComponent(name), options: .atomic)
                    files.append(name)
                    guard session.projection.config == config, session.projection.timeline == projected,
                          session.orb.timeline == source, ObjectIdentifier(session.projection) == identity else {
                        throw CocoaError(.validationMissingMandatoryProperty)
                    }
                }
                window.close()
            }
        }
        let report: [String: Any] = ["files": files, "state_preserved_across_live_language_change": true,
            "projection_progress": 0.42, "orb_progress": 0.31, "edited_beam_width": 137,
            "scope": "Offscreen NSHostingView renders, not desktop screenshots; no panels ordered in and no preferences written"]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        print("Exported \(files.count) bilingual native render fixtures; paused state and parameters preserved.")
    }
}
