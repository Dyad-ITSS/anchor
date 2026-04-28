import SwiftUI
import AnchorCore
import Network
import AppKit

// NSViewRepresentable wrapper — fixes macOS SwiftUI paste rendering bug where
// pasted text doesn't appear until focus changes (setNeedsDisplay not called).
private struct NativeTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var isDisabled: Bool = false

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        field.isEditable = !isDisabled
        field.isEnabled = !isDisabled
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text { nsView.stringValue = text }
        nsView.isEditable = !isDisabled
        nsView.isEnabled = !isDisabled
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        init(text: Binding<String>) { _text = text }
        func controlTextDidChange(_ obj: Notification) {
            guard let f = obj.object as? NSTextField else { return }
            text = f.stringValue
        }
    }
}

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

            VStack(spacing: 8) {
                NativeTextField(placeholder: "Display Name", text: $displayName)
                    .frame(height: 22)

                NativeTextField(placeholder: "Host / IP", text: $host)
                    .frame(height: 22)

                NativeTextField(placeholder: "Share Name (case-sensitive)", text: $shareName)
                    .frame(height: 22)

                NativeTextField(placeholder: "Username (optional)", text: $username)
                    .frame(height: 22)

                HStack {
                    if !entitlement.isPro {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.secondary)
                    }
                    NativeTextField(
                        placeholder: vpnFallbackPlaceholder,
                        text: entitlement.isPro ? $fallbackHost : .constant(""),
                        isDisabled: !entitlement.isPro
                    )
                    .frame(height: 22)
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
