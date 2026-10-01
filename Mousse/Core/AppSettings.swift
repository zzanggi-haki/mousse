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

enum HighlightColor: String, CaseIterable, Identifiable {
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

/// User-tunable preferences, persisted to UserDefaults on every change.
@MainActor
final class AppSettings: ObservableObject {
    static let sizeRange: ClosedRange<Double> = 24...160
    static let opacityRange: ClosedRange<Double> = 0.15...1

    private enum Key {
        static let style = "mousse.highlight.style"
        static let color = "mousse.highlight.color"
        static let size = "mousse.highlight.size"
        static let opacity = "mousse.highlight.opacity"
        static let dimOnFind = "mousse.find.dim"
    }

    private let defaults: UserDefaults

    @Published var highlightStyle: HighlightStyle {
        didSet { defaults.set(highlightStyle.rawValue, forKey: Key.style) }
    }
    @Published var highlightColor: HighlightColor {
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        highlightStyle = defaults.string(forKey: Key.style).flatMap(HighlightStyle.init) ?? .filled
        highlightColor = defaults.string(forKey: Key.color).flatMap(HighlightColor.init) ?? .yellow
        highlightSize = (defaults.object(forKey: Key.size) as? Double)
            .map { $0.clamped(to: Self.sizeRange) } ?? 56
        highlightOpacity = (defaults.object(forKey: Key.opacity) as? Double)
            .map { $0.clamped(to: Self.opacityRange) } ?? 0.45
        dimOnFind = defaults.object(forKey: Key.dimOnFind) as? Bool ?? true
    }

    var highlightAppearance: HighlightAppearance {
        HighlightAppearance(
            style: highlightStyle,
            color: highlightColor.nsColor,
            diameter: highlightSize,
            opacity: highlightOpacity
        )
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
