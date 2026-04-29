import Darwin
import Foundation
import Network

/// Scans the local /24 subnet for hosts with port 445 open.
/// Uses NWConnection (works in sandbox with network.client entitlement).
@MainActor
final class SubnetScanner: ObservableObject {
    @Published var found: [String] = []
    @Published var isScanning = false
    @Published var progress: Double = 0

    func scan() async {
        guard let ips = localSubnetIPs() else { return }
        isScanning = true
        found = []
        progress = 0

        let total = ips.count
        var completed = 0

        for batch in ips.chunked(into: 40) {
            await withTaskGroup(of: (String, Bool).self) { group in
                for ip in batch {
                    group.addTask { (ip, await Self.probe445(host: ip)) }
                }
                for await (ip, open) in group {
                    completed += 1
                    progress = Double(completed) / Double(total)
                    if open { found.append(ip) }
                }
            }
        }

        isScanning = false
    }

    // MARK: - Private

    private static func probe445(host: String) async -> Bool {
        await withCheckedContinuation { cont in
            let conn = NWConnection(host: .init(host), port: 445, using: .tcp)
            var done = false
            let timeout = DispatchWorkItem {
                guard !done else { return }
                done = true; conn.cancel()
                cont.resume(returning: false)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5, execute: timeout)
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard !done else { return }
                    done = true; timeout.cancel(); conn.cancel()
                    cont.resume(returning: true)
                case .failed, .cancelled:
                    guard !done else { return }
                    done = true; timeout.cancel()
                    cont.resume(returning: false)
                default: break
                }
            }
            conn.start(queue: .global())
        }
    }

    private func localSubnetIPs() -> [String]? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let addr = ptr {
            defer { ptr = addr.pointee.ifa_next }
            guard addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: addr.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }

            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            addr.pointee.ifa_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                inet_ntop(AF_INET, &$0.pointee.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN))
            }
            let ip = String(cString: buf)
            guard !ip.hasPrefix("127."), !ip.hasPrefix("169.254.") else { continue }

            let parts = ip.split(separator: ".")
            guard parts.count == 4 else { continue }
            let base = "\(parts[0]).\(parts[1]).\(parts[2])."
            return (1 ... 254).map { "\(base)\($0)" }
        }
        return nil
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
