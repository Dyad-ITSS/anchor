import Testing
import Foundation
@testable import AnchorCore

@Suite("ConfigStore")
struct ConfigStoreTests {

    // MARK: - Helpers

    /// Returns a unique temp file URL that doesn't exist yet.
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    // MARK: - Tests

    @Test("Save config with 1 share and load it back — displayName matches")
    func testSaveAndLoad() async throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = ConfigStore(fileURL: url)
        let share = Share(displayName: "Home NAS", host: "192.168.1.10", shareName: "homes")
        let config = AnchorConfig(shares: [share])

        try await store.save(config)
        let loaded = try await store.load()

        #expect(loaded.shares.count == 1)
        #expect(loaded.shares[0].displayName == "Home NAS")
    }

    @Test("Load from path with no file returns default AnchorConfig with empty shares")
    func testLoadMissingFileReturnsDefault() async throws {
        let url = tempFileURL()
        // Do NOT create the file — store.load() should handle the missing-file case gracefully.

        let store = ConfigStore(fileURL: url)
        let config = try await store.load()

        #expect(config.shares.isEmpty)
        #expect(config.activeProfile == nil)
        #expect(config.schemaVersion == 1)
    }

    @Test("Save config with 1 share, then save empty config — load returns empty shares")
    func testSaveOverwrites() async throws {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = ConfigStore(fileURL: url)
        let share = Share(displayName: "Office NAS", host: "10.0.0.5", shareName: "data")
        let configWithShare = AnchorConfig(shares: [share])
        let emptyConfig = AnchorConfig()

        try await store.save(configWithShare)
        try await store.save(emptyConfig)

        let loaded = try await store.load()
        #expect(loaded.shares.isEmpty)
    }
}
