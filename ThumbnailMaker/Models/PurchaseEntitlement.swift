import Foundation
import StoreKit

/// The three App Store Connect products that unlock Premium (SUB).
/// Weekly and monthly share the "ThumbnailMaker Premium" subscription group
/// (levels 1 and 2); lifetime is the original non-consumable from 2024.
enum PurchasePlan: String, CaseIterable, Identifiable, Sendable {
    case weekly = "com.williamjiamin.ThumbnailMaker.premium.weekly"
    case monthly = "com.williamjiamin.ThumbnailMaker.premium.monthly"
    case lifetime = "com.williamjiamin.ThumbnailMaker.premiumlifetime2024"

    var id: String { rawValue }
    var productID: String { rawValue }

    /// Paywall display order: weekly, monthly, lifetime.
    static let displayOrder: [PurchasePlan] = [.weekly, .monthly, .lifetime]
    static var allProductIDs: [String] { displayOrder.map(\.productID) }

    init?(productID: String) { self.init(rawValue: productID) }

    var isSubscription: Bool { self != .lifetime }

    /// Higher wins when several entitlements are active at once (lifetime beats any subscription).
    var rank: Int {
        switch self {
        case .weekly: return 1
        case .monthly: return 2
        case .lifetime: return 3
        }
    }

    var title: String {
        switch self {
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .lifetime: return "Lifetime"
        }
    }

    var periodName: String? {
        switch self {
        case .weekly: return "week"
        case .monthly: return "month"
        case .lifetime: return nil
        }
    }

    /// Fallback price if StoreKit has not returned the localized product yet (never used to purchase).
    var referencePrice: String {
        switch self {
        case .weekly: return "$0.99"
        case .monthly: return "$2.99"
        case .lifetime: return "$9.99"
        }
    }

    /// "$0.99 / week" or "$9.99" — always fed StoreKit's localized displayPrice when available.
    func priceLine(displayPrice: String) -> String {
        guard let periodName else { return displayPrice }
        return "\(displayPrice) / \(periodName)"
    }

    /// The billing disclosure shown under each plan row.
    var billingNote: String {
        switch self {
        case .weekly: return "Auto-renews weekly until cancelled"
        case .monthly: return "Auto-renews monthly until cancelled"
        case .lifetime: return "One-time purchase, yours forever"
        }
    }

    var purchaseButtonTitle: String {
        isSubscription ? "Subscribe \(title)" : "Buy Lifetime"
    }
}

/// A testable projection of StoreKit's signed transaction result, not a second receipt verifier.
struct PurchaseEntitlement: Equatable, Sendable {
    let productID: String
    let isVerified: Bool
    var isRevoked = false
    /// Subscription period end; nil for the non-consumable lifetime product.
    var expirationDate: Date?
    /// A subscription superseded by a higher level in the same group no longer grants by itself.
    var isUpgraded = false
    /// StoreKit reports the subscription in billing grace/retry-with-access, so an elapsed
    /// expirationDate must not lock a paying subscriber out.
    var isInBillingGracePeriod = false
    /// From the verified renewal info when known; nil means "unknown" (e.g. a bare update).
    var willAutoRenew: Bool?

    init(
        productID: String,
        isVerified: Bool = true,
        isRevoked: Bool = false,
        expirationDate: Date? = nil,
        isUpgraded: Bool = false,
        isInBillingGracePeriod: Bool = false,
        willAutoRenew: Bool? = nil
    ) {
        self.productID = productID
        self.isVerified = isVerified
        self.isRevoked = isRevoked
        self.expirationDate = expirationDate
        self.isUpgraded = isUpgraded
        self.isInBillingGracePeriod = isInBillingGracePeriod
        self.willAutoRenew = willAutoRenew
    }

    init(_ result: VerificationResult<StoreKit.Transaction>) {
        switch result {
        case .verified(let transaction):
            productID = transaction.productID
            isVerified = true
            isRevoked = transaction.revocationDate != nil || transaction.revocationReason != nil
            expirationDate = transaction.expirationDate
            isUpgraded = transaction.isUpgraded
        case .unverified(let transaction, _):
            productID = transaction.productID
            isVerified = false
        }
    }

    var plan: PurchasePlan? { PurchasePlan(productID: productID) }

    /// Premium = lifetime OR an active, verified, non-revoked, non-expired subscription.
    func grantsAccess(at now: Date) -> Bool {
        guard isVerified, !isRevoked, !isUpgraded else { return false }
        guard let expirationDate else { return true }
        return expirationDate > now || isInBillingGracePeriod
    }

    /// Reads the verified renewal state for a subscription transaction (grace period, auto-renew).
    static func resolvingSubscriptionStatus(
        _ result: VerificationResult<StoreKit.Transaction>
    ) async -> PurchaseEntitlement {
        var entitlement = PurchaseEntitlement(result)
        guard case .verified(let transaction) = result,
              transaction.productType == .autoRenewable,
              let status = await transaction.subscriptionStatus else {
            return entitlement
        }
        if status.state == .inGracePeriod || status.state == .inBillingRetryPeriod {
            // Billing retry without grace does NOT keep access: only grace does.
            entitlement.isInBillingGracePeriod = status.state == .inGracePeriod
        }
        if case .verified(let renewalInfo) = status.renewalInfo {
            entitlement.willAutoRenew = renewalInfo.willAutoRenew
        }
        return entitlement
    }
}

@MainActor
struct PurchaseEntitlementSource {
    var current: () async throws -> [PurchaseEntitlement]
    var synchronize: () async throws -> Void

    static var storeKit: PurchaseEntitlementSource {
        PurchaseEntitlementSource(
            current: {
                var entitlements: [PurchaseEntitlement] = []
                for await result in StoreKit.Transaction.currentEntitlements {
                    try Task.checkCancellation()
                    entitlements.append(await PurchaseEntitlement.resolvingSubscriptionStatus(result))
                }
                try Task.checkCancellation()
                return entitlements
            },
            synchronize: { try await AppStore.sync() }
        )
    }
}

enum PurchaseVerificationFailure: Equatable {
    case networkUnavailable
    case cancelled
    case unverifiedTransaction
    case storeUnavailable

    static func classify(_ error: Error) -> PurchaseVerificationFailure {
        if error is CancellationError { return .cancelled }
        if let storeError = error as? StoreKitError {
            switch storeError {
            case .userCancelled:
                return .cancelled
            case .networkError(let networkError):
                return classify(networkError)
            case .systemError(let underlyingError):
                return classify(underlyingError)
            default:
                return .storeUnavailable
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return .networkUnavailable
            case NSURLErrorCancelled, NSURLErrorUserCancelledAuthentication:
                return .cancelled
            default:
                return .storeUnavailable
            }
        }
        if nsError.domain == SKErrorDomain && nsError.code == SKError.paymentCancelled.rawValue {
            return .cancelled
        }
        return .storeUnavailable
    }
}

/// Describes the latest verification operation. A failed sync does not erase locally verified access.
enum PurchaseVerificationState: Equatable {
    case notVerified
    case loading
    case verified
    case failed(PurchaseVerificationFailure)
}

enum PurchaseRestoreState: Equatable {
    case idle
    case restoring
    case restored
    case noPurchases
    case failed(PurchaseVerificationFailure)

    var message: String? {
        switch self {
        case .idle, .restoring:
            return nil
        case .restored:
            return "Purchases restored successfully."
        case .noPurchases:
            return "No active purchases were found for this Apple Account."
        case .failed(.networkUnavailable):
            return "Could not connect to the App Store. Check your connection and try restoring again."
        case .failed(.cancelled):
            return "Purchase restoration was cancelled."
        case .failed(.unverifiedTransaction):
            return "A purchase could not be verified. Please try restoring again."
        case .failed(.storeUnavailable):
            return "Failed to restore purchases. Please try again."
        }
    }
}

enum PurchaseOutcome {
    case success(PurchaseEntitlement)
    case userCancelled
    case pending
    case unknown
}
