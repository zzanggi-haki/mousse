import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    /// Watches clicks in other apps so the popover closes when the user clicks
    /// anywhere outside it. `.transient` alone doesn't reliably do this for
    /// LSUIElement menu bar apps.
    private var globalClickMonitor: Any?
    private var dismissSubscription: AnyCancellable?

    init(model: AppModel) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()

        let hosting = NSHostingController(rootView: MenuBarRootView(model: model, settings: model.settings))
        hosting.sizingOptions = [.preferredContentSize]
        popover.behavior = .transient
        popover.contentViewController = hosting
        popover.delegate = self
        dismissSubscription = model.menuDismissRequests.sink { [weak self] in
            self?.popover.performClose(nil)
        }

        if let button = statusItem.button {
            // The cursor as a slice of cake (vector PDF authored at its menu bar size,
            // 22×14 pt), template-rendered so it adapts to light/dark menu bars.
            let image = NSImage(named: "MenuBarIcon")
            image?.isTemplate = true
            button.image = image
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            installGlobalClickMonitor()
        }
    }

    private func installGlobalClickMonitor() {
        removeGlobalClickMonitor()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.popover.performClose(nil)
            }
        }
    }

    private func removeGlobalClickMonitor() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }

    // MARK: - NSPopoverDelegate

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            self.removeGlobalClickMonitor()
        }
    }
}
