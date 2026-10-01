import AppKit
import Carbon.HIToolbox

/// A global key combination: a virtual key code plus Carbon modifier flags.
/// Key codes are physical positions, so shortcuts work the same under the Korean
/// input source.
struct Hotkey: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static func control(_ keyCode: Int, option: Bool = false, shift: Bool = false, command: Bool = false) -> Hotkey {
        var mods = UInt32(controlKey)
        if option { mods |= UInt32(optionKey) }
        if shift { mods |= UInt32(shiftKey) }
        if command { mods |= UInt32(cmdKey) }
        return Hotkey(keyCode: UInt32(keyCode), modifiers: mods)
    }

    /// A shortcut from a recorded key press (AppKit modifier flags → Carbon).
    init(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        self.init(keyCode: UInt32(keyCode), modifiers: Self.carbonModifiers(from: flags))
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        return mods
    }

    /// Global shortcuts need ⌃, ⌥ or ⌘ so they don't swallow ordinary typing;
    /// function keys are the exception.
    var isUsableGlobally: Bool {
        let anchors = UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey)
        return modifiers & anchors != 0 || Self.functionKeys.contains(Int(keyCode))
    }

    /// Display form in Apple's canonical modifier order, e.g. "⌃⌥H".
    var displayString: String {
        Self.modifierSymbols(modifiers) + Self.keyName(for: Int(keyCode))
    }

    static func modifierSymbols(_ modifiers: UInt32) -> String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s
    }

    private static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    private static func keyName(for keyCode: Int) -> String {
        let names: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
            kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
            kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
            kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
            kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
            kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
            kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
            kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Escape: "⎋", kVK_Tab: "⇥",
            kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘",
            kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
            kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        ]
        return names[keyCode] ?? "#\(keyCode)"
    }
}

/// The actions Mousse exposes as global shortcuts.
enum HotkeyAction: UInt32, CaseIterable, Identifiable {
    case toggleHighlight = 1
    case findCursor = 2
    case toggleDrawing = 3

    var id: UInt32 { rawValue }

    var label: String {
        switch self {
        case .toggleHighlight: return "커서 강조"
        case .findCursor: return "위치 찾기"
        case .toggleDrawing: return "그리기 모드"
        }
    }

    /// ⌃⌥ + letter, picked to stay clear of Magnet/Rectangle's ⌃⌥ window-snapping keys
    /// (arrows, C, D–G, E, T, U, I, J, K, Return).
    var defaultHotkey: Hotkey {
        switch self {
        case .toggleHighlight: return .control(kVK_ANSI_H, option: true)
        case .findCursor: return .control(kVK_ANSI_L, option: true)
        case .toggleDrawing: return .control(kVK_ANSI_A, option: true)
        }
    }
}

/// Registers system-wide hotkeys through Carbon's `RegisterEventHotKey`, which needs no
/// Accessibility or Input Monitoring permission. Delivers both press and release so
/// hold-to-use actions can be built on it.
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    struct Handlers {
        var onPress: @MainActor () -> Void
        var onRelease: (@MainActor () -> Void)?
    }

    private static let signature: OSType = 0x4D53_5345  // 'MSSE'

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: Handlers] = [:]
    private var eventHandler: EventHandlerRef?

    private init() {}

    /// Returns false if the system refused the combination (e.g. another app owns it).
    @discardableResult
    func register(id: UInt32, hotkey: Hotkey, handlers: Handlers) -> Bool {
        installEventHandlerIfNeeded()
        unregister(id: id)

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            hotkey.keyCode, hotkey.modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref
        )
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        self.handlers[id] = handlers
        return true
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        handlers.removeValue(forKey: id)
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == HotkeyCenter.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                let isPress = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                HotkeyCenter.shared.dispatch(id: hotKeyID.id, isPress: isPress)
                return noErr
            },
            specs.count,
            &specs,
            nil,
            &eventHandler
        )
    }

    private func dispatch(id: UInt32, isPress: Bool) {
        guard let entry = handlers[id] else { return }
        // Carbon delivers hotkey events on the main event loop.
        MainActor.assumeIsolated {
            if isPress {
                entry.onPress()
            } else {
                entry.onRelease?()
            }
        }
    }
}
