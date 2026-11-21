//
//  EditorParityUITests.swift
//  ThumbnailMakerUITests
//
//  EDITOR (1.1.0 parity): quick-add strip, unified asset Library, text
//  inspector Effects / Shadow tabs and the quick "Actions" row, each opened
//  on a phone and run through the full accessibility audit.
//

import XCTest

final class EditorParityUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testQuickAddStripAddsTextAndQuickActionsEditIt() throws {
        let app = launch(["-DisableDraftPersistence"])

        let strip = app.descendants(matching: .any)["editorQuickAddStrip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        for identifier in ["quickAddBackground", "quickAddText", "quickAddImage", "quickAddShape", "quickAddSticker", "quickAddLibrary"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(identifier) should exist")
            assertMinimumHitTarget(button)
        }

        tap(app.buttons["quickAddText"])
        let textLayer = app.buttons["layerSelectionTextLayer1"]
        XCTAssertTrue(textLayer.waitForExistence(timeout: 5), "Quick add Text creates a text layer")

        let actions = app.descendants(matching: .any)["layerQuickActions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        let duplicate = app.buttons["quickAction_duplicate"]
        scrollToHittable(duplicate, in: app)
        // A tap delivered while the scroll view is still decelerating from the swipe only
        // stops the scroll — iOS does not activate the button. That made this test fail
        // intermittently (1 in 4 full runs). Wait for the control to stop moving first.
        waitUntilSettled(duplicate)
        XCTAssertTrue(duplicate.isHittable)
        assertMinimumHitTarget(duplicate)
        tap(duplicate)
        XCTAssertTrue(app.buttons["layerSelectionTextLayer2"].waitForExistence(timeout: 5), "Duplicate adds a second text layer")

        let delete = app.buttons["quickAction_delete"]
        tap(delete)
        XCTAssertTrue(waitForDisappearance(app.buttons["layerSelectionTextLayer2"]), "Delete removes the copy")

        let flip = app.buttons["quickAction_flip"]
        for _ in 0..<3 where !flip.isHittable {
            actions.swipeLeft()
        }
        XCTAssertTrue(flip.isHittable)
        XCTAssertTrue(flip.isEnabled)
        assertMinimumHitTarget(flip)
        tap(flip)
        XCTAssertTrue(app.buttons["Undo"].isEnabled)

        attachScreenshot(app, "editor-quick-actions")
        try audit(app)
    }

    @MainActor
    func testAssetLibraryInsertsStickerAndPassesAudit() throws {
        let app = launch(["-DisableDraftPersistence"])

        let library = app.buttons["quickAddLibrary"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        tap(library)

        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["assetLibraryPhotoImage"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["assetLibrarySection_brand"].exists)
        attachScreenshot(app, "editor-asset-library")
        try audit(app)

        let sticker = app.buttons["assetLibraryItem_sticker0"]
        XCTAssertTrue(sticker.waitForExistence(timeout: 5))
        tap(sticker)

        XCTAssertTrue(app.buttons["layerSelectionSticker1"].waitForExistence(timeout: 5), "Tapping a sticker inserts a sticker layer")

        // The inserted sticker is now offered under "Used in This Project".
        tap(app.buttons["quickAddSticker"])
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        let recent = app.descendants(matching: .any)["assetLibrarySection_recent"]
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        XCTAssertTrue(recent.buttons.firstMatch.waitForExistence(timeout: 5))
        tap(app.buttons["assetLibraryCloseButton"])
        XCTAssertTrue(waitForDisappearance(app.navigationBars["Library"]))
    }

    @MainActor
    func testBackgroundSheetOpensAndPassesAudit() throws {
        let app = launch(["-DisableDraftPersistence"])

        let background = app.buttons["quickAddBackground"]
        XCTAssertTrue(background.waitForExistence(timeout: 5))
        tap(background)

        XCTAssertTrue(app.navigationBars["Background"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["backgroundPhotoPicker"].exists)
        attachScreenshot(app, "editor-background-sheet")
        try audit(app)

        tap(app.buttons["backgroundSheetDoneButton"])
        XCTAssertTrue(waitForDisappearance(app.navigationBars["Background"]))
    }

    @MainActor
    func testTextInspectorEffectsAndShadowTabs() throws {
        let app = launch(["-DisableDraftPersistence"])

        tap(app.buttons["quickAddText"])
        XCTAssertTrue(app.buttons["layerSelectionTextLayer1"].waitForExistence(timeout: 5))

        let effects = app.buttons["textStyleEffectsTab"]
        XCTAssertTrue(effects.waitForExistence(timeout: 5))
        scrollToHittable(effects, in: app)
        assertMinimumHitTarget(effects)
        tap(effects)
        XCTAssertTrue(app.sliders["textStyleOutlineWidth"].waitForExistence(timeout: 5), "Effects shows outline controls")
        XCTAssertFalse(app.switches["textStyleShadowToggle"].exists)

        let shadow = app.buttons["textStyleShadowTab"]
        scrollToHittable(shadow, in: app)
        tap(shadow)
        XCTAssertTrue(app.switches["textStyleShadowToggle"].waitForExistence(timeout: 5), "Shadow shows shadow controls")
        XCTAssertFalse(app.sliders["textStyleOutlineWidth"].exists)
        try audit(app)
    }

    /// FRAME: "Grab from Video" opens from the Library once it has closed,
    /// offers Photos and Files pickers, and passes the audit.
    @MainActor
    func testVideoFrameGrabberOpensFromLibraryAndPassesAudit() throws {
        let app = launch(["-DisableDraftPersistence"])

        let library = app.buttons["quickAddLibrary"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        tap(library)
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        let fromLibrary = app.buttons["assetLibraryVideoFrame"]
        XCTAssertTrue(fromLibrary.waitForExistence(timeout: 5))
        assertMinimumHitTarget(fromLibrary)
        tap(fromLibrary)

        XCTAssertTrue(app.navigationBars["Grab from Video"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Library"].exists)
        XCTAssertTrue(app.buttons["videoFramePhotosPicker"].exists)
        XCTAssertTrue(app.buttons["videoFrameFilesButton"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["videoFrameEmptyState"].exists)
        attachScreenshot(app, "video-frame-grabber-empty")
        try audit(app)

        tap(app.buttons["videoFrameCloseButton"])
        XCTAssertTrue(waitForDisappearance(app.navigationBars["Grab from Video"]))
        XCTAssertTrue(app.navigationBars["Simple Maker"].exists)
    }

    // MARK: GAPS

    @MainActor
    func testQuickAddStripIsTheOnlyAddEntryPoint() throws {
        let app = launch(["-DisableDraftPersistence", "-UITestSeedSelectedImage"])
        XCTAssertTrue(app.buttons["quickAddText"].waitForExistence(timeout: 5))
        // The old add-button grid duplicated the strip; each action now has one place.
        for _ in 0..<6 { app.swipeUp() }
        for identifier in ["addTextLayerButton", "addImageLayerButton", "addStickerLayerButton", "addShapeLayerButton"] {
            XCTAssertFalse(app.buttons[identifier].exists, identifier)
        }
        XCTAssertFalse(app.buttons["Select Image"].exists)
        // Unique actions stay in the grid.
        XCTAssertTrue(app.buttons["addEmojiStickerButton"].exists)
    }

    @MainActor
    func testMainTitleAutoFitToggle() throws {
        let app = launch(["-DisableDraftPersistence", "-UITestSeedDenseTitle"])
        XCTAssertTrue(app.descendants(matching: .any)["overlayTextLayer"].waitForExistence(timeout: 5))

        let toggle = app.switches["overlayAutoFitToggle"]
        scrollToHittable(toggle, in: app, maxSwipes: 10)
        XCTAssertTrue(toggle.exists)
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: toggle)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed)
        attachScreenshot(app, "gaps-overlay-autofit")
    }

    // MARK: Helpers

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-UITestSkipHome"] // SHELL: start in the editor, not Create Home
        app.launch()
        XCTAssertTrue(app.navigationBars["Simple Maker"].waitForExistence(timeout: 10))
        return app
    }

    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) {
        for _ in 0..<maxSwipes where !isOnScreen(element, in: app) {
            app.swipeUp()
        }
    }

    private func isOnScreen(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let tabBar = app.tabBars.firstMatch
        let bottom = tabBar.exists ? tabBar.frame.minY : app.frame.maxY
        return element.frame.maxY <= bottom
    }

    private func tap(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func assertMinimumHitTarget(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(element.frame.width + 0.5, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height + 0.5, 44, file: file, line: line)
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

    /// Waits until an element's frame is unchanged across consecutive samples, i.e. any
    /// scroll deceleration has finished and a tap will activate it rather than stop scrolling.
    @MainActor
    private func waitUntilSettled(_ element: XCUIElement, timeout: TimeInterval = 4) {
        let deadline = Date().addingTimeInterval(timeout)
        var previous = element.frame
        var stableSamples = 0
        while Date() < deadline && stableSamples < 3 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            let current = element.frame
            stableSamples = current == previous ? stableSamples + 1 : 0
            previous = current
        }
    }

}
