import SwiftUI
import AnchorCore

private let freeShareLimit = 3

struct SharesTabView: View {
    @State private var config: AnchorConfig = AnchorConfig()
    @State private var selectedShareID: UUID?
    @State private var showingAddSheet = false
    @State private var editingShare: Share?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selectedShareID) {
                ForEach(config.shares) { share in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(share.displayName)
                            .fontWeight(.medium)
                        Text("smb://\(share.host)/\(share.shareName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .tag(share.id)
                    .onTapGesture(count: 2) {
                        editingShare = share
                    }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))

            HStack {
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus")
                }
                .disabled(config.shares.count >= freeShareLimit)

                Button(action: removeSelectedShare) {
                    Image(systemName: "minus")
                }
                .disabled(selectedShareID == nil)

                Spacer()

                if config.shares.count >= freeShareLimit {
                    Text("\(config.shares.count)/\(freeShareLimit) shares (Free) — Upgrade to Pro for more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
        }
        .task {
            await loadConfig()
        }
        .sheet(isPresented: $showingAddSheet) {
            ShareEditSheet(share: nil) { saved in
                addShare(saved)
            }
        }
        .sheet(item: $editingShare) { share in
            ShareEditSheet(share: share) { updated in
                updateShare(updated)
            }
        }
    }

    private func removeSelectedShare() {
        guard let id = selectedShareID else { return }
        config = AnchorConfig(
            shares: config.shares.filter { $0.id != id },
            activeProfile: config.activeProfile,
            schemaVersion: config.schemaVersion
        )
        selectedShareID = nil
        Task { await saveConfig() }
    }

    private func addShare(_ share: Share) {
        config = AnchorConfig(
            shares: config.shares + [share],
            activeProfile: config.activeProfile,
            schemaVersion: config.schemaVersion
        )
        Task { await saveConfig() }
    }

    private func updateShare(_ updated: Share) {
        let newShares = config.shares.map { $0.id == updated.id ? updated : $0 }
        config = AnchorConfig(
            shares: newShares,
            activeProfile: config.activeProfile,
            schemaVersion: config.schemaVersion
        )
        Task { await saveConfig() }
    }

    @MainActor
    private func loadConfig() async {
        let store = try? ConfigStore()
        config = (try? await store?.load()) ?? AnchorConfig()
    }

    @MainActor
    private func saveConfig() async {
        guard let store = try? ConfigStore() else { return }
        try? await store.save(config)
        MountNotifications.postConfigUpdated()
    }
}
