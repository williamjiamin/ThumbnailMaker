//
//  GapsClosureTests.swift
//  ThumbnailMakerTests
//
//  GAPS: App Store rating gating, main-title auto-fit persistence and
//  sizing, Settings support links, and the Projects tab editor filter.
//

import Foundation
import SwiftUI
import Testing
import UIKit
@testable import ThumbnailMaker

// MARK: - Rating prompt policy

struct AppReviewPromptPolicyTests {
    @Test func doesNotPromptBeforeTheThirdExport() {
        var policy = AppReviewPromptPolicy()
        let result1 = policy.recordSuccessfulExport(appVersion: "1.3.0", isPurchaseFlowActive: false)
        #expect(result1 == .notEnoughExports)
        let result2 = policy.recordSuccessfulExport(appVersion: "1.3.0", isPurchaseFlowActive: false)
        #expect(result2 == .notEnoughExports)
        #expect(policy.state.successfulExportCount == 2)
        #expect(policy.state.lastPromptedVersion == nil)
    }

    @Test func promptsOnTheThirdExportAndRecordsTheVersion() {
        var policy = AppReviewPromptPolicy()
        policy.recordSuccessfulExport(appVersion: "1.3.0", isPurchaseFlowActive: false)
        policy.recordSuccessfulExport(appVersion: "1.3.0", isPurchaseFlowActive: false)
        let third = policy.recordSuccessfulExport(appVersion: "1.3.0", isPurchaseFlowActive: false)
        #expect(third == .prompt)
        #expect(policy.state.lastPromptedVersion == "1.3.0")
        #expect(policy.state.successfulExportCount == 3)
    }

    @Test func promptsAtMostOncePerVersion() {
        var policy = AppReviewPromptPolicy(state: AppReviewPromptState(successfulExportCount: 3, lastPromptedVersion: "1.3.0"))
        let result3 = policy.recordSuccessfulExport(appVersion: "1.3.0", isPurchaseFlowActive: false)
        #expect(result3 == .alreadyPromptedThisVersion)
        let result4 = policy.recordSuccessfulExport(appVersion: "1.3.0", isPurchaseFlowActive: false)
        #expect(result4 == .alreadyPromptedThisVersion)
        #expect(policy.state.lastPromptedVersion == "1.3.0")
    }

    @Test func aNewVersionMayPromptAgain() {
        var policy = AppReviewPromptPolicy(state: AppReviewPromptState(successfulExportCount: 7, lastPromptedVersion: "1.2.0"))
        let result5 = policy.recordSuccessfulExport(appVersion: "1.3.0", isPurchaseFlowActive: false)
        #expect(result5 == .prompt)
        #expect(policy.state.lastPromptedVersion == "1.3.0")
    }

    @Test func neverPromptsDuringAPurchaseAndRetriesOnTheNextExport() {
        var policy = AppReviewPromptPolicy(state: AppReviewPromptState(successfulExportCount: 2))
        let blocked = policy.recordSuccessfulExport(appVersion: "1.3.0", isPurchaseFlowActive: true)
        #expect(blocked == .purchaseFlowActive)
        #expect(policy.state.lastPromptedVersion == nil)
        #expect(policy.state.successfulExportCount == 3)
        let result6 = policy.recordSuccessfulExport(appVersion: "1.3.0", isPurchaseFlowActive: false)
        #expect(result6 == .prompt)
    }

    @Test func decisionDoesNotMutate() {
        let policy = AppReviewPromptPolicy(state: AppReviewPromptState(successfulExportCount: 3))
        #expect(policy.decision(appVersion: "1.3.0", isPurchaseFlowActive: false) == .prompt)
        #expect(policy.state.lastPromptedVersion == nil)
        #expect(policy.state.successfulExportCount == 3)
    }

    @Test func stateRoundTripsThroughJSON() throws {
        let state = AppReviewPromptState(successfulExportCount: 4, lastPromptedVersion: "1.3.0")
        let decoded = try JSONDecoder().decode(AppReviewPromptState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
    }
}

@MainActor
struct AppReviewPromptControllerTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "GapsReviewPrompt.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func requestsReviewOnTheThirdExportOnlyAndPersists() {
        let defaults = makeDefaults()
        let controller = AppReviewPromptController(
            defaults: defaults,
            appVersion: { "1.3.0" },
            isPurchaseRunning: { false },
            isDisabled: false
        )
        let first = controller.recordSuccessfulExport()
        let second = controller.recordSuccessfulExport()
        let third = controller.recordSuccessfulExport()
        let fourth = controller.recordSuccessfulExport()
        #expect(!first)
        #expect(!second)
        #expect(third)
        #expect(!fourth)

        let reloaded = AppReviewPromptController(
            defaults: defaults,
            appVersion: { "1.3.0" },
            isPurchaseRunning: { false },
            isDisabled: false
        )
        #expect(reloaded.state.successfulExportCount == 4)
        #expect(reloaded.state.lastPromptedVersion == "1.3.0")
        let fifth = reloaded.recordSuccessfulExport()
        #expect(!fifth)
    }

    @Test func runningPurchaseBlocksThePrompt() {
        var purchasing = true
        let controller = AppReviewPromptController(
            defaults: makeDefaults(),
            appVersion: { "1.3.0" },
            isPurchaseRunning: { purchasing },
            isDisabled: false
        )
        _ = controller.recordSuccessfulExport()
        _ = controller.recordSuccessfulExport()
        let duringPurchase = controller.recordSuccessfulExport()
        #expect(!duringPurchase)
        purchasing = false
        let afterPurchase = controller.recordSuccessfulExport()
        #expect(afterPurchase)
    }

    @Test func visiblePaywallBlocksThePrompt() {
        let controller = AppReviewPromptController(
            defaults: makeDefaults(),
            appVersion: { "1.3.0" },
            isPurchaseRunning: { false },
            isDisabled: false
        )
        _ = controller.recordSuccessfulExport()
        _ = controller.recordSuccessfulExport()
        controller.paywallDidAppear()
        #expect(controller.isPurchaseFlowActive)
        let whilePaywall = controller.recordSuccessfulExport()
        #expect(!whilePaywall)
        controller.paywallDidDisappear()
        controller.paywallDidDisappear() // extra disappear never goes negative
        #expect(!controller.isPurchaseFlowActive)
        let afterPaywall = controller.recordSuccessfulExport()
        #expect(afterPaywall)
    }

    @Test func disabledControllerNeverPromptsOrRecords() {
        let defaults = makeDefaults()
        let controller = AppReviewPromptController(
            defaults: defaults,
            appVersion: { "1.3.0" },
            isPurchaseRunning: { false },
            isDisabled: true
        )
        for _ in 0..<5 {
            let result = controller.recordSuccessfulExport()
            #expect(!result)
        }
        #expect(controller.state.successfulExportCount == 0)
    }

    @Test func automationRunsAreDetected() {
        #expect(AppReviewPromptController.isAutomationRun(arguments: ["-UITestSkipHome"], environment: [:]))
        #expect(AppReviewPromptController.isAutomationRun(arguments: ["-DisableDraftPersistence"], environment: [:]))
        #expect(AppReviewPromptController.isAutomationRun(arguments: [], environment: ["XCTestConfigurationFilePath": "/x"]))
        #expect(!AppReviewPromptController.isAutomationRun(arguments: ["/path/to/app"], environment: [:]))
    }
}

// MARK: - Main-title auto-fit

@MainActor
struct OverlayAutoFitTests {
    private let canvas = CGSize(width: 1024, height: 576)
    private let longTitle = "THIS IS A VERY LONG TITLE THAT DEFINITELY DOES NOT FIT ON THE CANVAS AT THIS HUGE SIZE EVER"

    @Test func configurationsDefaultToOff() {
        #expect(!SimpleMakerConfigurationModel().overlayAutoFit)
        #expect(!PremiumMakerConfigurationModel().overlayAutoFit)
        #expect(ThumbnailDocumentText().autoFit == nil)
    }

    @Test func offIsOmittedFromJSONSoOldDocumentsAreUnchanged() throws {
        let json = try #require(String(data: try JSONEncoder().encode(ThumbnailDocumentText(value: "Hi")), encoding: .utf8))
        #expect(!json.contains("autoFit"))
        let explicitFalse = ThumbnailDocumentText(value: "Hi", autoFit: false)
        #expect(explicitFalse.autoFit == nil)
    }

    @Test func documentTextDecodesWithoutTheKey() throws {
        let data = try JSONEncoder().encode(ThumbnailDocumentText(value: "Old"))
        let decoded = try JSONDecoder().decode(ThumbnailDocumentText.self, from: data)
        #expect(decoded.autoFit == nil)
        #expect(decoded.value == "Old")
    }

    @Test func simpleConfigurationRoundTripsThroughTheDocument() throws {
        var configuration = SimpleMakerConfigurationModel()
        configuration.overlayText = "Title"
        configuration.overlayAutoFit = true
        let document = configuration.document
        #expect(document.text.autoFit == true)

        let decoded = try JSONDecoder().decode(ThumbnailDocument.self, from: JSONEncoder().encode(document))
        #expect(decoded.text.autoFit == true)
        #expect(decoded.makeSimpleConfiguration().overlayAutoFit)
    }

    @Test func premiumConfigurationRoundTripsThroughTheDocument() {
        var configuration = PremiumMakerConfigurationModel()
        configuration.overlayText = "Title"
        configuration.overlayAutoFit = true
        let document = configuration.document
        #expect(document.text.autoFit == true)
        #expect(document.makePremiumConfiguration().overlayAutoFit)
        // Switching editors keeps the flag (shared document text).
        #expect(document.makeSimpleConfiguration().overlayAutoFit)

        configuration.overlayAutoFit = false
        #expect(configuration.document.text.autoFit == nil)
    }

    @Test func withoutAutoFitTheRequestedSizeIsUsed() {
        let size = ThumbnailTextAutoFit.overlayFontSize(
            text: longTitle,
            font: .goNoto,
            requested: 190,
            style: nil,
            autoFit: false,
            canvasSize: canvas
        )
        #expect(size == 190)
    }

    @Test func autoFitShrinksALongTitleWithinTheFloor() {
        let size = ThumbnailTextAutoFit.overlayFontSize(
            text: longTitle,
            font: .goNoto,
            requested: 190,
            style: nil,
            autoFit: true,
            canvasSize: canvas
        )
        #expect(size < 190)
        #expect(size >= 190 * ThumbnailTextAutoFit.minimumScale)
    }

    @Test func autoFitKeepsAShortTitleAtItsSize() {
        let size = ThumbnailTextAutoFit.overlayFontSize(
            text: "Hi",
            font: .goNoto,
            requested: 80,
            style: nil,
            autoFit: true,
            canvasSize: canvas
        )
        #expect(size == 80)
    }

    @Test func autoFitScalesWithTheCanvas() {
        let small = ThumbnailTextAutoFit.overlayFontSize(
            text: longTitle,
            font: .goNoto,
            requested: 190,
            style: nil,
            autoFit: true,
            canvasSize: canvas
        )
        let large = ThumbnailTextAutoFit.overlayFontSize(
            text: longTitle,
            font: .goNoto,
            requested: 380,
            style: nil,
            autoFit: true,
            canvasSize: CGSize(width: canvas.width * 2, height: canvas.height * 2)
        )
        let ratio = large / small
        #expect(abs(ratio - 2) < 0.15)
    }

    @Test func invalidRequestedSizesAreSafe() {
        let zero = ThumbnailTextAutoFit.overlayFontSize(
            text: longTitle, font: .goNoto, requested: 0, style: nil, autoFit: true, canvasSize: canvas
        )
        let infinite = ThumbnailTextAutoFit.overlayFontSize(
            text: longTitle, font: .goNoto, requested: .infinity, style: nil, autoFit: true, canvasSize: canvas
        )
        #expect(zero >= 0.3)
        #expect(infinite.isFinite)
    }
}

// MARK: - Settings + Projects tab

struct SettingsSupportLinkTests {
    @Test func writeReviewLinkTargetsThisApp() {
        let url = AppSupportLinks.writeReview.absoluteString
        #expect(url == "https://apps.apple.com/app/id6738887943?action=write-review")
    }

    @Test func supportSiteIsTheGitHubPagesSite() {
        #expect(AppSupportLinks.supportSite.absoluteString == "https://williamjiamin.github.io/ThumbnailMaker/")
    }

    @Test func featureListMatchesTheOneOneZeroSettings() {
        #expect(SettingsFeature.all.count == 5)
        #expect(SettingsFeature.all.first?.title == "Multiple aspect ratios for every platform")
        #expect(Set(SettingsFeature.all.map(\.id)).count == SettingsFeature.all.count)
    }
}

struct ProjectsTabEditorFilterTests {
    @Test func eachFilterMapsToItsEditor() {
        #expect(ProjectsTabEditorFilter.simple.editorMode == .simple)
        #expect(ProjectsTabEditorFilter.premium.editorMode == .premium)
        #expect(ProjectsTabEditorFilter.simple.createStage == .simpleEditor)
        #expect(ProjectsTabEditorFilter.premium.createStage == .premiumEditor)
        #expect(ProjectsTabEditorFilter.allCases.map(\.title) == ["Simple", "Premium"])
    }
}
