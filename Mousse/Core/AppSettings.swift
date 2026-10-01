import AppKit

enum HighlightStyle: String, CaseIterable, Identifiable {
    case filled
    case ring

    var id: String { rawValue }

    var label: String {
        switch self {
        case .filled: return "채움"
        case .ring: return "링"
        }
    }
}

/// The preset colors offered by every swatch picker (highlight, pen, rectangle fill).
enum PaletteColor: String, CaseIterable, Identifiable {
    case yellow, orange, red, purple, blue, green

    var id: String { rawValue }

    var label: String {
        switch self {
        case .yellow: return "노랑"
        case .orange: return "주황"
        case .red: return "빨강"
        case .purple: return "보라"
        case .blue: return "파랑"
        case .green: return "초록"
        }
    }

    var nsColor: NSColor {
        switch self {
        case .yellow: return NSColor(srgbRed: 1.00, green: 0.84, blue: 0.04, alpha: 1)
        case .orange: return NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1)
        case .red: return NSColor(srgbRed: 1.00, green: 0.27, blue: 0.23, alpha: 1)
        case .purple: return NSColor(srgbRed: 0.75, green: 0.35, blue: 0.95, alpha: 1)
        case .blue: return NSColor(srgbRed: 0.04, green: 0.52, blue: 1.00, alpha: 1)
        case .green: return NSColor(srgbRed: 0.19, green: 0.82, blue: 0.35, alpha: 1)
        }
    }
}

/// Everything the overlay needs to draw the cursor highlight, captured as a value so
/// the overlay never reads settings directly.
struct HighlightAppearance: Equatable {
    var style: HighlightStyle
    var color: NSColor
    var diameter: CGFloat
    var opacity: CGFloat

    var ringWidth: CGFloat { max(3, diameter * 0.07) }
}

/// The tools available inside drawing mode, each switched to with a single key.
enum DrawTool: String, CaseIterable, Identifiable {
    case rectangle
    case pen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rectangle: return "사각형"
        case .pen: return "펜"
        }
    }

    /// The key that selects this tool while drawing mode is on.
    var key: String {
        switch self {
        case .rectangle: return "R"
        case .pen: return "P"
        }
    }
}

/// How drawn shapes look and how long they stay, captured as a value for the overlay.
struct DrawingStyle: Equatable {
    var lineColor: NSColor
    /// Rectangle fill with its opacity already applied; nil when the fill is off.
    var fillColor: NSColor?
    var lineWidth: CGFloat
    /// Seconds a finished shape stays before fading out; nil keeps it until Esc.
    var fadeDelay: TimeInterval?
}

/// User-tunable preferences, persisted to UserDefaults on every change.
@MainActor
final class AppSettings: ObservableObject {
    static let sizeRange: ClosedRange<Double> = 24...160
    static let opacityRange: ClosedRange<Double> = 0.15...1
    static let lineWidthRange: ClosedRange<Double> = 2...12
    static let fillOpacityRange: ClosedRange<Double> = 0...0.6
    static let fadeDelayRange: ClosedRange<Double> = 1...10

    private enum Key {
        static let style = "mousse.highlight.style"
        static let color = "mousse.highlight.color"
        static let size = "mousse.highlight.size"
        static let opacity = "mousse.highlight.opacity"
        static let dimOnFind = "mousse.find.dim"
        static let drawTool = "mousse.draw.tool"
        static let drawLineColor = "mousse.draw.lineColor"
        static let drawLineWidth = "mousse.draw.lineWidth"
        static let drawFillColor = "mousse.draw.fillColor"
        static let drawFillOpacity = "mousse.draw.fillOpacity"
        static let drawAutoFade = "mousse.draw.autoFade"
        static let drawFadeDelay = "mousse.draw.fadeDelay"

        static func hotkey(_ action: HotkeyAction) -> String { "mousse.hotkey.\(action.rawValue)" }
    }

    private let defaults: UserDefaults

    @Published var highlightStyle: HighlightStyle {
        didSet { defaults.set(highlightStyle.rawValue, forKey: Key.style) }
    }
    @Published var highlightColor: PaletteColor {
        didSet { defaults.set(highlightColor.rawValue, forKey: Key.color) }
    }
    /// Diameter in points.
    @Published var highlightSize: Double {
        didSet { defaults.set(highlightSize, forKey: Key.size) }
    }
    @Published var highlightOpacity: Double {
        didSet { defaults.set(highlightOpacity, forKey: Key.opacity) }
    }
    /// Whether "find cursor" dims the rest of the screen around the spotlight.
    @Published var dimOnFind: Bool {
        didSet { defaults.set(dimOnFind, forKey: Key.dimOnFind) }
    }

    /// The tool drawing mode starts with: whichever was used last.
    @Published var drawTool: DrawTool {
        didSet { defaults.set(drawTool.rawValue, forKey: Key.drawTool) }
    }
    /// Pen strokes and rectangle outlines.
    @Published var drawLineColor: PaletteColor {
        didSet { defaults.set(drawLineColor.rawValue, forKey: Key.drawLineColor) }
    }
    @Published var drawLineWidth: Double {
        didSet { defaults.set(drawLineWidth, forKey: Key.drawLineWidth) }
    }
    @Published var drawFillColor: PaletteColor {
        didSet { defaults.set(drawFillColor.rawValue, forKey: Key.drawFillColor) }
    }
    /// 0 turns the rectangle fill off.
    @Published var drawFillOpacity: Double {
        didSet { defaults.set(drawFillOpacity, forKey: Key.drawFillOpacity) }
    }
    @Published var drawAutoFade: Bool {
        didSet { defaults.set(drawAutoFade, forKey: Key.drawAutoFade) }
    }
    @Published var drawFadeDelay: Double {
        didSet { defaults.set(drawFadeDelay, forKey: Key.drawFadeDelay) }
    }

    /// User-chosen shortcuts; actions missing here use their default.
    @Published private(set) var customHotkeys: [HotkeyAction: Hotkey]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        highlightStyle = defaults.string(forKey: Key.style).flatMap(HighlightStyle.init) ?? .filled
        highlightColor = defaults.string(forKey: Key.color).flatMap(PaletteColor.init) ?? .yellow
        highlightSize = (defaults.object(forKey: Key.size) as? Double)
            .map { $0.clamped(to: Self.sizeRange) } ?? 56
        highlightOpacity = (defaults.object(forKey: Key.opacity) as? Double)
            .map { $0.clamped(to: Self.opacityRange) } ?? 0.45
        dimOnFind = defaults.object(forKey: Key.dimOnFind) as? Bool ?? true

        drawTool = defaults.string(forKey: Key.drawTool).flatMap(DrawTool.init) ?? .rectangle
        drawLineColor = defaults.string(forKey: Key.drawLineColor).flatMap(PaletteColor.init) ?? .red
        drawLineWidth = (defaults.object(forKey: Key.drawLineWidth) as? Double)
            .map { $0.clamped(to: Self.lineWidthRange) } ?? 4
        drawFillColor = defaults.string(forKey: Key.drawFillColor).flatMap(PaletteColor.init) ?? .yellow
        drawFillOpacity = (defaults.object(forKey: Key.drawFillOpacity) as? Double)
            .map { $0.clamped(to: Self.fillOpacityRange) } ?? 0.2
        drawAutoFade = defaults.object(forKey: Key.drawAutoFade) as? Bool ?? true
        drawFadeDelay = (defaults.object(forKey: Key.drawFadeDelay) as? Double)
            .map { $0.clamped(to: Self.fadeDelayRange) } ?? 3

        var hotkeys: [HotkeyAction: Hotkey] = [:]
        for action in HotkeyAction.allCases {
            if let stored = defaults.array(forKey: Key.hotkey(action)) as? [Int], stored.count == 2 {
                hotkeys[action] = Hotkey(keyCode: UInt32(stored[0]), modifiers: UInt32(stored[1]))
            }
        }
        customHotkeys = hotkeys
    }

    var highlightAppearance: HighlightAppearance {
        HighlightAppearance(
            style: highlightStyle,
            color: highlightColor.nsColor,
            diameter: highlightSize,
            opacity: highlightOpacity
        )
    }

    var drawingStyle: DrawingStyle {
        DrawingStyle(
            lineColor: drawLineColor.nsColor,
            fillColor: drawFillOpacity > 0.005 ? drawFillColor.nsColor.withAlphaComponent(drawFillOpacity) : nil,
            lineWidth: drawLineWidth,
            fadeDelay: drawAutoFade ? drawFadeDelay : nil
        )
    }

    func hotkey(for action: HotkeyAction) -> Hotkey {
        customHotkeys[action] ?? action.defaultHotkey
    }

    /// Stores a shortcut for `action`; nil restores its default.
    func setHotkey(_ hotkey: Hotkey?, for action: HotkeyAction) {
        if let hotkey, hotkey != action.defaultHotkey {
            customHotkeys[action] = hotkey
            defaults.set([Int(hotkey.keyCode), Int(hotkey.modifiers)], forKey: Key.hotkey(action))
        } else {
            customHotkeys[action] = nil
            defaults.removeObject(forKey: Key.hotkey(action))
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
