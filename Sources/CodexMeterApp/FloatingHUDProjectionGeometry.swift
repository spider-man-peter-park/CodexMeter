import AppKit
import OrbMotionKit
import ProjectionMotionKit

struct FloatingHUDProjectionGeometry {
    let projection: ProjectionGeometry
    let dashboardFrame: CGRect
    let viewportOrigin: CGPoint
    private let hudBounds: CGRect

    init(orb: CGRect, visibleFrame: CGRect, profile: FloatingHUDProjectionProfile) {
        projection = ProjectionGeometry(visibleFrame: visibleFrame, config: profile.projection,
            orb: OrbParameters(), orbFrame: orb)
        let hud = HUDLayout(visibleSize: visibleFrame.size, config: profile.hud)
        let bounds = hud.moduleFrames.values.reduce(hud.coreFrame) { $0.union($1) }
        hudBounds = bounds
        let crop = bounds.insetBy(dx: -18, dy: -18).intersection(CGRect(origin: .zero, size: visibleFrame.size))
        viewportOrigin = crop.origin
        dashboardFrame = CGRect(x: visibleFrame.minX + crop.minX, y: visibleFrame.maxY - crop.maxY,
            width: crop.width, height: crop.height)
    }

    func containsRetentionPoint(_ point: CGPoint) -> Bool {
        if projection.orbFrame.contains(point) { return true }
        let local = CGPoint(x: point.x - projection.visibleFrame.minX, y: projection.visibleFrame.maxY - point.y)
        return hudBounds.contains(local) || HUDInteractionState.isInTransit(local,
            source: projection.source, hudBounds: hudBounds)
    }
}
