import StoreKit
import AnchorCore

@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()
    static let proProductID = "com.yourname.anchor.pro"

    @Published private(set) var proProduct: Product?
    @Published private(set) var isPurchasing = false
    @Published private(set) var purchaseError: String?

    private init() {}

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.proProductID])
            proProduct = products.first
        } catch {
            // Product not available in this environment (no App Store Connect setup yet)
        }
    }

    func purchase() async {
        guard let product = proProduct else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verification.payloadValue
                await transaction.finish()
                ProKeychain.unlock(token: transaction.id.description)
                await EntitlementManager.shared.refresh()
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase pending approval"
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await EntitlementManager.shared.refresh()
    }
}
