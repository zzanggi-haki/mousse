import AppKit
import Carbon.HIToolbox
import Combine

/// Wires settings, global hotkeys and the overlay together. The menu bar UI and the
/// hotkeys both act through this one object, so they always agree on state.
@MainActor
final class AppModel: ObservableObject {
    let settings: AppSettings

    @Published var isHighlightOn = false {
        didSet { overlay.setHighlight(on: isHighlightOn) }
    }
    @Published private(set) var isDrawing = false
    /// Hotkeys the system refused to register (usually already taken by another app).
    @Published private(set) var failedHotkeys: [HotkeyAction] = []
    /// Asks the menu bar popover to close (drawing or the settings window takes over).
    let menuDismissRequests = PassthroughSubject<Void, Never>()

    /// Esc ends drawing mode. It is a global hotkey only while drawing, so it works even
    /// if Mousse couldn't take focus, and never steals Esc from other apps otherwise.
    private static let drawingEscapeID: UInt32 = 100

    private let overlay: OverlayController
    private lazy var settingsWindow = SettingsWindowController(model: self)
    private var lastAppearance: HighlightAppearance
    private var hotkeysSuspended = false
    private var escapeRegistered = false
    private var cancellables: Set<AnyCancellable> = []

    init(settings: AppSettings) {
        self.settings = settings
        lastAppearance = settings.highlightAppearance
        overlay = OverlayController(
            appearance: settings.highlightAppearance,
            dimsOnFind: settings.dimOnFind
        )
        overlay.onDrawingKey = { [weak self] keyCode in self?.handleDrawingKey(keyCode) }
        overlay.onDrawingInterrupted = { [weak self] in self?.stopDrawing() }
        registerHotkeys()
        observeSettings()
        #if DEBUG
        installDebugTrigger()
        #endif
    }

    func toggleHighlight() {
        isHighlightOn.toggle()
    }

    func findCursor() {
        overlay.findCursor()
    }

    // MARK: - Drawing mode

    func toggleDrawing() {
        isDrawing ? stopDrawing() : startDrawing()
    }

    func startDrawing() {
        guard !isDrawing else { return }
        isDrawing = true
        menuDismissRequests.send()
        escapeRegistered = HotkeyCenter.shared.register(
            id: Self.drawingEscapeID,
            hotkey: Hotkey(keyCode: UInt32(kVK_Escape), modifiers: 0),
            handlers: .init(onPress: { [weak self] in self?.stopDrawing() })
        )
        overlay.startDrawing(tool: settings.drawTool, style: settings.drawingStyle)
    }

    func stopDrawing() {
        guard isDrawing else { return }
        isDrawing = false
        HotkeyCenter.shared.unregister(id: Self.drawingEscapeID)
        escapeRegistered = false
        overlay.stopDrawing()
    }

    func selectDrawTool(_ tool: DrawTool) {
        settings.drawTool = tool
        overlay.setDrawingTool(tool)
    }

    private func handleDrawingKey(_ keyCode: UInt16) {
        switch Int(keyCode) {
        case kVK_ANSI_R: selectDrawTool(.rectangle)
        case kVK_ANSI_P: selectDrawTool(.pen)
        case kVK_Escape: stopDrawing()
        default: break
        }
    }

    // MARK: - Settings window

    func openSettings() {
        menuDismissRequests.send()
        settingsWindow.show()
    }

    // MARK: - Hotkeys

    func hotkey(for action: HotkeyAction) -> Hotkey {
        settings.hotkey(for: action)
    }

    /// Assigns a new shortcut. Returns a message to show instead when it can't be used.
    func setHotkey(_ hotkey: Hotkey, for action: HotkeyAction) -> String? {
        guard hotkey.isUsableGlobally else {
            return "⌃·⌥·⌘ 중 하나 이상을 같이 눌러 주세요."
        }
        if let other = HotkeyAction.allCases.first(where: { $0 != action && self.hotkey(for: $0) == hotkey }) {
            return "'\(other.label)'에서 이미 쓰는 조합이에요 (\(hotkey.displayString))."
        }
        settings.setHotkey(hotkey, for: action)
        if !hotkeysSuspended { registerHotkeys() }
        return nil
    }

    func resetHotkeys() {
        HotkeyAction.allCases.forEach { settings.setHotkey(nil, for: $0) }
        if !hotkeysSuspended { registerHotkeys() }
    }

    /// While a shortcut is being recorded, Mousse's own hotkeys are released so the
    /// recorder sees the key press instead of the action firing.
    func suspendHotkeys() {
        guard !hotkeysSuspended else { return }
        hotkeysSuspended = true
        HotkeyAction.allCases.forEach { HotkeyCenter.shared.unregister(id: $0.rawValue) }
    }

    func resumeHotkeys() {
        guard hotkeysSuspended else { return }
        hotkeysSuspended = false
        registerHotkeys()
    }

    private func registerHotkeys() {
        var failed: [HotkeyAction] = []
        for action in HotkeyAction.allCases {
            let ok = HotkeyCenter.shared.register(
                id: action.rawValue,
                hotkey: hotkey(for: action),
                handlers: .init(onPress: { [weak self] in self?.perform(action) })
            )
            if !ok { failed.append(action) }
        }
        failedHotkeys = failed
    }

    private func perform(_ action: HotkeyAction) {
        switch action {
        case .toggleHighlight: toggleHighlight()
        case .findCursor: findCursor()
        case .toggleDrawing: toggleDrawing()
        }
    }

    private func observeSettings() {
        // objectWillChange fires before the new value lands; hop to the main queue
        // (which also runs during slider drags) to read the updated settings.
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.settingsDidChange() }
            .store(in: &cancellables)
    }

    #if DEBUG
    /// Debug builds only: lets scripts drive the overlay without touching the user's
    /// keyboard or mouse, e.g. `swift scripts/debug_trigger.swift find`.
    private func installDebugTrigger() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.zzanggi.mousse.debug"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let command = note.object as? String else { return }
                switch command {
                case "highlightOn": self.isHighlightOn = true
                case "highlightOff": self.isHighlightOn = false
                case "find": self.findCursor()
                case "menuShow": DebugSnapshot.showMenu(model: self)
                case "menuHide": DebugSnapshot.hideMenu()
                case "drawOn": self.startDrawing()
                case "drawOff": self.stopDrawing()
                case "drawRect": self.selectDrawTool(.rectangle)
                case "drawPen": self.selectDrawTool(.pen)
                case "drawDemo": self.runDrawingDemo()
                case "settingsHide": self.settingsWindow.debugHide()
                default:
                    if command.hasPrefix("dump:") {
                        self.dumpState(to: String(command.dropFirst("dump:".count)))
                    } else if command.hasPrefix("settingsShow") {
                        let tab = Int(command.split(separator: ":").last ?? "") ?? 0
                        self.settingsWindow.debugShowBehind(tabIndex: tab)
                    }
                }
            }
        }
    }

    /// Writes the state a script can't see from outside (e.g. `dump:/tmp/mousse.txt`).
    private func dumpState(to path: String) {
        let lines = [
            "isDrawing=\(isDrawing)",
            "escapeRegistered=\(escapeRegistered)",
            "drawTool=\(settings.drawTool.rawValue)",
            "isActive=\(NSApp.isActive)",
            "keyWindow=\(NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "nil")",
            "frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil")",
            "failedHotkeys=\(failedHotkeys.map(\.label))",
            "hotkeys=\(HotkeyAction.allCases.map { "\($0.label):\(hotkey(for: $0).displayString)" })",
        ]
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Draws a rectangle and a pen stroke on the screen under the cursor through the real
    /// mouse handlers, but without capturing input or taking focus, then lets them fade.
    private func runDrawingDemo() {
        guard !isDrawing else { return }
        overlay.stopDrawing()
        overlay.startDrawing(tool: .rectangle, style: settings.drawingStyle, interactive: false)
        overlay.debugStroke(.rectangle, through: [CGPoint(x: 0.18, y: 0.62), CGPoint(x: 0.46, y: 0.82)])
        let squiggle = (0...40).map { i -> CGPoint in
            let t = CGFloat(i) / 40
            return CGPoint(x: 0.55 + 0.3 * t, y: 0.7 + 0.06 * sin(t * .pi * 3))
        }
        overlay.debugStroke(.pen, through: squiggle)
        let linger = (settings.drawAutoFade ? settings.drawFadeDelay : 3) + 1.5
        DispatchQueue.main.asyncAfter(deadline: .now() + linger) { [weak self] in
            guard let self, !self.isDrawing else { return }
            self.overlay.stopDrawing()
        }
    }
    #endif

    private func settingsDidChange() {
        let appearance = settings.highlightAppearance
        overlay.update(appearance: appearance, dimsOnFind: settings.dimOnFind, drawingStyle: settings.drawingStyle)
        if appearance != lastAppearance {
            lastAppearance = appearance
            if !isHighlightOn { overlay.previewHighlight() }
        }
    }
}
