import SwiftUI
import AnchorCore

struct NetworkBrowserSheet: View {
    let onAdd: (_ host: String, _ shareName: String, _ displayName: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var bonjour = BonjourScanner()
    @StateObject private var subnet = SubnetScanner()

    @State private var shareMap: [String: [String]] = [:]
    @State private var loadingHosts: Set<String> = []
    @State private var expandedHost: String? = nil
    @State private var showManualEntry = false
    @State private var manualHost = ""
    @State private var resolvedNames: [String: String] = [:]
    @State private var resolvingIPs: Set<String> = []

    private var allServers: [(name: String, host: String)] {
        var result = bonjour.servers.map { (name: friendlyName($0.name), host: $0.host) }
        let bonjourHosts = Set(bonjour.servers.map(\.host))
        for ip in subnet.found where !bonjourHosts.contains(ip) {
            let name = resolvedNames[ip] ?? ip
            result.append((name: name, host: ip))
        }
        return result
    }

    private func friendlyName(_ raw: String) -> String {
        raw.hasSuffix(".local") ? String(raw.dropLast(6)) : raw
    }

    private func resolveNameIfNeeded(ip: String) {
        guard resolvedNames[ip] == nil, !resolvingIPs.contains(ip) else { return }
        resolvingIPs.insert(ip)
        Task {
            if let name = await ShareEnumerator.serverName(for: ip) {
                resolvedNames[ip] = name.lowercased()
            }
            resolvingIPs.remove(ip)
        }
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
        .task {
            // #17 — Auto-trigger subnet scan if Bonjour finds fewer than 2 servers after 3 s
            try? await Task.sleep(for: .seconds(3))
            if bonjour.servers.count < 2 && !subnet.isScanning {
                await subnet.scan()
            }
        }
        .onChange(of: subnet.found) { ips in
            let bonjourHosts = Set(bonjour.servers.map(\.host))
            for ip in ips where !bonjourHosts.contains(ip) {
                resolveNameIfNeeded(ip: ip)
            }
        }
        .sheet(isPresented: $showManualEntry) { manualEntrySheet }
    }

    // MARK: - Header

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

    // MARK: - Server list

    private var serverList: some View {
        List {
            if allServers.isEmpty {
                if bonjour.isSearching || subnet.isScanning {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.75)
                        Text(subnet.isScanning ? "Scanning subnet…" : "Searching via Bonjour…")
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
        // #19 — resolving skeleton: name is still the IP while lookup runs
        let isResolvingName = resolvingIPs.contains(server.host) && server.name == server.host

        VStack(alignment: .leading, spacing: 0) {
            EmptyView().onAppear {
                if server.name == server.host { resolveNameIfNeeded(ip: server.host) }
            }

            // Server header row
            Button { toggleExpand(server) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "server.rack")
                        .foregroundColor(.accentColor)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        if isResolvingName {
                            // #19 — skeleton placeholder while NetBIOS name resolves
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 100, height: 12)
                            Text(server.host).font(.caption).foregroundColor(.secondary)
                        } else {
                            Text(server.name).fontWeight(.medium)
                            if server.name != server.host {
                                Text(server.host).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }

                    Spacer()

                    if isLoading {
                        ProgressView().scaleEffect(0.65)
                    } else {
                        // #18 — animated chevron rotation
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundColor(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .animation(.easeInOut(duration: 0.18), value: isExpanded)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Share sub-rows
            if isExpanded {
                if let shares {
                    if shares.isEmpty {
                        Text("No accessible shares found")
                            .font(.caption).foregroundColor(.secondary)
                            .padding(.leading, 34).padding(.top, 4)
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
                                        .frame(width: 16)
                                    Text(share)
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .font(.caption).foregroundColor(.accentColor)
                                }
                                // #20 — deeper indent for share rows
                                .padding(.leading, 34)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Bottom bar

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
            Button { showManualEntry = true } label: {
                Label("Enter IP Manually…", systemImage: "keyboard")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Manual entry sheet

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
        if expandedHost == server.host { expandedHost = nil; return }
        expandedHost = server.host
        guard shareMap[server.host] == nil && !loadingHosts.contains(server.host) else { return }
        loadingHosts.insert(server.host)
        Task {
            let shares = await ShareEnumerator.enumerate(host: server.host)
            shareMap[server.host] = shares
            loadingHosts.remove(server.host)
        }
    }
}
