import AppKit
import QuartzCore

/// Owns one overlay window per screen and drives the on-screen effects. Overlays are
/// ordered out and mouse tracking is stopped whenever nothing is being drawn, so an
/// idle Mousse costs nothing.
@MainActor
final class OverlayController: NSObject {
    private static let previewDuration: TimeInterval = 1.2
    private static let fadeOutDelay: TimeInterval = 0.2

    private var windows: [OverlayWindow] = []
    private var appearance: HighlightAppearance
    private var findColor: NSColor
    private var dimsOnFind = true

    private var highlightOn = false
    private var previewing = false
    private var previewWorkItem: DispatchWorkItem?
    private var orderOutWorkItem: DispatchWorkItem?

    private var findAnimation: FindCursorAnimation?
    private var findStartTime: CFTimeInterval = 0
    private var displayLink: CADisplayLink?

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var screenObserver: NSObjectProtocol?

    private var highlightVisible: Bool { highlightOn || previewing }
    private var needsOverlay: Bool { highlightVisible || findAnimation != nil }

    init(appearance: HighlightAppearance, dimsOnFind: Bool) {
        self.appearance = appearance
        self.findColor = appearance.color
        self.dimsOnFind = dimsOnFind
        super.init()
        rebuildWindows()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildWindows() }
        }
    }

    // MARK: - Public API

    func setHighlight(on: Bool) {
        guard on != highlightOn else { return }
        highlightOn = on
        if on { cancelPreview() }
        refresh(animated: true)
    }

    /// Briefly shows the highlight at the cursor so appearance changes can be seen
    /// while the highlight itself is off.
    func previewHighlight() {
        guard !highlightOn else { return }
        previewing = true
        refresh(animated: false)

        previewWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.previewing = false
            self.refresh(animated: true)
        }
        previewWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.previewDuration, execute: work)
    }

    func update(appearance: HighlightAppearance, dimsOnFind: Bool) {
        self.appearance = appearance
        self.findColor = appearance.color
        self.dimsOnFind = dimsOnFind
        windows.forEach { $0.overlayView.applyHighlight(appearance) }
    }

    func findCursor() {
        let mouse = NSEvent.mouseLocation
        let screenSize = (screen(containing: mouse) ?? NSScreen.main)?.frame.size ?? CGSize(width: 1440, height: 900)
        let startRadius = (min(screenSize.width, screenSize.height) * 0.5).clamped(to: 320...640)
        let endRadius = max(appearance.diameter / 2 + 18, 44)

        findAnimation = FindCursorAnimation(startRadius: startRadius, endRadius: endRadius)
        findStartTime = CACurrentMediaTime()
        refresh(animated: false)
        startDisplayLink()
        renderFindFrame()
    }

    // MARK: - State → windows

    private func refresh(animated: Bool) {
        if needsOverlay {
            orderOutWorkItem?.cancel()
            orderOutWorkItem = nil
            windows.forEach { $0.orderFrontRegardless() }
            startMouseTracking()
            positionHighlight(at: NSEvent.mouseLocation)
        } else {
            stopMouseTracking()
            scheduleOrderOut()
        }
        windows.forEach { $0.overlayView.setHighlightVisible(highlightVisible, animated: animated) }
    }

    private func scheduleOrderOut() {
        orderOutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.needsOverlay else { return }
            self.windows.forEach { $0.orderOut(nil) }
        }
        orderOutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeOutDelay, execute: work)
    }

    private func cancelPreview() {
        previewWorkItem?.cancel()
        previewWorkItem = nil
        previewing = false
    }

    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil); $0.close() }
        windows = NSScreen.screens.map { screen in
            let window = OverlayWindow(screen: screen)
            window.overlayView.applyHighlight(appearance)
            return window
        }
        if needsOverlay {
            refresh(animated: false)
        }
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    // MARK: - Mouse tracking

    private func startMouseTracking() {
        guard globalMouseMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        // Mouse-move monitoring needs no special permission (unlike key events).
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.positionHighlight(at: NSEvent.mouseLocation) }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.positionHighlight(at: NSEvent.mouseLocation) }
            return event
        }
    }

    private func stopMouseTracking() {
        if let monitor = globalMouseMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMouseMonitor { NSEvent.removeMonitor(monitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
    }

    private func positionHighlight(at globalPoint: CGPoint) {
        for window in windows {
            window.overlayView.moveHighlight(to: window.localPoint(fromGlobal: globalPoint))
        }
    }

    // MARK: - Find-cursor animation

    private func startDisplayLink() {
        guard displayLink == nil, let view = windows.first?.overlayView else { return }
        let link = view.displayLink(target: self, selector: #selector(displayLinkFired(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        renderFindFrame()
    }

    private func renderFindFrame() {
        guard let animation = findAnimation else { return }
        let t = CACurrentMediaTime() - findStartTime

        guard t < FindCursorAnimation.duration else {
            findAnimation = nil
            displayLink?.invalidate()
            displayLink = nil
            windows.forEach { $0.overlayView.renderFind(nil) }
            refresh(animated: false)
            return
        }

        let mouse = NSEvent.mouseLocation
        let frame = animation.frame(at: t)
        for window in windows {
            let containsCursor = NSMouseInRect(mouse, window.frame, false)
            window.overlayView.renderFind(OverlayView.FindRender(
                center: containsCursor ? window.localPoint(fromGlobal: mouse) : nil,
                frame: frame,
                dimsScreen: dimsOnFind,
                color: findColor
            ))
        }
        positionHighlight(at: mouse)
    }
}
