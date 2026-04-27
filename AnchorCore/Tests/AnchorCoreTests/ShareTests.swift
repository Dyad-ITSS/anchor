import Testing
import Foundation
@testable import AnchorCore

@Suite("Share")
struct ShareTests {

    // MARK: - Defaults

    @Test("Default init leaves optional fields nil and sets correct defaults")
    func testShareDefaultsPortNil() {
        let share = Share(
            displayName: "Test Share",
            host: "192.168.1.1",
            shareName: "data"
        )
        #expect(share.port == nil)
        #expect(share.username == nil)
        #expect(share.fallbackHost == nil)
        #expect(share.unmountWhenUnreachable == true)
        #expect(share.profiles.isEmpty)
    }

    // MARK: - JSON round-trip

    @Test("Encode/decode preserves all fields including username, fallbackHost, profiles")
    func testShareRoundTripsJSON() throws {
        let original = Share(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789012")!,
            displayName: "Office NAS",
            host: "10.0.0.5",
            shareName: "SCANS",
            username: "alice",
            port: 8445,
            unmountWhenUnreachable: false,
            fallbackHost: "vpn.example.com",
            profiles: ["home", "office"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Share.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.displayName == original.displayName)
        #expect(decoded.host == original.host)
        #expect(decoded.shareName == original.shareName)
        #expect(decoded.username == original.username)
        #expect(decoded.port == original.port)
        #expect(decoded.unmountWhenUnreachable == original.unmountWhenUnreachable)
        #expect(decoded.fallbackHost == original.fallbackHost)
        #expect(decoded.profiles == original.profiles)
    }

    // MARK: - smbURL

    @Test("smbURL without username produces smb://host/share format")
    func testSMBURLNoUser() {
        let share = Share(
            displayName: "Data",
            host: "192.168.0.99",
            shareName: "data"
        )
        let url = share.smbURL(host: "192.168.0.99")
        #expect(url?.absoluteString == "smb://192.168.0.99/data")
    }

    @Test("smbURL with username produces smb://user@host/share format")
    func testSMBURLWithUser() {
        let share = Share(
            displayName: "SCANS",
            host: "10.0.4.250",
            shareName: "SCANS",
            username: "4tech"
        )
        let url = share.smbURL(host: "10.0.4.250")
        #expect(url?.absoluteString == "smb://4tech@10.0.4.250/SCANS")
    }

    @Test("smbURL percent-encodes spaces in share name")
    func testSMBURLEncodesSpaces() {
        let share = Share(
            displayName: "Dyad Capital",
            host: "10.0.4.1",
            shareName: "Dyad Capital"
        )
        let url = share.smbURL(host: "10.0.4.1")
        #expect(url?.absoluteString == "smb://10.0.4.1/Dyad%20Capital")
    }

    @Test("smbURL uses supplied host instead of share.host (fallback path)")
    func testSMBURLWithFallbackHost() {
        let s = Share(displayName: "NAS", host: "192.168.0.99", shareName: "data")
        #expect(s.smbURL(host: "100.64.93.215") == URL(string: "smb://100.64.93.215/data"))
    }
}
