import StoreKit

@MainActor
class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()
    
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs = Set<String>()
    @Published var remainingFreeTries: Int
    @Published private(set) var hasUsedFreeTrial: Bool
    
    private let maxFreeTries = 3
    private let productIDs = ["com.williamjiamin.ThumbnailMaker.premium"]
    private var productsLoaded = false
    
    private init() {
        // Load saved remaining tries
        remainingFreeTries = UserDefaults.standard.integer(forKey: "remainingFreeTries")
        hasUsedFreeTrial = UserDefaults.standard.bool(forKey: "hasUsedFreeTrial")
        
        if remainingFreeTries == 0 && !UserDefaults.standard.bool(forKey: "hasInitializedTries") {
            // First time initialization
            remainingFreeTries = maxFreeTries
            UserDefaults.standard.set(true, forKey: "hasInitializedTries")
            UserDefaults.standard.set(maxFreeTries, forKey: "remainingFreeTries")
        }
        
        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
        
        listenForTransactions()
    }
    
    private func listenForTransactions() {
        Task.detached { @MainActor in
            for await result in Transaction.updates {
                await self.handleTransactionResult(result)
            }
        }
    }
    
    private func loadProducts() async {
        guard !productsLoaded else { return }
        do {
            products = try await Product.products(for: productIDs)
            productsLoaded = true
        } catch {
            print("Failed to load products:", error)
        }
    }
    
    private func updatePurchasedProducts() async {
        for await result in Transaction.currentEntitlements {
            await handleTransactionResult(result)
        }
    }
    
    private func handleTransactionResult(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            return
        }
        
        if transaction.revocationDate == nil {
            purchasedProductIDs.insert(transaction.productID)
        } else {
            purchasedProductIDs.remove(transaction.productID)
        }
    }
    
    func purchase() async throws {
        guard let product = products.first else { return }
        
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            await handleTransactionResult(verification)
        case .userCancelled:
            break
        case .pending:
            break
        @unknown default:
            break
        }
    }
    
    func useFreeTrial() {
        guard remainingFreeTries > 0 else { return }
        remainingFreeTries -= 1
        UserDefaults.standard.set(remainingFreeTries, forKey: "remainingFreeTries")
    }
    
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
        } catch {
            print("Failed to restore purchases:", error)
        }
    }
    
    #if targetEnvironment(simulator)
    var canAccessPremium: Bool {
        true // Always allow access in simulator
    }
    #else
    var canAccessPremium: Bool {
        !purchasedProductIDs.isEmpty || remainingFreeTries > 0
    }
    #endif
} 