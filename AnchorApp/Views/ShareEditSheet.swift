import SwiftUI
import AnchorCore
import Network
import AppKit

enum TestState: Equatable {
    case idle
    case testing
    case ok(Int)
    case fail
    case skipped  // VPN path when no fallback host is configured
}

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

// Label + native field pair matching the mockup design
private struct LabeledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isDisabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            NativeTextField(placeholder: placeholder, text: $text, isDisabled: isDisabled)
                .frame(height: 22)
        }
    }
}

struct ShareEditSheet: View {
    @EnvironmentObject var entitlement: EntitlementManager

    let onSave: (Share) -> Void

    @State private var displayName: String
    @State private var host: String
    @State private var shareName: String
    @State private var username: String
    @State private var portString: String
    @State private var fallbackHost: String
    @State private var testState: TestState = .idle

    // Share discovery
    @State private var discoveredShares: [String] = []
    @State private var isDiscovering = false
    @State private var discoveryAttempted = false

    // Connection test — separate state per path
    @State private var lanState: TestState = .idle
    @State private var vpnState: TestState = .idle

    private let existingShare: Share?

    @Environment(\.dismiss) private var dismiss

    private var detectedVPN: String? {
        UserDefaults(suiteName: "group.com.yourname.anchor")?.string(forKey: "detectedVPN")
    }

    init(share: Share?,
         prefilledHost: String = "",
         prefilledShareName: String = "",
         prefilledDisplayName: String = "",
         onSave: @escaping (Share) -> Void) {
        self.existingShare = share
        self.onSave = onSave
        _displayName = State(initialValue: share?.displayName ?? prefilledDisplayName)
        _host = State(initialValue: share?.host ?? prefilledHost)
        _shareName = State(initialValue: share?.shareName ?? prefilledShareName)
        _username = State(initialValue: share?.username ?? "")
        _portString = State(initialValue: share?.port.map(String.init) ?? "")
        _fallbackHost = State(initialValue: share?.fallbackHost ?? "")
    }

    private var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        !shareName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var vpnPlaceholder: String {
        if let vpn = detectedVPN, vpn != "None" {
            return "e.g. 100.64.93.215 — \(vpn) detected"
        }
        return "e.g. 100.64.93.215 or hostname.tailscale"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(existingShare == nil ? "Add Share" : "Edit Share")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {

                    LabeledField(label: "Display Name", placeholder: "e.g. Mac Mini (dev)", text: $displayName)

                    HStack(spacing: 8) {
                        LabeledField(label: "Host / IP", placeholder: "192.168.0.99", text: $host)
                        LabeledField(label: "Port (blank = 445)", placeholder: "445", text: $portString)
                            .frame(width: 90)
                    }

                    // Share Name — picker if shares discovered, text field otherwise
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("SHARE NAME")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            if !host.trimmingCharacters(in: .whitespaces).isEmpty {
                                Button {
                                    Task { await discoverShares() }
                                } label: {
                                    if isDiscovering {
                                        HStack(spacing: 4) {
                                            ProgressView().scaleEffect(0.6)
                                            Text("Discovering…").font(.system(size: 10))
                                        }
                                    } else {
                                        Label(discoveryAttempted ? "Refresh" : "Discover Shares",
                                              systemImage: "arrow.clockwise.circle")
                                            .font(.system(size: 10))
                                    }
                                }
                                .buttonStyle(.borderless)
                                .foregroundColor(.accentColor)
                                .disabled(isDiscovering)
                            }
                        }
                        if !discoveredShares.isEmpty {
                            Picker("", selection: $shareName) {
                                Text("Select a share…").tag("")
                                ForEach(discoveredShares, id: \.self) { s in
                                    HStack {
                                        Image(systemName: "folder")
                                        Text(s)
                                    }.tag(s)
                                }
                            }
                            .labelsHidden()
                            .onChange(of: shareName) { newValue in
                                if displayName.isEmpty || displayName == host {
                                    displayName = newValue
                                }
                            }
                        } else {
                            NativeTextField(placeholder: "case-sensitive", text: $shareName)
                                .frame(height: 22)
                        }
                        if discoveryAttempted && discoveredShares.isEmpty && !isDiscovering {
                            Text("No accessible shares found — enter name manually")
                                .font(.system(size: 10)).foregroundColor(.secondary)
                        }
                    }

                    LabeledField(label: "Username (blank = Keychain default)", placeholder: "", text: $username)

                    // Pro Features divider
                    HStack(spacing: 8) {
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(Color(white: 0.5, opacity: 0.2))
                        HStack(spacing: 4) {
                            Text("Pro Features")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                            if !entitlement.isPro {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(Color(white: 0.5, opacity: 0.2))
                    }
                    .padding(.vertical, 2)

                    LabeledField(
                        label: "VPN Fallback Host",
                        placeholder: vpnPlaceholder,
                        text: entitlement.isPro ? $fallbackHost : .constant(""),
                        isDisabled: !entitlement.isPro
                    )
                    .help(entitlement.isPro ? "Mesh VPN IP or hostname used when LAN is unreachable" : "Upgrade to Pro to enable VPN fallback routing")

                    // Test Connection — tests LAN + VPN in parallel
                    let isTesting = lanState == .testing || vpnState == .testing
                    let hasVPN = entitlement.isPro && !fallbackHost.trimmingCharacters(in: .whitespaces).isEmpty
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Button(action: { Task { await testConnection() } }) {
                                HStack(spacing: 5) {
                                    if isTesting { ProgressView().scaleEffect(0.7) }
                                    Text("Test Connection")
                                }
                            }
                            .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty || isTesting)

                            if lanState == .idle && vpnState == .idle {
                                Text(hasVPN ? "Tests LAN + VPN paths" : "Tests LAN path")
                                    .font(.caption).foregroundColor(Color(white: 0.5))
                            }
                            Spacer()
                        }

                        if lanState != .idle || vpnState != .idle {
                            VStack(alignment: .leading, spacing: 4) {
                                TestPathRow(label: "LAN", state: lanState)
                                if hasVPN || vpnState != .idle {
                                    TestPathRow(label: "VPN", state: vpnState, isVPN: true)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(white: 0.5, opacity: 0.15), lineWidth: 1)
                    )
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 400)
        .task {
            // Auto-discover shares when sheet opens with a pre-filled host
            guard existingShare == nil,
                  !host.trimmingCharacters(in: .whitespaces).isEmpty,
                  shareName.isEmpty
            else { return }
            await discoverShares()
        }
    }

    private func discoverShares() async {
        isDiscovering = true
        let h = host.trimmingCharacters(in: .whitespaces)
        let u = username.trimmingCharacters(in: .whitespaces)
        discoveredShares = await ShareEnumerator.enumerate(host: h, username: u.isEmpty ? nil : u)
        discoveryAttempted = true
        isDiscovering = false
        // Auto-select if only one share found
        if discoveredShares.count == 1 {
            shareName = discoveredShares[0]
        }
    }

    private func testConnection() async {
        let lanHost = host.trimmingCharacters(in: .whitespaces)
        let vpnHost = fallbackHost.trimmingCharacters(in: .whitespaces)
        let hasVPN = entitlement.isPro && !vpnHost.isEmpty

        lanState = .testing
        vpnState = hasVPN ? .testing : .skipped

        // Run both probes in parallel
        async let lanProbe = probe445(host: lanHost)
        async let vpnProbe = hasVPN ? probe445(host: vpnHost) : (false, 0)

        let (lanOk, lanMs) = await lanProbe
        let (vpnOk, vpnMs) = await vpnProbe

        lanState = lanOk ? .ok(lanMs) : .fail
        vpnState = hasVPN ? (vpnOk ? .ok(vpnMs) : .fail) : .skipped
    }

    private func probe445(host: String) async -> (Bool, Int) {
        let start = Date()
        let reachable = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let conn = NWConnection(host: .init(host), port: 445, using: .tcp)
            var done = false
            let timer = DispatchWorkItem {
                guard !done else { return }
                done = true; conn.cancel()
                cont.resume(returning: false)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5, execute: timer)
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard !done else { return }
                    done = true; timer.cancel(); conn.cancel()
                    cont.resume(returning: true)
                case .failed, .cancelled:
                    guard !done else { return }
                    done = true; timer.cancel()
                    cont.resume(returning: false)
                default: break
                }
            }
            conn.start(queue: .global())
        }
        return (reachable, Int(Date().timeIntervalSince(start) * 1000))
    }

    private func save() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        let trimmedFallback = fallbackHost.trimmingCharacters(in: .whitespaces)
        let port = Int(portString.trimmingCharacters(in: .whitespaces))
        let share = Share(
            id: existingShare?.id ?? UUID(),
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            host: host.trimmingCharacters(in: .whitespaces),
            shareName: shareName.trimmingCharacters(in: .whitespaces),
            username: trimmedUsername.isEmpty ? nil : trimmedUsername,
            port: port,
            unmountWhenUnreachable: existingShare?.unmountWhenUnreachable ?? true,
            fallbackHost: entitlement.isPro && !trimmedFallback.isEmpty ? trimmedFallback : existingShare?.fallbackHost,
            profiles: existingShare?.profiles ?? []
        )
        onSave(share)
        dismiss()
    }
}

// MARK: - Test path result row

private struct TestPathRow: View {
    let label: String
    let state: TestState
    var isVPN: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 28, alignment: .leading)

            switch state {
            case .idle:
                EmptyView()
            case .testing:
                ProgressView().scaleEffect(0.6)
                Text("Testing…").font(.caption).foregroundColor(.secondary)
            case .ok(let ms):
                let color: Color = isVPN ? .blue : .green
                Circle().fill(color).frame(width: 7, height: 7)
                    .shadow(color: color.opacity(0.5), radius: 2)
                Text("Reachable · \(ms)ms").font(.caption).foregroundColor(color)
            case .fail:
                Circle().fill(Color.red).frame(width: 7, height: 7)
                Text("Unreachable").font(.caption).foregroundColor(.red)
            case .skipped:
                Text("—").font(.caption).foregroundColor(Color(white: 0.5))
                Text("no fallback host configured").font(.caption).foregroundColor(Color(white: 0.5))
            }
        }
    }
}
