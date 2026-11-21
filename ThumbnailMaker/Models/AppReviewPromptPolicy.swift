//
//  AppReviewPromptPolicy.swift
//  ThumbnailMaker
//
//  GAPS: when to ask for an App Store rating. Pure value logic so the
//  gating is unit-testable; AppReviewPromptController persists it and calls
//  StoreKit's requestReview.
//
//  Rules:
//  - Only confirmed exports count (Photos / Files / completed share).
//  - Ask after the 3rd successful export, never before.
//  - At most once per app version (CFBundleShortVersionString).
//  - Never while a purchase or restore is running or the paywall is up.
//    A blocked export still counts, so the next eligible export asks.
//

import Foundation

struct AppReviewPromptState: Codable, Equatable {
    var successfulExportCount: Int = 0
    /// Version string the prompt was last requested for, if any.
    var lastPromptedVersion: String?
}

enum AppReviewPromptDecision: Equatable {
    case prompt
    case notEnoughExports
    case alreadyPromptedThisVersion
    case purchaseFlowActive
}

struct AppReviewPromptPolicy: Equatable {
    static let requiredExportCount = 3

    var state: AppReviewPromptState

    init(state: AppReviewPromptState = AppReviewPromptState()) {
        self.state = state
    }

    /// What would happen for the NEXT prompt check, without recording anything.
    func decision(appVersion: String, isPurchaseFlowActive: Bool) -> AppReviewPromptDecision {
        if state.successfulExportCount < Self.requiredExportCount {
            return .notEnoughExports
        }
        if state.lastPromptedVersion == appVersion {
            return .alreadyPromptedThisVersion
        }
        if isPurchaseFlowActive {
            return .purchaseFlowActive
        }
        return .prompt
    }

    /// Counts one successful export and says whether to request a review now.
    /// When it returns `.prompt` the version is recorded, so it never repeats
    /// for the same version.
    @discardableResult
    mutating func recordSuccessfulExport(
        appVersion: String,
        isPurchaseFlowActive: Bool
    ) -> AppReviewPromptDecision {
        if state.successfulExportCount < Int.max {
            state.successfulExportCount += 1
        }
        let result = decision(appVersion: appVersion, isPurchaseFlowActive: isPurchaseFlowActive)
        if result == .prompt {
            state.lastPromptedVersion = appVersion
        }
        return result
    }
}
