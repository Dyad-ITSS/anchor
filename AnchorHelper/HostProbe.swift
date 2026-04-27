import Foundation
import Network

/// Checks whether a host accepts TCP connections on port 445 within the given timeout.
enum HostProbe {
    static func isReachable(_ host: String, port: UInt16 = 445, timeout: TimeInterval = 1.0) async -> Bool {
        await withCheckedContinuation { continuation in
            guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return continuation.resume(returning: false) }
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: endpointPort,
                using: .tcp
            )

            var resolved = false

            func resolve(_ value: Bool) {
                guard !resolved else { return }
                resolved = true
                connection.cancel()
                continuation.resume(returning: value)
            }

            let timeoutItem = DispatchWorkItem {
                resolve(false)
            }

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

            DispatchQueue.global().asyncAfter(
                deadline: .now() + timeout,
                execute: timeoutItem
            )
        }
    }
}
