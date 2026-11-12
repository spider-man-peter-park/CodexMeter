import Combine
import Foundation

@MainActor
public final class MotionController: ObservableObject {
    @Published public var parameters: OrbParameters
    @Published public private(set) var timeline = MotionTimeline()
    @Published public private(set) var reduceMotion = false
    @Published public private(set) var isSuspended = false
    private var driver: Task<Void, Never>?
    private var isStarted = false
    private var previousTick: TimeInterval?

    public init(parameters: OrbParameters = OrbParameters()) {
        self.parameters = parameters
    }

    deinit {
        driver?.cancel()
    }

    public func start() {
        isStarted = true
        reconcileDriver()
    }

    public func stop() {
        isStarted = false
        cancelDriver()
    }

    public func setSuspended(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        reconcileDriver()
    }

    public func setReduceMotion(_ enabled: Bool) {
        guard enabled != reduceMotion else { return }
        reduceMotion = enabled
        reconcileDriver()
    }

    public func activate() { mutate { $0.activate() } }
    public func retract() { mutate { $0.retract() } }
    public func setHovered(_ hovered: Bool) { mutate { $0.setHovered(hovered) } }
    public func scrub(to progress: Double) { mutate { $0.scrub(to: progress) } }
    public func play() { mutate { $0.play() } }
    public func pause() { mutate { $0.pause() } }
    public func reset() { mutate { $0.reset() } }
    public func setLooping(_ looping: Bool) {
        mutate {
            $0.isLooping = looping
            if looping { $0.play() }
        }
    }
    public func setPlaybackRate(_ rate: Double) {
        guard OrbParameters.playbackRates.contains(rate) else { return }
        mutate { $0.playbackRate = rate }
    }

    private func mutate(_ body: (inout MotionTimeline) -> Void) {
        body(&timeline)
        // Interactive changes own the current presentation value; no implicit animation retargets it.
        previousTick = ProcessInfo.processInfo.systemUptime
        reconcileDriver()
    }

    private var needsTicks: Bool {
        isStarted && !isSuspended && timeline.isPlaying && (!reduceMotion || timeline.isTransitioning)
    }

    private var tickNanoseconds: UInt64 {
        timeline.isTransitioning ? 16_666_667 : 33_333_333
    }

    private func reconcileDriver() {
        guard needsTicks else { cancelDriver(); return }
        guard driver == nil else { return }
        previousTick = ProcessInfo.processInfo.systemUptime
        driver = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let interval = self?.tickNanoseconds ?? 33_333_333
                do { try await Task.sleep(nanoseconds: interval) }
                catch { break }
                guard !Task.isCancelled else { break }
                self?.tick()
            }
        }
    }

    private func cancelDriver() {
        driver?.cancel()
        driver = nil
        previousTick = nil
    }

    private func tick() {
        guard needsTicks else { cancelDriver(); return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = previousTick.map { now - $0 } ?? 0
        previousTick = now
        // A sleep, debugger stop, or stalled event loop must not finish an unseen animation.
        guard elapsed > 0, elapsed < 0.25 else { return }
        timeline.advance(seconds: elapsed, parameters: parameters, reduceMotion: reduceMotion)
        if !needsTicks { cancelDriver() }
    }
}
