//
//  AppShellUITests.swift
//  ThumbnailMakerUITests
//
//  SHELL (1.1.0 rebuild): the Create / Projects / Settings shell, the Create
//  home and the Quick Create wizard. These launch WITHOUT -UITestSkipHome so
//  they exercise the real first screen.
//

import XCTest

final class AppShellUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // The simulator keeps its last orientation between runs; pin portrait
        // like the other UI suites so the phone layout is what is exercised.
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testHomeShowsCreateChoicesAndPassesAudit() throws {
        let app = launchToHome()

        XCTAssertTrue(app.staticTexts["Create a Thumbnail"].exists)
        XCTAssertTrue(app.buttons["startFromScratchButton"].exists)
        XCTAssertTrue(app.buttons["openProEditorButton"].exists)
        XCTAssertTrue(app.tabBars.buttons["Create"].exists)
        XCTAssertTrue(app.tabBars.buttons["Projects"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
        attachScreenshot(app, "shell-home")
        try audit(app)
    }

    @MainActor
    func testQuickCreateFinishLandsInEditorAsUndoableDesign() throws {
        let app = launchToHome()
        app.buttons["quickCreateButton"].tap()

        XCTAssertTrue(app.navigationBars["Quick Create"].waitForExistence(timeout: 5))
        let indicator = app.descendants(matching: .any)["quickCreateStepIndicator"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 5))
        XCTAssertEqual(indicator.label, "Step 1 of 4")

        // Step 1: format, category, template.
        tapElement(app.buttons["quickCreateFormat-instagram"])
        tapElement(app.buttons["quickCreateCategory-gaming"])
        let epic = app.buttons["quickCreateTemplate-quick-epic-gameplay"]
        XCTAssertTrue(epic.waitForExistence(timeout: 5))
        tapElement(epic)
        XCTAssertTrue(epic.isSelected)
        attachScreenshot(app, "quick-create-template")
        app.buttons["quickCreateNextButton"].tap()

        // Step 2: title + subtitle.
        XCTAssertTrue(waitForLabel(indicator, "Step 2 of 4"))
        let titleField = app.descendants(matching: .any)["quickCreateTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("BOSS FIGHT")
        let subtitleField = app.descendants(matching: .any)["quickCreateSubtitleField"]
        subtitleField.tap()
        subtitleField.typeText("Part 2")
        attachScreenshot(app, "quick-create-text")
        app.buttons["quickCreateNextButton"].tap()

        // Step 3: a text style.
        XCTAssertTrue(waitForLabel(indicator, "Step 3 of 4"))
        let glow = app.buttons["quickCreateTextStyle-glow"]
        XCTAssertTrue(glow.waitForExistence(timeout: 5))
        tapElement(glow)
        app.buttons["quickCreateNextButton"].tap()

        // Step 4: export, then create.
        XCTAssertTrue(waitForLabel(indicator, "Step 4 of 4"))
        XCTAssertTrue(app.descendants(matching: .any)["quickCreateExportSize"].waitForExistence(timeout: 5))
        attachScreenshot(app, "quick-create-export")
        app.buttons["quickCreateFinishButton"].tap()

        // Lands in the editor with the wizard's design...
        XCTAssertTrue(app.navigationBars["Simple Maker"].waitForExistence(timeout: 10))
        let overlayText = app.textViews["Overlay text"]
        XCTAssertTrue(overlayText.waitForExistence(timeout: 5))
        XCTAssertTrue((overlayText.value as? String ?? "").contains("BOSS FIGHT"))
        XCTAssertFalse(app.navigationBars["Quick Create"].exists)
        attachScreenshot(app, "quick-create-result-in-editor")

        // ...as one normal, undoable step back to the blank canvas.
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(undo.isEnabled)
        undo.tap()
        XCTAssertTrue(waitForValue(overlayText) { !$0.contains("BOSS FIGHT") })
    }

    @MainActor
    func testSkipToEditorOpensEditorWithChosenLayoutAndHomeReturns() throws {
        let app = launchToHome()
        app.buttons["quickCreateButton"].tap()
        XCTAssertTrue(app.navigationBars["Quick Create"].waitForExistence(timeout: 5))

        let boldCenter = app.buttons["quickCreateTemplate-quick-bold-center"]
        XCTAssertTrue(boldCenter.waitForExistence(timeout: 5))
        tapElement(boldCenter)
        app.buttons["quickCreateSkipButton"].tap()

        XCTAssertTrue(app.navigationBars["Simple Maker"].waitForExistence(timeout: 10))
        let overlayText = app.textViews["Overlay text"]
        XCTAssertTrue(overlayText.waitForExistence(timeout: 5))
        XCTAssertTrue((overlayText.value as? String ?? "").contains("YOUR TEXT"))

        // Re-tapping the Create tab returns Home (the phone toolbar has no
        // room for a Home button; iPad shows one as well).
        app.tabBars.buttons["Create"].tap()
        XCTAssertTrue(app.buttons["quickCreateButton"].waitForExistence(timeout: 5))
        // The design is still there to continue.
        XCTAssertTrue(app.buttons["continueEditingButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCancelReturnsHomeAndStartFromScratchOpensEditor() throws {
        let app = launchToHome()
        app.buttons["quickCreateButton"].tap()
        XCTAssertTrue(app.navigationBars["Quick Create"].waitForExistence(timeout: 5))
        app.buttons["quickCreateCancelButton"].tap()
        XCTAssertTrue(app.buttons["quickCreateButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Quick Create"].exists)

        app.buttons["startFromScratchButton"].tap()
        XCTAssertTrue(app.navigationBars["Simple Maker"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["settingsButton"].exists)
    }

    @MainActor
    func testSettingsTabShowsSettingsWithoutDoneButton() throws {
        let app = launchToHome()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["settingsAppVersion"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Settings"].buttons["Done"].exists)
    }

    // MARK: GAPS

    @MainActor
    func testSettingsShowsFeaturesAndSupport() throws {
        let app = launchToHome()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Multiple aspect ratios for every platform"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Works completely offline"].exists)

        let rate = app.buttons["settingsRateAppButton"]
        for _ in 0..<6 where !rate.isHittable { app.swipeUp() }
        XCTAssertTrue(rate.isHittable)
        XCTAssertTrue(app.buttons["settingsSupportLink"].exists)

        let privacy = app.buttons["settingsPrivacyPolicyLink"]
        for _ in 0..<4 where !privacy.isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["settingsTermsLink"].exists)
        attachScreenshot(app, "gaps-settings-support")
        privacy.tap()
        XCTAssertTrue(app.navigationBars["Privacy Policy"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testProjectsTabListsPremiumProjectsAndOpensThePremiumEditor() throws {
        let app = XCUIApplication()
        // The project library only exists with persistence on; use the
        // isolated temporary UI-test library.
        app.launchArguments = ["-UITestSeedProjectLibrary"]
        app.launch()
        XCTAssertTrue(app.buttons["quickCreateButton"].waitForExistence(timeout: 10))

        app.tabBars.buttons["Projects"].tap()
        XCTAssertTrue(app.navigationBars["Projects"].waitForExistence(timeout: 5))
        let premiumSegment = app.segmentedControls["projectsEditorPicker"].buttons["Premium"]
        XCTAssertTrue(premiumSegment.waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["projectsEditorPicker"].buttons["Simple"].isSelected)
        premiumSegment.tap()
        XCTAssertTrue(waitForSelected(premiumSegment))

        let newProject = app.buttons["newProjectButton"]
        XCTAssertTrue(newProject.waitForExistence(timeout: 10))
        attachScreenshot(app, "gaps-projects-premium")
        newProject.tap()

        // Opening a Premium project lands in the Premium editor (or its
        // paywall when Premium is locked), never the Simple editor.
        let premiumEditor = app.navigationBars["Premium"]
        let paywall = app.staticTexts["Premium Maker"]
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline && !premiumEditor.exists && !paywall.exists {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(premiumEditor.exists || paywall.exists)
        XCTAssertFalse(app.navigationBars["Simple Maker"].exists)

        app.tabBars.buttons["Projects"].tap()
        XCTAssertTrue(app.navigationBars["Projects"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["projectsEditorPicker"].buttons["Premium"].isSelected)
    }

    private func waitForSelected(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.isSelected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return element.isSelected
    }

    // MARK: Helpers

    private func launchToHome() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-DisableDraftPersistence"]
        app.launch()
        XCTAssertTrue(app.buttons["quickCreateButton"].waitForExistence(timeout: 10))
        return app
    }

    private func tapElement(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.label == label { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return element.label == label
    }

    private func waitForValue(
        _ element: XCUIElement,
        timeout: TimeInterval = 5,
        _ predicate: (String) -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(element.value as? String ?? "") { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return predicate(element.value as? String ?? "")
    }

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
            XCTFail("\(issues.count) accessibility issue(s):\n" + issues.joined(separator: "\n---\n"), file: file, line: line)
        }
    }

    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
