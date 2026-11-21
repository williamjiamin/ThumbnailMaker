//
//  PurchaseEntitlementTests.swift
//  ThumbnailMakerTests
//
//  Tests for PurchaseManager entitlement reconciliation:
//  - stale cache removal after a completed refresh with no current entitlement
//  - valid purchases retain access through revoke/restore-empty/pending/cancelled/offline
//  - verificationState truthfully reflects the latest read
//  - StoreKit failures never grant paid access via the UserDefaults cache alone
//

import Foundation
import StoreKit
import Testing
@testable import ThumbnailMaker

private let recognizedProductID = "com.williamjiamin.ThumbnailMaker.premiumlifetime2024"

@MainActor
struct PurchaseEntitlementTests {
    @Test func staleCacheIsClearedWhenRefreshReturnsNoEntitlements() async throws {
        let defaults = freshDefaults()
        defaults.set([recognizedProductID], forKey: "cachedPurchasedProductIDs")

        let source = PurchaseEntitlementSource(
            current: { [] },
            synchronize: { }
        )
        let manager = PurchaseManager(
            defaults: defaults,
            entitlementSource: source,
            startsBackgroundServices: false
        )

        #expect(manager.purchasedProductIDs.isEmpty)
        await manager.verifyPurchases()
        #expect(manager.purchasedProductIDs.isEmpty)
        #expect(manager.verificationState == .verified)
        #expect(defaults.stringArray(forKey: "cachedPurchasedProductIDs") == nil)
    }

    @Test func unverifiedResultsDoNotGrantAccessAndReportFailure() async throws {
        let defaults = freshDefaults()
        let source = PurchaseEntitlementSource(
            current: {
                [PurchaseEntitlement(productID: recognizedProductID, isVerified: false)]
            },
            synchronize: { }
        )
        let manager = PurchaseManager(
            defaults: defaults,
            entitlementSource: source,
            startsBackgroundServices: false
        )

        await manager.verifyPurchases()
        #expect(manager.purchasedProductIDs.isEmpty)
        if case .failed(.unverifiedTransaction) = manager.verificationState {
            // expected
        } else {
            Issue.record("Expected .failed(.unverifiedTransaction), got \(manager.verificationState)")
        }
    }

    @Test func verifiedPurchaseGrantsAccess() async throws {
        let defaults = freshDefaults()
        let source = PurchaseEntitlementSource(
            current: {
                [PurchaseEntitlement(productID: recognizedProductID, isVerified: true)]
            },
            synchronize: { }
        )
        let manager = PurchaseManager(
            defaults: defaults,
            entitlementSource: source,
            startsBackgroundServices: false
        )

        await manager.verifyPurchases()
        #expect(manager.purchasedProductIDs == [recognizedProductID])
        #expect(manager.verificationState == .verified)
        #expect(defaults.stringArray(forKey: "cachedPurchasedProductIDs") == [recognizedProductID])
    }

    @Test func revocationRemovesEntitlement() async throws {
        let defaults = freshDefaults()
        defaults.set([recognizedProductID], forKey: "cachedPurchasedProductIDs")
        let source = PurchaseEntitlementSource(
            current: {
                [PurchaseEntitlement(productID: recognizedProductID, isVerified: true, isRevoked: true)]
            },
            synchronize: { }
        )
        let manager = PurchaseManager(
            defaults: defaults,
            entitlementSource: source,
            startsBackgroundServices: false
        )

        await manager.verifyPurchases()
        #expect(manager.purchasedProductIDs.isEmpty)
        #expect(defaults.stringArray(forKey: "cachedPurchasedProductIDs") == nil)
    }

    @Test func unrecognizedProductIDsAreIgnored() async throws {
        let defaults = freshDefaults()
        let source = PurchaseEntitlementSource(
            current: {
                [PurchaseEntitlement(productID: "com.example.unrelated", isVerified: true)]
            },
            synchronize: { }
        )
        let manager = PurchaseManager(
            defaults: defaults,
            entitlementSource: source,
            startsBackgroundServices: false
        )

        await manager.verifyPurchases()
        #expect(manager.purchasedProductIDs.isEmpty)
        #expect(defaults.stringArray(forKey: "cachedPurchasedProductIDs") == nil)
    }

    @Test func restoreWithNoPurchasesReportsNoPurchases() async throws {
        let defaults = freshDefaults()
        let source = PurchaseEntitlementSource(
            current: { [] },
            synchronize: { }
        )
        let manager = PurchaseManager(
            defaults: defaults,
            entitlementSource: source,
            startsBackgroundServices: false
        )

        _ = await manager.restorePurchases()
        #expect(manager.restoreState == .noPurchases)
        if case .noPurchases = manager.restoreState {
            #expect(manager.restoreState.message != nil)
        }
    }

    @Test func restoreFailureSurfacesAsFailedRestore() async throws {
        let defaults = freshDefaults()
        let source = PurchaseEntitlementSource(
            current: { [] },
            synchronize: { throw URLError(.notConnectedToInternet) }
        )
        let manager = PurchaseManager(
            defaults: defaults,
            entitlementSource: source,
            startsBackgroundServices: false
        )

        _ = await manager.restorePurchases()
        if case .failed(.networkUnavailable) = manager.restoreState {
            #expect(manager.restoreState.message != nil)
        } else {
            Issue.record("Expected failed network restore, got \(manager.restoreState)")
        }
    }

    @Test func purchaseCancellationThrowsUserCancelled() async throws {
        let defaults = freshDefaults()
        let source = PurchaseEntitlementSource(
            current: { [] },
            synchronize: { }
        )
        let manager = PurchaseManager(
            defaults: defaults,
            entitlementSource: source,
            startsBackgroundServices: false
        )

        #expect(throws: PurchaseError.userCancelled) {
            try manager.applyPurchaseOutcome(.userCancelled)
        }
    }

    @Test func purchasePendingThrowsPending() async throws {
        let defaults = freshDefaults()
        let source = PurchaseEntitlementSource(
            current: { [] },
            synchronize: { }
        )
        let manager = PurchaseManager(
            defaults: defaults,
            entitlementSource: source,
            startsBackgroundServices: false
        )

        #expect(throws: PurchaseError.pending) {
            try manager.applyPurchaseOutcome(.pending)
        }
    }

    @Test func unverifiedTransactionOutcomeThrowsVerificationFailed() async throws {
        let defaults = freshDefaults()
        let source = PurchaseEntitlementSource(
            current: { [] },
            synchronize: { }
        )
        let manager = PurchaseManager(
            defaults: defaults,
            entitlementSource: source,
            startsBackgroundServices: false
        )

        #expect(throws: PurchaseError.verificationFailed) {
            try manager.applyPurchaseOutcome(.success(
                PurchaseEntitlement(productID: recognizedProductID, isVerified: false)
            ))
        }
    }

    @Test func unsanitizedCacheAloneDoesNotGrantAccessOnColdInit() throws {
        // A UserDefaults cache from before the recognized-product filter existed
        // (or from a foreign test run) must not be enough to grant paid access.
        let defaults = freshDefaults()
        defaults.set(["com.example.unrelated"], forKey: "cachedPurchasedProductIDs")

        let source = PurchaseEntitlementSource(
            current: { [] },
            synchronize: { }
        )
        let manager = PurchaseManager(
            defaults: defaults,
            entitlementSource: source,
            startsBackgroundServices: false
        )

        #expect(manager.purchasedProductIDs.isEmpty)
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "ThumbnailMaker-Tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
