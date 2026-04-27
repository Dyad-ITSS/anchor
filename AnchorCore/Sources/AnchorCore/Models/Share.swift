import Foundation

/// A configured network share that Anchor can mount/unmount.
public struct Share: Codable, Identifiable, Equatable {
    public var id: UUID
    public var displayName: String
    public var host: String              // Primary (LAN) IP or hostname
    public var shareName: String
    public var username: String?         // nil = use Keychain default for host
    public var port: Int?                // nil = 445 (SMB default)
    public var unmountWhenUnreachable: Bool
    public var fallbackHost: String?     // Mesh VPN IP or FQDN (Pro only — nil in free tier)
    public var profiles: Set<String>

    public init(
        id: UUID = UUID(),
        displayName: String,
        host: String,
        shareName: String,
        username: String? = nil,
        port: Int? = nil,
        unmountWhenUnreachable: Bool = true,
        fallbackHost: String? = nil,
        profiles: Set<String> = []
    ) {
        self.id = id
        self.displayName = displayName
        self.host = host
        self.shareName = shareName
        self.username = username
        self.port = port
        self.unmountWhenUnreachable = unmountWhenUnreachable
        self.fallbackHost = fallbackHost
        self.profiles = profiles
    }

    /// Returns the smb:// URL for the given host, URL-encoding spaces in shareName.
    /// - With username: `smb://username@host/share`
    /// - Without: `smb://host/share`
    public func smbURL(host targetHost: String) -> URL? {
        let encodedShare = shareName
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? shareName

        var urlString: String
        if let user = username {
            urlString = "smb://\(user)@\(targetHost)/\(encodedShare)"
        } else {
            urlString = "smb://\(targetHost)/\(encodedShare)"
        }
        return URL(string: urlString)
    }
}
