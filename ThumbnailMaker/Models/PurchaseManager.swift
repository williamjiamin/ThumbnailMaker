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
    /// Product IDs whose verified entitlement currently grants Premium (SUB: any plan).
    @Published private(set) var purchasedProductIDs = Set<String>()
    /// The verified entitlement behind each ID in `purchasedProductIDs` (expiry, renewal info).
    @Published private(set) var activeEntitlements: [String: PurchaseEntitlement] = [:]
    @Published private(set) var productLoadState: ProductLoadState = .idle
    @Published private(set) var purchasingPlan: PurchasePlan?
    @Published var remainingFreeTries: Int
    @Published private(set) var hasUsedFreeTrial: Bool
    @Published private(set) var isRestoringPurchases = false
    @Published private(set) var verificationInProgress = false
    @Published private(set) var verificationState: PurchaseVerificationState = .notVerified
    @Published private(set) var restoreState: PurchaseRestoreState = .idle
    @Published private(set) var youtubeImportsRemaining: Int
    
    // Add these new properties for the timer
    @Published private(set) var timeRemainingString: String = "--:--:--"
    private var timerCancellable: AnyCancellable?
    
    private let maxFreeTries = 3
    private let productIDs = PurchasePlan.allProductIDs
    private let now: () -> Date
    private var productsLoaded = false
    
    private let defaults: UserDefaults
    private let entitlementSource: PurchaseEntitlementSource
    private var transactionListener: Task<Void, Never>?
    private var verificationTask: Task<Bool, Never>?
    private var verificationTaskID: UUID?
    private var entitlementRevision = 0
    private var lastVerificationDate: Date?
    private let verificationInterval: TimeInterval = 86400 // 24 hours
    
    private var maxDailyYoutubeImports: Int {
        DebugSettings.premiumQuotaLimit
    }
    
    private var maxFreeYoutubeImports: Int {
        DebugSettings.freeQuotaLimit
    }
    
    private var lastYoutubeImportReset: Date?
    
    init(
        defaults: UserDefaults = .standard,
        entitlementSource: PurchaseEntitlementSource? = nil,
        startsBackgroundServices: Bool = true,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.now = now
        self.entitlementSource = entitlementSource ?? .storeKit
        print("🔍 [PurchaseManager] Initializing...")
        // Initialize properties from UserDefaults
        remainingFreeTries = defaults.integer(forKey: UserDefaultsKeys.remainingFreeTries)
        hasUsedFreeTrial = defaults.bool(forKey: UserDefaultsKeys.hasUsedFreeTrial)
        
        // Critical fix: Always load YouTube import values from UserDefaults
        youtubeImportsRemaining = defaults.integer(forKey: UserDefaultsKeys.youtubeImportsRemaining)
        lastYoutubeImportReset = defaults.object(forKey: UserDefaultsKeys.lastYoutubeImportReset) as? Date
        
        // UserDefaults is only a hint. StoreKit supplies locally verified transactions,
        // including offline; an unsigned product-ID cache must not grant paid access.
        if let cachedProductIDs = defaults.stringArray(forKey: UserDefaultsKeys.cachedPurchasedProductIDs) {
            let recognizedCache = Set(cachedProductIDs).intersection(productIDs)
            if recognizedCache.isEmpty {
                defaults.removeObject(forKey: UserDefaultsKeys.cachedPurchasedProductIDs)
            } else {
                defaults.set(recognizedCache.sorted(), forKey: UserDefaultsKeys.cachedPurchasedProductIDs)
            }
        }

        #if DEBUG
        if startsBackgroundServices && ProcessInfo.processInfo.arguments.contains("-UITestUnlockPremium") {
            setEntitlements([PurchasePlan.lifetime.productID: PurchaseEntitlement(productID: PurchasePlan.lifetime.productID)])
            remainingFreeTries = maxFreeTries
            verificationState = .verified
        }
        #endif
        
        print("🔍 [PurchaseManager] Initial values:")
        print("- YouTube imports remaining: \(youtubeImportsRemaining)")
        print("- Last reset date: \(String(describing: lastYoutubeImportReset))")
        print("- Premium status: \(isPremium)")
        
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
        
        guard startsBackgroundServices else { return }
        startResetTimer()

        #if DEBUG
        // This existing explicit UI-test fixture must not be cleared by live StoreKit.
        if ProcessInfo.processInfo.arguments.contains("-UITestUnlockPremium") { return }
        #endif
        
        listenForTransactions()
        
        Task {
            await silentlyVerifyPurchases()
        }
        Task { await loadProducts() }
    }
    
    private func listenForTransactions() {
        transactionListener = Task { @MainActor [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard !Task.isCancelled else { return }
                await self?.handleTransactionResult(result)
            }
        }
    }

    deinit {
        transactionListener?.cancel()
        verificationTask?.cancel()
    }
    
    private func loadProducts() async {
        guard !productsLoaded, productLoadState != .loading else { return }
        productLoadState = .loading
        do {
            let loaded = try await Product.products(for: productIDs)
            // StoreKit returns products in no particular order; keep weekly, monthly, lifetime.
            products = PurchasePlan.displayOrder.compactMap { plan in
                loaded.first { $0.id == plan.productID }
            }
            productsLoaded = !products.isEmpty
            productLoadState = products.isEmpty ? .failed : .loaded
        } catch {
            print("Failed to load products:", error)
            productLoadState = .failed
        }
    }

    /// Paywall entry point: loads (or retries) the StoreKit products.
    func loadProductsIfNeeded() async {
        await loadProducts()
    }

    func product(for plan: PurchasePlan) -> Product? {
        products.first { $0.id == plan.productID }
    }

    // MARK: - Premium status (SUB)

    /// Premium = lifetime OR any active, verified, non-revoked, non-expired subscription.
    /// Re-evaluated against the clock so a subscription that lapses while the app runs stops granting.
    var isPremium: Bool {
        let date = now()
        return activeEntitlements.values.contains { $0.grantsAccess(at: date) }
    }

    /// The highest plan currently granting Premium (lifetime beats monthly beats weekly).
    var activePlan: PurchasePlan? {
        activeEntitlement?.plan
    }

    var activeEntitlement: PurchaseEntitlement? {
        let date = now()
        return activeEntitlements.values
            .filter { $0.grantsAccess(at: date) }
            .max { ($0.plan?.rank ?? 0) < ($1.plan?.rank ?? 0) }
    }

    /// True when the user's Premium comes only from a subscription, so "Manage Subscription" is relevant.
    var hasActiveSubscription: Bool {
        activePlan?.isSubscription == true
    }

    private func setEntitlements(_ entitlements: [String: PurchaseEntitlement]) {
        activeEntitlements = entitlements
        purchasedProductIDs = Set(entitlements.keys)
    }

    /// Drops subscriptions whose period ended while the app was running.
    func pruneExpiredEntitlements() {
        let date = now()
        let remaining = activeEntitlements.filter { $0.value.grantsAccess(at: date) }
        guard remaining.count != activeEntitlements.count else { return }
        setEntitlements(remaining)
        persistPurchasedProducts()
    }
    
    private func handleTransactionResult(_ result: VerificationResult<StoreKit.Transaction>) async {
        let entitlement = await PurchaseEntitlement.resolvingSubscriptionStatus(result)
        _ = applyTransaction(entitlement)
        if case .verified(let transaction) = result, productIDs.contains(transaction.productID) {
            await transaction.finish()
        }
    }

    /// Handles one verified StoreKit update; complete snapshots use replacement below.
    @discardableResult
    func applyTransaction(_ entitlement: PurchaseEntitlement) -> Bool {
        guard productIDs.contains(entitlement.productID) else { return false }
        entitlementRevision += 1
        let wasPremiumBefore = isPremium
        let grants = entitlement.grantsAccess(at: now())
        var updated = activeEntitlements

        if !entitlement.isVerified {
            updated.removeValue(forKey: entitlement.productID)
            verificationState = .failed(.unverifiedTransaction)
        } else if !grants {
            // Revoked, expired, or upgraded away: this product no longer grants by itself.
            updated.removeValue(forKey: entitlement.productID)
            verificationState = .verified
        } else {
            updated[entitlement.productID] = entitlement
            verificationState = .verified
        }
        setEntitlements(updated)
        persistPurchasedProducts()

        // Preserve the existing rule: only a transaction-driven upgrade resets quota.
        if !wasPremiumBefore && isPremium {
            resetYoutubeImports()
        }
        return grants
    }

    private func persistPurchasedProducts() {
        if purchasedProductIDs.isEmpty {
            defaults.removeObject(forKey: UserDefaultsKeys.cachedPurchasedProductIDs)
        } else {
            defaults.set(purchasedProductIDs.sorted(), forKey: UserDefaultsKeys.cachedPurchasedProductIDs)
        }
    }

    /// Legacy entry point (pre-SUB callers): buys the lifetime unlock.
    func purchase() async throws {
        try await purchase(plan: .lifetime)
    }

    func purchase(plan: PurchasePlan) async throws {
        guard purchasingPlan == nil else { throw PurchaseError.purchaseInProgress }
        if products.isEmpty { await loadProducts() }
        guard let product = product(for: plan) else {
            throw PurchaseError.productNotFound
        }
        purchasingPlan = plan
        defer { purchasingPlan = nil }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let entitlement = await PurchaseEntitlement.resolvingSubscriptionStatus(verification)
            try applyPurchaseOutcome(.success(entitlement))
            if case .verified(let transaction) = verification {
                await transaction.finish()
            }
        case .userCancelled:
            try applyPurchaseOutcome(.userCancelled)
        case .pending:
            try applyPurchaseOutcome(.pending)
        @unknown default:
            try applyPurchaseOutcome(.unknown)
        }
    }

    /// Kept separate from Product.purchase so pending/cancelled outcomes are testable
    /// without manufacturing a signed StoreKit transaction or contacting the store.
    func applyPurchaseOutcome(_ outcome: PurchaseOutcome) throws {
        switch outcome {
        case .success(let entitlement):
            guard applyTransaction(entitlement) else {
                throw PurchaseError.verificationFailed
            }
        case .userCancelled:
            throw PurchaseError.userCancelled
        case .pending:
            throw PurchaseError.pending
        case .unknown:
            throw PurchaseError.unknown
        }
    }

    func useFreeTrial() {
        guard remainingFreeTries > 0 else { return }
        
        remainingFreeTries -= 1
        defaults.set(remainingFreeTries, forKey: "remainingFreeTries")
        defaults.set(true, forKey: "hasUsedFreeTrial")
        
        // Synchronize to ensure the value is saved immediately
        defaults.synchronize()
    }
    
    func restorePurchases() async {
        let result = await synchronizePurchases()
        guard let message = result.message else { return }
        NotificationCenter.default.post(
            name: NSNotification.Name("ShowPurchaseMessage"),
            object: nil,
            userInfo: ["message": message]
        )
    }

    /// Restore without broadcasting ShowPurchaseMessage (the paywall shows its own alert).
    func restorePurchasesResult() async -> PurchaseRestoreState {
        await synchronizePurchases()
    }

    /// Size of the free "premium tries" allowance shown by the Settings meter.
    var totalFreeTries: Int { maxFreeTries }

    var canAccessPremium: Bool {
        if !verificationInProgress && !isRestoringPurchases,
           let lastVerificationDate,
           Date().timeIntervalSince(lastVerificationDate) > verificationInterval {
            Task { await verifyPurchases() }
        }
        return isPremium || remainingFreeTries > 0
    }

    /// Regular verification reads StoreKit's local signed entitlements. It never
    /// invokes the authentication prompt associated with AppStore.sync().
    func verifyPurchases() async {
        guard !isRestoringPurchases else { return }
        _ = await refreshEntitlements()
    }

    private func refreshEntitlements(forceFresh: Bool = false) async -> Bool {
        if let previousTask = verificationTask {
            let previousID = verificationTaskID
            let succeeded = await previousTask.value
            if !forceFresh { return succeeded }
            if verificationTaskID == previousID {
                verificationTask = nil
            } else {
                return await refreshEntitlements(forceFresh: true)
            }
        }
        verificationInProgress = true
        verificationState = .loading
        let taskID = UUID()
        let task = Task { @MainActor in await self.readCurrentEntitlements() }
        verificationTaskID = taskID
        verificationTask = task
        let succeeded = await task.value
        if verificationTaskID == taskID {
            verificationTask = nil
            verificationTaskID = nil
            verificationInProgress = false
        }
        return succeeded
    }

    private func readCurrentEntitlements() async -> Bool {
        do {
            // A transaction update may arrive during enumeration. Re-read rather
            // than allowing an older snapshot to overwrite that update.
            while true {
                try Task.checkCancellation()
                let revision = entitlementRevision
                let entitlements = try await entitlementSource.current()
                try Task.checkCancellation()
                guard revision == entitlementRevision else { continue }

                let recognized = entitlements.filter { productIDs.contains($0.productID) }
                let date = now()
                var granting: [String: PurchaseEntitlement] = [:]
                for entitlement in recognized where entitlement.grantsAccess(at: date) {
                    // Keep the entitlement that lasts longest if StoreKit lists a product twice.
                    if let existing = granting[entitlement.productID],
                       let existingExpiry = existing.expirationDate,
                       let newExpiry = entitlement.expirationDate,
                       existingExpiry >= newExpiry {
                        continue
                    }
                    granting[entitlement.productID] = entitlement
                }
                setEntitlements(granting)
                persistPurchasedProducts() // An authoritative empty set clears the cache too.
                lastVerificationDate = Date()

                if recognized.contains(where: { !$0.isVerified }) {
                    verificationState = .failed(.unverifiedTransaction)
                    return false
                }
                verificationState = .verified
                return true
            }
        } catch {
            // A failed/cancelled read is not an authoritative empty snapshot.
            // Keep access established by earlier signed transactions, never by UserDefaults alone.
            verificationState = .failed(PurchaseVerificationFailure.classify(error))
            return false
        }
    }

    private func synchronizePurchases() async -> PurchaseRestoreState {
        guard !isRestoringPurchases else { return .restoring }
        isRestoringPurchases = true
        restoreState = .restoring
        defer { isRestoringPurchases = false }

        // Let an older local read finish before starting the user-requested sync.
        if let verificationTask { _ = await verificationTask.value }
        do {
            try Task.checkCancellation()
            try await entitlementSource.synchronize()
            try Task.checkCancellation()
            if await refreshEntitlements(forceFresh: true) {
                restoreState = isPremium ? .restored : .noPurchases
            } else if case .failed(let failure) = verificationState {
                restoreState = .failed(failure)
            } else {
                restoreState = .failed(.storeUnavailable)
            }
        } catch {
            let failure = PurchaseVerificationFailure.classify(error)
            verificationState = .failed(failure)
            restoreState = .failed(failure)
        }
        return restoreState
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
        let defaults = self.defaults
        let isPremium = self.isPremium
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
        
        let defaults = self.defaults
        
        if youtubeImportsRemaining <= 0 {
            print("📊 [PurchaseManager] No imports remaining, can't use import")
            return isPremium ? .limitReachedPremium : .limitReachedFree
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
    
    func manuallyVerifyPurchases() async -> Bool {
        // Return whether this request actually verified an active purchase, not
        // whether an earlier result still grants access after an offline sync failure.
        await synchronizePurchases() == .restored
    }

    private func silentlyVerifyPurchases() async {
        _ = await refreshEntitlements()
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
        pruneExpiredEntitlements()
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

enum PurchaseError: Error, Equatable {
    case productNotFound
    case verificationFailed
    case userCancelled
    case pending
    case purchaseInProgress
    case unknown
}

enum ProductLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed
}
