import AppKit
import AnchorCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // no dock icon
        menuBarController = MenuBarController()
        HelperManager.shared.registerIfNeeded()
        Task { await EntitlementManager.shared.refresh() }
        Task { await StoreManager.shared.loadProducts() }
    }
}
