import SwiftUI
import AppKit
import AnchorCore

struct AboutTabView: View {
    @EnvironmentObject var entitlement: EntitlementManager
    @EnvironmentObject var store: StoreManager

    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 56))
                .foregroundColor(.accentColor)

            Text("Anchor")
                .font(.title)
                .fontWeight(.bold)

            Text("Version \(version)")
                .foregroundColor(.secondary)

            // Pro status badge
            if entitlement.isPro {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("Anchor Pro — Active")
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.12))
                .cornerRadius(6)

                // Export / import (Pro only)
                Divider().padding(.horizontal, 40)

                HStack(spacing: 12) {
                    Button("Export Config") {
                        Task { @MainActor in
                            guard let configStore = try? ConfigStore(),
                                  let config = try? await configStore.load(),
                                  let data = try? JSONEncoder().encode(config) else { return }
                            let panel = NSSavePanel()
                            panel.nameFieldStringValue = "anchor-config.json"
                            if panel.runModal() == .OK, let url = panel.url {
                                try? data.write(to: url)
                            }
                        }
                    }

                    Button("Import Config") {
                        Task { @MainActor in
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.json]
                            if panel.runModal() == .OK,
                               let url = panel.url,
                               let data = try? Data(contentsOf: url),
                               let config = try? JSONDecoder().decode(AnchorConfig.self, from: data),
                               let configStore = try? ConfigStore() {
                                try? await configStore.save(config)
                                MountNotifications.postConfigUpdated()
                            }
                        }
                    }
                }
            } else {
                Text("Free — up to 3 shares")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(6)

                VStack(spacing: 8) {
                    Button("Upgrade to Pro — \(store.proProduct?.displayPrice ?? "$9.99")") {
                        Task { await store.purchase() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isPurchasing)

                    Button("Restore Purchase") {
                        Task { await store.restorePurchases() }
                    }
                    .foregroundColor(.secondary)
                    .disabled(store.isPurchasing)
                }
                .padding(.top, 4)
            }

            Link("View on GitHub", destination: URL(string: "https://github.com")!)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
