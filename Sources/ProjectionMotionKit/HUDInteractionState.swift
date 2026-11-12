import Foundation

public enum HUDInteractionPhase: String, CaseIterable, Sendable {
    case idle, opening, previewing, interacting, closing
}

public enum HUDPointerRegion: Equatable, Sendable {
    case outside, source, transit, hud
}

public enum HUDProjectionIntent: Equatable, Sendable {
    case open, close
}

/// Pointer policy chooses a target; it never edits or replaces the continuous playhead.
public struct HUDInteractionState: Equatable, Sendable {
    public private(set) var phase: HUDInteractionPhase = .idle
    public private(set) var region: HUDPointerRegion = .outside
    public var exitDelay = 0.55
    public var transitGrace = 1.2
    private var outsideSince: Double?
    private var transitSince: Double?
    private var automatic = false
    private var suppressedUntilExit = false

    public init() {}
    public var needsDeadline: Bool { automatic && (region == .outside || region == .transit) }

    public mutating func manualOpen() {
        automatic = false
        suppressedUntilExit = false
        outsideSince = nil; transitSince = nil
        phase = .opening
    }

    public mutating func manualClose() {
        automatic = false
        suppressedUntilExit = region == .source || region == .hud
        outsideSince = nil; transitSince = nil
        phase = .closing
    }

    public mutating func manualPlayback(progress: Double) {
        automatic = false
        outsideSince = nil; transitSince = nil
        phase = progress <= 0 ? .idle : .previewing
    }

    public mutating func engageHUD() {
        automatic = true
        suppressedUntilExit = false
        outsideSince = nil; transitSince = nil
        region = .hud; phase = .interacting
    }

    public mutating func update(region next: HUDPointerRegion, now: Double, progress: Double) -> HUDProjectionIntent? {
        guard now.isFinite, progress.isFinite else { return nil }
        let changed = next != region
        region = next
        if next == .outside || next == .transit { suppressedUntilExit = false }
        if next == .source || next == .hud {
            outsideSince = nil; transitSince = nil
            guard !suppressedUntilExit else {
                if progress <= 0 { phase = .idle }
                return nil
            }
            // Explicit transport commands retain ownership until a new pointer entry.
            guard automatic || changed else { return nil }
            let reopen = !automatic || phase == .closing || phase == .idle
            automatic = true
            phase = next == .hud ? .interacting : progress >= 1 ? .previewing : .opening
            return reopen ? .open : nil
        }
        if !automatic {
            if progress <= 0 { phase = .idle }
            else if phase == .opening && progress >= 1 { phase = .previewing }
            return nil
        }
        if next == .transit {
            if transitSince == nil { transitSince = now }
            if now - (transitSince ?? now) < max(0.05, transitGrace) {
                outsideSince = nil
                phase = progress >= 1 ? .previewing : .opening
                return nil
            }
        } else {
            transitSince = nil
            if outsideSince == nil { outsideSince = now }
            if now - (outsideSince ?? now) < max(0.05, exitDelay) {
                phase = progress >= 1 ? .previewing : .opening
                return nil
            }
        }
        automatic = false
        phase = progress <= 0 ? .idle : .closing
        return .close
    }

    /// A bounded widening corridor tolerates travel without creating a capturing window.
    public static func isInTransit(_ point: CGPoint, source: CGPoint, hudBounds: CGRect) -> Bool {
        let destination = CGPoint(x: hudBounds.midX, y: hudBounds.midY)
        let dx = destination.x - source.x, dy = destination.y - source.y
        let squaredLength = dx * dx + dy * dy
        guard squaredLength > 1 else { return false }
        let t = ((point.x - source.x) * dx + (point.y - source.y) * dy) / squaredLength
        guard t >= 0, t <= 1.1 else { return false }
        let nearest = CGPoint(x: source.x + dx * t, y: source.y + dy * t)
        let width = 36 + min(180, hudBounds.height * 0.5) * t
        return hypot(point.x - nearest.x, point.y - nearest.y) <= width
    }
}
