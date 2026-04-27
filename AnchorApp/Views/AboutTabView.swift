import SwiftUI

struct AboutTabView: View {
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

            Text("Free — up to 3 shares")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(6)

            VStack(spacing: 8) {
                Button("Upgrade to Pro — $9.99") {
                    // TODO: Implement StoreKit purchase (Task 14)
                }
                .buttonStyle(.borderedProminent)

                Button("Restore Purchase") {
                    // TODO: Implement StoreKit restore (Task 14)
                }
                .foregroundColor(.secondary)

                Link("View on GitHub", destination: URL(string: "https://github.com")!)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
