//
//  AppStoreScreenshotTests.swift
//  ThumbnailMakerUITests
//
//  SHOTS (1.3.0): App Store screenshots of the current product, captured on a
//  6.9" iPhone and a 13" iPad. Every design shown is seeded from editor layers
//  (gradient, text, callouts, emoji) through DEBUG launch arguments, so no
//  photos or third-party imagery appear. The regular UI suite skips this
//  class; run it through scripts/capture-screenshots.sh.
//
//  Keep the attachment names in sync with required_names in
//  scripts/capture-screenshots.sh.
//

import XCTest
import UIKit

final class AppStoreScreenshotTests: XCTestCase {

    private static let showcaseArguments = [
        "-UITestSeedShowcaseDesign",
        "-DisableDraftPersistence"
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testIPhoneAppStoreScreenshots() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("Requires an iPhone simulator.")
        }
        try captureProductTour(device: "iphone")
    }

    @MainActor
    func testIPadAppStoreScreenshots() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("Requires an iPad simulator.")
        }
        try captureProductTour(device: "ipad")
    }

    // MARK: - Tour

    @MainActor
    private func captureProductTour(device: String) throws {
        // 1-2: Create home and the Quick Create template step.
        let homeApp = launchApp(Self.showcaseArguments)
        let quickCreate = homeApp.buttons["quickCreateButton"]
        XCTAssertTrue(quickCreate.waitForExistence(timeout: 10))
        XCTAssertTrue(homeApp.buttons["startFromScratchButton"].exists)
        settle()
        attachScreenshot(named: "01-\(device)-create-home")

        tap(quickCreate)
        XCTAssertTrue(homeApp.navigationBars["Quick Create"].waitForExistence(timeout: 5))
        XCTAssertTrue(homeApp.descendants(matching: .any)["quickCreateStepIndicator"].waitForExistence(timeout: 5))
        let boldCenter = homeApp.buttons["quickCreateTemplate-quick-bold-center"]
        XCTAssertTrue(boldCenter.waitForExistence(timeout: 5))
        tap(boldCenter)
        settle()
        attachScreenshot(named: "02-\(device)-quick-create-templates")
        homeApp.terminate()

        // 3-5: the editor with a finished design, A/B/C compare, styles.
        let app = launchApp(["-UITestSkipHome"] + Self.showcaseArguments)
        XCTAssertTrue(app.navigationBars["Simple Maker"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["in 5 minutes"].waitForExistence(timeout: 5)
                      || app.descendants(matching: .any)["layerSelectionStrip"].waitForExistence(timeout: 5))
        settle()
        attachScreenshot(named: "03-\(device)-editor-design")

        let compare = revealVariantsControl("variantCompareButton", in: app)
        tap(compare)
        XCTAssertTrue(app.navigationBars["Compare Variants"].waitForExistence(timeout: 5))
        for slot in ["a", "b", "c"] {
            XCTAssertTrue(
                app.descendants(matching: .any)["variantComparePane_\(slot)"].waitForExistence(timeout: 5),
                "Compare sheet should show a seeded pane for every variant"
            )
        }
        settle()
        attachScreenshot(named: "04-\(device)-variants-compare")
        dismissSheet(in: app)
        let compareBar = app.navigationBars["Compare Variants"]
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: compareBar)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed)

        if device == "ipad" {
            try captureTextStyles(in: app, device: device)
        } else {
            try captureCallouts(in: app, device: device)
        }
        app.terminate()

        // 6: the paywall with weekly, monthly and lifetime plans.
        let paywallApp = launchApp(["-UITestSkipHome", "-UITestPaywallReferencePrices"] + Self.showcaseArguments)
        // iPhone shows a bottom tab bar; iPadOS 18 shows a top tab bar whose
        // Settings tab is identified as "settingsTab".
        let settingsTab = paywallApp.buttons.matching(
            NSPredicate(format: "identifier == %@", "settingsTab")
        ).firstMatch
        let phoneSettingsTab = paywallApp.tabBars.buttons["Settings"]
        XCTAssertTrue(phoneSettingsTab.waitForExistence(timeout: 10) || settingsTab.waitForExistence(timeout: 5))
        tap(phoneSettingsTab.exists ? phoneSettingsTab : settingsTab)
        let upgrade = paywallApp.buttons["settings.upgrade"]
        scrollToHittable(upgrade, in: paywallApp, maxSwipes: 8)
        XCTAssertTrue(upgrade.waitForExistence(timeout: 5))
        settle() // a tap during scroll deceleration only stops the scroll
        let lifetimePlan = paywallApp.buttons["paywall.plan.lifetime"]
        for _ in 0..<3 where !lifetimePlan.exists {
            tap(upgrade)
            _ = lifetimePlan.waitForExistence(timeout: 4)
        }
        XCTAssertTrue(lifetimePlan.waitForExistence(timeout: 5))
        for plan in ["weekly", "monthly", "lifetime"] {
            XCTAssertTrue(
                paywallApp.buttons["paywall.plan.\(plan)"].waitForExistence(timeout: 5),
                "Paywall should list every plan"
            )
        }
        XCTAssertTrue(paywallApp.staticTexts["$9.99"].waitForExistence(timeout: 10))
        if device == "ipad" {
            // The iPad form sheet is shorter than the paywall: scroll so all
            // three plans and the purchase button are in frame.
            settle()
            let weekly = paywallApp.buttons["paywall.plan.weekly"]
            let start = weekly.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -240)))
            XCTAssertTrue(paywallApp.buttons["paywall.purchase"].waitForExistence(timeout: 5))
        }
        settle()
        attachScreenshot(named: "06-\(device)-premium-plans")
        paywallApp.terminate()
    }

    /// iPhone: the "Arrows, badges & callouts" menu opened over the design.
    @MainActor
    private func captureCallouts(in app: XCUIApplication, device: String) throws {
        let canvasTop = app.navigationBars["Simple Maker"]
        for _ in 0..<8 where !canvasTop.isHittable {
            app.swipeDown()
        }
        let shapeMenu = app.buttons["quickAddShape"]
        XCTAssertTrue(shapeMenu.waitForExistence(timeout: 5))
        // Menu items may surface by label rather than identifier.
        let burst = app.buttons.matching(
            NSPredicate(format: "identifier == %@ OR label == %@", "addCalloutPreset-burstBadge", "Burst Badge")
        ).firstMatch
        tap(shapeMenu)
        if !burst.waitForExistence(timeout: 3) {
            shapeMenu.press(forDuration: 0.8)
        }
        XCTAssertTrue(burst.waitForExistence(timeout: 5))
        settle()
        attachScreenshot(named: "05-\(device)-callouts")
    }

    /// iPad: the canvas stays in the left pane while the right pane shows the
    /// text style presets for the selected subtitle layer.
    @MainActor
    private func captureTextStyles(in app: XCUIApplication, device: String) throws {
        let subtitleChip = app.buttons["layerSelectionTextLayer1"]
        if subtitleChip.waitForExistence(timeout: 3) {
            tap(subtitleChip)
        }
        let presetRow = app.descendants(matching: .any)["textStylePresetRow"]
        scrollToHittable(presetRow, in: app, maxSwipes: 10, from: app.descendants(matching: .any)["layerSelectionStrip"])
        XCTAssertTrue(presetRow.waitForExistence(timeout: 5))
        settle()
        attachScreenshot(named: "05-\(device)-text-styles")
    }

    // MARK: - Helpers

    private func launchApp(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    /// Returns a control from the Variants & Sizes section, expanding the
    /// compact (phone) disclosure first when the section is collapsed.
    private func revealVariantsControl(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let control = app.buttons[identifier]
        let toggle = app.buttons["compactVariantsSectionToggle"]
        if !control.exists, toggle.waitForExistence(timeout: 5) {
            scrollToHittable(toggle, in: app, maxSwipes: 10)
            tap(toggle)
        }
        XCTAssertTrue(control.waitForExistence(timeout: 5), "Variants control should exist")
        scrollToHittable(control, in: app, maxSwipes: 10)
        return control
    }

    private func dismissSheet(in app: XCUIApplication) {
        for label in ["Done", "Close"] {
            let button = app.navigationBars.buttons[label]
            if button.exists {
                button.tap()
                return
            }
        }
        app.swipeDown(velocity: .fast)
    }

    private func attachScreenshot(named name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// Lets animations, fonts and async previews finish before a capture.
    private func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
    }

    private func scrollToHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int,
        from scrollAnchor: XCUIElement? = nil
    ) {
        for _ in 0..<maxSwipes where !isOnScreen(element, in: app) {
            if let scrollAnchor, scrollAnchor.exists {
                scrollAnchor.swipeUp()
            } else {
                app.swipeUp()
            }
        }
    }

    /// Hittable and fully clear of the tab bar, so a tap lands.
    private func isOnScreen(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let tabBar = app.tabBars.firstMatch
        let bottom = tabBar.exists ? tabBar.frame.minY : app.frame.maxY
        return element.frame.maxY <= bottom
    }

    private func tap(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }
}
