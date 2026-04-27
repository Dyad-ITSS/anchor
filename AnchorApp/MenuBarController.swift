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
    }

    private func updateIcon() {
        let activeShares = config.activeShares
        let allMounted = !activeShares.isEmpty && activeShares.allSatisfy { shareStates[$0.id] == .mounted }
        let anyMounted = activeShares.contains { shareStates[$0.id] == .mounted }

        let tint: NSColor
        if activeShares.isEmpty {
            tint = .secondaryLabelColor
        } else if allMounted {
            tint = .controlAccentColor
        } else if anyMounted {
            tint = .systemYellow
        } else {
            tint = .systemRed
        }

        let image = NSImage(systemSymbolName: "externaldrive.connected.to.line.below", accessibilityDescription: "Anchor")
        image?.isTemplate = false
        statusItem.button?.image = image
        statusItem.button?.contentTintColor = tint
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
        statusItem.menu = menu
    }

    @objc private func reconnectAll() { MountNotifications.postConfigUpdated() }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
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
