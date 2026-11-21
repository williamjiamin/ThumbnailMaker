import StoreKit
import SwiftUI

/// SUB: Settings "Subscription" section — status, active plan with renewal/expiry,
/// free-tries meter, upgrade (paywall), Manage Subscription and Restore Purchases.
struct SubscriptionSettingsSection: View {
    @ObservedObject var purchaseManager: PurchaseManager
    @State private var isPaywallPresented = false
    @State private var isManageSubscriptionsPresented = false

    var body: some View {
        Section {
            if let entitlement = purchaseManager.activeEntitlement, let plan = entitlement.plan {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Premium Active · \(plan.title)", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("settings.activePlan")
                    Text(SubscriptionStatusText.detail(for: entitlement))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.planRenewal")
                }
                if plan.isSubscription {
                    Button {
                        isManageSubscriptionsPresented = true
                    } label: {
                        Label("Manage Subscription", systemImage: "creditcard")
                    }
                    .accessibilityIdentifier("settings.manageSubscription")
                    Button {
                        isPaywallPresented = true
                    } label: {
                        Label("Change Plan", systemImage: "arrow.left.arrow.right")
                    }
                }
            } else {
                Label("Free Version", systemImage: "star")
                PremiumTriesMeter(
                    remaining: purchaseManager.remainingFreeTries,
                    total: purchaseManager.totalFreeTries
                )
                Button {
                    isPaywallPresented = true
                } label: {
                    Label("Upgrade to Premium", systemImage: "crown")
                        .fontWeight(.semibold)
                }
                .accessibilityIdentifier("settings.upgrade")
            }

            Button {
                Task { await purchaseManager.restorePurchases() }
            } label: {
                HStack {
                    Label("Restore Purchases", systemImage: "arrow.clockwise")
                    if purchaseManager.isRestoringPurchases {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(purchaseManager.isRestoringPurchases)
            .accessibilityIdentifier("settings.restorePurchases")
        } header: {
            Text("Subscription")
        } footer: {
            Text("Linked to your Apple ID. Restore purchases when switching devices.")
        }
        .sheet(isPresented: $isPaywallPresented) {
            PremiumPaywallView(presentation: .sheet)
        }
        .manageSubscriptionsSheet(isPresented: $isManageSubscriptionsPresented)
        .onChange(of: isManageSubscriptionsPresented) { _, isPresented in
            // Pick up cancellations/plan changes made in the system sheet.
            if !isPresented { Task { await purchaseManager.verifyPurchases() } }
        }
    }
}

/// Pure formatting for the active plan's renewal/expiry line (unit-tested).
enum SubscriptionStatusText {
    static func detail(
        for entitlement: PurchaseEntitlement,
        now: Date = Date(),
        formatter: DateFormatter = defaultFormatter
    ) -> String {
        guard let plan = entitlement.plan, plan.isSubscription else {
            return "Lifetime unlock — one-time purchase, never expires."
        }
        guard let expiration = entitlement.expirationDate else {
            return "Auto-renews until cancelled."
        }
        let date = formatter.string(from: expiration)
        if expiration <= now {
            return entitlement.isInBillingGracePeriod
                ? "Payment issue — update your payment method to keep Premium."
                : "Expired on \(date)."
        }
        switch entitlement.willAutoRenew {
        case true?: return "Renews on \(date)."
        case false?: return "Cancelled — Premium ends on \(date)."
        case nil: return "Renews or ends on \(date)."
        }
    }

    static let defaultFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
