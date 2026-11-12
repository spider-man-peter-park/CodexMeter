import Combine
import Foundation

@MainActor
public final class HUDDashboardController: ObservableObject {
    @Published public var config = HUDConfiguration() {
        didSet {
            let interactive = config.enabledModules.subtracting(config.disabledModules)
            if let selected, !interactive.contains(selected) { overview() }
            if let hovered, !interactive.contains(hovered) { self.hovered = nil }
        }
    }
    @Published public private(set) var hovered: HUDModule?
    @Published public private(set) var selected: HUDModule?
    @Published public private(set) var expanded = false
    @Published public private(set) var snapshot = HUDDataSnapshot()
    @Published public private(set) var visible = false
    private let provider: any HUDDataProviding
    private var sampler: Task<Void, Never>?

    public init(provider: (any HUDDataProviding)? = nil) {
        self.provider = provider ?? NativeHUDDataProvider()
    }

    deinit { sampler?.cancel() }

    public func hover(_ module: HUDModule?) {
        let next = module.flatMap { config.enabledModules.contains($0) && !config.disabledModules.contains($0) ? $0 : nil }
        guard next != hovered else { return }
        hovered = next
    }

    public func select(_ module: HUDModule) {
        guard config.enabledModules.contains(module), !config.disabledModules.contains(module) else { return }
        if selected == module { if !expanded { expanded = true } }
        else { selected = module; expanded = false }
    }

    public func expandSelection() {
        guard selected != nil, !expanded else { return }
        expanded = true
    }

    public func overview() {
        guard selected != nil || expanded else { return }
        selected = nil; expanded = false
    }
    public func setDecorativeMotion(_ enabled: Bool) {
        guard enabled != config.decorativeMotion else { return }
        config.decorativeMotion = enabled
    }

    public func setVisible(_ value: Bool) {
        guard visible != value else { return }
        visible = value
        sampler?.cancel(); sampler = nil
        provider.reset()
        guard value else { hovered = nil; return }
        refresh()
        sampler = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { break }
                guard !Task.isCancelled else { break }
                self?.refresh()
            }
        }
    }

    public func refresh(now: Date = Date()) {
        guard visible else { return }
        snapshot = provider.sample(modules: config.enabledModules.subtracting(config.disabledModules), now: now)
    }
}
