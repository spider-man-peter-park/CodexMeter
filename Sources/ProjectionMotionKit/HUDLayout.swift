import Foundation
import AppKit

public enum HUDTarget: Hashable, Sendable {
    case core
    case module(HUDModule)
}

public struct HUDGeneration: Equatable, Sendable {
    public let core: Double
    public let rings: Double
    public let connector: Double
    public let border: Double
    public let content: Double

    public init(progress: Double, moduleIndex: Int = 0) {
        let sample = ProjectionSample(progress: progress)
        let stagger = Double(max(0, min(5, moduleIndex))) * 0.016
        core = sample.stage(0.35, 0.49)
        rings = sample.stage(0.45, 0.66)
        connector = sample.stage(0.62 + stagger, 0.72 + stagger)
        border = sample.stage(0.69 + stagger, 0.81 + stagger)
        content = sample.stage(0.78 + stagger, 0.91 + stagger)
    }
}

public enum HUDDesignTokens {
    public static let outerInset = 26.0
    public static let minimumCoreDiameter = 240.0
    public static let maximumCoreDiameter = 340.0
    public static let labelSize = 11.0
    public static let bodySize = 12.0
    public static let metricSize = 24.0
    public static let hoverDuration = 0.18
    public static let selectionDuration = 0.32
    public static let minimumLineWidth = 0.65
    public static let moduleCornerCut = 15.0
    public static let textPrimary = NSColor(calibratedRed: 0.88, green: 0.96, blue: 1, alpha: 1)
    public static let textSecondary = NSColor(calibratedRed: 0.53, green: 0.67, blue: 0.72, alpha: 1)
    public static let accentBlue = NSColor(calibratedRed: 0.34, green: 0.64, blue: 1, alpha: 1)
    public static let secondaryViolet = NSColor(calibratedRed: 0.68, green: 0.65, blue: 1, alpha: 1)
    public static let mockAmber = NSColor(calibratedRed: 0.96, green: 0.76, blue: 0.43, alpha: 1)
    public static func primaryCyan(hue: Double) -> NSColor {
        NSColor(calibratedHue: hue, saturation: 0.57, brightness: 0.97, alpha: 1)
    }
    public static func metricFont(size: Double, weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }
}

public struct HUDLayout: Equatable, Sendable {
    public let visibleSize: CGSize
    public let coreFrame: CGRect
    public let moduleFrames: [HUDModule: CGRect]
    public let disabledModules: Set<HUDModule>
    public let isCompact: Bool
    public var center: CGPoint { CGPoint(x: coreFrame.midX, y: coreFrame.midY) }
    public var interactionFrames: [HUDTarget: CGRect] {
        var result = Dictionary(uniqueKeysWithValues: moduleFrames.map { (HUDTarget.module($0.key), $0.value) })
        result[.core] = coreFrame
        return result
    }

    public init(visibleSize: CGSize, config raw: HUDConfiguration) {
        let config = raw.sanitized
        disabledModules = config.disabledModules
        let width = max(1, visibleSize.width), height = max(1, visibleSize.height)
        self.visibleSize = CGSize(width: width, height: height)
        isCompact = config.density == .compact || width < 1160 || height < 720
        let inset = HUDDesignTokens.outerInset
        let horizontalInset = max(inset, 118)
        let fittingCore = min(width * 0.3, height * 0.42)
        let diameter = min(max(HUDDesignTokens.minimumCoreDiameter, config.coreDiameter),
                           HUDDesignTokens.maximumCoreDiameter, fittingCore)
        let center = CGPoint(x: width / 2, y: height / 2)
        coreFrame = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                           width: diameter, height: diameter)
        let spacing = min(44, max(12, config.spacing))
        let availableSide = width / 2 - diameter / 2 - spacing - horizontalInset
        let idealWidth = (isCompact ? 212.0 : config.density == .expanded ? 270 : 244) * min(1.16, max(0.85, config.moduleScale))
        let moduleWidth = max(120, min(idealWidth, availableSide))
        let moduleHeight = min(isCompact ? 124.0 : 142.0, max(84, (height - 150) / 3.2))
        let leftX = max(horizontalInset, center.x - diameter / 2 - spacing - moduleWidth)
        let rightX = min(width - horizontalInset - moduleWidth, center.x + diameter / 2 + spacing)
        let upperY = max(inset, center.y - moduleHeight - (isCompact ? 34 : 54))
        let lowerY = min(height - inset - moduleHeight, center.y + (isCompact ? 8 : 24))
        var frames: [HUDModule: CGRect] = [:]
        let mirror = config.layoutVariant.isMultiple(of: 2)
        frames[.system] = CGRect(x: mirror ? leftX : rightX, y: upperY + 12, width: moduleWidth, height: moduleHeight)
        frames[.performance] = CGRect(x: mirror ? leftX : rightX, y: lowerY + 4, width: moduleWidth, height: moduleHeight)
        frames[.ai] = CGRect(x: mirror ? rightX : leftX, y: upperY, width: moduleWidth, height: moduleHeight - 8)
        frames[.network] = CGRect(x: mirror ? rightX : leftX, y: lowerY - 8, width: moduleWidth, height: moduleHeight + 4)
        let bottomY = max(center.y + diameter / 2 + spacing, lowerY + moduleHeight + 18)
        let bottomHeight = min(isCompact ? 92 : 108, height - inset - bottomY)
        if bottomHeight >= 76 {
            let bottomWidth = min(isCompact ? 222 : 260, (width - inset * 2 - spacing) / 2)
            frames[.activity] = CGRect(x: center.x - bottomWidth - spacing / 2, y: bottomY,
                                       width: bottomWidth, height: bottomHeight)
            frames[.controls] = CGRect(x: center.x + spacing / 2, y: bottomY - 2,
                                       width: bottomWidth, height: bottomHeight)
        }
        let bounds = CGRect(origin: .zero, size: self.visibleSize).insetBy(dx: 8, dy: 8)
        moduleFrames = frames.filter { config.enabledModules.contains($0.key) && bounds.contains($0.value) }
    }

    public func frame(for target: HUDTarget) -> CGRect? {
        switch target { case .core: return coreFrame; case .module(let module): return moduleFrames[module] }
    }

    public func target(at point: CGPoint) -> HUDTarget? {
        let radius = coreFrame.width / 2
        if hypot(point.x - center.x, point.y - center.y) <= radius { return .core }
        for module in HUDModule.allCases {
            guard !disabledModules.contains(module) else { continue }
            guard let frame = moduleFrames[module], frame.contains(point) else { continue }
            let local = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
            let cut = HUDDesignTokens.moduleCornerCut
            if local.x + local.y < cut || frame.width - local.x + frame.height - local.y < cut { continue }
            if module == .performance || module == .network {
                if frame.midX < center.x {
                    let t = min(1, max(0, local.y / (frame.height - cut)))
                    if local.x > frame.width - 80 * t * (1 - t) { continue }
                } else {
                    let t = min(1, max(0, (local.y - cut) / (frame.height - 5 - cut)))
                    if local.x < 80 * t * (1 - t) { continue }
                }
            }
            return .module(module)
        }
        return nil
    }

    public func module(atCorePoint point: CGPoint) -> HUDModule? {
        guard !moduleFrames.isEmpty else { return nil }
        let angle = atan2(point.y - center.y, point.x - center.x)
        return moduleFrames.filter { !disabledModules.contains($0.key) }.min { left, right in
            func distance(_ frame: CGRect) -> Double {
                let target = atan2(frame.midY - center.y, frame.midX - center.x)
                return abs(atan2(sin(target - angle), cos(target - angle)))
            }
            return distance(left.value) < distance(right.value)
        }?.key
    }
}
