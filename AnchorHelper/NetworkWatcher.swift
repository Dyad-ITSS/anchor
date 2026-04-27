import Foundation
import Network

/// Emits a value whenever the network path changes.
final class NetworkWatcher {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.yourname.anchor.networkwatcher")

    var pathUpdates: AsyncStream<NWPath> {
        AsyncStream { continuation in
            monitor.pathUpdateHandler = { path in
                continuation.yield(path)
            }
            continuation.onTermination = { [monitor] _ in
                monitor.cancel()
            }
            monitor.start(queue: queue)
        }
    }

    deinit {
        monitor.cancel()
    }
}
