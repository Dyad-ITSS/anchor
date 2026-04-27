import Foundation

// MARK: - Error

/// Errors thrown by ``ConfigStore``.
public enum ConfigStoreError: Error {
    /// The App Group container could not be resolved — check entitlements.
    case appGroupUnavailable
}

// MARK: - ConfigStore

/// Persists ``AnchorConfig`` to a JSON file in the App Group container.
///
/// Use the ``init()`` designated initialiser in production (requires App Group
/// entitlement). Inject an explicit ``fileURL`` in tests to avoid the entitlement
/// dependency.
///
/// Declared as an `actor` so that concurrent reads/writes from AnchorApp and
/// AnchorHelper are serialised without manual locking.
public actor ConfigStore {

    // MARK: Properties

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    // MARK: Init

    /// Production initialiser — resolves the file URL from the App Group container.
    ///
    /// - Throws: ``ConfigStoreError/appGroupUnavailable`` when the container cannot
    ///   be resolved (e.g. entitlement missing or sandbox misconfigured).
    public init() throws {
        guard let url = AppGroup.configFileURL else {
            throw ConfigStoreError.appGroupUnavailable
        }
        self.fileURL = url
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc
    }

    /// Test-friendly initialiser — uses an explicit file URL.
    ///
    /// - Parameter fileURL: Path where config will be read from / written to.
    public init(fileURL: URL) {
        self.fileURL = fileURL
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc
    }

    // MARK: Public API

    /// Loads the config from disk.
    ///
    /// If the file does not exist, returns ``AnchorConfig()`` (empty config) — this
    /// is not treated as an error so first-launch behaviour is well defined.
    ///
    /// - Returns: The decoded ``AnchorConfig``, or a default instance when no file exists.
    /// - Throws: Any `JSONDecoder` error encountered while decoding an existing file.
    public func load() throws -> AnchorConfig {
        guard (try? fileURL.checkResourceIsReachable()) == true else {
            return AnchorConfig()
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(AnchorConfig.self, from: data)
    }

    /// Saves `config` to disk atomically.
    ///
    /// - Parameter config: The configuration to persist.
    /// - Throws: Any error from encoding or writing the file.
    public func save(_ config: AnchorConfig) throws {
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
    }
}
