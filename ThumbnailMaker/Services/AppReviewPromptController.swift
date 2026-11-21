//
//  AppReviewPromptController.swift
//  ThumbnailMaker
//
//  GAPS: persists AppReviewPromptPolicy and asks StoreKit for a rating
//  after the 3rd successful export (see the policy for the rules).
//

import StoreKit
import SwiftUI

@MainActor
final class AppReviewPromptController {
    static let shared = AppReviewPromptController()

    static let storageKey = "appReviewPromptState.v1"

    private let defaults: UserDefaults
    private let appVersion: () -> String
    private let isPurchaseRunning: @MainActor () -> Bool
    private let isDisabled: Bool
    private var visiblePaywallCount = 0

    init(
        defaults: UserDefaults = .standard,
        appVersion: @escaping () -> String = AppReviewPromptController.bundleVersion,
        isPurchaseRunning: @escaping @MainActor () -> Bool = {
            let manager = PurchaseManager.shared
            return manager.purchasingPlan != nil || manager.isRestoringPurchases
        },
        isDisabled: Bool = AppReviewPromptController.isAutomationRun(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
    ) {
        self.defaults = defaults
        self.appVersion = appVersion
        self.isPurchaseRunning = isPurchaseRunning
        self.isDisabled = isDisabled
    }

    var state: AppReviewPromptState {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode(AppReviewPromptState.self, from: data) else {
            return AppReviewPromptState()
        }
        return decoded
    }

    var isPurchaseFlowActive: Bool {
        visiblePaywallCount > 0 || isPurchaseRunning()
    }

    /// The paywall reports itself so a rating prompt never covers it.
    func paywallDidAppear() { visiblePaywallCount += 1 }
    func paywallDidDisappear() { visiblePaywallCount = max(0, visiblePaywallCount - 1) }

    /// Records one confirmed export; true when a review should be requested now.
    func recordSuccessfulExport() -> Bool {
        guard !isDisabled else { return false }
        var policy = AppReviewPromptPolicy(state: state)
        let decision = policy.recordSuccessfulExport(
            appVersion: appVersion(),
            isPurchaseFlowActive: isPurchaseFlowActive
        )
        if let data = try? JSONEncoder().encode(policy.state) {
            defaults.set(data, forKey: Self.storageKey)
        }
        return decision == .prompt
    }

    nonisolated static func bundleVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Unit-test hosts and UI-test launches never show the system prompt:
    /// it would cover the UI under test.
    nonisolated static func isAutomationRun(arguments: [String], environment: [String: String]) -> Bool {
        if environment["XCTestConfigurationFilePath"] != nil { return true }
        return arguments.contains { argument in
            argument.hasPrefix("-UITest")
                || argument == "-DisableDraftPersistence"
                || argument == "-DisableReviewPrompt"
        }
    }
}

/// Watches an editor's confirmed-export events and requests a rating when
/// the controller allows it.
private struct AppReviewPromptModifier: ViewModifier {
    let exportEvent: ThumbnailExportEvent?
    @Environment(\.requestReview) private var requestReview

    func body(content: Content) -> some View {
        content.onChange(of: exportEvent?.id) { _, newID in
            guard newID != nil else { return }
            if AppReviewPromptController.shared.recordSuccessfulExport() {
                requestReview()
            }
        }
    }
}

extension View {
    /// GAPS: App Store rating prompt after the 3rd successful export.
    func appReviewPrompt(after exportEvent: ThumbnailExportEvent?) -> some View {
        modifier(AppReviewPromptModifier(exportEvent: exportEvent))
    }
}
