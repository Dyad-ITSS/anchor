import AnchorCore
import AppKit

final class MenuBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var mountEvents: [UUID: MountEvent] = [:]
    private var config: AnchorConfig = .init()
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
        let allMounted = !active.isEmpty && states.allSatisfy { $0 == .mounted }
        let anyError = states.contains { $0 == .unreachable || $0 == .error }

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
            item.representedObject = share
            item.action = state == .mounted ? #selector(openShare(_:)) : #selector(reconnectAll)
            item.target = self
            // Custom view pins latency to the actual trailing edge, bypassing NSMenu's reserved shortcut column
            item.view = ShareMenuItemView(share: share, event: event, state: state)
            menu.addItem(item)
        }

        if !config.activeShares.isEmpty { menu.addItem(.separator()) }

        // Reconnect All — demoted visually
        let reconnect = NSMenuItem()
        let reconnectAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        ]
        reconnect.attributedTitle = NSAttributedString(string: "Reconnect All", attributes: reconnectAttrs)
        reconnect.action = #selector(reconnectAll)
        reconnect.keyEquivalent = "r"
        reconnect.target = self
        menu.addItem(reconnect)

        let settings = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Anchor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func openShare(_ sender: NSMenuItem) {
        guard let share = sender.representedObject as? Share else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Volumes/\(share.shareName)"))
    }

    @objc private func reconnectAll() {
        MountNotifications.postConfigUpdated()
    }

    @objc private func openSettings() {
        DispatchQueue.main.async {
            SettingsWindowController.shared.show()
        }
    }

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
        guard let dev = (try? FileManager.default.attributesOfFileSystem(forPath: path))?[.systemNumber] as? Int,
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

// MARK: - ShareMenuItemView

private final class ShareMenuItemView: NSView {
    private let dotLabel = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "")
    private let latencyLabel = NSTextField(labelWithString: "")
    private let dotColor: NSColor
    private let latencyColor: NSColor

    init(share: Share, event: MountEvent?, state: MountState) {
        switch state {
        case .mounted: dotColor = .systemGreen
        case .mounting: dotColor = .systemYellow
        case .unreachable, .error: dotColor = .systemRed
        case .unmounted: dotColor = .tertiaryLabelColor
        }

        let isVPN = state == .mounted &&
            event?.mountedHost == share.fallbackHost && share.fallbackHost != nil
        latencyColor = isVPN ? .systemBlue : .systemGreen

        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 20))

        for field in [dotLabel, nameLabel, latencyLabel] {
            field.isEditable = false
            field.isBordered = false
            field.backgroundColor = .clear
            field.translatesAutoresizingMaskIntoConstraints = false
            addSubview(field)
        }

        dotLabel.font = .menuFont(ofSize: 0)
        dotLabel.textColor = dotColor
        dotLabel.stringValue = "●"

        nameLabel.font = .menuFont(ofSize: 0)
        nameLabel.textColor = .labelColor
        if state == .unreachable || state == .error {
            let s = NSMutableAttributedString(string: share.displayName,
                                              attributes: [.font: NSFont.menuFont(ofSize: 0),
                                                           .foregroundColor: NSColor.secondaryLabelColor,
                                                           .strikethroughStyle: NSUnderlineStyle.single.rawValue])
            nameLabel.attributedStringValue = s
        } else {
            nameLabel.stringValue = share.displayName
        }

        latencyLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        latencyLabel.textColor = latencyColor
        latencyLabel.alignment = .right
        if state == .mounted, let event {
            let route = isVPN ? "VPN" : "LAN"
            var label = route
            if let ms = event.latencyMs, ms > 0 { label += " · \(ms)ms" }
            latencyLabel.stringValue = label
        }

        NSLayoutConstraint.activate([
            dotLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            dotLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: dotLabel.trailingAnchor, constant: 6),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: latencyLabel.leadingAnchor, constant: -8),

            latencyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            latencyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            latencyLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func draw(_ dirtyRect: NSRect) {
        let highlighted = enclosingMenuItem?.isHighlighted == true
        if highlighted {
            NSColor.selectedMenuItemColor.setFill()
            bounds.fill()
            dotLabel.textColor = .selectedMenuItemTextColor
            nameLabel.textColor = .selectedMenuItemTextColor
            latencyLabel.textColor = .selectedMenuItemTextColor
        } else {
            dotLabel.textColor = dotColor
            if nameLabel.attributedStringValue.length > 0 {
                nameLabel.textColor = .secondaryLabelColor
            } else {
                nameLabel.textColor = .labelColor
            }
            latencyLabel.textColor = latencyColor
        }
        super.draw(dirtyRect)
    }
}
