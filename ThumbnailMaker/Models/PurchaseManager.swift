import StoreKit

@MainActor
class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()
    
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs = Set<String>()
    @Published var remainingFreeTries: Int
    @Published private(set) var hasUsedFreeTrial: Bool
    @Published private(set) var isRestoringPurchases = false
    
    private let maxFreeTries = 3
    private let productIDs = ["com.williamjiamin.ThumbnailMaker.premium2024"]
    private var productsLoaded = false
    
    private var verificationResult: VerificationResult<Transaction>?
    
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
        // Store verification result
        verificationResult = result
        
        guard case .verified(let transaction) = result else {
            // Invalid transaction, remove access
            await MainActor.run {
                purchasedProductIDs.removeAll()
            }
            return
        }
        
        await MainActor.run {
            if transaction.revocationDate == nil {
                purchasedProductIDs.insert(transaction.productID)
            } else {
                purchasedProductIDs.remove(transaction.productID)
            }
        }
        
        // Always finish the transaction
        await transaction.finish()
    }
    
    func purchase() async throws {
        guard let product = products.first else {
            throw PurchaseError.productNotFound
        }
        
        // Start transaction
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            await handleTransactionResult(verification)
        case .userCancelled:
            throw PurchaseError.userCancelled
        case .pending:
            throw PurchaseError.pending
        @unknown default:
            throw PurchaseError.unknown
        }
    }
    
    func useFreeTrial() {
        guard remainingFreeTries > 0 else { return }
        
        remainingFreeTries -= 1
        UserDefaults.standard.set(remainingFreeTries, forKey: "remainingFreeTries")
        UserDefaults.standard.set(true, forKey: "hasUsedFreeTrial")
        
        // Synchronize to ensure the value is saved immediately
        UserDefaults.standard.synchronize()
    }
    
    func restorePurchases() async {
        await MainActor.run {
            isRestoringPurchases = true
        }
        
        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
            
            await MainActor.run {
                isRestoringPurchases = false
                // Show success message
                NotificationCenter.default.post(
                    name: NSNotification.Name("ShowPurchaseMessage"),
                    object: nil,
                    userInfo: ["message": "Purchases restored successfully"]
                )
            }
        } catch {
            await MainActor.run {
                isRestoringPurchases = false
                // Show error message
                NotificationCenter.default.post(
                    name: NSNotification.Name("ShowPurchaseMessage"),
                    object: nil,
                    userInfo: ["message": "Failed to restore purchases. Please try again."]
                )
            }
        }
    }
    
    var canAccessPremium: Bool {
        // More secure premium access check
        if !purchasedProductIDs.isEmpty {
            return true
        }
        if remainingFreeTries > 0 {
            return true
        }
        return false
    }
}

enum PurchaseError: Error {
    case productNotFound
    case userCancelled
    case pending
    case unknown
} 
