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
        let anyMounted = activeShares.contains { shareStates[$0.id] == .mounted }

        let image = NSImage(systemSymbolName: "externaldrive.connected.to.line.below", accessibilityDescription: "Anchor")
        image?.isTemplate = true
        statusItem.button?.image = image

        // nil tint = system adapts automatically (white on dark, black on light)
        // coloured tint = status override
        if activeShares.isEmpty {
            statusItem.button?.contentTintColor = nil
        } else if allMounted {
            statusItem.button?.contentTintColor = .controlAccentColor
        } else if anyMounted {
            statusItem.button?.contentTintColor = .systemYellow
        } else {
            statusItem.button?.contentTintColor = .systemRed
        }
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
            let store = try? ConfigStore()
            self.config = (try? await store?.load()) ?? AnchorConfig()
            self.buildMenu()
            self.updateIcon()
        }
    }

    private func observeStateChanges() {
        notificationObserver = MountNotifications.observeStateChanged { [weak self] event in
            self?.shareStates[event.shareID] = event.state
            self?.buildMenu()
            self?.updateIcon()
        }
    }
}
