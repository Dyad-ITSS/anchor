import SwiftUI
import AnchorCore

struct ProfilesTabView: View {
    @EnvironmentObject var entitlement: EntitlementManager
    @EnvironmentObject var store: StoreManager

    @State private var config: AnchorConfig = AnchorConfig()
    @State private var newProfileName: String = ""

    private var allProfiles: [String] {
        let names = config.shares.flatMap { Array($0.profiles) }
        return Array(Set(names)).sorted()
    }

    var body: some View {
        if entitlement.isPro {
            proProfilesView
        } else {
            lockedView
        }
    }

    // MARK: - Locked (free tier)

    private var lockedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill").font(.largeTitle).foregroundColor(.secondary)
            Text("Profiles are a Pro feature").fontWeight(.medium)
            Text("Organise shares into Home, Office, and Travel profiles.")
                .multilineTextAlignment(.center).foregroundColor(.secondary).font(.callout)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Pro profiles UI

    private var proProfilesView: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: Binding(
                get: { config.activeProfile },
                set: { newProfile in
                    config = AnchorConfig(
                        shares: config.shares,
                        activeProfile: newProfile,
                        schemaVersion: config.schemaVersion
                    )
                    Task { await saveConfig() }
                }
            )) {
                // "All" pseudo-profile
                HStack {
                    Image(systemName: config.activeProfile == nil ? "checkmark" : "circle")
                        .foregroundColor(config.activeProfile == nil ? .accentColor : .secondary)
                    Text("All Shares")
                }
                .tag(Optional<String>.none)
                .onTapGesture {
                    config = AnchorConfig(
                        shares: config.shares,
                        activeProfile: nil,
                        schemaVersion: config.schemaVersion
                    )
                    Task { await saveConfig() }
                }

                ForEach(allProfiles, id: \.self) { profile in
                    HStack {
                        Image(systemName: config.activeProfile == profile ? "checkmark" : "circle")
                            .foregroundColor(config.activeProfile == profile ? .accentColor : .secondary)
                        Text(profile)
                    }
                    .tag(Optional(profile))
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))

            HStack(spacing: 6) {
                TextField("New profile name", text: $newProfileName)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let name = newProfileName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    newProfileName = ""
                    // Profile is just a name; shares are assigned in ShareEditSheet.
                    // Set it as active immediately.
                    config = AnchorConfig(
                        shares: config.shares,
                        activeProfile: name,
                        schemaVersion: config.schemaVersion
                    )
                    Task { await saveConfig() }
                }
                .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(8)
        }
        .task { await loadConfig() }
    }

    // MARK: - Config I/O

    @MainActor
    private func loadConfig() async {
        guard let configStore = try? ConfigStore() else { return }
        config = (try? await configStore.load()) ?? AnchorConfig()
    }

    @MainActor
    private func saveConfig() async {
        guard let configStore = try? ConfigStore() else { return }
        let snapshot = config
        try? await configStore.save(snapshot)
        MountNotifications.postConfigUpdated()
    }
}
