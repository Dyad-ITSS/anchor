import SwiftUI

struct ProfilesTabView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill").font(.largeTitle).foregroundColor(.secondary)
            Text("Profiles are a Pro feature").fontWeight(.medium)
            Text("Organise shares into Home, Office, and Travel profiles.")
                .multilineTextAlignment(.center).foregroundColor(.secondary).font(.callout)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
