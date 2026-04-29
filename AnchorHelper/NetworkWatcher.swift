import Foundation
import Network

/// Emits a value whenever the network path changes.
final class NetworkWatcher {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.zieseniss.anchor.networkwatcher")

    var pathUpdates: AsyncStream<NWPath> {
        AsyncStream { continuation in
            monitor.pathUpdateHandler = { path in
                continuation.yield(path)
            }
            continuation.onTermination = { [weak self] _ in
                self?.monitor.cancel()
            }
            monitor.start(queue: queue)
            // Yield current path immediately so consumers don't wait for first change
            continuation.yield(monitor.currentPath)
        }
    }

    deinit {
        monitor.cancel()
    }
}
