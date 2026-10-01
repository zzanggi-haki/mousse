import AppKit
import QuartzCore

/// A dark pill that tells the presenter which drawing tool is active. It fades in,
/// lingers briefly and fades out as one keyframe animation, so no timer is involved.
final class HintLayer: CALayer {
    private static let lifetime: CFTimeInterval = 1.8
    private static let padding = CGSize(width: 14, height: 7)

    private let textLayer = CATextLayer()

    override init() {
        super.init()
        actions = Self.noActions
        backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        opacity = 0
        isHidden = true
        textLayer.actions = Self.noActions
        addSublayer(textLayer)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setContentsScale(_ scale: CGFloat) {
        contentsScale = scale
        textLayer.contentsScale = scale
    }

    func show(_ text: NSAttributedString, centeredAt center: CGPoint) {
        let textSize = text.size()
        let size = CGSize(
            width: ceil(textSize.width) + Self.padding.width * 2,
            height: ceil(textSize.height) + Self.padding.height * 2
        )
        bounds = CGRect(origin: .zero, size: size)
        position = center
        cornerRadius = size.height / 2
        textLayer.string = text
        textLayer.frame = CGRect(
            x: Self.padding.width, y: Self.padding.height,
            width: ceil(textSize.width), height: ceil(textSize.height)
        )

        isHidden = false
        removeAnimation(forKey: "hint")
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.08, 0.8, 1]
        fade.duration = Self.lifetime
        add(fade, forKey: "hint")
        opacity = 0
    }

    func hide() {
        removeAnimation(forKey: "hint")
        isHidden = true
    }

    /// "사각형 그리기   R 사각형 · P 펜 · Esc 끝" with the active tool emphasised.
    static func text(for tool: DrawTool) -> NSAttributedString {
        let strong: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let soft: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.65),
        ]
        let keys = DrawTool.allCases.map { "\($0.key) \($0.label)" } + ["Esc 끝"]
        let text = NSMutableAttributedString(string: "\(tool.label) 그리기", attributes: strong)
        text.append(NSAttributedString(string: "    " + keys.joined(separator: " · "), attributes: soft))
        return text
    }

    private static let noActions: [String: CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "opacity": NSNull(), "hidden": NSNull(),
        "contents": NSNull(), "string": NSNull(), "frame": NSNull(), "cornerRadius": NSNull(),
    ]
}

/// Cursors for drawing mode: a crosshair for rectangles, a dot the size and color of
/// the pen for freehand strokes.
@MainActor
enum DrawingCursor {
    /// The pen cursor is re-applied on every mouse move, so keep the last one built.
    private static var cachedPen: (color: NSColor, width: CGFloat, cursor: NSCursor)?

    static func cursor(for input: OverlayView.DrawingInput) -> NSCursor {
        switch input.tool {
        case .rectangle:
            return .crosshair
        case .pen:
            let color = input.style.lineColor, width = input.style.lineWidth
            if let cached = cachedPen, cached.color == color, cached.width == width {
                return cached.cursor
            }
            let cursor = penCursor(color: color, width: width)
            cachedPen = (color, width, cursor)
            return cursor
        }
    }

    private static func penCursor(color: NSColor, width: CGFloat) -> NSCursor {
        let dot = max(width, 6)
        let side = ceil(dot + 4)
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: (side - dot) / 2, dy: (side - dot) / 2))
            color.setFill()
            circle.fill()
            // A thin white edge keeps the dot visible on any background.
            NSColor.white.withAlphaComponent(0.9).setStroke()
            circle.lineWidth = 1.5
            circle.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: side / 2, y: side / 2))
    }
}
