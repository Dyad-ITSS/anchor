import SwiftUI
import AnchorCore
import Network

enum TestState: Equatable {
    case idle
    case testing
    case ok(Int)
    case fail
}

struct ShareEditSheet: View {
    @EnvironmentObject var entitlement: EntitlementManager

    let onSave: (Share) -> Void

    @State private var displayName: String
    @State private var host: String
    @State private var shareName: String
    @State private var username: String
    @State private var fallbackHost: String
    @State private var testState: TestState = .idle

    private let existingShare: Share?

    @Environment(\.dismiss) private var dismiss

    private var detectedVPN: String? {
        UserDefaults(suiteName: "group.com.yourname.anchor")?.string(forKey: "detectedVPN")
    }

    init(share: Share?, onSave: @escaping (Share) -> Void) {
        self.existingShare = share
        self.onSave = onSave
        _displayName = State(initialValue: share?.displayName ?? "")
        _host = State(initialValue: share?.host ?? "")
        _shareName = State(initialValue: share?.shareName ?? "")
        _username = State(initialValue: share?.username ?? "")
        _fallbackHost = State(initialValue: share?.fallbackHost ?? "")
    }

    private var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        !shareName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var vpnFallbackPlaceholder: String {
        if let vpn = detectedVPN, vpn != "None" {
            return "VPN Fallback Host (\(vpn) detected)"
        }
        return "VPN Fallback Host"
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
                    if !entitlement.isPro {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.secondary)
                    }
                    TextField(
                        vpnFallbackPlaceholder,
                        text: entitlement.isPro ? $fallbackHost : .constant("")
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(!entitlement.isPro)
                    .help(entitlement.isPro ? "VPN fallback host for this share" : "Upgrade to Pro to enable VPN fallback host")
                }
            }

            HStack(spacing: 10) {
                Button(action: { Task { await testConnection() } }) {
                    HStack(spacing: 5) {
                        if case .testing = testState {
                            ProgressView().scaleEffect(0.7)
                        }
                        Text("Test Connection")
                    }
                }
                .disabled(host.isEmpty || testState == .testing)

                switch testState {
                case .idle: EmptyView()
                case .testing: Text("Testing…").font(.caption).foregroundColor(.secondary)
                case .ok(let ms):
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 7, height: 7)
                        Text("Reachable · \(ms)ms").font(.caption).foregroundColor(.green)
                    }
                case .fail:
                    HStack(spacing: 4) {
                        Circle().fill(Color.red).frame(width: 7, height: 7)
                        Text("Unreachable").font(.caption).foregroundColor(.red)
                    }
                }
                Spacer()
            }
            .padding(.top, 8)

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

    private func testConnection() async {
        testState = .testing
        let start = Date()
        let reachable = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let conn = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: 445)!,
                using: .tcp
            )
            var done = false
            let timer = DispatchWorkItem {
                guard !done else { return }
                done = true
                conn.cancel()
                cont.resume(returning: false)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5, execute: timer)
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard !done else { return }
                    done = true
                    timer.cancel()
                    conn.cancel()
                    cont.resume(returning: true)
                case .failed, .cancelled:
                    guard !done else { return }
                    done = true
                    timer.cancel()
                    cont.resume(returning: false)
                default: break
                }
            }
            conn.start(queue: .global())
        }
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        testState = reachable ? .ok(ms) : .fail
    }

    private func save() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        let trimmedFallback = fallbackHost.trimmingCharacters(in: .whitespaces)
        let share = Share(
            id: existingShare?.id ?? UUID(),
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            host: host.trimmingCharacters(in: .whitespaces),
            shareName: shareName.trimmingCharacters(in: .whitespaces),
            username: trimmedUsername.isEmpty ? nil : trimmedUsername,
            port: existingShare?.port,
            unmountWhenUnreachable: existingShare?.unmountWhenUnreachable ?? true,
            fallbackHost: entitlement.isPro && !trimmedFallback.isEmpty ? trimmedFallback : existingShare?.fallbackHost,
            profiles: existingShare?.profiles ?? []
        )
        onSave(share)
        dismiss()
    }
}
