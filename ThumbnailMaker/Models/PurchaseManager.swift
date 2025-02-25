import StoreKit

private struct UserDefaultsKeys {
    static let youtubeImportsRemaining = "youtubeImportsRemaining"
    static let lastYoutubeImportReset = "lastYoutubeImportReset"
    static let remainingFreeTries = "remainingFreeTries"
    static let hasInitializedTries = "hasInitializedTries"
    static let hasUsedFreeTrial = "hasUsedFreeTrial"
}

@MainActor
class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()
    
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs = Set<String>()
    @Published var remainingFreeTries: Int
    @Published private(set) var hasUsedFreeTrial: Bool
    @Published private(set) var isRestoringPurchases = false
    @Published private(set) var verificationInProgress = false
    @Published private(set) var youtubeImportsRemaining: Int
    
    private let maxFreeTries = 3
    private let productIDs = ["com.williamjiamin.ThumbnailMaker.premiumlifetime2024"]
    private var productsLoaded = false
    
    private var verificationResult: VerificationResult<Transaction>?
    private var lastVerificationDate: Date?
    private let verificationInterval: TimeInterval = 3600 // 1 hour
    
    private let maxDailyYoutubeImports = 5  // Changed from 100 to 5 for testing
    private let maxFreeYoutubeImports = 3
    private var lastYoutubeImportReset: Date?
    
    private init() {
        print("🔍 [PurchaseManager] Initializing...")
        // Initialize properties from UserDefaults
        let defaults = UserDefaults.standard
        remainingFreeTries = defaults.integer(forKey: UserDefaultsKeys.remainingFreeTries)
        hasUsedFreeTrial = defaults.bool(forKey: UserDefaultsKeys.hasUsedFreeTrial)
        lastYoutubeImportReset = defaults.object(forKey: UserDefaultsKeys.lastYoutubeImportReset) as? Date
        youtubeImportsRemaining = defaults.integer(forKey: UserDefaultsKeys.youtubeImportsRemaining)
        
        print("🔍 [PurchaseManager] Initial values:")
        print("- YouTube imports remaining: \(youtubeImportsRemaining)")
        print("- Last reset date: \(String(describing: lastYoutubeImportReset))")
        
        // Handle first launch initialization
        if !defaults.bool(forKey: UserDefaultsKeys.hasInitializedTries) {
            remainingFreeTries = maxFreeTries
            defaults.set(true, forKey: UserDefaultsKeys.hasInitializedTries)
            defaults.set(maxFreeTries, forKey: UserDefaultsKeys.remainingFreeTries)
            defaults.synchronize()
        }
        
        Task {
            print("🔍 [PurchaseManager] Starting product loading...")
            await loadProducts()
            await updatePurchasedProducts()
            print("🔍 [PurchaseManager] Products loaded, checking YouTube imports...")
            await MainActor.run {
                checkAndResetYoutubeImports()
            }
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
        print("🔍 [PurchaseManager] Handling transaction result...")
        verificationResult = result
        
        guard case .verified(let transaction) = result else {
            print("❌ [PurchaseManager] Transaction not verified")
            await MainActor.run {
                purchasedProductIDs.removeAll()
            }
            return
        }
        
        // Check UserDefaults for previous premium status
        let defaults = UserDefaults.standard
        let previousImports = defaults.integer(forKey: UserDefaultsKeys.youtubeImportsRemaining)
        let lastResetDate = defaults.object(forKey: UserDefaultsKeys.lastYoutubeImportReset) as? Date
        
        let wasPremiumBefore = previousImports > maxFreeYoutubeImports || 
                              (lastResetDate != nil && !purchasedProductIDs.isEmpty)
        
        print("🔍 [PurchaseManager] Was premium before (based on imports): \(wasPremiumBefore)")
        print("🔍 [PurchaseManager] Current purchasedProductIDs: \(purchasedProductIDs)")
        
        await MainActor.run {
            if transaction.revocationDate == nil {
                purchasedProductIDs.insert(transaction.productID)
                print("🔍 [PurchaseManager] Added product ID: \(transaction.productID)")
                print("🔍 [PurchaseManager] Updated purchasedProductIDs: \(purchasedProductIDs)")
                
                // Only reset if this is truly the first time becoming premium
                if !wasPremiumBefore && purchasedProductIDs.count == 1 {
                    print("📢 [PurchaseManager] First-time premium upgrade detected, resetting imports")
                    resetYoutubeImports()
                }
            } else {
                purchasedProductIDs.remove(transaction.productID)
                print("❌ [PurchaseManager] Removed revoked product ID: \(transaction.productID)")
            }
        }
        
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
        // Remove the YouTube imports check from here to avoid view update issues
        if let lastVerification = lastVerificationDate,
           Date().timeIntervalSince(lastVerification) > verificationInterval {
            Task {
                await verifyPurchases()
            }
        }
        
        if verificationInProgress {
            return false
        }
        
        return !purchasedProductIDs.isEmpty || remainingFreeTries > 0
    }
    
    func verifyPurchases() async {
        guard !verificationInProgress else { return }
        
        await MainActor.run {
            verificationInProgress = true
        }
        
        do {
            try await verifyReceipt()
        } catch {
            await MainActor.run {
                verificationInProgress = false
            }
        }
    }
    
    private func verifyReceipt() async throws {
        // Verify with App Store
        try await AppStore.sync()
        
        var verifiedProducts = Set<String>()
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                // Only accept non-revoked, valid transactions
                if transaction.revocationDate == nil && 
                   transaction.revocationReason == nil {
                    verifiedProducts.insert(transaction.productID)
                }
            }
        }
        
        await MainActor.run {
            purchasedProductIDs = verifiedProducts
            lastVerificationDate = Date()
            verificationInProgress = false
        }
    }
    
    func checkAndResetYoutubeImports() {
        print("\n🔄 [PurchaseManager] Checking YouTube imports reset...")
        print("- Current imports remaining: \(youtubeImportsRemaining)")
        print("- Last reset date: \(String(describing: lastYoutubeImportReset))")
        print("- Is premium: \(!purchasedProductIDs.isEmpty)")
        
        guard let lastReset = lastYoutubeImportReset else {
            print("⚠️ [PurchaseManager] No last reset date found, performing initial reset")
            resetYoutubeImports()
            return
        }
        
        if !Calendar.current.isDateInToday(lastReset) {
            print("⚠️ [PurchaseManager] Last reset not from today, performing daily reset")
            print("- Last reset: \(lastReset)")
            print("- Current date: \(Date())")
            resetYoutubeImports()
        } else {
            print("✅ [PurchaseManager] Reset not needed - last reset was today")
        }
    }
    
    private func resetYoutubeImports() {
        print("\n🔄 [PurchaseManager] Resetting YouTube imports...")
        let defaults = UserDefaults.standard
        let isPremium = !purchasedProductIDs.isEmpty
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        print("- Is premium: \(isPremium)")
        print("- Current purchasedProductIDs: \(purchasedProductIDs)")
        
        youtubeImportsRemaining = isPremium ? maxDailyYoutubeImports : maxFreeYoutubeImports
        lastYoutubeImportReset = today
        
        print("- New imports remaining: \(youtubeImportsRemaining)")
        print("- New reset date: \(String(describing: lastYoutubeImportReset))")
        
        defaults.set(youtubeImportsRemaining, forKey: UserDefaultsKeys.youtubeImportsRemaining)
        defaults.set(lastYoutubeImportReset, forKey: UserDefaultsKeys.lastYoutubeImportReset)
        defaults.synchronize()
    }
    
    enum YouTubeImportStatus {
        case success
        case limitReachedFree
        case limitReachedPremium
    }
    
    func useYoutubeImport() -> YouTubeImportStatus {
        let defaults = UserDefaults.standard
        
        // Always load the latest value from UserDefaults
        youtubeImportsRemaining = defaults.integer(forKey: UserDefaultsKeys.youtubeImportsRemaining)
        checkAndResetYoutubeImports()
        
        if youtubeImportsRemaining <= 0 {
            return purchasedProductIDs.isEmpty ? .limitReachedFree : .limitReachedPremium
        }
        
        youtubeImportsRemaining -= 1
        defaults.set(youtubeImportsRemaining, forKey: UserDefaultsKeys.youtubeImportsRemaining)
        defaults.synchronize()
        
        return .success
    }
    
    private var nextResetDate: Date? {
        guard let lastReset = lastYoutubeImportReset else { return nil }
        let calendar = Calendar.current
        let nextDay = calendar.startOfDay(for: lastReset).addingTimeInterval(24 * 3600)
        return nextDay
    }
    
    var timeUntilNextReset: String {
        guard let nextReset = nextResetDate else { return "" }
        let now = Date()
        let components = Calendar.current.dateComponents([.hour, .minute], from: now, to: nextReset)
        
        guard let hours = components.hour, let minutes = components.minute else { return "" }
        return String(format: "%02d:%02d", hours, minutes)
    }
}

enum PurchaseError: Error {
    case productNotFound
    case userCancelled
    case pending
    case unknown
} 
