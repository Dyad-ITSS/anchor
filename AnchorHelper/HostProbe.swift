import Foundation
import Network

/// Checks whether a host accepts TCP connections on port 445.
/// Returns (reachable, latencyMs) — latencyMs is 0 when not reachable.
enum HostProbe {
    static func isReachable(_ host: String, port: UInt16 = 445, timeout: TimeInterval = 1.0) async -> (Bool, Int) {
        let start = Date()
        let reachable = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
                return continuation.resume(returning: false)
            }
            let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
            var resolved = false

            func resolve(_ value: Bool) {
                guard !resolved else { return }
                resolved = true
                connection.cancel()
                continuation.resume(returning: value)
            }

            let timeoutItem = DispatchWorkItem { resolve(false) }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    timeoutItem.cancel()
                    resolve(true)
                case .failed, .cancelled:
                    timeoutItem.cancel()
                    resolve(false)
                default:
                    break
                }
            }

            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
        }
        let latencyMs = reachable ? Int(Date().timeIntervalSince(start) * 1000) : 0
        return (reachable, latencyMs)
    }
}
