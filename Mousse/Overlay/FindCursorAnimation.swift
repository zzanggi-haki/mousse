import QuartzCore

/// Timeline for "find my cursor": the screen dims, a spotlight closes in on the cursor,
/// a ping ripples out from it, then everything fades away. Pure math — the overlay
/// samples it once per display frame so the effect can follow a moving cursor.
struct FindCursorAnimation {
    static let duration: CFTimeInterval = 1.3

    private static let fadeInEnd: CFTimeInterval = 0.12
    private static let shrinkEnd: CFTimeInterval = 0.6
    private static let pulseEnd: CFTimeInterval = 1.05
    private static let fadeOutStart: CFTimeInterval = 0.95
    private static let pulseTravel: CGFloat = 36

    struct Frame {
        /// Radius of the clear spotlight hole and its ring.
        var spotlightRadius: CGFloat
        /// Overall visibility of the dim + ring, 0...1.
        var envelope: CGFloat
        var pulseRadius: CGFloat
        var pulseAlpha: CGFloat
    }

    let startRadius: CGFloat
    let endRadius: CGFloat

    func frame(at t: CFTimeInterval) -> Frame {
        let shrink = Self.easeOutCubic(Self.progress(t, 0, Self.shrinkEnd))
        let fadeIn = Self.progress(t, 0, Self.fadeInEnd)
        let fadeOut = Self.progress(t, Self.fadeOutStart, Self.duration)
        let pulse = Self.progress(t, Self.shrinkEnd, Self.pulseEnd)

        return Frame(
            spotlightRadius: startRadius + (endRadius - startRadius) * shrink,
            envelope: fadeIn * (1 - fadeOut * fadeOut),
            pulseRadius: endRadius + Self.pulseTravel * Self.easeOutCubic(pulse),
            pulseAlpha: pulse > 0 ? 1 - pulse : 0
        )
    }

    private static func progress(_ t: CFTimeInterval, _ start: CFTimeInterval, _ end: CFTimeInterval) -> CGFloat {
        CGFloat(((t - start) / (end - start)).clamped(to: 0...1))
    }

    private static func easeOutCubic(_ x: CGFloat) -> CGFloat {
        1 - pow(1 - x, 3)
    }
}
