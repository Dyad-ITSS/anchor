import Testing
import Foundation
@testable import AnchorCore

@Suite("AnchorConfig")
struct AnchorConfigTests {

    // MARK: - JSON round-trip

    @Test("Empty config encodes and decodes preserving defaults")
    func testEmptyConfigRoundTrips() throws {
        let config = AnchorConfig()
        #expect(config.shares.isEmpty)
        #expect(config.activeProfile == nil)
        #expect(config.schemaVersion == 1)

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AnchorConfig.self, from: data)

        #expect(decoded.shares.isEmpty)
        #expect(decoded.activeProfile == nil)
        #expect(decoded.schemaVersion == 1)
    }

    // MARK: - activeShares filtering

    @Test("activeShares with profile 'home' includes profile-matched and empty-profile shares, excludes 'office'")
    func testSharesForProfileFiltersCorrectly() {
        let homeShare = Share(
            displayName: "Home NAS",
            host: "192.168.1.10",
            shareName: "home",
            profiles: ["home"]
        )
        let officeShare = Share(
            displayName: "Office NAS",
            host: "10.0.0.5",
            shareName: "office",
            profiles: ["office"]
        )
        let alwaysShare = Share(
            displayName: "Always",
            host: "192.168.1.1",
            shareName: "always"
            // profiles defaults to []
        )

        let config = AnchorConfig(
            shares: [homeShare, officeShare, alwaysShare],
            activeProfile: "home"
        )

        let active = config.activeShares
        #expect(active.count == 2)
        #expect(active.contains { $0.id == homeShare.id })
        #expect(active.contains { $0.id == alwaysShare.id })
        #expect(!active.contains { $0.id == officeShare.id })
    }

    @Test("activeShares with nil activeProfile returns all shares")
    func testSharesForNilProfileReturnsAll() {
        let shareA = Share(displayName: "A", host: "10.0.0.1", shareName: "a", profiles: ["home"])
        let shareB = Share(displayName: "B", host: "10.0.0.2", shareName: "b", profiles: ["office"])
        let shareC = Share(displayName: "C", host: "10.0.0.3", shareName: "c")

        let config = AnchorConfig(
            shares: [shareA, shareB, shareC],
            activeProfile: nil
        )

        let active = config.activeShares
        #expect(active.count == 3)
    }
}
