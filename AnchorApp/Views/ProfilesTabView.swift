import AnchorCore
import SwiftUI

struct ProfilesTabView: View {
    @EnvironmentObject var entitlement: EntitlementManager
    @EnvironmentObject var store: StoreManager

    @State private var config: AnchorConfig = .init()
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

    // MARK: - Locked (#25 — ghost preview behind frosted overlay)

    private var lockedView: some View {
        ZStack {
            // Ghost profiles rendered behind the blur
            VStack(alignment: .leading, spacing: 0) {
                List {
                    HStack {
                        Image(systemName: "circle").foregroundColor(.secondary)
                        Text("All Shares")
                    }
                    ForEach(["Home", "Office", "Travel"], id: \.self) { name in
                        HStack {
                            Image(systemName: "circle").foregroundColor(.secondary)
                            Text(name)
                        }
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .disabled(true)

                HStack(spacing: 6) {
                    TextField("New profile name", text: .constant(""))
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                    Button("Add") {}.disabled(true)
                }
                .padding(8)
            }
            .blur(radius: 4)
            .allowsHitTesting(false)

            // Frosted panel on top
            VStack(spacing: 12) {
                Image(systemName: "person.2.badge.key.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.secondary)

                Text("Profiles")
                    .font(.headline)

                Text("Switch between Home, Office, and Travel profiles — mounting only the shares you need for each context.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .font(.callout)
                    .frame(maxWidth: 260)

                Text("Available in Anchor Pro")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
            .padding(24)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 4)
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
                HStack {
                    Image(systemName: config.activeProfile == nil ? "checkmark" : "circle")
                        .foregroundColor(config.activeProfile == nil ? .accentColor : .secondary)
                    Text("All Shares")
                }
                .tag(String?.none)
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
        config = (try? await ConfigStore().load()) ?? AnchorConfig()
    }

    @MainActor
    private func saveConfig() async {
        let snapshot = config
        try? await ConfigStore().save(snapshot)
        MountNotifications.postConfigUpdated()
    }
}
