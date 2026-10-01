import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case cursor, drawing, shortcuts, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cursor: return "커서"
        case .drawing: return "그리기"
        case .shortcuts: return "단축키"
        case .general: return "일반"
        }
    }

    var symbol: String {
        switch self {
        case .cursor: return "cursorarrow.rays"
        case .drawing: return "pencil.and.outline"
        case .shortcuts: return "command"
        case .general: return "gearshape"
        }
    }
}

/// Shared between the toolbar (AppKit) and the tab content (SwiftUI).
@MainActor
final class SettingsSelection: ObservableObject {
    @Published var tab: SettingsTab = .cursor
}

/// A classic preferences window: toolbar tabs on top, SwiftUI content below. The window
/// resizes to each tab's content. Owned by AppModel and reused across openings.
@MainActor
final class SettingsWindowController: NSObject, NSToolbarDelegate, NSWindowDelegate {
    private let model: AppModel
    private let selection = SettingsSelection()
    private let recorder: HotkeyRecorder
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
        recorder = HotkeyRecorder(model: model)
        super.init()
    }

    func show() {
        let window = makeWindowIfNeeded()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    #if DEBUG
    /// Debug builds only: shows the window behind every other window, without taking
    /// focus, so scripts can capture it with `screencapture -l <windowID>`.
    func debugShowBehind(tabIndex: Int) {
        let window = makeWindowIfNeeded()
        select(SettingsTab.allCases[tabIndex.clamped(to: 0...(SettingsTab.allCases.count - 1))])
        window.orderBack(nil)
    }

    func debugHide() {
        window?.orderOut(nil)
    }
    #endif

    private func makeWindowIfNeeded() -> NSWindow {
        if let window { return window }

        let root = SettingsView(model: model, settings: model.settings, selection: selection, recorder: recorder)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self

        let toolbar = NSToolbar(identifier: "MousseSettings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .preference

        self.window = window
        select(selection.tab)
        window.center()
        return window
    }

    private func select(_ tab: SettingsTab) {
        recorder.stop()
        selection.tab = tab
        window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(tab.rawValue)
        window?.title = tab.title
    }

    @objc private func toolbarItemClicked(_ sender: NSToolbarItem) {
        guard let tab = SettingsTab(rawValue: sender.itemIdentifier.rawValue) else { return }
        select(tab)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        recorder.stop()
    }

    func windowDidResignKey(_ notification: Notification) {
        recorder.stop()
    }

    // MARK: - NSToolbarDelegate

    private var tabIdentifiers: [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { tabIdentifiers }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { tabIdentifiers }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { tabIdentifiers }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let tab = SettingsTab(rawValue: itemIdentifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.title
        item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
        item.target = self
        item.action = #selector(toolbarItemClicked(_:))
        return item
    }
}
