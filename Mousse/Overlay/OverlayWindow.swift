import AppKit
import QuartzCore

/// A transparent, click-through panel covering one screen. It floats above everything
/// (including full-screen apps and the menu bar) and is included in screen sharing.
/// In drawing mode it takes mouse and key input instead of passing it through.
final class OverlayWindow: NSPanel {
    let overlayView: OverlayView

    /// Whether the overlay is capturing input for drawing mode.
    var capturesInput = false {
        didSet {
            ignoresMouseEvents = !capturesInput
            acceptsMouseMovedEvents = capturesInput
        }
    }

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

    override var canBecomeKey: Bool { capturesInput }
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

    /// The active tool and style while this screen accepts drawing input.
    struct DrawingInput {
        var tool: DrawTool
        var style: DrawingStyle
    }

    private static let dimAlpha: CGFloat = 0.45
    private static let fadeDuration: CFTimeInterval = 0.15

    private let canvas = DrawingCanvas()
    private let dimLayer = CAShapeLayer()
    private let spotlightRingLayer = CAShapeLayer()
    private let pulseLayer = CAShapeLayer()
    private let highlightLayer = CAShapeLayer()
    private let hintLayer = HintLayer()

    private var highlightAppearance: HighlightAppearance?

    /// Non-nil while drawing mode is on; mouse drags then draw instead of passing through.
    var drawingInput: DrawingInput? {
        didSet {
            if drawingInput == nil { canvas.finish() }
            window?.invalidateCursorRects(for: self)
        }
    }
    /// Key presses while drawing mode is on (virtual key codes, layout-independent).
    var onKeyDown: ((UInt16) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        let noActions: [String: CAAction] = [
            "position": NSNull(), "bounds": NSNull(), "path": NSNull(), "opacity": NSNull(),
            "fillColor": NSNull(), "strokeColor": NSNull(), "lineWidth": NSNull(), "hidden": NSNull(),
        ]
        // Back to front: drawings, find-cursor dim and rings, highlight, hint.
        layer?.addSublayer(canvas.layer)
        for shape in [dimLayer, spotlightRingLayer, pulseLayer, highlightLayer] {
            shape.actions = noActions
            shape.isHidden = true
            layer?.addSublayer(shape)
        }
        layer?.addSublayer(hintLayer)

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
        canvas.setContentsScale(scale)
        hintLayer.setContentsScale(scale)
    }

    // MARK: - Drawing

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let input = drawingInput else { return }
        canvas.begin(input.tool, style: input.style, at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        guard drawingInput != nil else { return }
        canvas.extend(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        guard drawingInput != nil else { return }
        canvas.extend(to: convert(event.locationInWindow, from: nil))
        canvas.finish()
    }

    override func keyDown(with event: NSEvent) {
        // Swallow every key while drawing so nothing beeps; the controller acts on the
        // few it knows.
        guard drawingInput != nil else { return super.keyDown(with: event) }
        if !event.isARepeat { onKeyDown?(event.keyCode) }
    }

    override func resetCursorRects() {
        if let input = drawingInput {
            addCursorRect(bounds, cursor: DrawingCursor.cursor(for: input))
        }
    }

    func clearDrawings() {
        canvas.clear()
    }

    // MARK: - Hint

    /// Shows a short-lived pill near the bottom of this screen.
    func showHint(_ text: NSAttributedString) {
        hintLayer.show(text, centeredAt: CGPoint(x: bounds.midX, y: 120))
    }

    func hideHint() {
        hintLayer.hide()
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
