import AnchorCore
import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private init() {
        let hosting = NSHostingView(rootView:
            SettingsView()
                .environmentObject(EntitlementManager.shared)
                .environmentObject(StoreManager.shared))
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Anchor"
        win.toolbarStyle = .unified
        win.titlebarAppearsTransparent = false
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.contentView = hosting
        win.center()
        super.init(window: win)
        win.delegate = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("not used")
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        if window?.isVisible == true {
            window?.orderFrontRegardless()
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        window?.makeKeyAndOrderFront(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
