import AppKit
import Carbon.HIToolbox

/// A global key combination: a virtual key code plus Carbon modifier flags.
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

    /// Display form in Apple's canonical modifier order, e.g. "⌃⌥H".
    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + Self.keyName(for: Int(keyCode))
    }

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
            kVK_Space: "Space", kVK_Return: "↩", kVK_Escape: "⎋", kVK_Tab: "⇥",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        ]
        return names[keyCode] ?? "#\(keyCode)"
    }
}

/// The actions Mousse exposes as global shortcuts.
enum HotkeyAction: UInt32, CaseIterable {
    case toggleHighlight = 1
    case findCursor = 2

    var label: String {
        switch self {
        case .toggleHighlight: return "커서 강조"
        case .findCursor: return "위치 찾기"
        }
    }

    /// ⌃⌥ + letter, picked to stay clear of Magnet/Rectangle's ⌃⌥ window-snapping keys
    /// (arrows, C, D–G, E, T, U, I, J, K, Return).
    var defaultHotkey: Hotkey {
        switch self {
        case .toggleHighlight: return .control(kVK_ANSI_H, option: true)
        case .findCursor: return .control(kVK_ANSI_L, option: true)
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
