import Foundation
import Network

// MARK: - VPNKind

enum VPNKind: String {
    case tailscale = "Tailscale"
    case netbird   = "NetBird"
    case zerotier  = "ZeroTier"
    case wireguard = "WireGuard (generic)"
    case none      = "None"
}

// MARK: - VPNDetector

enum VPNDetector {
    /// Returns the detected mesh VPN, or .none.
    ///
    /// Detection order (highest specificity first):
    /// 1. Tailscale  — 100.64/10 range + `tailscaled` process running
    /// 2. NetBird    — 100.64/10 range (no tailscaled process)
    /// 3. ZeroTier   — 172.22/15 range (172.22.x.x or 172.23.x.x)
    /// 4. WireGuard  — `utun` interface with any private IP not matched above
    /// 5. None
    static func detect() -> VPNKind {
        let interfaces = enumerateInterfaces()

        // Check Tailscale first — same IP range as NetBird; process presence distinguishes them.
        for iface in interfaces {
            if isInCGNATRange(iface.addr) {
                if tailscaledIsRunning() {
                    writeToUserDefaults(VPNKind.tailscale)
                    return .tailscale
                }
            }
        }

        // NetBird — 100.64/10, no tailscaled process.
        for iface in interfaces {
            if isInCGNATRange(iface.addr) {
                writeToUserDefaults(VPNKind.netbird)
                return .netbird
            }
        }

        // ZeroTier — 172.22/15 (172.22.x.x and 172.23.x.x).
        for iface in interfaces {
            if isInZeroTierRange(iface.addr) {
                writeToUserDefaults(VPNKind.zerotier)
                return .zerotier
            }
        }

        // Generic WireGuard — utun interface with any private IP not already matched.
        for iface in interfaces where iface.name.hasPrefix("utun") {
            if isPrivateIP(iface.addr) && !isInCGNATRange(iface.addr) && !isInZeroTierRange(iface.addr) {
                writeToUserDefaults(VPNKind.wireguard)
                return .wireguard
            }
        }

        writeToUserDefaults(VPNKind.none)
        return .none
    }

    // MARK: - Private helpers

    private struct Interface {
        let name: String
        let addr: in_addr
    }

    /// Walks `getifaddrs` and returns IPv4 interfaces.
    private static func enumerateInterfaces() -> [Interface] {
        var result: [Interface] = []
        var ifaPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaPtr) == 0, let head = ifaPtr else { return result }
        defer { freeifaddrs(head) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }
            guard let sa = ifa.pointee.ifa_addr,
                  sa.pointee.sa_family == AF_INET else { continue }
            let name = String(cString: ifa.pointee.ifa_name)
            let addr = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            result.append(Interface(name: name, addr: addr))
        }
        return result
    }

    /// `100.64.0.0/10` — shared between Tailscale and NetBird.
    /// Range: 100.64.0.0 – 100.127.255.255
    private static func isInCGNATRange(_ addr: in_addr) -> Bool {
        // Network byte order: addr.s_addr is big-endian on all platforms.
        let ip = bigEndianToHost(addr.s_addr)
        // 100.64.0.0  = 0x64400000
        // 100.127.255.255 = 0x647FFFFF
        // Mask /10 = 0xFFC00000
        let network: UInt32 = 0x64400000
        let mask: UInt32    = 0xFFC00000
        return (ip & mask) == (network & mask)
    }

    /// `172.22.0.0/15` — ZeroTier.
    /// Range: 172.22.0.0 – 172.23.255.255
    private static func isInZeroTierRange(_ addr: in_addr) -> Bool {
        let ip = bigEndianToHost(addr.s_addr)
        // 172.22.0.0  = 0xAC160000
        // Mask /15 = 0xFFFE0000
        let network: UInt32 = 0xAC160000
        let mask: UInt32    = 0xFFFE0000
        return (ip & mask) == (network & mask)
    }

    /// Returns true for RFC-1918 private ranges:
    /// 10/8, 172.16/12, 192.168/16
    private static func isPrivateIP(_ addr: in_addr) -> Bool {
        let ip = bigEndianToHost(addr.s_addr)
        let ranges: [(network: UInt32, mask: UInt32)] = [
            (0x0A000000, 0xFF000000), // 10.0.0.0/8
            (0xAC100000, 0xFFF00000), // 172.16.0.0/12
            (0xC0A80000, 0xFFFF0000), // 192.168.0.0/16
        ]
        return ranges.contains { (ip & $0.mask) == ($0.network & $0.mask) }
    }

    /// Converts network (big-endian) byte order to host order.
    private static func bigEndianToHost(_ value: UInt32) -> UInt32 {
        UInt32(bigEndian: value)
    }

    /// Returns true if `tailscaled` is running as a process.
    private static func tailscaledIsRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", "tailscaled"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError  = FileHandle.nullDevice
        return (try? task.run()) != nil && { task.waitUntilExit(); return task.terminationStatus == 0 }()
    }

    /// Persists the detected VPN kind to the shared App Group UserDefaults.
    private static func writeToUserDefaults(_ kind: VPNKind) {
        UserDefaults(suiteName: "group.com.yourname.anchor")?.set(kind.rawValue, forKey: "detectedVPN")
    }
}
