import AppKit
import SwiftUI

/// Wraps `NSStatusItem` setup + click handling behind a small, reusable API.
/// Meant to be instantiated by an app's `AppDelegate` / `@main` entry point
/// once a real app target exists (`MainAppUI`, later) -- this package has no
/// executable target of its own and never attempts to run as a menu bar app
/// standalone.
///
/// Not unit tested: constructing a real `NSStatusItem` requires a live
/// AppKit application session, which isn't available (or meaningful) in a
/// headless `swift test` run. Everything this type delegates to (stats,
/// thresholds, monitoring) is tested independently.
@MainActor
public final class MenuBarController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()

    public init(statusBar: NSStatusBar = .system) {
        self.statusItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        popover.behavior = .transient
        configureButton()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "MClean Pro")
        button.target = self
        button.action = #selector(togglePopover)
    }

    /// Optional short status text shown next to the icon (e.g. free disk space).
    public func setStatusText(_ text: String?) {
        statusItem.button?.title = text ?? ""
    }

    /// Hosts an arbitrary SwiftUI view as the popover's content. Kept
    /// generic so this package doesn't need to own (or depend on)
    /// `UIDesignSystem` -- the app layer supplies the real popover UI, this
    /// type just hosts it.
    public func setPopoverContent<Content: View>(@ViewBuilder _ content: () -> Content) {
        popover.contentViewController = NSHostingController(rootView: content())
    }

    /// Removes the icon from the menu bar, e.g. as part of handling a "Quit"
    /// menu item. Not automatic on deinit -- the app decides its own
    /// menu-bar lifecycle.
    public func removeFromMenuBar() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
