import AppKit
import QuartzCore

/// A transparent, click-through panel covering one screen. It floats above everything
/// (including full-screen apps and the menu bar) and is included in screen sharing.
final class OverlayWindow: NSPanel {
    let overlayView: OverlayView

    init(screen: NSScreen) {
        overlayView = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        contentView = overlayView
        setFrame(screen.frame, display: false)
        overlayView.setContentsScale(screen.backingScaleFactor)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Converts a global (Cocoa, bottom-left origin) point into this overlay's view space.
    func localPoint(fromGlobal point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - frame.origin.x, y: point.y - frame.origin.y)
    }
}

/// Draws the overlay's effects with Core Animation layers. Implicit animations are
/// disabled on every layer so positions track the cursor without lag; fades are
/// explicit animations.
final class OverlayView: NSView {
    struct FindRender {
        /// Cursor position in this view, or nil when the cursor is on another screen.
        var center: CGPoint?
        var frame: FindCursorAnimation.Frame
        var dimsScreen: Bool
        var color: NSColor
    }

    private static let dimAlpha: CGFloat = 0.45
    private static let fadeDuration: CFTimeInterval = 0.15

    private let dimLayer = CAShapeLayer()
    private let spotlightRingLayer = CAShapeLayer()
    private let pulseLayer = CAShapeLayer()
    private let highlightLayer = CAShapeLayer()

    private var highlightAppearance: HighlightAppearance?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        let noActions: [String: CAAction] = [
            "position": NSNull(), "bounds": NSNull(), "path": NSNull(), "opacity": NSNull(),
            "fillColor": NSNull(), "strokeColor": NSNull(), "lineWidth": NSNull(), "hidden": NSNull(),
        ]
        for shape in [dimLayer, spotlightRingLayer, pulseLayer, highlightLayer] {
            shape.actions = noActions
            shape.isHidden = true
            layer?.addSublayer(shape)
        }

        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = NSColor.black.cgColor
        spotlightRingLayer.fillColor = nil
        spotlightRingLayer.lineWidth = 4
        pulseLayer.fillColor = nil
        pulseLayer.lineWidth = 3
        highlightLayer.opacity = 0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setContentsScale(_ scale: CGFloat) {
        for shape in [dimLayer, spotlightRingLayer, pulseLayer, highlightLayer] {
            shape.contentsScale = scale
        }
    }

    // MARK: - Cursor highlight

    func applyHighlight(_ appearance: HighlightAppearance) {
        guard appearance != highlightAppearance else { return }
        highlightAppearance = appearance

        let d = appearance.diameter
        let bounds = CGRect(x: 0, y: 0, width: d, height: d)
        highlightLayer.bounds = bounds

        switch appearance.style {
        case .filled:
            highlightLayer.path = CGPath(ellipseIn: bounds, transform: nil)
            highlightLayer.fillColor = appearance.color.withAlphaComponent(appearance.opacity).cgColor
            highlightLayer.strokeColor = appearance.color
                .withAlphaComponent(min(1, appearance.opacity + 0.3)).cgColor
            highlightLayer.lineWidth = 1.5
        case .ring:
            let w = appearance.ringWidth
            highlightLayer.path = CGPath(ellipseIn: bounds.insetBy(dx: w / 2, dy: w / 2), transform: nil)
            highlightLayer.fillColor = nil
            highlightLayer.strokeColor = appearance.color.withAlphaComponent(appearance.opacity).cgColor
            highlightLayer.lineWidth = w
        }
    }

    func moveHighlight(to point: CGPoint) {
        highlightLayer.position = point
    }

    func setHighlightVisible(_ visible: Bool, animated: Bool) {
        let target: Float = visible ? 1 : 0
        if visible { highlightLayer.isHidden = false }
        guard highlightLayer.opacity != target else { return }

        if animated {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = highlightLayer.presentation()?.opacity ?? highlightLayer.opacity
            fade.toValue = target
            fade.duration = Self.fadeDuration
            highlightLayer.add(fade, forKey: "fade")
        }
        highlightLayer.opacity = target
    }

    // MARK: - Find cursor

    func renderFind(_ render: FindRender?) {
        guard let render else {
            dimLayer.isHidden = true
            spotlightRingLayer.isHidden = true
            pulseLayer.isHidden = true
            return
        }

        let f = render.frame
        let screenPath = CGMutablePath()
        screenPath.addRect(bounds)

        if let center = render.center {
            let ring = Self.circle(center: center, radius: f.spotlightRadius)
            screenPath.addPath(ring)

            spotlightRingLayer.isHidden = false
            spotlightRingLayer.path = ring
            spotlightRingLayer.strokeColor = render.color.withAlphaComponent(f.envelope).cgColor

            pulseLayer.isHidden = f.pulseAlpha <= 0
            pulseLayer.path = Self.circle(center: center, radius: f.pulseRadius)
            pulseLayer.strokeColor = render.color.withAlphaComponent(f.pulseAlpha * f.envelope).cgColor
        } else {
            spotlightRingLayer.isHidden = true
            pulseLayer.isHidden = true
        }

        dimLayer.isHidden = !render.dimsScreen
        dimLayer.path = screenPath
        dimLayer.fillColor = NSColor.black.withAlphaComponent(Self.dimAlpha * f.envelope).cgColor
    }

    private static func circle(center: CGPoint, radius: CGFloat) -> CGPath {
        CGPath(
            ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2),
            transform: nil
        )
    }
}
