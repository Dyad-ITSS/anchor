import AppKit
import AnchorCore

final class MenuBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var shareStates: [UUID: MountState] = [:]
    private var config: AnchorConfig = AnchorConfig()
    private var notificationObserver: NSObjectProtocol?

    init() {
        loadConfig()
        observeStateChanges()
        updateIcon()
        buildMenu()
        // Use explicit click handler — more reliable than statusItem.menu on unsigned builds
        statusItem.button?.action = #selector(statusButtonClicked(_:))
        statusItem.button?.target = self
        statusItem.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }

    @objc private func statusButtonClicked(_ sender: NSStatusBarButton) {
        guard let menu = statusItem.menu else { return }
        // Detach menu briefly so button click doesn't fight with menu display
        statusItem.menu = nil
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: sender.bounds.height + 4),
                   in: sender)
        statusItem.menu = menu
    }

    private func updateIcon() {
        let activeShares = config.activeShares
        let allMounted = !activeShares.isEmpty && activeShares.allSatisfy { shareStates[$0.id] == .mounted }

        // Use fill variant when everything is mounted, outline otherwise.
        // Never set contentTintColor — template icons auto-adapt (white/dark mode)
        // and tinting breaks visibility on the pressed dark button background.
        let symbolName = allMounted
            ? "externaldrive.connected.to.line.below.fill"
            : "externaldrive.connected.to.line.below"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Anchor")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.contentTintColor = nil
    }

    func buildMenu() {
        let menu = NSMenu()
        for share in config.activeShares {
            let state = shareStates[share.id] ?? .unmounted
            let dot = state == .mounted ? "● " : "○ "
            let item = NSMenuItem(title: "\(dot)\(share.displayName)", action: nil, keyEquivalent: "")
            menu.addItem(item)
        }
        if !config.activeShares.isEmpty { menu.addItem(.separator()) }
        let reconnect = NSMenuItem(title: "Reconnect All", action: #selector(reconnectAll), keyEquivalent: "r")
        reconnect.target = self
        menu.addItem(reconnect)
        let settings = NSMenuItem(title: "Open Anchor Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        menu.addItem(NSMenuItem(title: "Anchor \(version)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Anchor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func reconnectAll() { MountNotifications.postConfigUpdated() }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    private func loadConfig() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let store = ConfigStore()
            self.config = (try? await store.load()) ?? AnchorConfig()
            // Seed initial states from the filesystem — don't wait for helper notifications,
            // which may have fired before our observer was registered.
            for share in self.config.activeShares where self.shareStates[share.id] == nil {
                let path = "/Volumes/\(share.shareName)"
                if self.isMountPoint(path) {
                    self.shareStates[share.id] = .mounted
                }
            }
            self.buildMenu()
            self.updateIcon()
        }
    }

    /// Returns true if path is a mount point (different device than its parent).
    private func isMountPoint(_ path: String) -> Bool {
        let parent = (path as NSString).deletingLastPathComponent
        guard let dev  = (try? FileManager.default.attributesOfFileSystem(forPath: path))?[.systemNumber] as? Int,
              let pDev = (try? FileManager.default.attributesOfFileSystem(forPath: parent))?[.systemNumber] as? Int
        else { return false }
        return dev != pDev
    }

    private func observeStateChanges() {
        notificationObserver = MountNotifications.observeStateChanged { [weak self] event in
            self?.shareStates[event.shareID] = event.state
            self?.buildMenu()
            self?.updateIcon()
        }
    }
}
