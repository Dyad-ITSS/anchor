import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            SharesTabView()
                .tabItem { Label("Shares", systemImage: "externaldrive.connected.to.line.below") }
            ProfilesTabView()
                .tabItem { Label("Profiles", systemImage: "person.2") }
            AboutTabView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 380)
    }
}
