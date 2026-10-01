import AppKit
import QuartzCore

/// The shapes drawn on one screen in drawing mode. Each shape is its own layer so it
/// can fade out on its own schedule; fades are Core Animation timelines, not timers.
@MainActor
final class DrawingCanvas {
    private static let fadeDuration: CFTimeInterval = 0.6
    private static let clearDuration: CFTimeInterval = 0.15
    /// Drags shorter than this in both directions are treated as a click and dropped.
    private static let minRectSide: CGFloat = 4

    let layer = CALayer()

    private struct Stroke {
        let shape: CAShapeLayer
        let tool: DrawTool
        let style: DrawingStyle
        var points: [CGPoint]
    }

    private var current: Stroke?
    private var contentsScale: CGFloat = 2

    init() {
        layer.actions = DrawingCanvas.noActions
    }

    func setContentsScale(_ scale: CGFloat) {
        contentsScale = scale
        layer.contentsScale = scale
        layer.sublayers?.forEach { $0.contentsScale = scale }
    }

    // MARK: - Strokes

    func begin(_ tool: DrawTool, style: DrawingStyle, at point: CGPoint) {
        finish()
        let shape = CAShapeLayer()
        shape.actions = Self.noActions
        shape.contentsScale = contentsScale
        shape.lineWidth = style.lineWidth
        shape.strokeColor = style.lineColor.cgColor
        shape.lineJoin = .round
        shape.lineCap = .round
        switch tool {
        case .rectangle: shape.fillColor = style.fillColor?.cgColor
        case .pen: shape.fillColor = nil
        }
        layer.addSublayer(shape)
        current = Stroke(shape: shape, tool: tool, style: style, points: [point])
        updatePath()
    }

    func extend(to point: CGPoint) {
        guard current != nil else { return }
        switch current!.tool {
        case .rectangle:
            // Only the anchor and the latest corner matter.
            current!.points = [current!.points[0], point]
        case .pen:
            current!.points.append(point)
        }
        updatePath()
    }

    /// Ends the stroke in progress and starts its fade-out timer, if any.
    func finish() {
        guard let stroke = current else { return }
        current = nil

        if stroke.tool == .rectangle {
            let rect = Self.rect(stroke.points)
            if rect.width < Self.minRectSide && rect.height < Self.minRectSide {
                stroke.shape.removeFromSuperlayer()
                return
            }
        }
        if let delay = stroke.style.fadeDelay {
            fadeOut(stroke.shape, after: delay)
        }
    }

    /// Removes every shape with a quick fade (Esc ends drawing mode).
    func clear() {
        current = nil
        guard let shapes = layer.sublayers, !shapes.isEmpty else { return }
        CATransaction.begin()
        // Remove only the shapes that existed now, in case drawing restarts mid-fade.
        CATransaction.setCompletionBlock { shapes.forEach { $0.removeFromSuperlayer() } }
        for shape in shapes {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = shape.presentation()?.opacity ?? shape.opacity
            fade.toValue = 0
            fade.duration = Self.clearDuration
            shape.removeAnimation(forKey: "fadeOut")
            shape.add(fade, forKey: "clear")
            shape.opacity = 0
        }
        CATransaction.commit()
    }

    // MARK: - Private

    private func updatePath() {
        guard let stroke = current else { return }
        switch stroke.tool {
        case .rectangle:
            let rect = Self.rect(stroke.points)
            let radius = min(6, rect.width / 2, rect.height / 2)
            stroke.shape.path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .pen:
            stroke.shape.path = Self.smoothPath(through: stroke.points)
        }
    }

    private func fadeOut(_ shape: CAShapeLayer, after delay: TimeInterval) {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.beginTime = shape.convertTime(CACurrentMediaTime(), from: nil) + delay
        fade.duration = Self.fadeDuration
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        // Hold the "from" value until the delayed fade begins.
        fade.fillMode = .backwards

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak shape] in shape?.removeFromSuperlayer() }
        shape.add(fade, forKey: "fadeOut")
        shape.opacity = 0
        CATransaction.commit()
    }

    private static func rect(_ points: [CGPoint]) -> CGRect {
        let a = points[0]
        let b = points.last ?? a
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y).standardized
    }

    /// A pen stroke through `points`, smoothed with quadratic curves through the
    /// midpoints. A single point becomes a dot (round caps on a zero-length line).
    static func smoothPath(through points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else {
            path.addLine(to: first)
            return path
        }
        for i in 1..<points.count {
            let previous = points[i - 1]
            let mid = CGPoint(x: (previous.x + points[i].x) / 2, y: (previous.y + points[i].y) / 2)
            path.addQuadCurve(to: mid, control: previous)
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    private static let noActions: [String: CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "path": NSNull(), "opacity": NSNull(),
        "fillColor": NSNull(), "strokeColor": NSNull(), "lineWidth": NSNull(), "hidden": NSNull(),
        "sublayers": NSNull(), "contents": NSNull(),
    ]
}
