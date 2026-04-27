import Foundation

/// The mount status of a single share.
public enum MountState: String, Codable, Equatable, Sendable {
    case mounted
    case unmounted
    case unreachable
    case mounting
    case error
}

/// An event emitted when a share's mount state changes.
public struct MountEvent: Codable, Equatable, Sendable {
    public let shareID: UUID
    public let state: MountState
    /// Which host was used — primary or fallback.
    public let mountedHost: String?

    public init(shareID: UUID, state: MountState, mountedHost: String? = nil) {
        self.shareID = shareID
        self.state = state
        self.mountedHost = mountedHost
    }
}
