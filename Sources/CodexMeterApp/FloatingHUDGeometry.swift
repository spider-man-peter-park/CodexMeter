import AppKit

enum FloatingHUDEdge: CaseIterable {
    case left, right, bottom, top
}

struct FloatingHUDComposition: Equatable {
    static let cardCornerRadius: CGFloat = 8
    let size: NSSize
    let coreFrame: NSRect
    let cardFrames: [NSRect]
    let isCompact: Bool

    init(size: NSSize) {
        let width = size.width.isFinite ? max(1, size.width) : 1
        let height = size.height.isFinite ? max(1, size.height) : 1
        self.size = NSSize(width: width, height: height)
        isCompact = width < 900 || height < 540
        if isCompact {
            let gap = min(16, max(4, min(width, height) * 0.025))
            let diameter = min(184, width * 0.4, height * 0.26)
            coreFrame = NSRect(x: (width - diameter) / 2, y: gap, width: diameter, height: diameter)
            let gridTop = coreFrame.maxY + gap
            let cardWidth = max(1, (width - gap * 3) / 2)
            let cardHeight = max(1, (height - gridTop - gap * 3) / 2)
            cardFrames = [
                NSRect(x: gap, y: gridTop, width: cardWidth, height: cardHeight),
                NSRect(x: gap * 2 + cardWidth, y: gridTop, width: cardWidth, height: cardHeight),
                NSRect(x: gap, y: gridTop + cardHeight + gap, width: cardWidth, height: cardHeight),
                NSRect(x: gap * 2 + cardWidth, y: gridTop + cardHeight + gap, width: cardWidth, height: cardHeight)
            ]
        } else {
            let diameter = min(420, width * 0.39, height * 0.64)
            coreFrame = NSRect(x: (width - diameter) / 2, y: (height - diameter) / 2,
                width: diameter, height: diameter)
            let cardWidth = min(264, width * 0.25)
            let cardHeight = min(162, height * 0.245)
            let sideInset = min(32, width * 0.025)
            let top = height * 0.13
            let bottom = height - top - cardHeight
            let right = width - sideInset - cardWidth
            cardFrames = [
                NSRect(x: sideInset, y: top, width: cardWidth, height: cardHeight),
                NSRect(x: right, y: top, width: cardWidth, height: cardHeight),
                NSRect(x: sideInset, y: bottom, width: cardWidth, height: cardHeight),
                NSRect(x: right, y: bottom, width: cardWidth, height: cardHeight)
            ]
        }
    }

    // Composition frames use the top-left coordinate system shared with SwiftUI.
    func containsInteractivePoint(_ point: NSPoint) -> Bool {
        let radius = coreFrame.width / 2
        if hypot(point.x - coreFrame.midX, point.y - coreFrame.midY) <= radius { return true }
        return cardFrames.contains { frame in
            guard frame.contains(point) else { return false }
            let corner = min(Self.cardCornerRadius, frame.width / 2, frame.height / 2)
            let nearestX = min(max(point.x, frame.minX + corner), frame.maxX - corner)
            let nearestY = min(max(point.y, frame.minY + corner), frame.maxY - corner)
            return hypot(point.x - nearestX, point.y - nearestY) <= corner
        }
    }
}

struct FloatingHUDLayout: Equatable {
    let screenFrame: NSRect
    let orbFrame: NSRect
    let dashboardFrame: NSRect?
    let composition: FloatingHUDComposition?

    var beamOrigin: NSPoint { NSPoint(x: orbFrame.midX, y: orbFrame.midY) }
    var beamTarget: NSPoint { NSPoint(x: screenFrame.midX, y: screenFrame.midY) }

    func containsInteractivePoint(_ point: NSPoint) -> Bool {
        orbFrame.contains(point) || containsDashboardPoint(point)
    }

    func containsDashboardPoint(_ point: NSPoint) -> Bool {
        guard let dashboardFrame, let composition else { return false }
        return composition.containsInteractivePoint(NSPoint(x: point.x - dashboardFrame.minX,
            y: dashboardFrame.maxY - point.y))
    }

    func containsRetentionPoint(_ point: NSPoint) -> Bool {
        if containsInteractivePoint(point) { return true }
        guard let dashboardFrame else { return false }
        if dashboardFrame.contains(point) { return true }
        let dx = beamTarget.x - beamOrigin.x
        let dy = beamTarget.y - beamOrigin.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 1 else { return false }
        let t = ((point.x - beamOrigin.x) * dx + (point.y - beamOrigin.y) * dy) / lengthSquared
        guard (0...1).contains(t) else { return false }
        let projected = NSPoint(x: beamOrigin.x + t * dx, y: beamOrigin.y + t * dy)
        return hypot(point.x - projected.x, point.y - projected.y) <= 28 + t * 44
    }
}

enum FloatingHUDGeometry {
    static let orbSize: CGFloat = 68
    static let edgeMargin: CGFloat = 24
    static let dashboardSize = NSSize(width: 1120, height: 680)

    static func screen(for orb: NSRect, among screens: [NSRect], fallback: NSRect) -> NSRect {
        let center = NSPoint(x: orb.midX, y: orb.midY)
        guard center.x.isFinite, center.y.isFinite else { return fallback }
        return screens.first(where: { $0.contains(center) }) ?? fallback
    }

    static func clampedOrb(_ proposed: NSRect, on screen: NSRect) -> NSRect {
        let width = min(orbSize, max(1, screen.width))
        let height = min(orbSize, max(1, screen.height))
        let x = proposed.minX.isFinite ? proposed.minX : screen.maxX - width - edgeMargin
        let y = proposed.minY.isFinite ? proposed.minY : screen.midY - height / 2
        return NSRect(x: min(max(x, screen.minX), screen.maxX - width),
            y: min(max(y, screen.minY), screen.maxY - height), width: width, height: height)
    }

    static func nearestEdge(to orb: NSRect, on screen: NSRect) -> FloatingHUDEdge {
        let distances: [(FloatingHUDEdge, CGFloat)] = [
            (.left, abs(orb.minX - screen.minX)), (.right, abs(screen.maxX - orb.maxX)),
            (.bottom, abs(orb.minY - screen.minY)), (.top, abs(screen.maxY - orb.maxY))
        ]
        return distances.min(by: { $0.1 < $1.1 })?.0 ?? .right
    }

    static func snappedOrb(_ proposed: NSRect, on screen: NSRect) -> NSRect {
        var orb = clampedOrb(proposed, on: screen)
        let marginX = min(edgeMargin, max(0, (screen.width - orb.width) / 2))
        let marginY = min(edgeMargin, max(0, (screen.height - orb.height) / 2))
        let minX = screen.minX + marginX
        let maxX = screen.maxX - marginX - orb.width
        let minY = screen.minY + marginY
        let maxY = screen.maxY - marginY - orb.height
        let edge = nearestEdge(to: orb, on: screen)
        orb.origin.x = min(max(orb.minX, minX), maxX)
        orb.origin.y = min(max(orb.minY, minY), maxY)
        switch edge {
        case .left: orb.origin.x = minX
        case .right: orb.origin.x = maxX
        case .bottom: orb.origin.y = minY
        case .top: orb.origin.y = maxY
        }
        return orb
    }

    static func layout(orb proposed: NSRect, on screen: NSRect, expanded: Bool) -> FloatingHUDLayout {
        let orb = clampedOrb(proposed, on: screen)
        guard expanded else {
            return FloatingHUDLayout(screenFrame: screen, orbFrame: orb, dashboardFrame: nil, composition: nil)
        }
        let edge = nearestEdge(to: orb, on: screen)
        let horizontalEdge = edge == .left || edge == .right
        let availableWidth = max(1, screen.width - edgeMargin * 2)
        let availableHeight = max(1, screen.height - edgeMargin * 2)
        let width = min(dashboardSize.width, availableWidth,
            horizontalEdge ? max(320, screen.width - (orbSize + edgeMargin + 20) * 2) : availableWidth)
        let height = min(dashboardSize.height, availableHeight,
            horizontalEdge ? availableHeight : max(240, screen.height - (orbSize + edgeMargin + 20) * 2))
        let dashboard = NSRect(x: screen.midX - width / 2, y: screen.midY - height / 2, width: width, height: height)
        return FloatingHUDLayout(screenFrame: screen, orbFrame: orb, dashboardFrame: dashboard,
            composition: FloatingHUDComposition(size: dashboard.size))
    }
}

struct FloatingHUDInteraction {
    private(set) var expanded = false
    private(set) var dragging = false
    private(set) var generation = 0

    mutating func pointerEntered() {
        generation &+= 1
        if !dragging { expanded = true }
    }

    mutating func pointerExited() -> Int? {
        guard expanded, !dragging else { return nil }
        generation &+= 1
        return generation
    }

    mutating func completeExit(_ ticket: Int, pointerInside: Bool) -> Bool {
        guard ticket == generation, !pointerInside, !dragging, expanded else { return false }
        expanded = false
        return true
    }

    mutating func setExpanded(_ value: Bool) {
        generation &+= 1
        expanded = value
    }

    mutating func beginDrag() {
        generation &+= 1
        dragging = true
        expanded = false
    }

    mutating func endDrag() {
        generation &+= 1
        dragging = false
    }
}
