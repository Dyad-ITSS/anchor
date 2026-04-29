import AnchorCore
import AppKit
import Network
import SwiftUI

enum TestState: Equatable {
    case idle
    case testing
    case ok(Int)
    case fail
    case skipped
}

/// Fixes macOS SwiftUI paste-not-rendering bug (NativeTextField uses AppKit delegate).
private struct NativeTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var isDisabled: Bool = false

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField()
        f.placeholderString = placeholder
        f.bezelStyle = .roundedBezel
        f.delegate = context.coordinator
        f.isEditable = !isDisabled
        f.isEnabled = !isDisabled
        return f
    }

    func updateNSView(_ v: NSTextField, context _: Context) {
        if v.stringValue != text { v.stringValue = text }
        v.isEditable = !isDisabled
        v.isEnabled = !isDisabled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let f = obj.object as? NSTextField else { return }
            text = f.stringValue
        }
    }
}

/// #12 — Sentence-case label + native field (replaces uppercase style)
private struct FieldRow: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isDisabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
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
    @State private var lanState: TestState = .idle
    @State private var vpnState: TestState = .idle
    @State private var discoveredShares: [String] = []
    @State private var isDiscovering = false
    @State private var discoveryAttempted = false

    private let existingShare: Share?
    @Environment(\.dismiss) private var dismiss

    private var detectedVPN: String? {
        UserDefaults(suiteName: "group.com.dyad-itss.anchor")?.string(forKey: "detectedVPN")
    }

    init(share: Share?,
         prefilledHost: String = "",
         prefilledShareName: String = "",
         prefilledDisplayName: String = "",
         onSave: @escaping (Share) -> Void) {
        existingShare = share
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text(existingShare == nil ? "Add Share" : "Edit Share")
                .font(.headline)
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)

            Divider()

            // Form — no ScrollView (#16), fixed content fits in frame
            VStack(alignment: .leading, spacing: 12) {
                FieldRow(label: "Display name", placeholder: "e.g. Mac Mini (dev)", text: $displayName)

                HStack(spacing: 8) {
                    FieldRow(label: "Host / IP", placeholder: "192.168.0.99", text: $host)
                    FieldRow(label: "Port", placeholder: "445", text: $portString)
                        .frame(width: 80)
                }

                shareNameField

                FieldRow(label: "Username", placeholder: "blank = Keychain default", text: $username)

                // Pro section (#14 — subtle tinted background)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Rectangle().frame(height: 1).foregroundColor(Color(white: 0.5, opacity: 0.15))
                        HStack(spacing: 5) {
                            Text("Pro")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(entitlement.isPro ? .accentColor : .secondary)
                                .textCase(.uppercase)
                                .kerning(1)
                            if !entitlement.isPro {
                                Image(systemName: "lock.fill").font(.system(size: 9)).foregroundColor(.secondary)
                            }
                        }
                        Rectangle().frame(height: 1).foregroundColor(Color(white: 0.5, opacity: 0.15))
                    }

                    FieldRow(
                        label: "VPN fallback host",
                        placeholder: detectedVPN.map { "e.g. 100.64.x.x — \($0) detected" }
                            ?? "e.g. 100.64.93.215 or hostname.tailscale",
                        text: entitlement.isPro ? $fallbackHost : .constant(""),
                        isDisabled: !entitlement.isPro
                    )
                    .help("Mesh VPN IP (e.g. 100.64.x.x) or hostname used when the LAN host is unreachable. Enter a Tailscale, NetBird, or ZeroTier address.") // #13
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(entitlement.isPro ? 0.04 : 0.02))
                )

                testConnectionCard
            }
            .padding(20)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(!isValid)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(width: 400)
        .task {
            guard existingShare == nil,
                  !host.trimmingCharacters(in: .whitespaces).isEmpty,
                  shareName.isEmpty
            else { return }
            await discoverShares()
        }
    }

    // MARK: - Share name field

    private var shareNameField: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Share name")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                if !host.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        Task { await discoverShares() }
                    } label: {
                        if isDiscovering {
                            HStack(spacing: 3) {
                                ProgressView().scaleEffect(0.55)
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
                        HStack { Image(systemName: "folder"); Text(s) }.tag(s)
                    }
                }
                .labelsHidden()
                .onChange(of: shareName) { v in
                    if displayName.isEmpty || displayName == host { displayName = v }
                }
            } else {
                NativeTextField(placeholder: "case-sensitive", text: $shareName).frame(height: 22)
            }

            if discoveryAttempted && discoveredShares.isEmpty && !isDiscovering {
                Text("No accessible shares found — enter name manually")
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Test connection card

    private var testConnectionCard: some View {
        let isTesting = lanState == .testing || vpnState == .testing
        let hasVPN = entitlement.isPro && !fallbackHost.trimmingCharacters(in: .whitespaces).isEmpty
        return VStack(alignment: .leading, spacing: 8) {
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
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.5, opacity: 0.15), lineWidth: 1))
    }

    // MARK: - Logic

    private func discoverShares() async {
        isDiscovering = true
        let h = host.trimmingCharacters(in: .whitespaces)
        let u = username.trimmingCharacters(in: .whitespaces)
        discoveredShares = await ShareEnumerator.enumerate(host: h, username: u.isEmpty ? nil : u)
        discoveryAttempted = true
        isDiscovering = false
        if discoveredShares.count == 1 { shareName = discoveredShares[0] }
    }

    private func testConnection() async {
        let lanHost = host.trimmingCharacters(in: .whitespaces)
        let vpnHost = fallbackHost.trimmingCharacters(in: .whitespaces)
        let hasVPN = entitlement.isPro && !vpnHost.isEmpty
        lanState = .testing
        vpnState = hasVPN ? .testing : .skipped
        async let lan = probe445(host: lanHost)
        async let vpn = hasVPN ? probe445(host: vpnHost) : (false, 0)
        let (lanOk, lanMs) = await lan
        let (vpnOk, vpnMs) = await vpn
        lanState = lanOk ? .ok(lanMs) : .fail
        vpnState = hasVPN ? (vpnOk ? .ok(vpnMs) : .fail) : .skipped
    }

    private func probe445(host: String) async -> (Bool, Int) {
        let start = Date()
        let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let conn = NWConnection(host: .init(host), port: 445, using: .tcp)
            var done = false
            let timer = DispatchWorkItem {
                guard !done else { return }; done = true; conn.cancel(); cont.resume(returning: false)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5, execute: timer)
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard !done else { return }; done = true; timer.cancel(); conn.cancel(); cont.resume(returning: true)
                case .failed, .cancelled:
                    guard !done else { return }; done = true; timer.cancel(); cont.resume(returning: false)
                default: break
                }
            }
            conn.start(queue: .global())
        }
        return (ok, Int(Date().timeIntervalSince(start) * 1000))
    }

    private func save() {
        let trimmedUser = username.trimmingCharacters(in: .whitespaces)
        let trimmedFallback = fallbackHost.trimmingCharacters(in: .whitespaces)
        onSave(Share(
            id: existingShare?.id ?? UUID(),
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            host: host.trimmingCharacters(in: .whitespaces),
            shareName: shareName.trimmingCharacters(in: .whitespaces),
            username: trimmedUser.isEmpty ? nil : trimmedUser,
            port: Int(portString.trimmingCharacters(in: .whitespaces)),
            unmountWhenUnreachable: existingShare?.unmountWhenUnreachable ?? true,
            fallbackHost: entitlement.isPro && !trimmedFallback.isEmpty ? trimmedFallback : existingShare?.fallbackHost,
            profiles: existingShare?.profiles ?? []
        ))
        dismiss()
    }
}

// MARK: - TestPathRow

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
            case .idle: EmptyView()
            case .testing:
                ProgressView().scaleEffect(0.6)
                Text("Testing…").font(.caption).foregroundColor(.secondary)
            case let .ok(ms):
                let color: Color = isVPN ? .blue : .green
                Circle().fill(color).frame(width: 7, height: 7).shadow(color: color.opacity(0.5), radius: 2)
                Text("Reachable · \(ms)ms").font(.caption).foregroundColor(color)
            case .fail:
                Circle().fill(Color.red).frame(width: 7, height: 7)
                Text("Unreachable").font(.caption).foregroundColor(.red)
            case .skipped:
                Text("—  no fallback host configured").font(.caption).foregroundColor(Color(white: 0.5))
            }
        }
    }
}
