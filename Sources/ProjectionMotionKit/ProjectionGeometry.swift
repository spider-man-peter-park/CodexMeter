import Foundation
import OrbMotionKit

public struct ProjectionGeometry: Equatable, Sendable {
    public let visibleFrame: CGRect
    public let orbFrame: CGRect
    public let source: CGPoint
    public let center: CGPoint
    public let scale: Double
    public let radius: Double
    public let cardFrames: [CGRect]
    public let direction: Double

    public init(visibleFrame: CGRect, config raw: ProjectionConfig, orb: OrbParameters,
                orbFrame proposed: CGRect? = nil) {
        let p = raw.sanitized
        self.visibleFrame = visibleFrame
        let diameter = orb.sanitized.diameter + orb.sanitized.haloRadius * 2
        let x = p.edge == .left ? visibleFrame.minX + 12 : visibleFrame.maxX - diameter - 12
        let y = visibleFrame.minY + visibleFrame.height * p.verticalPosition - diameter / 2
        orbFrame = proposed ?? CGRect(x: x, y: min(visibleFrame.maxY - diameter, max(visibleFrame.minY, y)),
                                      width: diameter, height: diameter)
        // Layer geometry uses top-left coordinates; AppKit window frames use bottom-left coordinates.
        source = CGPoint(x: orbFrame.midX - visibleFrame.minX, y: visibleFrame.maxY - orbFrame.midY)
        center = CGPoint(x: visibleFrame.width / 2, y: visibleFrame.height / 2)
        direction = source.x < center.x ? 1 : -1
        let halfWidth = p.mainRadius * 1.45 + p.connectorLength + 136
        let halfHeight = p.mainRadius * 1.45 + 38
        let sourceClearance = abs(center.x - source.x) - orb.sanitized.diameter / 2 - 26
        scale = max(0.12, min(p.hudScale, (visibleFrame.width / 2 - 36) / halfWidth,
                    (visibleFrame.height / 2 - 36) / halfHeight, max(30, sourceClearance) / halfWidth))
        radius = p.mainRadius * scale
        var frames: [CGRect] = []
        for index in 0..<p.cardCount {
            let right = index.isMultiple(of: 2)
            let sign = right ? 1.0 : -1.0
            let middleX = center.x + sign * (p.mainRadius * 1.45 + p.connectorLength + 68) * scale
            let middleY = center.y + (index < 2 ? -0.56 : 0.56) * p.mainRadius * scale
            frames.append(CGRect(x: middleX - 68 * scale, y: middleY - 35 * scale,
                                 width: 136 * scale, height: 70 * scale))
        }
        cardFrames = frames
    }

    public func beamTip(at progress: Double) -> CGPoint {
        let t = ProjectionSample(progress: progress).beamExtension
        return CGPoint(x: source.x + (center.x - source.x) * t, y: source.y + (center.y - source.y) * t)
    }
    public static func containsOrb(_ point: CGPoint, in frame: CGRect, diameter: Double) -> Bool {
        hypot(point.x - frame.midX, point.y - frame.midY) <= diameter / 2 + 2
    }
}
