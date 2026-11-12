import AppKit

@MainActor
public final class ProjectionBackdropView: NSView {
    private let blur = NSVisualEffectView()
    private let tint = NSView()
    public override var isOpaque: Bool { false }
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    public init() {
        super.init(frame: .zero)
        blur.autoresizingMask = [.width, .height]
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .darkAqua)
        addSubview(blur)

        tint.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        addSubview(tint)
        configure(ProjectionBackdropConfiguration())
        setAccessibilityElement(false)
    }

    public func configure(_ configuration: ProjectionBackdropConfiguration) {
        let value = configuration.sanitized
        blur.alphaValue = CGFloat(value.blurIntensity)
        blur.isHidden = value.blurIntensity == 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(value.tintOpacity).cgColor
        CATransaction.commit()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}
