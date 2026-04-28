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

    /// Production initialiser — uses App Group container when available (signed build),
    /// falls back to /tmp/anchor-config.json for unsigned dev builds.
    public init() {
        let url: URL
        // containerURL returns non-nil even when unsigned; verify the directory exists
        // (signed + provisioned builds have the Group Container created automatically).
        if let groupURL = AppGroup.configFileURL,
           let containerDir = AppGroup.containerURL,
           FileManager.default.fileExists(atPath: containerDir.path) {
            url = groupURL
        } else {
            // Fallback: unsigned/dev build — use Application Support (survives reboots)
            let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Anchor", isDirectory: true)
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            url = appSupport.appendingPathComponent("config.json")
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

    /// The file URL being used by this store instance (for debugging).
    public var resolvedFileURL: URL { fileURL }

    // MARK: - Synchronous helpers (for UI layer — avoids actor hop timing issues)

    /// Saves synchronously from any thread. Use from SwiftUI views where
    /// async Task timing may race with view teardown.
    public nonisolated func saveSync(_ config: AnchorConfig) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(config) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Loads synchronously from any thread.
    public nonisolated func loadSync() -> AnchorConfig {
        guard (try? fileURL.checkResourceIsReachable()) == true,
              let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(AnchorConfig.self, from: data)
        else { return AnchorConfig() }
        return config
    }
}
