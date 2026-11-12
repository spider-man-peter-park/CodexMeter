import Combine
import Foundation
import OrbMotionKit

@MainActor
public final class ProjectionAnimationController: ObservableObject {
    @Published public var config = ProjectionConfig()
    @Published public private(set) var timeline = ProjectionTimeline()
    @Published public private(set) var reduceMotion = false
    @Published public private(set) var isSuspended = false
    @Published public private(set) var simulatedHover = false
    @Published public private(set) var pointerInside = false
    @Published public private(set) var lastAction = "Started"
    public let orbParameters: OrbParameters
    public let hud: HUDDashboardController
    private var hudSubscription: AnyCancellable?
    private var driver: Task<Void, Never>?
    private var started = false
    private var previousTick: Double?

    public init(orbParameters: OrbParameters) {
        self.orbParameters = orbParameters.sanitized
        hud = HUDDashboardController()
        hudSubscription = hud.$config.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.reconcile() }
        }
    }
    deinit { driver?.cancel() }

    public func start() { started = true; reconcile() }
    public func stop() { started = false; cancelDriver(); hud.setVisible(false); lastAction = "Stopped" }
    public func suspend(_ suspended: Bool) { isSuspended = suspended; reconcile() }
    public func setReduceMotion(_ enabled: Bool) { reduceMotion = enabled; reconcile() }
    public func expand() { simulatedHover = false; mutate { $0.isLooping = false; $0.forward() }; lastAction = "Expand" }
    public func retract() { simulatedHover = false; mutate { $0.isLooping = false; $0.reverse() }; lastAction = "Retract" }
    public func pause() { mutate { $0.pause() }; lastAction = "Pause" }
    public func play() { mutate { $0.play() }; lastAction = "Play" }
    public func reset() { simulatedHover = false; mutate { $0.reset() }; lastAction = "Reset" }
    public func hover(_ inside: Bool) {
        guard inside != pointerInside else { return }
        pointerInside = inside
        guard !timeline.isLooping else { return }
        mutate { $0.hover(inside || simulatedHover) }
        lastAction = inside ? "Source entered" : "Source exited"
    }
    public func simulateHover(_ inside: Bool) {
        simulatedHover = inside
        mutate { $0.isLooping = false; $0.hover(inside || pointerInside) }
        lastAction = inside ? "Simulated entry" : "Simulated exit"
    }
    public func clearPointer() { pointerInside = false }
    public func trackSourcePointer(_ inside: Bool) { if pointerInside != inside { pointerInside = inside } }
    public func scrub(to value: Double) { simulatedHover = false; mutate { $0.scrub(to: value) }; lastAction = "Scrubbed" }
    public func loop(_ looping: Bool) {
        if looping { simulatedHover = false }
        mutate { $0.isLooping = looping; if looping { $0.play() } }
        lastAction = looping ? "Loop enabled" : "Loop disabled"
    }
    public func speed(_ rate: Double) {
        guard [0.25, 0.5, 1, 2].contains(rate) else { return }
        mutate { $0.playbackRate = rate }
    }
    private var needsTicks: Bool {
        started && !isSuspended && timeline.isPlaying &&
            (timeline.isTransitioning || (!reduceMotion && hud.config.decorativeMotion))
    }
    private func mutate(_ action: (inout ProjectionTimeline) -> Void) {
        action(&timeline)
        previousTick = ProcessInfo.processInfo.systemUptime
        reconcile()
    }
    private func reconcile() {
        hud.setVisible(started && !isSuspended && timeline.progress > 0.45)
        guard needsTicks else { cancelDriver(); return }
        guard driver == nil else { return }
        previousTick = ProcessInfo.processInfo.systemUptime
        driver = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let interval: UInt64 = self?.timeline.isTransitioning == true ? 16_666_667 : 33_333_333
                do { try await Task.sleep(nanoseconds: interval) } catch { break }
                guard !Task.isCancelled else { break }
                self?.tick()
            }
        }
    }
    private func tick() {
        guard needsTicks else { cancelDriver(); return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = previousTick.map { now - $0 } ?? 0
        previousTick = now
        guard elapsed > 0, elapsed < 0.25 else { return }
        timeline.advance(seconds: elapsed, config: config, reducedMotion: reduceMotion,
                         decorationsPaused: !hud.config.decorativeMotion)
        hud.setVisible(started && !isSuspended && timeline.progress > 0.45)
        if !needsTicks { cancelDriver() }
    }
    private func cancelDriver() {
        driver?.cancel()
        driver = nil
        previousTick = nil
    }
}
