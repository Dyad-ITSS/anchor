import AppKit
import SwiftUI
import UserNotifications
import AnchorCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement=true in Info.plist already sets .accessory policy before launch
        menuBarController = MenuBarController()
        HelperManager.shared.registerIfNeeded()
        Task { await EntitlementManager.shared.refresh() }
        Task { await StoreManager.shared.loadProducts() }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    func showSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingView(rootView:
                SettingsView()
                    .environmentObject(EntitlementManager.shared)
                    .environmentObject(StoreManager.shared)
            )
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.title = "Anchor Settings"
            win.contentView = hosting
            win.center()
            win.isReleasedWhenClosed = false
            settingsWindow = win
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
