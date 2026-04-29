import Darwin
import Foundation

/// Discovers SMB servers on the local network via Bonjour (_smb._tcp).
/// Resolves the actual IPv4 address so deduplication with subnet scan works correctly.
final class BonjourScanner: NSObject, ObservableObject {
    struct Server: Identifiable, Equatable {
        let id = UUID()
        /// Friendly computer name, e.g. "mikeai" (Bonjour service name).
        let name: String
        /// IP address (preferred) or .local hostname — used as the SMB host value.
        let host: String
        static func == (lhs: Server, rhs: Server) -> Bool {
            lhs.host == rhs.host
        }
    }

    @Published var servers: [Server] = []
    @Published var isSearching = false

    private let browser = NetServiceBrowser()
    private var pending: [NetService] = []
    private var stopTimer: Task<Void, Never>?

    override init() {
        super.init()
        browser.delegate = self
    }

    func start() {
        DispatchQueue.main.async {
            self.isSearching = true
            self.browser.searchForServices(ofType: "_smb._tcp.", inDomain: "")
        }
        stopTimer?.cancel()
        stopTimer = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            await MainActor.run { self.isSearching = false }
        }
    }

    func stop() {
        browser.stop()
        pending.forEach { $0.stop() }
        pending = []
        stopTimer?.cancel()
        DispatchQueue.main.async { self.isSearching = false }
    }

    // MARK: - IP extraction

    /// Extracts the first IPv4 address from a resolved NetService's addresses array.
    private static func extractIPv4(from addresses: [Data]) -> String? {
        for data in addresses {
            var storage = sockaddr_storage()
            (data as NSData).getBytes(&storage, length: MemoryLayout<sockaddr_storage>.size)
            guard storage.ss_family == UInt8(AF_INET) else { continue }
            var addr = sockaddr_in()
            (data as NSData).getBytes(&addr, length: MemoryLayout<sockaddr_in>.size)
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &addr.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN))
            let ip = String(cString: buf)
            guard !ip.isEmpty, ip != "0.0.0.0" else { continue }
            return ip
        }
        return nil
    }
}

extension BonjourScanner: NetServiceBrowserDelegate {
    func netServiceBrowser(_: NetServiceBrowser, didFind service: NetService, moreComing _: Bool) {
        pending.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_: NetServiceBrowser, didRemove service: NetService, moreComing _: Bool) {
        pending.removeAll { $0 === service }
        DispatchQueue.main.async {
            self.servers.removeAll { $0.name == service.name }
        }
    }
}

extension BonjourScanner: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        // Prefer actual IP for the connect host — more reliable than .local when on VPN.
        let ip = Self.extractIPv4(from: sender.addresses ?? [])
        let raw = sender.hostName ?? sender.name
        let hostname = raw.hasSuffix(".") ? String(raw.dropLast()) : raw
        let connectHost = ip ?? hostname

        // Friendly display name: Bonjour service name (computer name, e.g. "mikeai").
        let name = sender.name

        let server = Server(name: name, host: connectHost)
        DispatchQueue.main.async {
            if !self.servers.contains(where: { $0.host == connectHost }) {
                self.servers.append(server)
            }
        }
    }
}
