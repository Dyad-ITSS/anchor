import AnchorCore
import Foundation
import RevenueCat

@MainActor
final class EntitlementManager: ObservableObject {
    static let shared = EntitlementManager()
    static let entitlementID = "pro"

    @Published private(set) var isPro: Bool = false

    private init() {
        // Replace with your actual RevenueCat Public SDK key
        // Get it from app.revenuecat.com → Project → API Keys → Public SDK Key
        Purchases.configure(withAPIKey: "appl_REPLACE_WITH_REAL_KEY")
        isPro = ProKeychain.isProUnlocked()
    }

    func refresh() async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            let entitled = customerInfo.entitlements[Self.entitlementID]?.isActive == true
            if entitled {
                ProKeychain.unlock(token: customerInfo.originalAppUserId)
            } else {
                ProKeychain.lock()
            }
            isPro = entitled
        } catch {
            // Network unavailable — fall back to cached Keychain value
            isPro = ProKeychain.isProUnlocked()
        }
    }
}
