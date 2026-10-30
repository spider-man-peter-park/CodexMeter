import AppKit
import CodexMeterCore
import Network

@MainActor final class InterruptionMonitor {
    private var monitor: NWPathMonitor?
    private var observers: [NSObjectProtocol] = []
    private var policy = RecoveryEventPolicy()
    private let sleep: () -> Void
    private let wake: (Bool) -> Void
    private let connection: (Bool, Bool) -> Void

    init(sleep: @escaping () -> Void, wake: @escaping (Bool) -> Void, connection: @escaping (Bool, Bool) -> Void) {
        self.sleep = sleep; self.wake = wake; self.connection = connection
    }
    func start() {
        guard monitor == nil else { return }
        policy = RecoveryEventPolicy()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleSleep() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        })
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor in self?.handlePath(available) }
        }
        self.monitor = monitor
        monitor.start(queue: DispatchQueue(label: "io.github.codexmeter.network-path", qos: .utility))
    }
    func stop() {
        monitor?.cancel(); monitor = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }
    private func handleSleep() { guard monitor != nil else { return }; policy.willSleep(); sleep() }
    private func handleWake() { guard monitor != nil else { return }; wake(policy.didWake()) }
    private func handlePath(_ available: Bool) {
        guard monitor != nil else { return }
        let recovered = policy.pathChanged(available: available)
        connection(available, recovered)
    }
}
