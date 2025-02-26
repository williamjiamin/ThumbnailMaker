import StoreKit
import Combine
import SwiftUI

private struct UserDefaultsKeys {
    static let youtubeImportsRemaining = "youtubeImportsRemaining"
    static let lastYoutubeImportReset = "lastYoutubeImportReset"
    static let remainingFreeTries = "remainingFreeTries"
    static let hasInitializedTries = "hasInitializedTries"
    static let hasUsedFreeTrial = "hasUsedFreeTrial"
    static let cachedPurchasedProductIDs = "cachedPurchasedProductIDs"
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
    
    // Add these new properties for the timer
    @Published private(set) var timeRemainingString: String = "--:--:--"
    private var timerCancellable: AnyCancellable?
    
    private let maxFreeTries = 3
    private let productIDs = ["com.williamjiamin.ThumbnailMaker.premiumlifetime2024"]
    private var productsLoaded = false
    
    private var verificationResult: VerificationResult<StoreKit.Transaction>?
    private var lastVerificationDate: Date?
    private let verificationInterval: TimeInterval = 3600 // 1 hour
    
    private var maxDailyYoutubeImports: Int {
        DebugSettings.premiumQuotaLimit
    }
    
    private var maxFreeYoutubeImports: Int {
        DebugSettings.freeQuotaLimit
    }
    
    private var lastYoutubeImportReset: Date?
    
    private init() {
        print("🔍 [PurchaseManager] Initializing...")
        // Initialize properties from UserDefaults
        let defaults = UserDefaults.standard
        remainingFreeTries = defaults.integer(forKey: UserDefaultsKeys.remainingFreeTries)
        hasUsedFreeTrial = defaults.bool(forKey: UserDefaultsKeys.hasUsedFreeTrial)
        
        // Critical fix: Always load YouTube import values from UserDefaults
        youtubeImportsRemaining = defaults.integer(forKey: UserDefaultsKeys.youtubeImportsRemaining)
        lastYoutubeImportReset = defaults.object(forKey: UserDefaultsKeys.lastYoutubeImportReset) as? Date
        
        // IMPORTANT NEW FIX: Load cached purchase status
        if let cachedProductIDs = defaults.stringArray(forKey: UserDefaultsKeys.cachedPurchasedProductIDs) {
            purchasedProductIDs = Set(cachedProductIDs)
            print("🔍 [PurchaseManager] Loaded cached purchases: \(purchasedProductIDs)")
        }
        
        print("🔍 [PurchaseManager] Initial values:")
        print("- YouTube imports remaining: \(youtubeImportsRemaining)")
        print("- Last reset date: \(String(describing: lastYoutubeImportReset))")
        print("- Premium status: \(!purchasedProductIDs.isEmpty)")
        
        // First launch initialization only - don't do automatic resets
        if lastYoutubeImportReset == nil {
            print("⚠️ [PurchaseManager] No last reset date found, performing initial setup")
            // Set initial values without resetting
            youtubeImportsRemaining = maxFreeYoutubeImports // Always start with free quota
            lastYoutubeImportReset = Calendar.current.startOfDay(for: Date())
            
            // Save to UserDefaults
            defaults.set(youtubeImportsRemaining, forKey: UserDefaultsKeys.youtubeImportsRemaining)
            defaults.set(lastYoutubeImportReset, forKey: UserDefaultsKeys.lastYoutubeImportReset)
            defaults.synchronize()
        }
        
        // Handle first launch initialization for free trials
        if !defaults.bool(forKey: UserDefaultsKeys.hasInitializedTries) {
            remainingFreeTries = maxFreeTries
            defaults.set(true, forKey: UserDefaultsKeys.hasInitializedTries)
            defaults.set(maxFreeTries, forKey: UserDefaultsKeys.remainingFreeTries)
            defaults.synchronize()
        }
        
        // After all initialization is done, start the timer
        startResetTimer()
        
        listenForTransactions()
        
        Task {
            print("🔍 [PurchaseManager] Starting product loading...")
            await loadProducts()
            await silentlyVerifyPurchases()
        }
    }
    
    private func listenForTransactions() {
        Task.detached { @MainActor in
            for await result in StoreKit.Transaction.updates {
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
        print("🔍 [PurchaseManager] Updating purchased products (WITHOUT quota reset)")
        for await result in StoreKit.Transaction.currentEntitlements {
            await handleTransactionResult(result, skipQuotaReset: true)
        }
    }
    
    private func handleTransactionResult(_ result: VerificationResult<StoreKit.Transaction>, skipQuotaReset: Bool = false) async {
        print("🔍 [PurchaseManager] Handling transaction result... (skipQuotaReset: \(skipQuotaReset))")
        verificationResult = result
        
        guard case .verified(let transaction) = result else {
            print("❌ [PurchaseManager] Transaction not verified")
            await MainActor.run {
                purchasedProductIDs.removeAll()
                // Clear cache when no valid transactions found
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cachedPurchasedProductIDs)
                UserDefaults.standard.synchronize()
            }
            return
        }
        
        let oldPurchasedIDs = purchasedProductIDs
        let wasPremiumBefore = !oldPurchasedIDs.isEmpty
        
        print("🔍 [PurchaseManager] Old purchase IDs: \(oldPurchasedIDs), was premium before: \(wasPremiumBefore)")
        
        await MainActor.run {
            if transaction.revocationDate == nil {
                purchasedProductIDs.insert(transaction.productID)
                print("🔍 [PurchaseManager] Added product ID: \(transaction.productID)")
                print("🔍 [PurchaseManager] Updated purchasedProductIDs: \(purchasedProductIDs)")
                
                // Cache the purchase status to UserDefaults
                UserDefaults.standard.set(Array(purchasedProductIDs), forKey: UserDefaultsKeys.cachedPurchasedProductIDs)
                UserDefaults.standard.synchronize()
                
                // Only reset quota on explicit premium upgrade, never during app startup
                let isNewPremium = !wasPremiumBefore && !purchasedProductIDs.isEmpty
                if isNewPremium && !skipQuotaReset {
                    print("📢 [PurchaseManager] First-time premium upgrade detected, resetting imports")
                    resetYoutubeImports()
                }
            } else {
                purchasedProductIDs.remove(transaction.productID)
                print("❌ [PurchaseManager] Removed revoked product ID: \(transaction.productID)")
                
                // Update cached status
                if purchasedProductIDs.isEmpty {
                    UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cachedPurchasedProductIDs)
                } else {
                    UserDefaults.standard.set(Array(purchasedProductIDs), forKey: UserDefaultsKeys.cachedPurchasedProductIDs)
                }
                UserDefaults.standard.synchronize()
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
        // Use a much longer verification interval (once per day max)
        let verificationInterval: TimeInterval = 86400 // 24 hours
        
        // Only verify occasionally
        if purchasedProductIDs.isEmpty && !verificationInProgress {
            if let lastVerification = lastVerificationDate,
               Date().timeIntervalSince(lastVerification) > verificationInterval {
                Task {
                    await verifyPurchases()
                }
            }
        }
        
        // Important: Return cached result immediately rather than waiting for verification
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
        // Only sync with App Store occasionally (once per day max)
        let defaults = UserDefaults.standard
        let lastSyncKey = "lastAppStoreSync"
        let syncInterval: TimeInterval = 86400 // 24 hours
        
        let shouldSync = if let lastSync = defaults.object(forKey: lastSyncKey) as? Date {
            Date().timeIntervalSince(lastSync) > syncInterval
        } else {
            true // First time, so sync
        }
        
        if shouldSync {
            print("🔄 [PurchaseManager] Syncing with App Store (daily check)")
            try await AppStore.sync()
            defaults.set(Date(), forKey: lastSyncKey)
            defaults.synchronize()
        } else {
            print("✅ [PurchaseManager] Using cached purchase status (avoiding password prompt)")
        }
        
        // Always check local entitlements (doesn't require password)
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
    
    private func checkAndResetYoutubeImports() {
        guard let lastReset = lastYoutubeImportReset else {
            // First reset
            resetYoutubeImports()
            return
        }
        
        let calendar = Calendar.current
        let now = Date()
        
        // Add debug print to trace the execution
        print("🔍 [Quota Check] Current time: \(now)")
        print("🔍 [Quota Check] Last reset: \(lastReset)")
        
        // In debug mode, reset after 3 minutes
        // In production mode, reset after midnight
        if DebugSettings.isDebugMode {
            // Simple time-based check for debug mode
            let timeSinceReset = now.timeIntervalSince(lastReset)
            print("🔍 [Quota Check] Time since reset: \(timeSinceReset)s, Required: \(DebugSettings.quotaResetInterval)s")
            
            if timeSinceReset >= DebugSettings.quotaResetInterval {
                print("🔍 [Quota Check] Debug reset triggered!")
                resetYoutubeImports()
            }
        } else {
            // Original production logic (reset at midnight)
            if !calendar.isDate(lastReset, inSameDayAs: now) {
                print("🔍 [Quota Check] Production reset triggered!")
                resetYoutubeImports()
            }
        }
    }
    
    private func resetYoutubeImports() {
        print("\n🔄 [PurchaseManager] Resetting YouTube imports...")
        let defaults = UserDefaults.standard
        let isPremium = !purchasedProductIDs.isEmpty
        let now = Date()  // Use current time, not start of day
        
        print("- Is premium: \(isPremium)")
        print("- Current purchasedProductIDs: \(purchasedProductIDs)")
        
        youtubeImportsRemaining = isPremium ? maxDailyYoutubeImports : maxFreeYoutubeImports
        lastYoutubeImportReset = now  // Use exact time for precise interval calculations
        
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
        // Check if we need to reset the quota first
        checkAndResetYoutubeImports()
        
        let defaults = UserDefaults.standard
        
        if youtubeImportsRemaining <= 0 {
            print("📊 [PurchaseManager] No imports remaining, can't use import")
            return purchasedProductIDs.isEmpty ? .limitReachedFree : .limitReachedPremium
        }
        
        // We have imports available, use one
        youtubeImportsRemaining -= 1
        print("📊 [PurchaseManager] Used YouTube import, new remaining: \(youtubeImportsRemaining)")
        
        // Save immediately with synchronize
        defaults.set(youtubeImportsRemaining, forKey: UserDefaultsKeys.youtubeImportsRemaining)
        defaults.synchronize()
        
        // Load products in background (without affecting quota)
        Task {
            if products.isEmpty {
                await loadProducts()
            }
        }
        
        return .success
    }
    
    var nextResetDate: Date? {
        guard let lastReset = lastYoutubeImportReset else { return nil }
        
        if DebugSettings.isDebugMode {
            // In debug mode, reset after 3 minutes from last reset
            return lastReset.addingTimeInterval(DebugSettings.quotaResetInterval)
        } else {
            // In production mode, reset at midnight
            let calendar = Calendar.current
            return calendar.startOfDay(for: lastReset).addingTimeInterval(24 * 3600)
        }
    }
    
    // Replace your existing timeUntilNextReset property with this one
    // that returns the live updating string
    var timeUntilNextReset: String {
        return timeRemainingString
    }
    
    var availableYoutubeImports: Int {
        // Return the in-memory value, which should always be up-to-date
        return youtubeImportsRemaining
    }
    
    // 3. Add a new method for explicit verification (only when user requests it)
    func manuallyVerifyPurchases() async -> Bool {
        print("🔍 [PurchaseManager] Manual purchase verification requested by user")
        guard !verificationInProgress else { return !purchasedProductIDs.isEmpty }
        
        await MainActor.run {
            verificationInProgress = true
        }
        
        do {
            // Force App Store sync since user explicitly requested it
            try await AppStore.sync()
            
            var verifiedProducts = Set<String>()
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result {
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
            
            return !purchasedProductIDs.isEmpty
        } catch {
            await MainActor.run {
                verificationInProgress = false
            }
            return !purchasedProductIDs.isEmpty
        }
    }
    
    // Add this new method for silent verification
    private func silentlyVerifyPurchases() async {
        print("🔍 [PurchaseManager] Silently verifying purchases on startup...")
        
        // Check local transactions without forcing App Store sync
        var foundProducts = Set<String>()
        
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.revocationDate == nil && 
                   transaction.revocationReason == nil {
                    foundProducts.insert(transaction.productID)
                    print("✅ [PurchaseManager] Found valid transaction: \(transaction.productID)")
                }
            }
        }
        
        // Update and cache the results
        if !foundProducts.isEmpty {
            purchasedProductIDs = foundProducts
            print("✅ [PurchaseManager] Updated premium status: \(purchasedProductIDs)")
            
            // Cache the valid purchases to UserDefaults
            UserDefaults.standard.set(Array(purchasedProductIDs), forKey: UserDefaultsKeys.cachedPurchasedProductIDs)
            UserDefaults.standard.synchronize()
        }
    }
    
    // Method to start the timer
    private func startResetTimer() {
        // Update immediately
        updateTimeRemainingString()
        
        // Then update every second
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateTimeRemainingString()
            }
    }
    
    // Method to update the time remaining string
    private func updateTimeRemainingString() {
        guard let nextReset = nextResetDate else {
            timeRemainingString = "--:--:--"
            return
        }
        
        let now = Date()
        let timeRemaining = max(0, nextReset.timeIntervalSince(now))
        
        // Debug prints
        if DebugSettings.isDebugMode {
            print("⏱️ [Timer] Next reset: \(nextReset), Time remaining: \(timeRemaining)s")
        }
        
        // Check if the timer has reached zero
        if timeRemaining <= 0 {
            // Only call reset once when we cross the threshold
            print("⏱️ [Timer] Threshold crossed, checking if reset needed")
            checkAndResetYoutubeImports()
            
            // Recalculate after potential reset
            guard let newNextReset = nextResetDate else {
                timeRemainingString = "--:--:--"
                return
            }
            
            let newTimeRemaining = max(0, newNextReset.timeIntervalSince(now))
            let hours = Int(newTimeRemaining) / 3600
            let minutes = (Int(newTimeRemaining) % 3600) / 60
            let seconds = Int(newTimeRemaining) % 60
            
            timeRemainingString = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            // Normal time update
            let hours = Int(timeRemaining) / 3600
            let minutes = (Int(timeRemaining) % 3600) / 60
            let seconds = Int(timeRemaining) % 60
            
            timeRemainingString = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
    }
}

enum PurchaseError: Error {
    case productNotFound
    case userCancelled
    case pending
    case unknown
}


