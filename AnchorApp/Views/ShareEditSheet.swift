import SwiftUI
import AnchorCore

struct ShareEditSheet: View {
    let onSave: (Share) -> Void

    @State private var displayName: String
    @State private var host: String
    @State private var shareName: String
    @State private var username: String

    private let existingShare: Share?

    @Environment(\.dismiss) private var dismiss

    init(share: Share?, onSave: @escaping (Share) -> Void) {
        self.existingShare = share
        self.onSave = onSave
        _displayName = State(initialValue: share?.displayName ?? "")
        _host = State(initialValue: share?.host ?? "")
        _shareName = State(initialValue: share?.shareName ?? "")
        _username = State(initialValue: share?.username ?? "")
    }

    private var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        !shareName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(existingShare == nil ? "Add Share" : "Edit Share")
                .font(.headline)
                .padding(.bottom, 16)

            Form {
                TextField("Display Name", text: $displayName)
                    .textFieldStyle(.roundedBorder)

                TextField("Host / IP", text: $host)
                    .textFieldStyle(.roundedBorder)

                TextField("Share Name (case-sensitive)", text: $shareName)
                    .textFieldStyle(.roundedBorder)

                TextField("Username (optional)", text: $username)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.secondary)
                    TextField("VPN Fallback Host", text: .constant(""))
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                        .help("Upgrade to Pro to enable VPN fallback host")
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(width: 360)
    }

    private func save() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        let share = Share(
            id: existingShare?.id ?? UUID(),
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            host: host.trimmingCharacters(in: .whitespaces),
            shareName: shareName.trimmingCharacters(in: .whitespaces),
            username: trimmedUsername.isEmpty ? nil : trimmedUsername,
            port: existingShare?.port,
            unmountWhenUnreachable: existingShare?.unmountWhenUnreachable ?? true,
            fallbackHost: existingShare?.fallbackHost,
            profiles: existingShare?.profiles ?? []
        )
        onSave(share)
        dismiss()
    }
}
