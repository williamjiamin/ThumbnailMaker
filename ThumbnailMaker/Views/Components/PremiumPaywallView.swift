import StoreKit
import SwiftUI

/// SUB: what the paywall is doing right now. Pure so the copy for each state is unit-tested.
enum PaywallPurchaseStatus: Equatable {
    case idle
    case purchasing(PurchasePlan)
    case pending
    case cancelled
    case purchased(PurchasePlan)
    case notice(String)
    case failed(String)

    static func from(_ error: Error) -> PaywallPurchaseStatus {
        switch error as? PurchaseError {
        case .userCancelled?:
            return .cancelled
        case .pending?:
            return .pending
        case .productNotFound?:
            return .failed("This plan is not available from the App Store right now. Check your connection and try again.")
        case .verificationFailed?:
            return .failed("The App Store could not verify this purchase. Nothing was unlocked; try Restore Purchases.")
        case .purchaseInProgress?:
            return .failed("A purchase is already in progress.")
        case .unknown?:
            return .failed("The purchase did not complete. Please try again.")
        case nil:
            switch PurchaseVerificationFailure.classify(error) {
            case .cancelled:
                return .cancelled
            case .networkUnavailable:
                return .failed("Could not connect to the App Store. Check your connection and try again.")
            case .unverifiedTransaction, .storeUnavailable:
                return .failed("The purchase did not complete. Please try again.")
            }
        }
    }

    var message: String? {
        switch self {
        case .idle, .purchasing:
            return nil
        case .pending:
            return "Your purchase is waiting for approval (for example Ask to Buy). Premium unlocks automatically once it is approved."
        case .cancelled:
            return "Purchase cancelled. Nothing was charged."
        case .purchased(let plan):
            return plan.isSubscription
                ? "Premium is active. Your \(plan.title.lowercased()) plan renews automatically until you cancel."
                : "Premium is unlocked for life. Thank you!"
        case .notice(let message), .failed(let message):
            return message
        }
    }

    var isPurchasing: Bool {
        if case .purchasing = self { return true }
        return false
    }
}

enum PaywallLinks {
    /// Apple's standard Licensed Application End User License Agreement (Terms of Use).
    static let standardEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

/// SUB: redesigned paywall with weekly, monthly and lifetime plans.
struct PremiumPaywallView: View {
    enum Presentation {
        /// Presented as a sheet: shows a close button and dismisses after a purchase.
        case sheet
        /// Embedded in a tab (Premium Maker when locked).
        case embedded
    }

    var presentation: Presentation = .sheet
    var headline: String = "Unlock Premium"

    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var selectedPlan: PurchasePlan = .lifetime
    @State private var status: PaywallPurchaseStatus = .idle
    @State private var legalDocument: LegalDocument?

    private struct LegalDocument: Identifiable {
        let title: String
        let name: String
        var id: String { name }
    }

    var body: some View {
        Group {
            switch presentation {
            case .sheet:
                NavigationStack {
                    content
                        .navigationTitle("Premium")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Not Now") { dismiss() }
                                    .accessibilityIdentifier("paywall.close")
                            }
                        }
                }
            case .embedded:
                content
            }
        }
        .task { await purchaseManager.loadProductsIfNeeded() }
        // GAPS: a rating prompt never covers the paywall.
        .onAppear { AppReviewPromptController.shared.paywallDidAppear() }
        .onDisappear { AppReviewPromptController.shared.paywallDidDisappear() }
        .onChange(of: purchaseManager.isPremium) { _, isPremium in
            if isPremium && presentation == .sheet && !status.isPurchasing { dismiss() }
        }
        .sheet(item: $legalDocument) { document in
            NavigationStack {
                LegalDocumentView(title: document.title, documentName: document.name)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { legalDocument = nil }
                        }
                    }
            }
        }
        .alert(
            "Purchase Status",
            isPresented: Binding(
                get: { status.message != nil && !isSuccessInSheet },
                set: { if !$0 { status = .idle } }
            )
        ) {
            Button("OK", role: .cancel) { status = .idle }
        } message: {
            Text(status.message ?? "")
        }
    }

    private var isSuccessInSheet: Bool {
        if case .purchased = status, presentation == .sheet { return true }
        return false
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                features
                plans
                purchaseButton
                disclosure
                links
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("paywall")
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "crown.fill")
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(colors: [.orange, .pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .accessibilityHidden(true)
            Text(headline)
                .font(.largeTitle.bold())
            Text("Pro tools for thumbnails that get clicked. Choose a plan that fits how often you publish.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Keep this list in sync with what is actually gated (PremiumMakerViewModel free
            // tries, CustomFont.isPremium, DebugSettings YouTube quotas). App Review rejects
            // paywalls that promise features the free tier already has.
            feature("wand.and.stars", "Unlimited Premium Maker", "Profile photo overlay, batch generation and advanced layer controls. Free includes 3 tries.")
            feature("textformat", "All premium fonts", "Every display font, including CJK and handwriting styles.")
            feature("play.rectangle", "500 YouTube imports a day", "Pull any video's thumbnail and title to start from. Free includes 3 a day.")
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.purple)
                .frame(minWidth: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var plans: some View {
        VStack(spacing: 10) {
            if purchaseManager.productLoadState == .failed, screenshotReferencePrice(for: selectedPlan) == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Plans could not be loaded from the App Store. Check your connection and try again.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Try Again") {
                        Task { await purchaseManager.loadProductsIfNeeded() }
                    }
                    .font(.footnote.bold())
                    .accessibilityIdentifier("paywall.retryProducts")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(PurchasePlan.displayOrder) { plan in
                planRow(plan)
            }
        }
    }

    private func planRow(_ plan: PurchasePlan) -> some View {
        let product = purchaseManager.product(for: plan)
        let selected = plan == selectedPlan
        let isCurrent = purchaseManager.activePlan == plan
        return Button {
            selectedPlan = plan
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.purple : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(plan.title).font(.headline)
                        if plan == .lifetime {
                            badge("Best Value", color: .orange)
                        }
                        if isCurrent {
                            badge("Current", color: .green)
                        }
                    }
                    Text(plan.billingNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let displayPrice = product?.displayPrice ?? screenshotReferencePrice(for: plan) {
                    Text(plan.priceLine(displayPrice: displayPrice))
                        .font(.subheadline.bold())
                        .multilineTextAlignment(.trailing)
                } else if purchaseManager.productLoadState == .failed {
                    Text("Unavailable").font(.caption).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .padding(14)
            .contentShape(Rectangle())
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Color.purple : Color(uiColor: .separator), lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("paywall.plan.\(plan.title.lowercased())")
    }

    /// SHOTS: App Store screenshot automation runs without a StoreKit
    /// configuration, so `-UITestPaywallReferencePrices` (DEBUG only) shows the
    /// reference prices instead of a spinner. Purchasing still needs a product.
    private func screenshotReferencePrice(for plan: PurchasePlan) -> String? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestPaywallReferencePrices") {
            return plan.referencePrice
        }
        #endif
        return nil
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var purchaseButton: some View {
        let product = purchaseManager.product(for: selectedPlan)
        let alreadyOwned = purchaseManager.activePlan == selectedPlan
            || purchaseManager.activePlan == .lifetime
        return Button {
            Task { await buy(selectedPlan) }
        } label: {
            HStack {
                if status.isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Text(alreadyOwned ? "Premium Active" : selectedPlan.purchaseButtonTitle)
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [.orange, .pink, .purple], startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .foregroundStyle(.white)
            .opacity((product == nil && screenshotReferencePrice(for: selectedPlan) == nil) || alreadyOwned ? 0.5 : 1)
        }
        .disabled(product == nil || status.isPurchasing || alreadyOwned)
        .accessibilityIdentifier("paywall.purchase")
    }

    /// Renewal terms required by App Review, stated on the screen itself.
    private var disclosure: some View {
        VStack(alignment: .leading, spacing: 6) {
            if selectedPlan.isSubscription {
                Text("Weekly and monthly plans are auto-renewable subscriptions. Payment is charged to your Apple Account at confirmation. The subscription auto-renews until cancelled, unless you cancel at least 24 hours before the end of the current period; your account is charged for renewal within 24 hours before the period ends. Manage or cancel any time in Settings > Apple Account > Subscriptions.")
            } else {
                Text("Lifetime is a one-time purchase, not a subscription. You pay once and keep Premium on every device signed in to the same Apple Account.")
                if purchaseManager.activePlan?.isSubscription == true {
                    // StoreKit does not cancel an existing subscription when a lifetime
                    // unlock is bought, so say so rather than let the user keep paying.
                    Text("You currently have an active subscription. Buying Lifetime does not cancel it — cancel it in Manage Subscription so you aren't charged again.")
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("paywall.cancelSubscriptionNotice")
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("paywall.disclosure")
    }

    private var links: some View {
        VStack(spacing: 12) {
            Button {
                Task { await restore() }
            } label: {
                if purchaseManager.isRestoringPurchases {
                    ProgressView()
                } else {
                    Text("Restore Purchases")
                }
            }
            .disabled(purchaseManager.isRestoringPurchases)
            .accessibilityIdentifier("paywall.restore")

            HStack(spacing: 16) {
                Button("Terms of Use (EULA)") { openURL(PaywallLinks.standardEULA) }
                    .accessibilityIdentifier("paywall.terms")
                Button("Terms of Service") {
                    legalDocument = LegalDocument(title: "Terms of Service", name: "terms_of_service")
                }
                Button("Privacy Policy") {
                    legalDocument = LegalDocument(title: "Privacy Policy", name: "privacy_policy")
                }
                .accessibilityIdentifier("paywall.privacy")
            }
            .font(.footnote)
        }
        .frame(maxWidth: .infinity)
        .font(.subheadline)
    }

    // MARK: Actions

    private func buy(_ plan: PurchasePlan) async {
        status = .purchasing(plan)
        do {
            try await purchaseManager.purchase(plan: plan)
            status = .purchased(plan)
            if presentation == .sheet { dismiss() }
        } catch {
            status = .from(error)
        }
    }

    private func restore() async {
        // Uses the non-broadcasting variant so a presenting Settings screen does not also alert.
        let result = await purchaseManager.restorePurchasesResult()
        switch result {
        case .restored:
            status = .notice(result.message ?? "Purchases restored successfully.")
        case .failed:
            status = .failed(result.message ?? "Failed to restore purchases. Please try again.")
        case .noPurchases:
            status = .notice(result.message ?? "No active purchases were found.")
        case .idle, .restoring:
            break
        }
    }
}

/// Small "3 premium tries left" meter matching the 1.1.0 Settings screenshot.
struct PremiumTriesMeter: View {
    let remaining: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: remaining > 0 ? "gift.fill" : "gift")
                .foregroundStyle(remaining > 0 ? Color.purple : Color.secondary)
            Text(PremiumTriesMeter.label(remaining: remaining))
                .font(.subheadline)
                .foregroundStyle(remaining > 0 ? Color.purple : Color.secondary)
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                ForEach(0..<max(total, 0), id: \.self) { index in
                    Capsule()
                        .fill(index < remaining ? Color.purple : Color.secondary.opacity(0.25))
                        .frame(width: 14, height: 6)
                }
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.premiumTries")
    }

    static func label(remaining: Int) -> String {
        switch remaining {
        case ..<1: return "No premium tries left"
        case 1: return "1 premium try left"
        default: return "\(remaining) premium tries left"
        }
    }
}
