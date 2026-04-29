import SwiftUI
import AnchorCore

private let freeShareLimit = 3

struct SharesTabView: View {
    @EnvironmentObject var entitlement: EntitlementManager

    @State private var config: AnchorConfig = ConfigStore().loadSync()
    @State private var mountEvents: [UUID: MountEvent] = [:]
    @State private var selectedID: UUID? = nil
    @State private var showingBrowser = false
    @State private var pendingAdd: PendingShare? = nil
    @State private var editingShare: Share? = nil
    @State private var notificationToken: NSObjectProtocol? = nil

    private var detectedVPN: String? {
        let v = UserDefaults(suiteName: "group.com.yourname.anchor")?.string(forKey: "detectedVPN") ?? "None"
        return v == "None" ? nil : v
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if config.shares.isEmpty {
                emptyState
            } else {
                shareList
            }

            Divider()
            toolbar
        }
        .onAppear { startObserving() }
        .onDisappear { stopObserving() }
        .sheet(isPresented: $showingBrowser) {
            NetworkBrowserSheet { host, shareName, displayName in
                pendingAdd = PendingShare(host: host, shareName: shareName, displayName: displayName)
            }
        }
        .sheet(item: $pendingAdd) { pending in
            ShareEditSheet(
                share: nil,
                prefilledHost: pending.host,
                prefilledShareName: pending.shareName,
                prefilledDisplayName: pending.displayName
            ) { saved in
                config = AnchorConfig(shares: config.shares + [saved],
                                      activeProfile: config.activeProfile,
                                      schemaVersion: config.schemaVersion)
                saveConfig()
            }
        }
        .sheet(item: $editingShare) { share in
            ShareEditSheet(share: share) { updated in
                let newShares = config.shares.map { $0.id == updated.id ? updated : $0 }
                config = AnchorConfig(shares: newShares, activeProfile: config.activeProfile,
                                      schemaVersion: config.schemaVersion)
                saveConfig()
            }
        }
    }

    // MARK: - Empty state (#9)

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No shares yet")
                .font(.headline)
            Text("Click + to browse your network and connect\nyour first drive.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button {
                guard entitlement.isPro || config.shares.count < freeShareLimit else { return }
                showingBrowser = true
            } label: {
                Label("Add Share", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Share list (#5 inset, #6 dot, #7 badge, #8 caption, #10 context menu)

    private var shareList: some View {
        List(selection: $selectedID) {
            ForEach(config.shares) { share in
                let event = mountEvents[share.id]
                let state = event?.state ?? .unmounted
                HStack(spacing: 10) {
                    StatusDot(state: state)
                        .opacity(state == .mounted || state == .unmounted ? 0 : 1) // dot hidden for clean states

                    VStack(alignment: .leading, spacing: 2) {
                        Text(share.displayName)
                            .fontWeight(.medium)
                            .strikethrough(state == .unreachable || state == .error, color: .secondary)
                            .foregroundColor(state == .unreachable || state == .error ? .secondary : .primary)
                        Text(share.host)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    ConnectionBadge(state: state, event: event, share: share)
                }
                .tag(share.id)
                .onTapGesture(count: 2) { editingShare = share }
                .contextMenu {                                          // #10 right-click
                    Button("Edit…") { editingShare = share }
                    if state == .mounted {
                        Button("Open in Finder") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/Volumes/\(share.shareName)"))
                        }
                    }
                    Divider()
                    Button("Remove", role: .destructive) { remove(share: share) }
                }
            }
        }
        .listStyle(.inset)                                             // #5
    }

    // MARK: - Bottom toolbar

    private var toolbar: some View {
        HStack(spacing: 0) {
            Button { showingBrowser = true } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .frame(width: 24, height: 22)
                .disabled(!entitlement.isPro && config.shares.count >= freeShareLimit)

            Button { removeSelected() } label: { Image(systemName: "minus") }
                .buttonStyle(.borderless)
                .frame(width: 24, height: 22)
                .disabled(selectedID == nil)

            Button("Edit…") {
                if let id = selectedID, let share = config.shares.first(where: { $0.id == id }) {
                    editingShare = share
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .disabled(selectedID == nil)
            .foregroundColor(selectedID == nil ? .secondary : .primary)

            Spacer()

            if !entitlement.isPro && config.shares.count >= freeShareLimit {
                Text("\(config.shares.count)/\(freeShareLimit) — Upgrade for more")
                    .font(.caption).foregroundColor(.secondary)
            }

            if let vpn = detectedVPN {
                HStack(spacing: 4) {
                    Circle().fill(Color.blue).frame(width: 6, height: 6)
                    Text(vpn).font(.caption).foregroundColor(.blue)
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func remove(share: Share) {
        config = AnchorConfig(shares: config.shares.filter { $0.id != share.id },
                              activeProfile: config.activeProfile,
                              schemaVersion: config.schemaVersion)
        if selectedID == share.id { selectedID = nil }
        saveConfig()
    }

    private func removeSelected() {
        guard let id = selectedID else { return }
        config = AnchorConfig(shares: config.shares.filter { $0.id != id },
                              activeProfile: config.activeProfile,
                              schemaVersion: config.schemaVersion)
        selectedID = nil
        saveConfig()
    }

    private func saveConfig() {
        ConfigStore().saveSync(config)
        MountNotifications.postConfigUpdated()
    }

    private func startObserving() {
        notificationToken = MountNotifications.observeStateChanged { event in
            mountEvents[event.shareID] = event
        }
    }

    private func stopObserving() {
        if let token = notificationToken {
            DistributedNotificationCenter.default().removeObserver(token)
            notificationToken = nil
        }
    }
}

// MARK: - PendingShare

struct PendingShare: Identifiable {
    let id = UUID()
    let host: String
    let shareName: String
    let displayName: String
}

// MARK: - ConnectionBadge (#7 — merged dot + route info)

private struct ConnectionBadge: View {
    let state: MountState
    let event: MountEvent?
    let share: Share

    private var isVPN: Bool {
        guard let host = event?.mountedHost, let fallback = share.fallbackHost else { return false }
        return host == fallback
    }

    var body: some View {
        switch state {
        case .mounted:
            let color: Color = isVPN ? .blue : .green
            let route = isVPN ? "VPN" : "LAN"
            let latency = event?.latencyMs.map { " · \($0)ms" } ?? ""
            Text("\(route)\(latency)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        case .mounting:
            Text("Mounting…")
                .font(.system(size: 10))
                .foregroundColor(.yellow)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.yellow.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        case .unreachable, .error:
            Text("Unreachable")
                .font(.system(size: 10))
                .foregroundColor(.red)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.red.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        case .unmounted:
            EmptyView()
        }
    }
}

// MARK: - StatusDot (#6 — 10px, only for transitional states)

struct StatusDot: View {
    let state: MountState
    @State private var animating = false

    var color: Color {
        switch state {
        case .mounted:             return .green
        case .mounting:            return .yellow
        case .unreachable, .error: return .red
        case .unmounted:           return Color(white: 0.4)
        }
    }

    var body: some View {
        ZStack {
            // Outer glow ring for mounted
            if state == .mounted {
                Circle()
                    .fill(color.opacity(0.25))
                    .frame(width: 16, height: 16)
            }
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .shadow(color: color.opacity(0.5), radius: 2)
        }
        .frame(width: 16, height: 16)
        .opacity(state == .mounting ? (animating ? 0.3 : 1.0) : 1.0)
        .animation(state == .mounting
            ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
            : .default,
            value: animating)
        .onAppear { if state == .mounting { animating = true } }
    }
}
