import Foundation
import AnchorCore

/// Thread-safe in-memory store of per-share mount states.
final class MountSession {
    private let lock = NSLock()
    private var states: [UUID: MountState] = [:]

    func state(for shareID: UUID) -> MountState {
        lock.lock()
        defer { lock.unlock() }
        return states[shareID] ?? .unmounted
    }

    func setState(_ state: MountState, for shareID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        states[shareID] = state
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        states = [:]
    }
}
