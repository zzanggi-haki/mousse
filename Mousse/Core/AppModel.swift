import AppKit
import Combine

/// Wires settings, global hotkeys and the overlay together. The menu bar UI and the
/// hotkeys both act through this one object, so they always agree on state.
@MainActor
final class AppModel: ObservableObject {
    let settings: AppSettings

    @Published var isHighlightOn = false {
        didSet { overlay.setHighlight(on: isHighlightOn) }
    }
    /// Hotkeys the system refused to register (usually already taken by another app).
    @Published private(set) var failedHotkeys: [HotkeyAction] = []

    private let overlay: OverlayController
    private var lastAppearance: HighlightAppearance
    private var cancellables: Set<AnyCancellable> = []

    init(settings: AppSettings) {
        self.settings = settings
        lastAppearance = settings.highlightAppearance
        overlay = OverlayController(
            appearance: settings.highlightAppearance,
            dimsOnFind: settings.dimOnFind
        )
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

    func hotkey(for action: HotkeyAction) -> Hotkey {
        action.defaultHotkey
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
                default: break
                }
            }
        }
    }
    #endif

    private func settingsDidChange() {
        let appearance = settings.highlightAppearance
        overlay.update(appearance: appearance, dimsOnFind: settings.dimOnFind)
        if appearance != lastAppearance {
            lastAppearance = appearance
            if !isHighlightOn { overlay.previewHighlight() }
        }
    }
}
