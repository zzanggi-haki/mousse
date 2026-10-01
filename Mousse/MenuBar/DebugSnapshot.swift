#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only: shows the menu bar popover content in a window parked behind every
/// other window, so scripts can capture it with `screencapture -l <windowID>` without
/// opening the real popover or covering the user's work.
@MainActor
enum DebugSnapshot {
    private static var window: NSWindow?

    static func showMenu(model: AppModel) {
        hideMenu()
        let hosting = NSHostingView(rootView: MenuBarRootView(model: model, settings: model.settings))
        let size = hosting.fittingSize
        let origin = (NSScreen.screens.last ?? NSScreen.main)?.visibleFrame.origin ?? .zero
        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "Mousse Debug Menu"
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderBack(nil)
        self.window = window
    }

    static func hideMenu() {
        window?.orderOut(nil)
        window = nil
    }
}
#endif
