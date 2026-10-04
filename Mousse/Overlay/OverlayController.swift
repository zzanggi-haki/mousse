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

    private struct DrawingSession {
        var tool: DrawTool
        var style: DrawingStyle
        /// False only for the Debug demo, which draws without capturing input.
        var interactive: Bool
        /// Re-activated when drawing ends, so the presenter's app gets focus back.
        var previousApp: NSRunningApplication?
    }
    private var drawing: DrawingSession?

    /// Key presses on the overlay while drawing mode is on.
    var onDrawingKey: ((UInt16) -> Void)?
    /// Drawing mode lost focus to another app (e.g. ⌘-Tab) and should end.
    var onDrawingInterrupted: (() -> Void)?

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var resignActiveObserver: NSObjectProtocol?

    private var highlightVisible: Bool { highlightOn || previewing }
    private var needsOverlay: Bool { highlightVisible || findAnimation != nil || drawing != nil }

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
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.drawing?.interactive == true else { return }
                self.onDrawingInterrupted?()
            }
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
        // Slider drags call this every tick; only the first one needs to show the overlay.
        if !previewing {
            previewing = true
            refresh(animated: false)
        }

        previewWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.previewing = false
            self.refresh(animated: true)
        }
        previewWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.previewDuration, execute: work)
    }

    func update(appearance: HighlightAppearance, dimsOnFind: Bool, drawingStyle: DrawingStyle) {
        self.appearance = appearance
        self.findColor = appearance.color
        self.dimsOnFind = dimsOnFind
        windows.forEach { $0.overlayView.applyHighlight(appearance) }
        if drawing != nil, drawing?.style != drawingStyle {
            drawing?.style = drawingStyle
            applyDrawingInput()
        }
    }

    // MARK: - Drawing mode

    /// Covers every screen with a drawing surface. Mousse becomes the active app so the
    /// overlay gets key presses and its cursor; the previous app is re-activated on stop.
    func startDrawing(tool: DrawTool, style: DrawingStyle, interactive: Bool = true) {
        if interactive, drawing?.interactive == false { stopDrawing() }  // replaces the Debug demo
        guard drawing == nil else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication
        drawing = DrawingSession(
            tool: tool,
            style: style,
            interactive: interactive,
            previousApp: interactive && frontmost != .current ? frontmost : nil
        )
        applyDrawingInput()
        refresh(animated: false)

        if interactive {
            NSApp.activate()
            focusDrawingWindow()
            applyCursorSoon()
        }
        showDrawingHint()
    }

    /// Ends drawing mode and erases everything drawn in it.
    func stopDrawing() {
        guard let session = drawing else { return }
        drawing = nil
        applyDrawingInput()
        windows.forEach {
            $0.overlayView.clearDrawings()
            $0.overlayView.hideHint()
        }
        if session.interactive {
            NSCursor.arrow.set()
            if let app = session.previousApp, !app.isTerminated {
                _ = app.activate(options: [])
            } else {
                NSApp.deactivate()
            }
        }
        refresh(animated: true)
    }

    func setDrawingTool(_ tool: DrawTool) {
        guard drawing != nil, drawing?.tool != tool else { return }
        drawing?.tool = tool
        applyDrawingInput()
        applyCursorSoon()
        showDrawingHint()
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
            for window in windows where !window.isVisible { window.orderFrontRegardless() }
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
        // The display link belongs to a view that is about to go away; a stale link
        // would stop firing and leave the find animation (and the overlay) stuck.
        displayLink?.invalidate()
        displayLink = nil
        windows.forEach { $0.orderOut(nil); $0.close() }
        windows = NSScreen.screens.map { screen in
            let window = OverlayWindow(screen: screen)
            window.overlayView.applyHighlight(appearance)
            window.overlayView.onKeyDown = { [weak self] keyCode in self?.onDrawingKey?(keyCode) }
            return window
        }
        applyDrawingInput()
        if needsOverlay {
            refresh(animated: false)
        }
        if findAnimation != nil { startDisplayLink() }
        if drawing?.interactive == true { focusDrawingWindow() }
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    private func window(containing point: CGPoint) -> OverlayWindow? {
        windows.first { NSMouseInRect(point, $0.frame, false) }
    }

    // MARK: - Drawing helpers

    /// Makes the overlay under the cursor key so R/P reach it.
    private func focusDrawingWindow() {
        let target = window(containing: NSEvent.mouseLocation) ?? windows.first
        target?.makeKey()
        target?.makeFirstResponder(target?.overlayView)
    }

    private func applyDrawingInput() {
        let input = drawing.map { OverlayView.DrawingInput(tool: $0.tool, style: $0.style) }
        for window in windows {
            window.capturesInput = drawing?.interactive ?? false
            window.overlayView.drawingInput = input
        }
    }

    private func showDrawingHint() {
        guard let tool = drawing?.tool else { return }
        let mouse = NSEvent.mouseLocation
        let text = HintLayer.text(for: tool)
        for window in windows {
            if NSMouseInRect(mouse, window.frame, false) {
                window.overlayView.showHint(text)
            } else {
                window.overlayView.hideHint()
            }
        }
    }

    /// Sets the tool cursor now and again once activation has settled, since becoming
    /// the active app can reset the cursor (same trick as ZoomIt's crosshair lease).
    private func applyCursorSoon() {
        applyDrawingCursor()
        for delay in [0.05, 0.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.applyDrawingCursor()
            }
        }
    }

    private func applyDrawingCursor() {
        guard let drawing, drawing.interactive else { return }
        DrawingCursor.cursor(for: .init(tool: drawing.tool, style: drawing.style)).set()
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
            MainActor.assumeIsolated {
                self?.positionHighlight(at: NSEvent.mouseLocation)
                // Cursor rects only cover the key overlay; keep the tool cursor on the
                // other screens too.
                self?.applyDrawingCursor()
            }
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

    #if DEBUG
    /// Debug builds only: replays a drag on the screen under the cursor through the real
    /// mouse handlers, without touching the user's mouse. Points are fractions of the screen.
    func debugStroke(_ tool: DrawTool, through fractions: [CGPoint]) {
        guard drawing != nil, let window = window(containing: NSEvent.mouseLocation) ?? windows.first,
              let first = fractions.first else { return }
        setDrawingTool(tool)
        let view = window.overlayView
        func event(_ type: NSEvent.EventType, _ f: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(
                with: type,
                location: CGPoint(x: view.bounds.width * f.x, y: view.bounds.height * f.y),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            )!
        }
        view.mouseDown(with: event(.leftMouseDown, first))
        fractions.dropFirst().forEach { view.mouseDragged(with: event(.leftMouseDragged, $0)) }
        view.mouseUp(with: event(.leftMouseUp, fractions.last!))
    }
    #endif

    // MARK: - Find-cursor animation

    private func startDisplayLink() {
        guard displayLink == nil,
              let view = (window(containing: NSEvent.mouseLocation) ?? windows.first)?.overlayView else { return }
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
