import AnchorCore
import Foundation

/// Actor-isolated in-memory store of per-share mount states.
actor MountSession {
    private var states: [UUID: MountState] = [:]

    func state(for shareID: UUID) -> MountState {
        states[shareID] ?? .unmounted
    }

    func setState(_ state: MountState, for shareID: UUID) {
        states[shareID] = state
    }

    func reset() {
        states.removeAll()
    }
}
