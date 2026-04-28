import Foundation

/// Discovers SMB servers on the local network via Bonjour (_smb._tcp).
/// Results appear within ~1 second for properly advertising devices.
final class BonjourScanner: NSObject, ObservableObject {

    struct Server: Identifiable, Equatable {
        let id = UUID()
        let name: String   // "Mike's Mac Mini"
        let host: String   // "mac-mini.local" or resolved IP
        static func == (lhs: Server, rhs: Server) -> Bool { lhs.host == rhs.host }
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
}

extension BonjourScanner: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        pending.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        pending.removeAll { $0 === service }
        DispatchQueue.main.async {
            self.servers.removeAll { $0.name == service.name }
        }
    }
}

extension BonjourScanner: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        let raw = sender.hostName ?? sender.name
        let host = raw.hasSuffix(".") ? String(raw.dropLast()) : raw
        let server = Server(name: sender.name, host: host)
        DispatchQueue.main.async {
            if !self.servers.contains(where: { $0.host == server.host }) {
                self.servers.append(server)
            }
        }
    }
}
