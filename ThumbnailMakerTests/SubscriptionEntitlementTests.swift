//
//  SubscriptionEntitlementTests.swift
//  ThumbnailMakerTests
//
//  SUB: Premium = lifetime OR any active, verified, non-revoked, non-expired subscription.
//  Existing weekly/monthly subscribers must keep Premium; APP-02 guarantees still hold.
//

import Foundation
import StoreKit
import Testing
@testable import ThumbnailMaker

private let weeklyID = "com.williamjiamin.ThumbnailMaker.premium.weekly"
private let monthlyID = "com.williamjiamin.ThumbnailMaker.premium.monthly"
private let lifetimeID = "com.williamjiamin.ThumbnailMaker.premiumlifetime2024"

@MainActor
private final class TestClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}

@MainActor
private final class EntitlementBox {
    var entitlements: [PurchaseEntitlement]
    var error: Error?
    init(_ entitlements: [PurchaseEntitlement]) { self.entitlements = entitlements }
}

@MainActor
struct SubscriptionEntitlementTests {
    private let referenceDate = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: Product catalogue

    @Test func productIDsMatchAppStoreConnectExactly() {
        #expect(PurchasePlan.weekly.productID == weeklyID)
        #expect(PurchasePlan.monthly.productID == monthlyID)
        #expect(PurchasePlan.lifetime.productID == lifetimeID)
        #expect(PurchasePlan.allProductIDs == [weeklyID, monthlyID, lifetimeID])
        #expect(PurchasePlan.weekly.isSubscription)
        #expect(PurchasePlan.monthly.isSubscription)
        #expect(!PurchasePlan.lifetime.isSubscription)
    }

    @Test func paywallCopyStatesRenewalAndOneTimeTerms() {
        #expect(PurchasePlan.weekly.priceLine(displayPrice: "$0.99") == "$0.99 / week")
        #expect(PurchasePlan.monthly.priceLine(displayPrice: "$2.99") == "$2.99 / month")
        #expect(PurchasePlan.lifetime.priceLine(displayPrice: "$9.99") == "$9.99")
        #expect(PurchasePlan.weekly.billingNote.contains("until cancelled"))
        #expect(PurchasePlan.monthly.billingNote.contains("until cancelled"))
        #expect(PurchasePlan.lifetime.billingNote.contains("One-time purchase"))
        #expect(PurchasePlan.weekly.referencePrice == "$0.99")
        #expect(PurchasePlan.monthly.referencePrice == "$2.99")
        #expect(PurchasePlan.lifetime.referencePrice == "$9.99")
    }

    @Test func storeKitConfigurationMatchesPlans() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("ThumbnailMakerPremium.storekit")
        let data = try Data(contentsOf: url)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let products = try #require(json["products"] as? [[String: Any]])
        let groups = try #require(json["subscriptionGroups"] as? [[String: Any]])
        #expect(groups.count == 1)
        let group = try #require(groups.first)
        #expect(group["name"] as? String == "ThumbnailMaker Premium")
        let subscriptions = try #require(group["subscriptions"] as? [[String: Any]])

        let lifetime = try #require(products.first)
        #expect(lifetime["productID"] as? String == lifetimeID)
        #expect(lifetime["type"] as? String == "NonConsumable")
        #expect(lifetime["displayPrice"] as? String == "9.99")

        let byID = Dictionary(uniqueKeysWithValues: subscriptions.compactMap { sub -> (String, [String: Any])? in
            guard let id = sub["productID"] as? String else { return nil }
            return (id, sub)
        })
        #expect(byID[weeklyID]?["recurringSubscriptionPeriod"] as? String == "P1W")
        #expect(byID[weeklyID]?["groupNumber"] as? Int == 1)
        #expect(byID[weeklyID]?["displayPrice"] as? String == "0.99")
        #expect(byID[monthlyID]?["recurringSubscriptionPeriod"] as? String == "P1M")
        #expect(byID[monthlyID]?["groupNumber"] as? Int == 2)
        #expect(byID[monthlyID]?["displayPrice"] as? String == "2.99")
    }

    // MARK: Entitlement rule

    @Test func grantsAccessRuleCoversEveryPlanAndState() {
        let now = referenceDate
        let future = now.addingTimeInterval(3600)
        let past = now.addingTimeInterval(-3600)

        #expect(PurchaseEntitlement(productID: lifetimeID).grantsAccess(at: now))
        #expect(PurchaseEntitlement(productID: weeklyID, expirationDate: future).grantsAccess(at: now))
        #expect(PurchaseEntitlement(productID: monthlyID, expirationDate: future).grantsAccess(at: now))
        #expect(!PurchaseEntitlement(productID: weeklyID, expirationDate: past).grantsAccess(at: now))
        #expect(!PurchaseEntitlement(productID: monthlyID, expirationDate: past).grantsAccess(at: now))
        #expect(!PurchaseEntitlement(productID: monthlyID, expirationDate: now).grantsAccess(at: now))
        #expect(PurchaseEntitlement(productID: monthlyID, expirationDate: past, isInBillingGracePeriod: true).grantsAccess(at: now))
        #expect(!PurchaseEntitlement(productID: monthlyID, isRevoked: true, expirationDate: future).grantsAccess(at: now))
        #expect(!PurchaseEntitlement(productID: lifetimeID, isRevoked: true).grantsAccess(at: now))
        #expect(!PurchaseEntitlement(productID: weeklyID, isVerified: false, expirationDate: future).grantsAccess(at: now))
        #expect(!PurchaseEntitlement(productID: weeklyID, expirationDate: future, isUpgraded: true).grantsAccess(at: now))
    }

    // MARK: Snapshot replacement

    @Test(arguments: [weeklyID, monthlyID])
    func activeSubscriptionGrantsPremium(productID: String) async {
        let (manager, defaults, _, _) = makeManager([
            PurchaseEntitlement(productID: productID, expirationDate: referenceDate.addingTimeInterval(86_400))
        ])
        await manager.verifyPurchases()
        #expect(manager.isPremium)
        #expect(manager.purchasedProductIDs == [productID])
        #expect(manager.activePlan?.productID == productID)
        #expect(manager.hasActiveSubscription)
        #expect(manager.verificationState == .verified)
        #expect(defaults.stringArray(forKey: "cachedPurchasedProductIDs") == [productID])
    }

    @Test func lifetimeStillGrantsPremium() async {
        let (manager, _, _, _) = makeManager([PurchaseEntitlement(productID: lifetimeID)])
        await manager.verifyPurchases()
        #expect(manager.isPremium)
        #expect(manager.activePlan == .lifetime)
        #expect(!manager.hasActiveSubscription)
    }

    @Test(arguments: [weeklyID, monthlyID])
    func expiredSubscriptionDoesNotGrant(productID: String) async {
        let (manager, defaults, _, _) = makeManager([
            PurchaseEntitlement(productID: productID, expirationDate: referenceDate.addingTimeInterval(-60))
        ])
        defaults.set([productID], forKey: "cachedPurchasedProductIDs")
        await manager.verifyPurchases()
        #expect(!manager.isPremium)
        #expect(manager.purchasedProductIDs.isEmpty)
        #expect(manager.activePlan == nil)
        #expect(defaults.stringArray(forKey: "cachedPurchasedProductIDs") == nil)
    }

    @Test(arguments: [weeklyID, monthlyID])
    func revokedSubscriptionDoesNotGrant(productID: String) async {
        let (manager, _, _, _) = makeManager([
            PurchaseEntitlement(
                productID: productID,
                isRevoked: true,
                expirationDate: referenceDate.addingTimeInterval(86_400)
            )
        ])
        await manager.verifyPurchases()
        #expect(!manager.isPremium)
        #expect(manager.purchasedProductIDs.isEmpty)
    }

    @Test func unverifiedSubscriptionDoesNotGrantAndReportsFailure() async {
        let (manager, _, _, _) = makeManager([
            PurchaseEntitlement(
                productID: monthlyID,
                isVerified: false,
                expirationDate: referenceDate.addingTimeInterval(86_400)
            )
        ])
        await manager.verifyPurchases()
        #expect(!manager.isPremium)
        #expect(manager.verificationState == .failed(.unverifiedTransaction))
    }

    @Test func gracePeriodKeepsPayingSubscriberPremium() async {
        let (manager, _, _, _) = makeManager([
            PurchaseEntitlement(
                productID: monthlyID,
                expirationDate: referenceDate.addingTimeInterval(-3600),
                isInBillingGracePeriod: true
            )
        ])
        await manager.verifyPurchases()
        #expect(manager.isPremium)
        #expect(manager.activePlan == .monthly)
    }

    @Test func emptySnapshotRemovesPreviouslyActiveSubscription() async {
        let (manager, defaults, box, _) = makeManager([
            PurchaseEntitlement(productID: weeklyID, expirationDate: referenceDate.addingTimeInterval(86_400))
        ])
        await manager.verifyPurchases()
        #expect(manager.isPremium)

        box.entitlements = []
        await manager.verifyPurchases()
        #expect(!manager.isPremium)
        #expect(manager.purchasedProductIDs.isEmpty)
        #expect(defaults.stringArray(forKey: "cachedPurchasedProductIDs") == nil)
    }

    @Test func offlineRefreshKeepsVerifiedSubscription() async {
        let (manager, _, box, _) = makeManager([
            PurchaseEntitlement(productID: monthlyID, expirationDate: referenceDate.addingTimeInterval(86_400))
        ])
        await manager.verifyPurchases()
        box.error = URLError(.notConnectedToInternet)
        await manager.verifyPurchases()
        #expect(manager.isPremium)
        #expect(manager.verificationState == .failed(.networkUnavailable))
    }

    @Test func subscriptionLapsingWhileRunningStopsGranting() async {
        let (manager, defaults, _, clock) = makeManager([
            PurchaseEntitlement(productID: weeklyID, expirationDate: referenceDate.addingTimeInterval(60))
        ])
        await manager.verifyPurchases()
        #expect(manager.isPremium)

        clock.date = referenceDate.addingTimeInterval(120)
        #expect(!manager.isPremium)
        manager.pruneExpiredEntitlements()
        #expect(manager.purchasedProductIDs.isEmpty)
        #expect(defaults.stringArray(forKey: "cachedPurchasedProductIDs") == nil)
    }

    @Test func activePlanPrefersLifetimeThenMonthlyThenWeekly() async {
        let future = referenceDate.addingTimeInterval(86_400)
        let (manager, _, box, _) = makeManager([
            PurchaseEntitlement(productID: weeklyID, expirationDate: future),
            PurchaseEntitlement(productID: monthlyID, expirationDate: future),
        ])
        await manager.verifyPurchases()
        #expect(manager.activePlan == .monthly)

        box.entitlements.append(PurchaseEntitlement(productID: lifetimeID))
        await manager.verifyPurchases()
        #expect(manager.activePlan == .lifetime)
        #expect(manager.purchasedProductIDs == [weeklyID, monthlyID, lifetimeID])
    }

    @Test func restoreWithActiveSubscriptionReportsRestored() async {
        let (manager, _, _, _) = makeManager([
            PurchaseEntitlement(productID: monthlyID, expirationDate: referenceDate.addingTimeInterval(86_400))
        ])
        let result = await manager.restorePurchasesResult()
        #expect(result == .restored)
        #expect(manager.isPremium)
    }

    @Test func restoreWithOnlyExpiredSubscriptionReportsNoPurchases() async {
        let (manager, _, _, _) = makeManager([
            PurchaseEntitlement(productID: monthlyID, expirationDate: referenceDate.addingTimeInterval(-86_400))
        ])
        let result = await manager.restorePurchasesResult()
        #expect(result == .noPurchases)
        #expect(!manager.isPremium)
    }

    // MARK: Transaction updates

    @Test func purchaseOfSubscriptionGrantsThroughOutcome() throws {
        let (manager, _, _, _) = makeManager([])
        try manager.applyPurchaseOutcome(.success(
            PurchaseEntitlement(productID: weeklyID, expirationDate: referenceDate.addingTimeInterval(604_800))
        ))
        #expect(manager.isPremium)
        #expect(manager.activePlan == .weekly)
    }

    @Test func expiredPurchaseOutcomeThrowsVerificationFailed() {
        let (manager, _, _, _) = makeManager([])
        #expect(throws: PurchaseError.verificationFailed) {
            try manager.applyPurchaseOutcome(.success(
                PurchaseEntitlement(productID: weeklyID, expirationDate: referenceDate.addingTimeInterval(-1))
            ))
        }
        #expect(!manager.isPremium)
    }

    @Test func expiredOrRevokedUpdateRemovesSubscription() {
        let (manager, _, _, _) = makeManager([])
        let future = referenceDate.addingTimeInterval(86_400)
        #expect(manager.applyTransaction(PurchaseEntitlement(productID: monthlyID, expirationDate: future)))
        #expect(manager.isPremium)

        #expect(!manager.applyTransaction(PurchaseEntitlement(productID: monthlyID, expirationDate: referenceDate.addingTimeInterval(-1))))
        #expect(!manager.isPremium)

        #expect(manager.applyTransaction(PurchaseEntitlement(productID: monthlyID, expirationDate: future)))
        #expect(!manager.applyTransaction(PurchaseEntitlement(productID: monthlyID, isRevoked: true, expirationDate: future)))
        #expect(!manager.isPremium)
    }

    @Test func upgradeWithinGroupKeepsPremiumOnNewPlan() {
        let (manager, _, _, _) = makeManager([])
        let future = referenceDate.addingTimeInterval(86_400)
        #expect(manager.applyTransaction(PurchaseEntitlement(productID: weeklyID, expirationDate: future)))
        #expect(!manager.applyTransaction(PurchaseEntitlement(productID: weeklyID, expirationDate: future, isUpgraded: true)))
        #expect(manager.applyTransaction(PurchaseEntitlement(productID: monthlyID, expirationDate: future)))
        #expect(manager.isPremium)
        #expect(manager.purchasedProductIDs == [monthlyID])
    }

    @Test func unknownProductUpdateIsIgnored() {
        let (manager, _, _, _) = makeManager([])
        #expect(!manager.applyTransaction(PurchaseEntitlement(productID: "com.example.other.weekly", expirationDate: referenceDate.addingTimeInterval(86_400))))
        #expect(!manager.isPremium)
    }

    @Test func sanitizedCacheKeepsSubscriptionIDsButNeverGrants() {
        let defaults = freshDefaults()
        defaults.set([monthlyID, "com.example.other"], forKey: "cachedPurchasedProductIDs")
        let manager = PurchaseManager(
            defaults: defaults,
            entitlementSource: PurchaseEntitlementSource(current: { [] }, synchronize: { }),
            startsBackgroundServices: false
        )
        #expect(!manager.isPremium)
        #expect(manager.purchasedProductIDs.isEmpty)
        #expect(defaults.stringArray(forKey: "cachedPurchasedProductIDs") == [monthlyID])
    }

    @Test func freeTriesStillGateCanAccessPremium() async {
        let (manager, _, _, _) = makeManager([])
        #expect(manager.totalFreeTries == 3)
        #expect(manager.remainingFreeTries == 3)
        #expect(manager.canAccessPremium)
        manager.useFreeTrial()
        manager.useFreeTrial()
        manager.useFreeTrial()
        #expect(manager.remainingFreeTries == 0)
        #expect(!manager.canAccessPremium)
        _ = manager.applyTransaction(PurchaseEntitlement(productID: weeklyID, expirationDate: referenceDate.addingTimeInterval(86_400)))
        #expect(manager.canAccessPremium)
    }

    // MARK: UI copy

    @Test func paywallStatusMapsPurchaseErrors() {
        #expect(PaywallPurchaseStatus.from(PurchaseError.userCancelled) == .cancelled)
        #expect(PaywallPurchaseStatus.from(PurchaseError.pending) == .pending)
        #expect(PaywallPurchaseStatus.from(StoreKitError.userCancelled) == .cancelled)
        if case .failed(let message) = PaywallPurchaseStatus.from(PurchaseError.productNotFound) {
            #expect(message.contains("not available"))
        } else {
            Issue.record("productNotFound should map to a failure message")
        }
        if case .failed = PaywallPurchaseStatus.from(URLError(.notConnectedToInternet)) {
        } else {
            Issue.record("offline should map to a failure message")
        }
        #expect(PaywallPurchaseStatus.cancelled.message?.contains("Nothing was charged") == true)
        #expect(PaywallPurchaseStatus.pending.message?.contains("approval") == true)
        #expect(PaywallPurchaseStatus.idle.message == nil)
        #expect(PaywallPurchaseStatus.purchasing(.weekly).isPurchasing)
        #expect(PaywallPurchaseStatus.purchased(.monthly).message?.contains("renews automatically") == true)
        #expect(PaywallPurchaseStatus.purchased(.lifetime).message?.contains("for life") == true)
    }

    @Test func settingsStatusTextDescribesRenewalAndExpiry() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let now = referenceDate
        let future = now.addingTimeInterval(7 * 86_400)
        let futureText = formatter.string(from: future)

        #expect(SubscriptionStatusText.detail(for: PurchaseEntitlement(productID: lifetimeID), now: now, formatter: formatter).contains("never expires"))
        #expect(SubscriptionStatusText.detail(
            for: PurchaseEntitlement(productID: weeklyID, expirationDate: future, willAutoRenew: true),
            now: now, formatter: formatter
        ) == "Renews on \(futureText).")
        #expect(SubscriptionStatusText.detail(
            for: PurchaseEntitlement(productID: monthlyID, expirationDate: future, willAutoRenew: false),
            now: now, formatter: formatter
        ) == "Cancelled — Premium ends on \(futureText).")
        #expect(SubscriptionStatusText.detail(
            for: PurchaseEntitlement(productID: monthlyID, expirationDate: future),
            now: now, formatter: formatter
        ) == "Renews or ends on \(futureText).")
        #expect(SubscriptionStatusText.detail(
            for: PurchaseEntitlement(productID: monthlyID, expirationDate: now.addingTimeInterval(-60), isInBillingGracePeriod: true),
            now: now, formatter: formatter
        ).contains("Payment issue"))
    }

    @Test func premiumTriesLabelMatchesSettingsScreenshot() {
        #expect(PremiumTriesMeter.label(remaining: 3) == "3 premium tries left")
        #expect(PremiumTriesMeter.label(remaining: 1) == "1 premium try left")
        #expect(PremiumTriesMeter.label(remaining: 0) == "No premium tries left")
    }

    // MARK: Helpers

    private func makeManager(
        _ entitlements: [PurchaseEntitlement]
    ) -> (PurchaseManager, UserDefaults, EntitlementBox, TestClock) {
        let defaults = freshDefaults()
        let box = EntitlementBox(entitlements)
        let clock = TestClock(referenceDate)
        let source = PurchaseEntitlementSource(
            current: {
                if let error = box.error { throw error }
                return box.entitlements
            },
            synchronize: { }
        )
        let manager = PurchaseManager(
            defaults: defaults,
            entitlementSource: source,
            startsBackgroundServices: false,
            now: { clock.date }
        )
        return (manager, defaults, box, clock)
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "ThumbnailMaker-SUB-Tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
