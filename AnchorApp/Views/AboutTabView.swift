import SwiftUI
import AppKit
import AnchorCore

struct AboutTabView: View {
    @EnvironmentObject var entitlement: EntitlementManager
    @EnvironmentObject var store: StoreManager
    @ObservedObject private var helperManager = HelperManager.shared

    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    var body: some View {
        VStack(spacing: 0) {
            // #23 — Launch at Login at top, before Pro section
            launchAtLoginRow
                .padding(.horizontal, 20).padding(.vertical, 12)

            Divider()

            VStack(spacing: 10) {
                appIcon
                    .padding(.top, 18)

                // #24 — inline PRO badge beside name
                HStack(spacing: 6) {
                    Text("Anchor")
                        .font(.title2).fontWeight(.bold)
                    if entitlement.isPro {
                        proBadge
                    }
                }

                Text("Version \(version)")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.bottom, 16)

            Divider()

            VStack(spacing: 10) {
                if entitlement.isPro {
                    proSection
                } else {
                    freeSection
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 16)

            Divider()

            footer
                .padding(.horizontal, 20).padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - App icon (#21 — tinted rounded-rect background, badge for Pro)

    private var appIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.accentColor.opacity(0.1))
                .frame(width: 76, height: 76)
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 36, weight: .medium))
                .foregroundColor(.accentColor)
        }
        .overlay(alignment: .bottomTrailing) {
            if entitlement.isPro {
                Circle()
                    .fill(Color.green)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .offset(x: 4, y: 4)
            }
        }
    }

    // MARK: - PRO badge (#24)

    private var proBadge: some View {
        Text("PRO")
            .font(.system(size: 9, weight: .semibold))
            .tracking(1.5)
            .foregroundColor(.accentColor)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Launch at Login (#23)

    private var launchAtLoginRow: some View {
        Toggle(isOn: Binding(
            get: { helperManager.isRegistered },
            set: { on in
                if on { helperManager.registerIfNeeded() }
                else  { helperManager.unregister() }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Launch at Login")
                    .font(.callout)
                Text("Start Anchor automatically when you log in")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .toggleStyle(.switch)
    }

    // MARK: - Pro section

    private var proSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                Text("Anchor Pro — Active").fontWeight(.medium)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 10) {
                Button("Export Config") {
                    Task { @MainActor in
                        guard let config = try? await ConfigStore().load(),
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
                           let config = try? JSONDecoder().decode(AnchorConfig.self, from: data) {
                            try? await ConfigStore().save(config)
                            MountNotifications.postConfigUpdated()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Free section

    private var freeSection: some View {
        VStack(spacing: 10) {
            Text("Free — up to 3 shares")
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

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
    }

    // MARK: - Footer (#22 — GitHub + MIT)

    private var footer: some View {
        HStack(spacing: 10) {
            Link(destination: URL(string: "https://github.com/Dyad-ITSS/anchor")!) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square").font(.caption2)
                    Text("GitHub")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Text("·").foregroundColor(Color(white: 0.5)).font(.caption)

            HStack(spacing: 4) {
                Image(systemName: "doc.text").font(.caption2)
                Text("MIT Licence")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }
}
