//
//  FirstExportGuideUITests.swift
//  ThumbnailMakerUITests
//
//  FEATURE-13: the first-export guide is opt-in under UI tests
//  (-UITestFirstExportGuide), so existing suites are unaffected.
//

import XCTest

final class FirstExportGuideUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // These tests assert the compact (phone, portrait) editor. The
        // simulator keeps its last orientation between runs, so pin it the
        // same way ThumbnailMakerUITests resets it in tearDown.
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testExistingUsersAreNotInterrupted() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-DisableDraftPersistence"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["simpleCompactEditorLayout"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["firstExportGuideCard"].exists)
    }

    @MainActor
    func testGuidedJourneyReachesExportStepThenHideAndResumeFromSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-DisableDraftPersistence", "-UITestFirstExportGuide", "-UITestSeedSelectedImage"]
        app.launch()

        let card = app.descendants(matching: .any)["firstExportGuideCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let addVisual = app.descendants(matching: .any)["firstExportGuideStep-addVisual"]
        XCTAssertTrue(addVisual.waitForExistence(timeout: 5))
        XCTAssertEqual(addVisual.value as? String, "Done")

        let done = NSPredicate(format: "value == %@", "Done")
        let current = NSPredicate(format: "value == %@", "Current step")
        let writeTitle = app.descendants(matching: .any)["firstExportGuideStep-writeTitle"]
        XCTAssertEqual(writeTitle.value as? String, "Done")

        // Clearing the seeded title re-opens the step (derived, not scripted).
        let overlayText = app.textViews["Overlay text"]
        XCTAssertTrue(overlayText.waitForExistence(timeout: 5))
        overlayText.tap()
        overlayText.typeKey("a", modifierFlags: .command)
        overlayText.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual((overlayText.value as? String) ?? "", "")
        let cleared = XCTAttachment(screenshot: app.screenshot())
        cleared.name = "guide-title-cleared"
        cleared.lifetime = .keepAlways
        add(cleared)
        app.buttons["overlayTextKeyboardDoneButton"].firstMatch.tap()
        expectation(for: current, evaluatedWith: writeTitle)
        waitForExpectations(timeout: 5)

        // "Edit Title" focuses the real overlay editor.
        let showMe = app.buttons["firstExportGuideShowMeButton"]
        XCTAssertTrue(showMe.waitForExistence(timeout: 5))
        showMe.tap()
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        expectation(for: focused, evaluatedWith: overlayText)
        waitForExpectations(timeout: 5)
        overlayText.typeText("Guide title")
        app.buttons["overlayTextKeyboardDoneButton"].firstMatch.tap()
        expectation(for: done, evaluatedWith: writeTitle)
        waitForExpectations(timeout: 5)

        // "Check Size" runs the real size check.
        app.buttons["firstExportGuideShowMeButton"].tap()
        let readiness = app.descendants(matching: .any)["firstExportGuideStep-checkReadiness"]
        expectation(for: done, evaluatedWith: readiness)
        waitForExpectations(timeout: 15)

        let exportStep = app.descendants(matching: .any)["firstExportGuideStep-export"]
        XCTAssertEqual(exportStep.value as? String, "Current step")
        XCTAssertTrue(app.buttons["firstExportGuideShareButton"].exists)

        // Hide, then resume from Settings at the same step.
        app.buttons["firstExportGuideHideButton"].tap()
        XCTAssertTrue(app.buttons["firstExportGuideResumeButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(card.exists)

        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        // Settings now leads with the app header, subscription, features and
        // support sections, so the Getting Started row sits below the fold of
        // the lazy List and must be scrolled into view.
        let settingsButton = app.buttons["firstExportGuideSettingsButton"]
        for _ in 0..<10 where !(settingsButton.exists && settingsButton.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.descendants(matching: .any)["firstExportGuideStep-export"].value as? String,
            "Current step"
        )

        // Skip hides the guide and leaves the work in place.
        app.buttons["firstExportGuideSkipButton"].tap()
        XCTAssertFalse(card.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["firstExportGuideResumeButton"].exists)
    }
}
