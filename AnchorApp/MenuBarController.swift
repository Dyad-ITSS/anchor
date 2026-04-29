import AppKit
import AnchorCore

final class MenuBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var mountEvents: [UUID: MountEvent] = [:]
    private var config: AnchorConfig = AnchorConfig()
    private var notificationObserver: NSObjectProtocol?

    init() {
        loadConfig()
        observeStateChanges()
        statusItem.button?.action = #selector(statusButtonClicked(_:))
        statusItem.button?.target = self
        statusItem.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }

    @objc private func statusButtonClicked(_ sender: NSStatusBarButton) {
        guard let menu = statusItem.menu else { return }
        statusItem.menu = nil
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
        statusItem.menu = menu
    }

    // MARK: - Icon

    private func updateIcon() {
        let active = config.activeShares
        let states = active.compactMap { mountEvents[$0.id]?.state }
        let allMounted    = !active.isEmpty && states.allSatisfy { $0 == .mounted }
        let anyError      = states.contains { $0 == .unreachable || $0 == .error }

        let symbolName: String
        if active.isEmpty {
            symbolName = "externaldrive"
        } else if allMounted {
            symbolName = "externaldrive.connected.to.line.below.fill"
        } else if anyError {
            symbolName = "externaldrive.trianglebadge.exclamationmark"
        } else {
            symbolName = "externaldrive.connected.to.line.below"
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Anchor")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.contentTintColor = nil
    }

    // MARK: - Menu

    func buildMenu() {
        let menu = NSMenu()

        for share in config.activeShares {
            let event = mountEvents[share.id]
            let state = event?.state ?? .unmounted
            let item = NSMenuItem()
            item.attributedTitle = shareTitle(share, event: event, state: state)
            item.representedObject = share
            item.action = state == .mounted ? #selector(openShare(_:)) : #selector(reconnectAll)
            item.target = self
            menu.addItem(item)
        }

        if !config.activeShares.isEmpty { menu.addItem(.separator()) }

        // Reconnect All — demoted visually
        let reconnect = NSMenuItem()
        let reconnectAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        ]
        reconnect.attributedTitle = NSAttributedString(string: "Reconnect All", attributes: reconnectAttrs)
        reconnect.action = #selector(reconnectAll)
        reconnect.keyEquivalent = "r"
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

    private func shareTitle(_ share: Share, event: MountEvent?, state: MountState) -> NSAttributedString {
        // Dot color
        let dotColor: NSColor
        switch state {
        case .mounted:             dotColor = .systemGreen
        case .mounting:            dotColor = .systemYellow
        case .unreachable, .error: dotColor = .systemRed
        case .unmounted:           dotColor = NSColor.tertiaryLabelColor
        }

        let result = NSMutableAttributedString(string: "● ", attributes: [.foregroundColor: dotColor])

        // Name — strikethrough on unreachable
        var nameAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.labelColor]
        if state == .unreachable || state == .error {
            nameAttrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            nameAttrs[.foregroundColor] = NSColor.secondaryLabelColor
        }
        result.append(NSAttributedString(string: share.displayName, attributes: nameAttrs))

        // Latency / route suffix for mounted shares
        if state == .mounted, let event {
            let isVPN = event.mountedHost == share.fallbackHost && share.fallbackHost != nil
            let route = isVPN ? "VPN" : "LAN"
            var suffix = "  \(route)"
            if let ms = event.latencyMs, ms > 0 { suffix += " · \(ms)ms" }
            result.append(NSAttributedString(string: suffix, attributes: [
                .foregroundColor: isVPN ? NSColor.systemBlue : NSColor.systemGreen,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            ]))
        }

        return result
    }

    // MARK: - Actions

    @objc private func openShare(_ sender: NSMenuItem) {
        guard let share = sender.representedObject as? Share else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Volumes/\(share.shareName)"))
    }

    @objc private func reconnectAll() { MountNotifications.postConfigUpdated() }

    @objc private func openSettings() { SettingsWindowController.shared.show() }

    // MARK: - Config loading

    private func loadConfig() {
        config = ConfigStore().loadSync()
        for share in config.activeShares where mountEvents[share.id] == nil {
            if isMountPoint("/Volumes/\(share.shareName)") {
                mountEvents[share.id] = MountEvent(shareID: share.id, state: .mounted, mountedHost: share.host)
            }
        }
        buildMenu()
        updateIcon()
    }

    private func isMountPoint(_ path: String) -> Bool {
        let parent = (path as NSString).deletingLastPathComponent
        guard let dev  = (try? FileManager.default.attributesOfFileSystem(forPath: path))?[.systemNumber] as? Int,
              let pDev = (try? FileManager.default.attributesOfFileSystem(forPath: parent))?[.systemNumber] as? Int
        else { return false }
        return dev != pDev
    }

    private func observeStateChanges() {
        notificationObserver = MountNotifications.observeStateChanged { [weak self] event in
            self?.mountEvents[event.shareID] = event
            self?.buildMenu()
            self?.updateIcon()
        }
    }
}
