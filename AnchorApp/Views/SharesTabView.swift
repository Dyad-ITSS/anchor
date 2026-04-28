import SwiftUI
import AnchorCore

private let freeShareLimit = 3

struct SharesTabView: View {
    @EnvironmentObject var entitlement: EntitlementManager

    @State private var config: AnchorConfig = ConfigStore().loadSync()
    @State private var mountEvents: [UUID: MountEvent] = [:]
    @State private var selectedID: UUID? = nil
    @State private var showingAdd = false
    @State private var editingShare: Share? = nil
    @State private var notificationToken: NSObjectProtocol? = nil

    private var detectedVPN: String? {
        let v = UserDefaults(suiteName: "group.com.yourname.anchor")?.string(forKey: "detectedVPN") ?? "None"
        return v == "None" ? nil : v
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selectedID) {
                ForEach(config.shares) { share in
                    let event = mountEvents[share.id]
                    let state = event?.state ?? .unmounted
                    HStack(spacing: 8) {
                        StatusDot(state: state)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(share.displayName).fontWeight(.medium)
                            Text("smb://\(share.host)/\(share.shareName)")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        StateBadge(state: state, mountedHost: event?.mountedHost, share: share)
                    }
                    .tag(share.id)
                    .onTapGesture(count: 2) {
                        editingShare = share
                    }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))

            Divider()

            HStack(spacing: 0) {
                // Add button
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .frame(width: 24, height: 22)
                    .disabled(!entitlement.isPro && config.shares.count >= freeShareLimit)

                // Remove button
                Button { removeSelected() } label: { Image(systemName: "minus") }
                    .buttonStyle(.borderless)
                    .frame(width: 24, height: 22)
                    .disabled(selectedID == nil)

                // Edit button
                Button("Edit…") {
                    if let id = selectedID,
                       let share = config.shares.first(where: { $0.id == id }) {
                        editingShare = share
                    }
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .disabled(selectedID == nil)
                .foregroundColor(selectedID == nil ? .secondary : .primary)

                Spacer()

                // Free tier cap label
                if !entitlement.isPro && config.shares.count >= freeShareLimit {
                    Text("\(config.shares.count)/\(freeShareLimit) — Upgrade to Pro for more")
                        .font(.caption).foregroundColor(.secondary)
                }

                // VPN indicator
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
        .onAppear { startObserving() }
        .onDisappear { stopObserving() }
        .sheet(isPresented: $showingAdd) {
            ShareEditSheet(share: nil) { saved in
                config = AnchorConfig(
                    shares: config.shares + [saved],
                    activeProfile: config.activeProfile,
                    schemaVersion: config.schemaVersion
                )
                saveConfig()
            }
        }
        .sheet(item: $editingShare) { share in
            ShareEditSheet(share: share) { updated in
                let newShares = config.shares.map { $0.id == updated.id ? updated : $0 }
                config = AnchorConfig(shares: newShares, activeProfile: config.activeProfile, schemaVersion: config.schemaVersion)
                saveConfig()
            }
        }
    }

    private func removeSelected() {
        guard let id = selectedID else { return }
        config = AnchorConfig(
            shares: config.shares.filter { $0.id != id },
            activeProfile: config.activeProfile,
            schemaVersion: config.schemaVersion
        )
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

// MARK: - Status badge (right side of each row)

private struct StateBadge: View {
    let state: MountState
    let mountedHost: String?
    let share: Share

    private var isVPN: Bool {
        guard let host = mountedHost, let fallback = share.fallbackHost else { return false }
        return host == fallback
    }

    var body: some View {
        Group {
            switch state {
            case .mounted:
                let label = isVPN ? "VPN" : "LAN"
                let color: Color = isVPN ? .blue : .green
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.12))
                    .cornerRadius(4)
            case .mounting:
                Text("Mounting…")
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.yellow.opacity(0.12))
                    .cornerRadius(4)
            case .unreachable, .error:
                Text("Unreachable")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.10))
                    .cornerRadius(4)
            case .unmounted:
                EmptyView()
            }
        }
    }
}

// MARK: - Status dot

struct StatusDot: View {
    let state: MountState
    @State private var animating = false

    var color: Color {
        switch state {
        case .mounted:     return Color(red: 0.188, green: 0.820, blue: 0.345)
        case .mounting:    return .yellow
        case .unreachable, .error: return .red
        case .unmounted:   return Color(white: 0.35)
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color.opacity(0.6), radius: 2)
            .opacity(state == .mounting ? (animating ? 0.3 : 1.0) : 1.0)
            .animation(state == .mounting
                ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                : .default,
                value: animating)
            .onAppear { if state == .mounting { animating = true } }
    }
}
