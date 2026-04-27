import XCTest
@testable import AnchorCore

final class ProKeychainTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ProKeychain.clearForTesting()
    }

    func testNotUnlockedByDefault() {
        XCTAssertFalse(ProKeychain.isProUnlocked())
    }

    func testUnlockAndRead() {
        ProKeychain.unlock(token: "test-entitlement-token")
        XCTAssertTrue(ProKeychain.isProUnlocked())
    }

    func testLockRemovesToken() {
        ProKeychain.unlock(token: "test-entitlement-token")
        ProKeychain.lock()
        XCTAssertFalse(ProKeychain.isProUnlocked())
    }

    func testUnlockOverwrites() {
        ProKeychain.unlock(token: "first-token")
        ProKeychain.unlock(token: "second-token")
        // Should not crash (no duplicate item error) and should still be unlocked
        XCTAssertTrue(ProKeychain.isProUnlocked())
    }
}
