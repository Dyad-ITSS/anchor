import SwiftUI
import AnchorCore

struct NetworkBrowserSheet: View {
    /// Called when the user picks a share (or just a host for manual name entry).
    let onAdd: (_ host: String, _ shareName: String, _ displayName: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var bonjour = BonjourScanner()
    @StateObject private var subnet = SubnetScanner()

    // Shares discovered per host: nil = not yet fetched, [] = fetched but empty
    @State private var shareMap: [String: [String]] = [:]
    @State private var loadingHosts: Set<String> = []
    @State private var expandedHost: String? = nil
    @State private var showManualEntry = false
    @State private var manualHost = ""

    private var allServers: [(name: String, host: String)] {
        var result = bonjour.servers.map { (name: $0.name, host: $0.host) }
        let bonjourHosts = Set(bonjour.servers.map(\.host))
        for ip in subnet.found where !bonjourHosts.contains(ip) {
            result.append((name: ip, host: ip))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            serverList
            Divider()
            bottomBar
        }
        .frame(width: 400, height: 460)
        .onAppear { bonjour.start() }
        .onDisappear { bonjour.stop() }
        .sheet(isPresented: $showManualEntry) { manualEntrySheet }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Browse Network").font(.headline)
                Text("Select a server then pick a share")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }
        }
        .padding(16)
    }

    private var serverList: some View {
        List {
            if allServers.isEmpty {
                if bonjour.isSearching {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.75)
                        Text("Searching via Bonjour…")
                            .font(.callout).foregroundColor(.secondary)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Label("No servers found on this network", systemImage: "network.slash")
                        .foregroundColor(.secondary)
                        .listRowBackground(Color.clear)
                }
            }

            ForEach(allServers, id: \.host) { server in
                serverRow(server)
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func serverRow(_ server: (name: String, host: String)) -> some View {
        let isExpanded = expandedHost == server.host
        let shares = shareMap[server.host]
        let isLoading = loadingHosts.contains(server.host)

        VStack(alignment: .leading, spacing: 0) {
            // Server header row
            Button {
                toggleExpand(server)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "server.rack")
                        .foregroundColor(.accentColor)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.name).fontWeight(.medium)
                        if server.name != server.host {
                            Text(server.host).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    if isLoading {
                        ProgressView().scaleEffect(0.65)
                    } else {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Shares sub-rows
            if isExpanded {
                if let shares {
                    if shares.isEmpty {
                        Text("No accessible shares found")
                            .font(.caption).foregroundColor(.secondary)
                            .padding(.leading, 30).padding(.top, 4)
                    } else {
                        ForEach(shares, id: \.self) { share in
                            Button {
                                let display = "\(server.name) (\(share))"
                                onAdd(server.host, share, display)
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "folder")
                                        .font(.caption).foregroundColor(.secondary)
                                        .frame(width: 20)
                                    Text(share)
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .font(.caption).foregroundColor(.accentColor)
                                }
                                .padding(.leading, 10)
                                .padding(.vertical, 3)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if subnet.isScanning {
                ProgressView(value: subnet.progress).frame(width: 80)
                Text("Scanning…").font(.caption).foregroundColor(.secondary)
            } else {
                Button {
                    Task { await subnet.scan() }
                } label: {
                    Label("Scan Subnet", systemImage: "magnifyingglass.circle")
                }
                .buttonStyle(.borderless)
                .help("Scan all IPs on this subnet for SMB servers (port 445)")
            }
            Spacer()
            Button {
                showManualEntry = true
            } label: {
                Label("Enter IP Manually…", systemImage: "keyboard")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var manualEntrySheet: some View {
        VStack(spacing: 12) {
            Text("Enter Server Address").font(.headline)
            Text("IP address or hostname of the SMB server")
                .font(.caption).foregroundColor(.secondary)
            TextField("192.168.0.99 or server.local", text: $manualHost)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
            HStack {
                Button("Cancel") { showManualEntry = false }
                    .keyboardShortcut(.cancelAction)
                Button("Browse Shares") {
                    let h = manualHost.trimmingCharacters(in: .whitespaces)
                    guard !h.isEmpty else { return }
                    showManualEntry = false
                    onAdd(h, "", h)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(manualHost.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    // MARK: - Logic

    private func toggleExpand(_ server: (name: String, host: String)) {
        if expandedHost == server.host {
            expandedHost = nil
            return
        }
        expandedHost = server.host
        // Only enumerate if we haven't yet
        guard shareMap[server.host] == nil && !loadingHosts.contains(server.host) else { return }
        loadingHosts.insert(server.host)
        Task {
            let shares = await ShareEnumerator.enumerate(host: server.host)
            shareMap[server.host] = shares
            loadingHosts.remove(server.host)
        }
    }
}
