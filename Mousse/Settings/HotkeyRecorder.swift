import AppKit
import Carbon.HIToolbox

/// Records a new global shortcut from the next key press in the settings window.
/// Mousse's own hotkeys are suspended meanwhile so pressing the current combination
/// records it instead of triggering it. Esc cancels.
@MainActor
final class HotkeyRecorder: ObservableObject {
    @Published private(set) var recording: HotkeyAction?
    /// Modifiers held so far, shown live while recording (Carbon flags).
    @Published private(set) var heldModifiers: UInt32 = 0
    @Published private(set) var message: String?

    private let model: AppModel
    private var monitor: Any?

    init(model: AppModel) {
        self.model = model
    }

    func start(_ action: HotkeyAction) {
        stop()
        message = nil
        recording = action
        model.suspendHotkeys()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            let (type, keyCode, flags) = (event.type, event.keyCode, event.modifierFlags)
            let consumed = MainActor.assumeIsolated {
                self?.consume(type: type, keyCode: keyCode, flags: flags) ?? false
            }
            return consumed ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        heldModifiers = 0
        guard recording != nil else { return }
        recording = nil
        model.resumeHotkeys()
    }

    func resetAll() {
        stop()
        message = nil
        model.resetHotkeys()
    }

    /// Returns true when the key press was used for recording and should be swallowed.
    private func consume(type: NSEvent.EventType, keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        guard let action = recording else { return false }
        let flags = flags.intersection([.control, .option, .shift, .command])

        if type == .flagsChanged {
            heldModifiers = Hotkey.carbonModifiers(from: flags)
            return false
        }
        if Int(keyCode) == kVK_Escape && flags.isEmpty {
            stop()
            return true
        }
        let hotkey = Hotkey(keyCode: keyCode, flags: flags)
        if let problem = model.setHotkey(hotkey, for: action) {
            message = problem
            return true
        }
        stop()  // re-registers everything, including the new shortcut
        message = model.failedHotkeys.contains(action)
            ? "다른 앱이 이미 쓰고 있어서 등록하지 못했어요 (\(hotkey.displayString))."
            : nil
        return true
    }
}
