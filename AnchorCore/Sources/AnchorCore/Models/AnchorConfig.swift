import Foundation

/// Top-level configuration stored in the App Group container.
public struct AnchorConfig: Codable, Equatable, Sendable {
    public var shares: [Share]
    public var activeProfile: String?
    public var schemaVersion: Int

    public init(
        shares: [Share] = [],
        activeProfile: String? = nil,
        schemaVersion: Int = 1
    ) {
        self.shares = shares
        self.activeProfile = activeProfile
        self.schemaVersion = schemaVersion
    }

    /// Returns shares active under the current profile.
    ///
    /// - Shares with an empty `profiles` set are always included.
    /// - When `activeProfile` is `nil`, all shares are returned.
    public var activeShares: [Share] {
        guard let profile = activeProfile else {
            return shares
        }
        return shares.filter { share in
            share.profiles.isEmpty || share.profiles.contains(profile)
        }
    }
}
