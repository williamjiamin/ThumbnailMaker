//
//  NewFeatureSmokeUITests.swift
//  ThumbnailMakerUITests
//
//  APP-07 / APP-08: opens each major wave 2-4 entry point on a phone and runs
//  a full accessibility audit (no exclusions) on the screen it shows.
//

import XCTest

final class NewFeatureSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: Projects (FEATURE-01)

    @MainActor
    func testProjectsSheetOpensAndPassesAudit() throws {
        // The project library only exists when persistence is on, so this one
        // test uses the isolated, temporary UI-test library instead of
        // -DisableDraftPersistence.
        let app = launch(["-UITestSeedProjectLibrary"])

        let projectsButton = app.buttons["projectsButton"]
        XCTAssertTrue(projectsButton.waitForExistence(timeout: 10))
        projectsButton.tap()

        XCTAssertTrue(app.navigationBars["Projects"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["newProjectButton"].waitForExistence(timeout: 5))
        attachScreenshot(app, "smoke-projects-sheet")
        try audit(app)
    }

    // MARK: Variants, compare, export queue, series (FEATURE-02 / 10 / 15)

    @MainActor
    func testVariantBarAndCompareSheetPassAudit() throws {
        let app = launch(["-DisableDraftPersistence", "-UITestSeedSelectedImage"])

        let duplicate = revealVariantsControl("variantDuplicateButton", in: app)
        tap(duplicate)

        let chipB = app.buttons["variantChip_b"]
        XCTAssertTrue(chipB.waitForExistence(timeout: 5))
        XCTAssertEqual(chipB.value as? String, "Editing", "The new variant becomes the one being edited")
        XCTAssertTrue(chipB.isSelected)
        XCTAssertFalse(app.buttons["variantChip_a"].isSelected)
        try audit(app)

        let compare = app.buttons["variantCompareButton"]
        XCTAssertTrue(compare.isEnabled)
        tap(compare)
        XCTAssertTrue(app.navigationBars["Compare Variants"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["variantComparePane_a"].waitForExistence(timeout: 5))
        attachScreenshot(app, "smoke-variant-compare")
        try audit(app)
    }

    @MainActor
    func testExportAllQueuePassesAudit() throws {
        let app = launch(["-DisableDraftPersistence", "-UITestSeedSelectedImage"])

        tap(revealVariantsControl("variantExportAllButton", in: app))
        XCTAssertTrue(app.descendants(matching: .any)["exportQueueSheet"].waitForExistence(timeout: 5))
        attachScreenshot(app, "smoke-export-queue")
        try audit(app)
    }

    @MainActor
    func testSeriesSheetPassesAudit() throws {
        let app = launch(["-DisableDraftPersistence", "-UITestSeedSelectedImage"])

        tap(revealVariantsControl("seriesButton", in: app))
        XCTAssertTrue(app.descendants(matching: .any)["seriesSheet"].waitForExistence(timeout: 5))
        attachScreenshot(app, "smoke-series-sheet")
        try audit(app)
    }

    // MARK: Templates (FEATURE-05)

    @MainActor
    func testTemplateGalleryAndSaveAsTemplatePassAudit() throws {
        let app = launch(["-DisableDraftPersistence", "-UITestSeedSelectedImage"])

        let templatesButton = app.buttons["templatesButton"]
        XCTAssertTrue(templatesButton.waitForExistence(timeout: 5))
        templatesButton.tap()
        XCTAssertTrue(app.navigationBars["Templates"].waitForExistence(timeout: 5))
        try audit(app)

        let saveAsTemplate = app.buttons["saveAsTemplateButton"]
        XCTAssertTrue(saveAsTemplate.waitForExistence(timeout: 5))
        saveAsTemplate.tap()
        XCTAssertTrue(app.navigationBars["Save as Template"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["saveTemplateNameField"].waitForExistence(timeout: 5))
        attachScreenshot(app, "smoke-save-as-template")
        try audit(app)
    }

    // MARK: Arrange (FEATURE-07)

    @MainActor
    func testArrangePanelExpandsAndPassesAudit() throws {
        let app = launch(["-DisableDraftPersistence", "-UITestSeedImageLayer"])

        let toggle = app.buttons["arrangePanelToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "Collapsed")
        scrollToHittable(toggle, in: app)
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "Expanded")

        let alignButton = app.buttons["arrangeGroupButton"]
        XCTAssertTrue(alignButton.waitForExistence(timeout: 5))
        scrollToHittable(alignButton, in: app)
        attachScreenshot(app, "smoke-arrange-panel")
        try audit(app)
    }

    // MARK: Adjustments (FEATURE-14) and cutout refinement (FEATURE-11)

    @MainActor
    func testAdjustmentsPanelPassesAudit() throws {
        let app = launch(["-DisableDraftPersistence", "-UITestSeedSelectedImage"])

        let adjustments = app.buttons["adjustmentsButton"]
        XCTAssertTrue(adjustments.waitForExistence(timeout: 5))
        XCTAssertTrue(adjustments.isEnabled)
        adjustments.tap()
        XCTAssertTrue(app.descendants(matching: .any)["adjustmentsPanel"].waitForExistence(timeout: 5))
        attachScreenshot(app, "smoke-adjustments")
        try audit(app)
    }

    @MainActor
    func testRefineCutoutSheetPassesAudit() throws {
        let app = launch(["-DisableDraftPersistence", "-UITestSeedSelectedImage"])

        let refine = app.buttons["refineCutoutButton"]
        for _ in 0..<8 where !refine.exists || !refine.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(refine.waitForExistence(timeout: 5))
        XCTAssertTrue(refine.isHittable)
        refine.tap()

        XCTAssertTrue(app.buttons["cutoutCancelButton"].waitForExistence(timeout: 10))
        attachScreenshot(app, "smoke-refine-cutout")
        try audit(app)
    }

    // MARK: Export presets (APP-07)

    @MainActor
    func testExportPresetRowsExposeSelection() throws {
        let app = launch(["-DisableDraftPersistence"])

        let exportButton = app.buttons["exportSettingsButton"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        scrollToHittable(exportButton, in: app)
        exportButton.tap()
        XCTAssertTrue(app.navigationBars["Export Settings"].waitForExistence(timeout: 5))

        let youTube = app.buttons["exportPreset-youtube-thumbnail"]
        let square = app.buttons["exportPreset-instagram-square"]
        XCTAssertTrue(youTube.waitForExistence(timeout: 5))
        XCTAssertTrue(youTube.isSelected)
        XCTAssertTrue((youTube.value as? String ?? "").hasPrefix("Selected"))
        XCTAssertTrue(square.exists)
        XCTAssertFalse(square.isSelected)

        square.tap()
        XCTAssertTrue(square.isSelected)
        XCTAssertFalse(youTube.isSelected)
        XCTAssertTrue((youTube.value as? String ?? "").hasPrefix("Not selected"))
        try audit(app)
    }

    // MARK: Helpers

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        // SHELL: these tests drive the editor directly, skipping the Create home.
        app.launchArguments = ["-UITestSkipHome"] + arguments
        app.launch()
        XCTAssertTrue(app.navigationBars["Simple Maker"].waitForExistence(timeout: 10))
        return app
    }

    /// Returns a control from the Variants & Sizes section, expanding the
    /// compact (phone) disclosure first when the section is collapsed.
    private func revealVariantsControl(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let control = app.buttons[identifier]
        let toggle = app.buttons["compactVariantsSectionToggle"]
        if !control.exists, toggle.waitForExistence(timeout: 5) {
            scrollToHittable(toggle, in: app)
            XCTAssertTrue(toggle.isHittable, file: file, line: line)
            toggle.tap()
        }
        XCTAssertTrue(control.waitForExistence(timeout: 5), "\(identifier) should exist", file: file, line: line)
        scrollToHittable(control, in: app)
        XCTAssertTrue(control.isHittable, "\(identifier) should be hittable", file: file, line: line)
        return control
    }

    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) {
        for _ in 0..<maxSwipes where !isOnScreen(element, in: app) {
            app.swipeUp()
        }
    }

    /// Hittable and fully clear of the tab bar, so a coordinate tap lands.
    private func isOnScreen(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let tabBar = app.tabBars.firstMatch
        let bottom = tabBar.exists ? tabBar.frame.minY : app.frame.maxY
        return element.frame.maxY <= bottom
    }

    private func tap(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// Runs the audit with no exclusions and reports every issue it finds
    /// (not just the first), so one run shows the whole list.
    private func audit(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws {
        guard #available(iOS 17.0, *) else { return }
        let auditTypes: XCUIAccessibilityAuditType = [
            .elementDetection,
            .hitRegion,
            .sufficientElementDescription,
            .dynamicType,
            .textClipped,
            .trait
        ]
        var issues: [String] = []
        try app.performAccessibilityAudit(for: auditTypes) { issue in
            issues.append(
                """
                \(issue.compactDescription)
                \(issue.detailedDescription)
                Element: \(String(describing: issue.element))
                """
            )
            return true
        }
        if !issues.isEmpty {
            XCTFail(
                "\(issues.count) accessibility issue(s):\n" + issues.joined(separator: "\n---\n"),
                file: file,
                line: line
            )
        }
    }

    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
