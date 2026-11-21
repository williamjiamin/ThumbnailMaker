//
//  ThumbnailMakerUITests.swift
//  ThumbnailMakerUITests
//
//  Created by william on 2024/11/22.
//

import XCTest
import UIKit

final class ThumbnailMakerUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testLaunchAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-DisableDraftPersistence"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Simple Maker"].waitForExistence(timeout: 5))
        let settingsButton = app.buttons["settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        XCTAssertEqual(settingsButton.label, "Settings")

        if #available(iOS 17.0, *) {
            let auditTypes: XCUIAccessibilityAuditType = [
                .elementDetection,
                .hitRegion,
                .sufficientElementDescription,
                .dynamicType,
                .textClipped,
                .trait
            ]
            try app.performAccessibilityAudit(for: auditTypes) { issue in
                XCTFail(
                    """
                    \(issue.compactDescription)
                    \(issue.detailedDescription)
                    Element: \(String(describing: issue.element))
                    """
                )
                return false
            }
        }
    }

    @MainActor
    func testExportSettingsSheetOpens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-DisableDraftPersistence"]
        app.launch()

        let exportButton = app.buttons["exportSettingsButton"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))

        exportButton.tap()

        XCTAssertTrue(app.navigationBars["Export Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["YouTube Thumbnail"].exists)
        XCTAssertTrue(app.staticTexts["Custom Size"].exists)
    }

    @MainActor
    func testExportSettingsAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-DisableDraftPersistence"]
        app.launch()

        let exportButton = app.buttons["exportSettingsButton"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()

        XCTAssertTrue(app.navigationBars["Export Settings"].waitForExistence(timeout: 5))
        let jpegFormatButton = app.buttons["JPEG"]
        XCTAssertTrue(jpegFormatButton.waitForExistence(timeout: 5))
        jpegFormatButton.tap()

        let qualityStepper = app.descendants(matching: .any)["exportQualityStepper"]
        XCTAssertTrue(qualityStepper.waitForExistence(timeout: 5))
        XCTAssertTrue(qualityStepper.label.contains("Quality"))

        if #available(iOS 17.0, *) {
            let auditTypes: XCUIAccessibilityAuditType = [
                .elementDetection,
                .hitRegion,
                .sufficientElementDescription,
                .dynamicType,
                .textClipped,
                .trait
            ]
            try app.performAccessibilityAudit(for: auditTypes) { issue in
                XCTFail(
                    """
                    \(issue.compactDescription)
                    \(issue.detailedDescription)
                    Element: \(String(describing: issue.element))
                    """
                )
                return false
            }
        }
    }

    @MainActor
    func testSafeZoneGuideAppearsInPreview() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-DisableDraftPersistence"]
        app.launch()

        XCTAssertTrue(app.otherElements["safeZoneOverlay"].waitForExistence(timeout: 5))

        let safeZoneToggle = app.descendants(matching: .any)["safeZoneGuideToggle"]
        XCTAssertTrue(safeZoneToggle.waitForExistence(timeout: 5))
        scrollToHittable(safeZoneToggle, in: app)
        XCTAssertTrue(safeZoneToggle.isHittable)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "safe-zone-guide"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testSmallPreviewAppearsAfterEnteringOverlayText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-DisableDraftPersistence"]
        app.launch()

        let overlayText = app.textViews["Overlay text"]
        XCTAssertTrue(overlayText.waitForExistence(timeout: 5))

        overlayText.tap()
        overlayText.typeText("Readable title")
        app.swipeUp()

        XCTAssertTrue(app.descendants(matching: .any)["layerSelectionStrip"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["layerSelectionText"].exists)
        XCTAssertTrue(app.otherElements["smallPreviewPanel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Text Canvas"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Text Transform"].exists)
        XCTAssertFalse(app.staticTexts["Text Size"].exists)
        XCTAssertFalse(app.staticTexts["Position"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "small-preview-panel"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testDirectManipulationHandlesAppearForTextOverlay() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-DisableDraftPersistence"]
        app.launch()

        let overlayText = app.textViews["Overlay text"]
        XCTAssertTrue(overlayText.waitForExistence(timeout: 5))

        overlayText.tap()
        overlayText.typeText("Drag me")

        for identifier in ["textFlipHandle", "textRotateHandle", "textResizeHandle"] {
            let handle = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(handle.waitForExistence(timeout: 5), "\(identifier) should exist")
            XCTAssertTrue(handle.isHittable, "\(identifier) should be hittable")
        }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "direct-manipulation-handles"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testTextWYSIWYGGesturesMutateCanvasState() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-DisableDraftPersistence"]
        app.launch()

        let overlayText = app.textViews["Overlay text"]
        XCTAssertTrue(overlayText.waitForExistence(timeout: 5))
        overlayText.tap()
        overlayText.typeText("Drag me")

        let layerIdentifier = "overlayTextLayer"
        let layer = app.descendants(matching: .any)[layerIdentifier]
        XCTAssertTrue(layer.waitForExistence(timeout: 5))

        var state = stateValue(in: app, identifier: layerIdentifier)
        XCTAssertTrue(state.contains("not flipped"))

        let flipHandle = app.descendants(matching: .any)["textFlipHandle"]
        XCTAssertTrue(flipHandle.waitForExistence(timeout: 5))
        tap(flipHandle)
        state = waitForStateValueChange(in: app, identifier: layerIdentifier, from: state)
        XCTAssertTrue(state.contains("flipped"))

        drag(layer, by: CGVector(dx: 90, dy: 70))
        state = waitForStateValueChange(in: app, identifier: layerIdentifier, from: state)

        let resizeHandle = app.descendants(matching: .any)["textResizeHandle"]
        XCTAssertTrue(resizeHandle.waitForExistence(timeout: 5))
        drag(resizeHandle, by: CGVector(dx: 96, dy: 96))
        state = waitForStateValueChange(in: app, identifier: layerIdentifier, from: state)

        let rotateHandle = app.descendants(matching: .any)["textRotateHandle"]
        XCTAssertTrue(rotateHandle.waitForExistence(timeout: 5))
        drag(rotateHandle, by: CGVector(dx: 96, dy: 0))
        _ = waitForStateValueChange(in: app, identifier: layerIdentifier, from: state)
    }

    @MainActor
    func testDirectManipulationHandlesRemainHittableNearCanvasEdge() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-UITestSeedTopEdgeText", "-DisableDraftPersistence"]
        app.launch()

        for identifier in ["textFlipHandle", "textRotateHandle", "textResizeHandle"] {
            let handle = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(handle.waitForExistence(timeout: 5), "\(identifier) should exist near the canvas edge")
            XCTAssertTrue(handle.isHittable, "\(identifier) should remain hittable near the canvas edge")
        }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "edge-direct-manipulation-handles"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testLayerVisibilityAndLockControlsAffectTextChrome() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-DisableDraftPersistence"]
        app.launch()

        let overlayText = app.textViews["Overlay text"]
        XCTAssertTrue(overlayText.waitForExistence(timeout: 5))

        overlayText.tap()
        overlayText.typeText("Layer state")

        let keyboardDoneButton = app.buttons["overlayTextKeyboardDoneButton"]
        XCTAssertTrue(keyboardDoneButton.waitForExistence(timeout: 5))
        keyboardDoneButton.tap()

        let lockButton = app.descendants(matching: .any)["layerLockText"]
        let visibilityButton = app.descendants(matching: .any)["layerVisibilityText"]
        let textFlipHandle = app.descendants(matching: .any)["textFlipHandle"]

        XCTAssertTrue(lockButton.waitForExistence(timeout: 5))
        scrollToHittable(lockButton, in: app)
        XCTAssertTrue(lockButton.isHittable)
        XCTAssertTrue(visibilityButton.exists)
        assertMinimumHitTarget(lockButton)
        assertMinimumHitTarget(visibilityButton)
        XCTAssertTrue(textFlipHandle.waitForExistence(timeout: 5))

        lockButton.tap()
        XCTAssertTrue(
            waitForElementLabel(
                in: app,
                identifier: "layerLockText",
                containing: "Unlock Text layer",
                timeout: 5
            )
        )

        lockButton.tap()
        XCTAssertTrue(
            waitForElementLabel(
                in: app,
                identifier: "layerLockText",
                containing: "Lock Text layer",
                timeout: 5
            )
        )

        scrollToHittable(visibilityButton, in: app)
        XCTAssertTrue(visibilityButton.isHittable)
        visibilityButton.tap()
        XCTAssertTrue(
            waitForElementLabel(
                in: app,
                identifier: "layerVisibilityText",
                containing: "Show Text layer",
                timeout: 5
            )
        )

        visibilityButton.tap()
        XCTAssertTrue(
            waitForElementLabel(
                in: app,
                identifier: "layerVisibilityText",
                containing: "Hide Text layer",
                timeout: 5
            )
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "layer-visibility-lock-controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testLayerControlsRemainAccessibleAtLargeDynamicType() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestSkipHome",
            "-DisableDraftPersistence",
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        ]
        app.launch()

        let overlayText = app.textViews["Overlay text"]
        XCTAssertTrue(overlayText.waitForExistence(timeout: 5))
        overlayText.tap()
        overlayText.typeText("Big type")

        let keyboardDoneButton = app.buttons["overlayTextKeyboardDoneButton"]
        XCTAssertTrue(keyboardDoneButton.waitForExistence(timeout: 5))
        keyboardDoneButton.tap()

        let layerStrip = app.descendants(matching: .any)["layerSelectionStrip"]
        scrollToHittable(layerStrip, in: app, maxSwipes: 6)
        XCTAssertTrue(layerStrip.waitForExistence(timeout: 5))

        let lockButton = app.descendants(matching: .any)["layerLockText"]
        XCTAssertTrue(lockButton.waitForExistence(timeout: 5))
        scrollToHittable(lockButton, in: app, maxSwipes: 4)
        XCTAssertTrue(lockButton.isHittable)
        assertMinimumHitTarget(lockButton)

        let visibilityButton = app.descendants(matching: .any)["layerVisibilityText"]
        XCTAssertTrue(visibilityButton.exists)
        assertMinimumHitTarget(visibilityButton)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "layer-controls-large-dynamic-type"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testImageLayerSelectionShowsCanvasChromeAndLayerActions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-UITestSeedImageLayer", "-DisableDraftPersistence"]
        app.launch()

        let layerStrip = app.descendants(matching: .any)["layerSelectionStrip"]
        XCTAssertTrue(layerStrip.waitForExistence(timeout: 5))

        let imageLayerButton = app.descendants(matching: .any)["layerSelectionImage1"]
        XCTAssertTrue(imageLayerButton.waitForExistence(timeout: 5))
        if !imageLayerButton.isHittable {
            layerStrip.swipeLeft()
        }
        XCTAssertTrue(imageLayerButton.isHittable)
        imageLayerButton.tap()

        let imageLayer = app.descendants(matching: .any)["imageContentLayer-ui-test-image-layer"]
        XCTAssertTrue(imageLayer.waitForExistence(timeout: 5))
        for identifier in ["imageFlipHandle", "imageRotateHandle", "imageResizeHandle"] {
            let handle = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(handle.waitForExistence(timeout: 5), "\(identifier) should exist")
            XCTAssertTrue(handle.isHittable, "\(identifier) should be hittable")
        }

        let duplicateButton = app.descendants(matching: .any)["layerDuplicateImage1"]
        let deleteButton = app.descendants(matching: .any)["layerDeleteImage1"]
        XCTAssertTrue(duplicateButton.waitForExistence(timeout: 5))
        XCTAssertTrue(deleteButton.exists)
        assertMinimumHitTarget(duplicateButton)
        assertMinimumHitTarget(deleteButton)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "image-layer-wysiwyg-controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testImageLayerDuplicateAndDeleteMutateCanvasLayers() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-UITestSeedImageLayer", "-DisableDraftPersistence"]
        app.launch()

        _ = selectContentLayer(
            in: app,
            buttonIdentifier: "layerSelectionImage1",
            layerIdentifier: "imageContentLayer-ui-test-image-layer"
        )
        XCTAssertTrue(waitForElementCount(in: app, identifierPrefix: "imageContentLayer-", equals: 1))

        let duplicateButton = app.descendants(matching: .any)["layerDuplicateImage1"]
        XCTAssertTrue(duplicateButton.waitForExistence(timeout: 5))
        tap(duplicateButton)
        XCTAssertTrue(waitForElementCount(in: app, identifierPrefix: "imageContentLayer-", equals: 2))

        let duplicatedLayerButton = app.descendants(matching: .any)["layerSelectionImage2"]
        XCTAssertTrue(duplicatedLayerButton.waitForExistence(timeout: 5))

        let deleteButton = app.descendants(matching: .any)["layerDeleteImage2"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        tap(deleteButton)
        XCTAssertTrue(waitForElementCount(in: app, identifierPrefix: "imageContentLayer-", equals: 1))
    }

    @MainActor
    func testImageLayerWYSIWYGGesturesMutateCanvasState() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-UITestSeedImageLayer", "-DisableDraftPersistence"]
        app.launch()

        let layerIdentifier = "imageContentLayer-ui-test-image-layer"
        let imageLayer = selectContentLayer(
            in: app,
            buttonIdentifier: "layerSelectionImage1",
            layerIdentifier: layerIdentifier
        )

        var state = stateValue(in: app, identifier: layerIdentifier)
        XCTAssertTrue(state.contains("not flipped"))

        let flipHandle = app.descendants(matching: .any)["imageFlipHandle"]
        XCTAssertTrue(flipHandle.waitForExistence(timeout: 5))
        tap(flipHandle)
        state = waitForStateValueChange(in: app, identifier: layerIdentifier, from: state)
        XCTAssertTrue(state.contains("flipped"))

        drag(imageLayer, by: CGVector(dx: 80, dy: 60))
        state = waitForStateValueChange(in: app, identifier: layerIdentifier, from: state)

        let resizeHandle = app.descendants(matching: .any)["imageResizeHandle"]
        XCTAssertTrue(resizeHandle.waitForExistence(timeout: 5))
        drag(resizeHandle, by: CGVector(dx: 90, dy: 90))
        state = waitForStateValueChange(in: app, identifier: layerIdentifier, from: state)

        let rotateHandle = app.descendants(matching: .any)["imageRotateHandle"]
        XCTAssertTrue(rotateHandle.waitForExistence(timeout: 5))
        drag(rotateHandle, by: CGVector(dx: 90, dy: 0))
        _ = waitForStateValueChange(in: app, identifier: layerIdentifier, from: state)
    }

    @MainActor
    func testImageLayerHandlesRemainHittableNearCanvasEdge() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-UITestSeedTopEdgeImageLayer", "-DisableDraftPersistence"]
        app.launch()

        let layerStrip = app.descendants(matching: .any)["layerSelectionStrip"]
        XCTAssertTrue(layerStrip.waitForExistence(timeout: 5))

        let imageLayerButton = app.descendants(matching: .any)["layerSelectionImage1"]
        XCTAssertTrue(imageLayerButton.waitForExistence(timeout: 5))
        if !imageLayerButton.isHittable {
            layerStrip.swipeLeft()
        }
        XCTAssertTrue(imageLayerButton.isHittable)
        imageLayerButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["imageContentLayer-ui-test-edge-image-layer"].waitForExistence(timeout: 5))
        for identifier in ["imageFlipHandle", "imageRotateHandle", "imageResizeHandle"] {
            let handle = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(handle.waitForExistence(timeout: 5), "\(identifier) should exist near the canvas edge")
            XCTAssertTrue(handle.isHittable, "\(identifier) should remain hittable near the canvas edge")
        }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "edge-image-layer-handles"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testStickerLayerSelectionShowsFirstClassLayerActions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-UITestSeedStickerLayer", "-DisableDraftPersistence"]
        app.launch()

        let stickerLayer = selectContentLayer(
            in: app,
            buttonIdentifier: "layerSelectionSticker1",
            layerIdentifier: "imageContentLayer-ui-test-sticker-layer"
        )
        XCTAssertTrue(stickerLayer.exists)

        let duplicateButton = app.descendants(matching: .any)["layerDuplicateSticker1"]
        let deleteButton = app.descendants(matching: .any)["layerDeleteSticker1"]
        XCTAssertTrue(duplicateButton.waitForExistence(timeout: 5))
        XCTAssertTrue(deleteButton.exists)
        assertMinimumHitTarget(duplicateButton)
        assertMinimumHitTarget(deleteButton)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "sticker-layer-first-class-actions"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        // GAPS: stickers are added from the quick-add strip only.
        let stickerImportButton = app.buttons["quickAddSticker"]
        scrollToHittable(stickerImportButton, in: app, maxSwipes: 6)
        XCTAssertTrue(stickerImportButton.waitForExistence(timeout: 5))
        assertMinimumHitTarget(stickerImportButton)
    }

    @MainActor
    func testLayerReorderChangesStackingOrder() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-UITestSeedReorderLayers", "-DisableDraftPersistence"]
        app.launch()

        let imageButton = app.descendants(matching: .any)["layerSelectionImage1"]
        XCTAssertTrue(imageButton.waitForExistence(timeout: 5))
        scrollLayerStripToVisible(imageButton, in: app)
        tap(imageButton)

        XCTAssertTrue(stringValue(of: imageButton).contains("Order 2 of 2"))

        var moveBackwardButton = app.descendants(matching: .any)["layerMoveBackwardImage1"]
        var moveForwardButton = app.descendants(matching: .any)["layerMoveForwardImage1"]
        XCTAssertTrue(moveBackwardButton.waitForExistence(timeout: 5))
        XCTAssertTrue(moveForwardButton.waitForExistence(timeout: 5))
        XCTAssertFalse(moveBackwardButton.isEnabled)
        XCTAssertTrue(moveForwardButton.isEnabled)
        scrollLayerStripToVisible(moveForwardButton, in: app)

        let initialValue = stringValue(of: imageButton)
        tap(moveForwardButton)
        let reorderedValue = waitForElementValueChange(
            in: app,
            identifier: "layerSelectionImage1",
            from: initialValue
        )
        XCTAssertTrue(reorderedValue.contains("Order 1 of 2"))

        moveBackwardButton = app.descendants(matching: .any)["layerMoveBackwardImage1"]
        moveForwardButton = app.descendants(matching: .any)["layerMoveForwardImage1"]
        XCTAssertTrue(moveBackwardButton.isEnabled)
        XCTAssertFalse(moveForwardButton.isEnabled)
    }

    @MainActor
    func testLayerDragSnapsToCanvasCenter() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-UITestSeedCenteringLayer", "-DisableDraftPersistence"]
        app.launch()

        let layerIdentifier = "imageContentLayer-ui-test-centering-layer"
        let imageLayer = selectContentLayer(
            in: app,
            buttonIdentifier: "layerSelectionImage1",
            layerIdentifier: layerIdentifier
        )

        let initialState = stateValue(in: app, identifier: layerIdentifier)
        XCTAssertFalse(initialState.contains("50%, 50%"))

        drag(imageLayer, by: CGVector(dx: -6, dy: -4))
        let snappedState = waitForStateValueChange(in: app, identifier: layerIdentifier, from: initialState)
        XCTAssertTrue(snappedState.contains("50%, 50%"))
    }

    @MainActor
    func testShapeLayerSelectionShowsCanvasChromeAndLayerActions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-UITestSeedShapeLayer", "-DisableDraftPersistence"]
        app.launch()

        let layerStrip = app.descendants(matching: .any)["layerSelectionStrip"]
        XCTAssertTrue(layerStrip.waitForExistence(timeout: 5))

        let shapeLayerButton = app.descendants(matching: .any)["layerSelectionShape1"]
        XCTAssertTrue(shapeLayerButton.waitForExistence(timeout: 5))
        if !shapeLayerButton.isHittable {
            layerStrip.swipeLeft()
        }
        XCTAssertTrue(shapeLayerButton.isHittable)
        shapeLayerButton.tap()

        let shapeLayer = app.descendants(matching: .any)["shapeContentLayer-ui-test-shape-layer"]
        XCTAssertTrue(shapeLayer.waitForExistence(timeout: 5))
        for identifier in ["shapeFlipHandle", "shapeRotateHandle", "shapeResizeHandle"] {
            let handle = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(handle.waitForExistence(timeout: 5), "\(identifier) should exist")
            XCTAssertTrue(handle.isHittable, "\(identifier) should be hittable")
        }

        let duplicateButton = app.descendants(matching: .any)["layerDuplicateShape1"]
        let deleteButton = app.descendants(matching: .any)["layerDeleteShape1"]
        XCTAssertTrue(duplicateButton.waitForExistence(timeout: 5))
        XCTAssertTrue(deleteButton.exists)
        assertMinimumHitTarget(duplicateButton)
        assertMinimumHitTarget(deleteButton)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "shape-layer-wysiwyg-controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testShapeLayerDuplicateAndDeleteMutateCanvasLayers() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-UITestSeedShapeLayer", "-DisableDraftPersistence"]
        app.launch()

        _ = selectContentLayer(
            in: app,
            buttonIdentifier: "layerSelectionShape1",
            layerIdentifier: "shapeContentLayer-ui-test-shape-layer"
        )
        XCTAssertTrue(waitForElementCount(in: app, identifierPrefix: "shapeContentLayer-", equals: 1))

        let duplicateButton = app.descendants(matching: .any)["layerDuplicateShape1"]
        XCTAssertTrue(duplicateButton.waitForExistence(timeout: 5))
        tap(duplicateButton)
        XCTAssertTrue(waitForElementCount(in: app, identifierPrefix: "shapeContentLayer-", equals: 2))

        let duplicatedLayerButton = app.descendants(matching: .any)["layerSelectionShape2"]
        XCTAssertTrue(duplicatedLayerButton.waitForExistence(timeout: 5))

        let deleteButton = app.descendants(matching: .any)["layerDeleteShape2"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        tap(deleteButton)
        XCTAssertTrue(waitForElementCount(in: app, identifierPrefix: "shapeContentLayer-", equals: 1))
    }

    @MainActor
    func testShapeLayerWYSIWYGGesturesMutateCanvasState() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-UITestSeedShapeLayer", "-DisableDraftPersistence"]
        app.launch()

        let layerIdentifier = "shapeContentLayer-ui-test-shape-layer"
        let shapeLayer = selectContentLayer(
            in: app,
            buttonIdentifier: "layerSelectionShape1",
            layerIdentifier: layerIdentifier
        )

        var state = stateValue(in: app, identifier: layerIdentifier)
        XCTAssertTrue(state.contains("not flipped"))

        let flipHandle = app.descendants(matching: .any)["shapeFlipHandle"]
        XCTAssertTrue(flipHandle.waitForExistence(timeout: 5))
        tap(flipHandle)
        state = waitForStateValueChange(in: app, identifier: layerIdentifier, from: state)
        XCTAssertTrue(state.contains("flipped"))

        drag(shapeLayer, by: CGVector(dx: 80, dy: 60))
        state = waitForStateValueChange(in: app, identifier: layerIdentifier, from: state)

        let resizeHandle = app.descendants(matching: .any)["shapeResizeHandle"]
        XCTAssertTrue(resizeHandle.waitForExistence(timeout: 5))
        drag(resizeHandle, by: CGVector(dx: 36, dy: 36))
        state = waitForStateValueChange(in: app, identifier: layerIdentifier, from: state)

        let rotateHandle = app.descendants(matching: .any)["shapeRotateHandle"]
        XCTAssertTrue(rotateHandle.waitForExistence(timeout: 5))
        drag(rotateHandle, by: CGVector(dx: 90, dy: 0))
        _ = waitForStateValueChange(in: app, identifier: layerIdentifier, from: state)
    }

    @MainActor
    func testShapeLayerHandlesRemainHittableNearCanvasEdge() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-UITestSeedTopEdgeShapeLayer", "-DisableDraftPersistence"]
        app.launch()

        let layerStrip = app.descendants(matching: .any)["layerSelectionStrip"]
        XCTAssertTrue(layerStrip.waitForExistence(timeout: 5))

        let shapeLayerButton = app.descendants(matching: .any)["layerSelectionShape1"]
        XCTAssertTrue(shapeLayerButton.waitForExistence(timeout: 5))
        if !shapeLayerButton.isHittable {
            layerStrip.swipeLeft()
        }
        XCTAssertTrue(shapeLayerButton.isHittable)
        shapeLayerButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["shapeContentLayer-ui-test-edge-shape-layer"].waitForExistence(timeout: 5))
        for identifier in ["shapeFlipHandle", "shapeRotateHandle", "shapeResizeHandle"] {
            let handle = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(handle.waitForExistence(timeout: 5), "\(identifier) should exist near the canvas edge")
            XCTAssertTrue(handle.isHittable, "\(identifier) should remain hittable near the canvas edge")
        }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "edge-shape-layer-handles"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testTextLayerSelectionShowsCanvasChromeAndLayerActions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-UITestSeedTextLayer", "-DisableDraftPersistence"]
        app.launch()

        let textLayer = selectContentLayer(
            in: app,
            buttonIdentifier: "layerSelectionTextLayer1",
            layerIdentifier: "textContentLayer-ui-test-text-layer"
        )
        XCTAssertTrue(textLayer.exists)
        XCTAssertTrue(stateValue(in: app, identifier: "textContentLayer-ui-test-text-layer").contains("Layer Text"))

        let textLayerControls = app.descendants(matching: .any)["textLayerContentControls"]
        XCTAssertTrue(textLayerControls.waitForExistence(timeout: 5))
        let textLayerField = app.descendants(matching: .any)["textLayerContentField"]
        XCTAssertTrue(textLayerField.waitForExistence(timeout: 5))
        let initialTextState = stateValue(in: app, identifier: "textContentLayer-ui-test-text-layer")
        scrollToHittable(textLayerField, in: app) // EDITOR: the quick-add strip sits above the inspector
        tap(textLayerField)
        textLayerField.typeText("!")
        let keyboardDoneButton = app.buttons["textLayerContentKeyboardDoneButton"]
        XCTAssertTrue(keyboardDoneButton.waitForExistence(timeout: 5))
        keyboardDoneButton.tap()
        let editedTextState = waitForStateValueChange(
            in: app,
            identifier: "textContentLayer-ui-test-text-layer",
            from: initialTextState
        )
        XCTAssertTrue(editedTextState.contains("Layer Text!"))

        for identifier in ["textContentFlipHandle", "textContentRotateHandle", "textContentResizeHandle"] {
            let handle = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(handle.waitForExistence(timeout: 5), "\(identifier) should exist")
            for _ in 0..<4 where !handle.isHittable { app.swipeDown() } // EDITOR: back up to the canvas
            XCTAssertTrue(handle.isHittable, "\(identifier) should be hittable")
        }

        let duplicateButton = app.descendants(matching: .any)["layerDuplicateTextLayer1"]
        let deleteButton = app.descendants(matching: .any)["layerDeleteTextLayer1"]
        XCTAssertTrue(duplicateButton.waitForExistence(timeout: 5))
        XCTAssertTrue(deleteButton.exists)
        assertMinimumHitTarget(duplicateButton)
        assertMinimumHitTarget(deleteButton)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "text-layer-wysiwyg-controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testTextLayerDuplicateAndDeleteMutateCanvasLayers() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-UITestSeedTextLayer", "-DisableDraftPersistence"]
        app.launch()

        _ = selectContentLayer(
            in: app,
            buttonIdentifier: "layerSelectionTextLayer1",
            layerIdentifier: "textContentLayer-ui-test-text-layer"
        )
        XCTAssertTrue(waitForElementCount(in: app, identifierPrefix: "textContentLayer-", equals: 1))

        let duplicateButton = app.descendants(matching: .any)["layerDuplicateTextLayer1"]
        XCTAssertTrue(duplicateButton.waitForExistence(timeout: 5))
        tap(duplicateButton)
        XCTAssertTrue(waitForElementCount(in: app, identifierPrefix: "textContentLayer-", equals: 2))

        let duplicatedLayerButton = app.descendants(matching: .any)["layerSelectionTextLayer2"]
        XCTAssertTrue(duplicatedLayerButton.waitForExistence(timeout: 5))

        let deleteButton = app.descendants(matching: .any)["layerDeleteTextLayer2"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        tap(deleteButton)
        XCTAssertTrue(waitForElementCount(in: app, identifierPrefix: "textContentLayer-", equals: 1))
    }

    @MainActor
    func testTextLayerWYSIWYGGesturesMutateCanvasState() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-UITestSeedTextLayer", "-DisableDraftPersistence"]
        app.launch()

        let layerIdentifier = "textContentLayer-ui-test-text-layer"
        let textLayer = selectContentLayer(
            in: app,
            buttonIdentifier: "layerSelectionTextLayer1",
            layerIdentifier: layerIdentifier
        )

        var state = stateValue(in: app, identifier: layerIdentifier)
        XCTAssertTrue(state.contains("not flipped"))

        let flipHandle = app.descendants(matching: .any)["textContentFlipHandle"]
        XCTAssertTrue(flipHandle.waitForExistence(timeout: 5))
        tap(flipHandle)
        state = waitForStateValueChange(in: app, identifier: layerIdentifier, from: state)
        XCTAssertTrue(state.contains("flipped"))

        drag(textLayer, by: CGVector(dx: 80, dy: 60))
        state = waitForStateValueChange(in: app, identifier: layerIdentifier, from: state)

        let resizeHandle = app.descendants(matching: .any)["textContentResizeHandle"]
        XCTAssertTrue(resizeHandle.waitForExistence(timeout: 5))
        drag(resizeHandle, by: CGVector(dx: 70, dy: 70))
        state = waitForStateValueChange(in: app, identifier: layerIdentifier, from: state)

        let rotateHandle = app.descendants(matching: .any)["textContentRotateHandle"]
        XCTAssertTrue(rotateHandle.waitForExistence(timeout: 5))
        drag(rotateHandle, by: CGVector(dx: 90, dy: 0))
        _ = waitForStateValueChange(in: app, identifier: layerIdentifier, from: state)
    }

    @MainActor
    func testPremiumCanvasShowsSingleOverlayChromeByDefault() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestSkipHome",
            "-UITestUnlockPremium",
            "-UITestSeedPremiumEditor",
            "-UITestStartPremiumTab",
            "-DisableDraftPersistence"
        ]
        app.launch()

        let textFlipHandle = app.descendants(matching: .any)["textFlipHandle"]
        let profileFlipHandle = app.descendants(matching: .any)["profileFlipHandle"]
        let layerStrip = app.descendants(matching: .any)["layerSelectionStrip"]
        let textLayerButton = app.descendants(matching: .any)["layerSelectionText"]
        let profileLayerButton = app.descendants(matching: .any)["layerSelectionProfile"]
        let textMoveBackwardButton = app.descendants(matching: .any)["layerMoveBackwardText"]
        let textMoveForwardButton = app.descendants(matching: .any)["layerMoveForwardText"]
        let profileMoveBackwardButton = app.descendants(matching: .any)["layerMoveBackwardProfile"]
        let profileMoveForwardButton = app.descendants(matching: .any)["layerMoveForwardProfile"]

        XCTAssertTrue(layerStrip.waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["Selected thumbnail image"].waitForExistence(timeout: 5))
        XCTAssertTrue(textLayerButton.exists)
        XCTAssertTrue(profileLayerButton.exists)
        XCTAssertTrue(textMoveBackwardButton.exists)
        XCTAssertTrue(textMoveForwardButton.exists)
        XCTAssertTrue(profileMoveBackwardButton.exists)
        XCTAssertTrue(profileMoveForwardButton.exists)
        for button in [
            textMoveBackwardButton,
            textMoveForwardButton,
            profileMoveBackwardButton,
            profileMoveForwardButton
        ] {
            assertMinimumHitTarget(button)
        }
        XCTAssertTrue(textFlipHandle.waitForExistence(timeout: 5))
        XCTAssertTrue(textFlipHandle.isHittable)
        XCTAssertFalse(profileFlipHandle.exists)

        profileLayerButton.tap()
        XCTAssertTrue(profileFlipHandle.waitForExistence(timeout: 5))
        XCTAssertTrue(profileFlipHandle.isHittable)
        XCTAssertFalse(textFlipHandle.exists)
        XCTAssertTrue(app.staticTexts["Profile Canvas"].exists)

        let profileLayer = app.descendants(matching: .any)
            .matching(identifier: "profileOverlayLayer")
            .firstMatch
        XCTAssertTrue(profileLayer.waitForExistence(timeout: 5))
        XCTAssertEqual(profileLayer.label, "Profile image overlay")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "premium-layer-selection"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testProfileWYSIWYGGesturesMutateCanvasState() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestSkipHome",
            "-UITestUnlockPremium",
            "-UITestSeedPremiumEditor",
            "-UITestStartPremiumTab",
            "-DisableDraftPersistence"
        ]
        app.launch()

        let profileLayerButton = app.descendants(matching: .any)["layerSelectionProfile"]
        XCTAssertTrue(profileLayerButton.waitForExistence(timeout: 5))
        tap(profileLayerButton)

        let layerIdentifier = "profileOverlayLayer"
        let profileLayer = app.descendants(matching: .any)[layerIdentifier]
        XCTAssertTrue(profileLayer.waitForExistence(timeout: 5))

        var state = stateValue(in: app, identifier: layerIdentifier)
        XCTAssertTrue(state.contains("not flipped"))

        let flipHandle = app.descendants(matching: .any)["profileFlipHandle"]
        XCTAssertTrue(flipHandle.waitForExistence(timeout: 5))
        tap(flipHandle)
        state = waitForStateValueChange(in: app, identifier: layerIdentifier, from: state)
        XCTAssertTrue(state.contains("flipped"))

        drag(profileLayer, by: CGVector(dx: -90, dy: 80))
        state = waitForStateValueChange(in: app, identifier: layerIdentifier, from: state)

        let resizeHandle = app.descendants(matching: .any)["profileResizeHandle"]
        XCTAssertTrue(resizeHandle.waitForExistence(timeout: 5))
        drag(resizeHandle, by: CGVector(dx: 90, dy: 90))
        state = waitForStateValueChange(in: app, identifier: layerIdentifier, from: state)

        let rotateHandle = app.descendants(matching: .any)["profileRotateHandle"]
        XCTAssertTrue(rotateHandle.waitForExistence(timeout: 5))
        drag(rotateHandle, by: CGVector(dx: 90, dy: 0))
        _ = waitForStateValueChange(in: app, identifier: layerIdentifier, from: state)
    }

    @MainActor
    func testPremiumEditorAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestSkipHome",
            "-UITestUnlockPremium",
            "-UITestSeedPremiumEditor",
            "-UITestStartPremiumTab",
            "-DisableDraftPersistence"
        ]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["layerSelectionStrip"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["Selected thumbnail image"].waitForExistence(timeout: 5))

        if #available(iOS 17.0, *) {
            let auditTypes: XCUIAccessibilityAuditType = [
                .elementDetection,
                .hitRegion,
                .sufficientElementDescription,
                .dynamicType,
                .textClipped,
                .trait
            ]
            try app.performAccessibilityAudit(for: auditTypes) { issue in
                let issueDetails = "\(issue.detailedDescription) \(String(describing: issue.element))"
                if issue.auditType == .elementDetection, issue.element == nil {
                    return true
                }
                if issueDetails.contains("overlayTextLayer")
                    || issueDetails.contains("overlayTextPreviewLayer") {
                    return true
                }

                XCTFail(
                    """
                    \(issue.compactDescription)
                    \(issue.detailedDescription)
                    Element: \(String(describing: issue.element))
                    """
                )
                return false
            }
        }
    }

    @MainActor
    func testUndoRedoToolbarButtonsAppear() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-DisableDraftPersistence"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Simple Maker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Undo"].exists)
        XCTAssertTrue(app.buttons["Redo"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "undo-redo-toolbar"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testUndoRedoKeyboardShortcutsRevertOverlayText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-DisableDraftPersistence"]
        app.launch()

        let overlayText = app.textViews["Overlay text"]
        XCTAssertTrue(overlayText.waitForExistence(timeout: 5))

        overlayText.tap()
        overlayText.typeText("Keyboard undo")

        let keyboardDoneButton = app.buttons["overlayTextKeyboardDoneButton"]
        XCTAssertTrue(keyboardDoneButton.waitForExistence(timeout: 5))
        keyboardDoneButton.tap()

        typeHardwareShortcut("z", modifierFlags: .command, in: app) {
            !self.stringValue(of: overlayText).contains("Keyboard undo")
        }
        XCTAssertFalse(stringValue(of: overlayText).contains("Keyboard undo"))

        typeHardwareShortcut("z", modifierFlags: [.command, .shift], in: app) {
            self.stringValue(of: overlayText).contains("Keyboard undo")
        }
        XCTAssertTrue(stringValue(of: overlayText).contains("Keyboard undo"))
    }

    /// Sends a hardware-keyboard shortcut and waits for its effect.
    ///
    /// On a freshly erased simulator, the synthesized hardware key event that
    /// follows on-screen-keyboard typing is intermittently dropped before it
    /// reaches the app (app-side logging showed no `pressesBegan` at all for the
    /// lost press, while a resend is delivered and handled). The shortcut is
    /// re-sent only while its effect is absent, so a real regression in the
    /// app's ⌘Z / ⇧⌘Z handling still fails the assertion that follows.
    private func typeHardwareShortcut(
        _ key: String,
        modifierFlags: XCUIElement.KeyModifierFlags,
        in app: XCUIApplication,
        maxAttempts: Int = 4,
        until effectApplied: () -> Bool
    ) {
        for _ in 0..<maxAttempts {
            app.typeKey(key, modifierFlags: modifierFlags)
            let deadline = Date().addingTimeInterval(1.0)
            while Date() < deadline {
                if effectApplied() { return }
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
        }
    }

    @MainActor
    func testBrandKitEditorOpensFromEditorActions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-DisableDraftPersistence"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Simple Maker"].waitForExistence(timeout: 5))

        // GAPS: the Brand Kit editor lives in the quick-add strip's Library.
        let libraryButton = app.buttons["quickAddLibrary"]
        XCTAssertTrue(libraryButton.waitForExistence(timeout: 5))
        scrollToHittable(libraryButton, in: app, maxSwipes: 6)
        libraryButton.tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))

        let brandKitButton = app.buttons["brandKitButton"]
        XCTAssertTrue(brandKitButton.waitForExistence(timeout: 5))
        scrollToHittable(brandKitButton, in: app, maxSwipes: 6)
        XCTAssertTrue(brandKitButton.isHittable)
        assertMinimumHitTarget(brandKitButton)
        brandKitButton.tap()

        XCTAssertTrue(app.navigationBars["Brand Kit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["brandKitNameField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Text color"].exists)
        XCTAssertTrue(app.staticTexts["Background color"].exists)

        let saveApplyButton = app.buttons["brandKitSaveApplyButton"]
        XCTAssertTrue(saveApplyButton.waitForExistence(timeout: 5))
        assertMinimumHitTarget(saveApplyButton)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "brand-kit-editor"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        saveApplyButton.tap()
        XCTAssertTrue(app.navigationBars["Simple Maker"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTemplateGalleryAppliesBuiltInTemplate() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-DisableDraftPersistence"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Simple Maker"].waitForExistence(timeout: 5))

        let templatesButton = app.buttons["Templates"]
        XCTAssertTrue(templatesButton.waitForExistence(timeout: 5))
        templatesButton.tap()

        XCTAssertTrue(app.navigationBars["Templates"].waitForExistence(timeout: 5))

        let templateCard = app.descendants(matching: .any)["templateCard-youtube-bold-launch"]
        XCTAssertTrue(templateCard.waitForExistence(timeout: 5))
        templateCard.tap()

        let overlayText = app.textViews["Overlay text"]
        XCTAssertTrue(overlayText.waitForExistence(timeout: 5))
        // The template's headline is on the canvas. (This used to match a
        // stray static text inside the small preview; APP-07 folds that
        // artwork text into the preview tile's label, so check the canvas.)
        XCTAssertTrue(
            waitForElementLabel(
                in: app,
                identifier: "overlayTextLayer",
                containing: "BIG REVEAL",
                timeout: 5
            )
        )
        XCTAssertTrue(app.descendants(matching: .any)["layerSelectionStrip"].waitForExistence(timeout: 5))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "template-gallery-applied"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testReadinessSuggestionShortensDenseTitle() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-UITestSeedDenseTitle", "-DisableDraftPersistence"]
        app.launch()

        let overlayText = app.textViews["Overlay text"]
        XCTAssertTrue(overlayText.waitForExistence(timeout: 5))

        let suggestionButton = app.descendants(matching: .any)["suggestionButton-text-shorten-dense-title"]
        scrollToHittable(suggestionButton, in: app, maxSwipes: 6)

        XCTAssertTrue(suggestionButton.waitForExistence(timeout: 5))
        XCTAssertTrue(suggestionButton.isHittable)
        assertMinimumHitTarget(suggestionButton)

        suggestionButton.tap()

        let updatedValue = overlayText.value as? String ?? ""
        XCTAssertFalse(updatedValue.contains("tiny previews"))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "readiness-suggestion-shorten-title"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testTitleIdeaStripShowsAndAppliesVariant() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-UITestSeedDenseTitle", "-DisableDraftPersistence"]
        app.launch()

        let titleIdeasLabel = app.descendants(matching: .any)["titleIdeasLabel"]
        scrollToHittable(titleIdeasLabel, in: app, maxSwipes: 6)
        XCTAssertTrue(titleIdeasLabel.waitForExistence(timeout: 5))

        let ideaCard = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "ideaCard-"))
            .firstMatch
        XCTAssertTrue(ideaCard.waitForExistence(timeout: 5))
        XCTAssertTrue(ideaCard.isHittable)
        assertMinimumHitTarget(ideaCard)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "title-ideas-strip"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        ideaCard.tap()

        XCTAssertTrue(app.textViews["Overlay text"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["layerSelectionStrip"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testExportSizeCheckShowsFileSize() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-UITestSeedSelectedImage", "-DisableDraftPersistence"]
        app.launch()

        let checkButton = app.descendants(matching: .any)["checkExportSizeButton"]
        for _ in 0..<3 where !checkButton.exists {
            app.swipeUp()
        }

        XCTAssertTrue(checkButton.waitForExistence(timeout: 5))
        checkButton.tap()

        let fileSizeLabel = app.descendants(matching: .any)["exportFileSizeLabel"]
        XCTAssertTrue(fileSizeLabel.waitForExistence(timeout: 10))

        let readinessLabel = app.descendants(matching: .any)["creatorReadinessLabel"]
        XCTAssertTrue(readinessLabel.waitForExistence(timeout: 5))
        app.swipeUp()

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "export-size-panel"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testSeededEditorLandscapeLayout() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSkipHome", "-UITestSeedSelectedImage", "-DisableDraftPersistence"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Simple Maker"].waitForExistence(timeout: 5))

        XCUIDevice.shared.orientation = .landscapeRight
        let landscapeDeadline = Date().addingTimeInterval(5)
        while app.frame.width <= app.frame.height && Date() < landscapeDeadline {
            XCUIDevice.shared.orientation = .landscapeRight
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertGreaterThan(app.frame.width, app.frame.height)

        let smallPreviewPanel = app.otherElements["smallPreviewPanel"]
        XCTAssertTrue(smallPreviewPanel.waitForExistence(timeout: 5))

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "seeded-editor-landscape"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testIpadUsesRegularSplitEditorLayouts() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("Requires an iPad simulator.")
        }

        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestSkipHome",
            "-UITestUnlockPremium",
            "-UITestSeedSelectedImage",
            "-UITestSeedPremiumEditor",
            "-DisableDraftPersistence"
        ]
        app.launch()

        let simpleRegularLayout = app.descendants(matching: .any)["simpleRegularEditorLayout"]
        XCTAssertTrue(simpleRegularLayout.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["simpleCompactEditorLayout"].exists)
        assertInspectorStartsAfterCanvasMajority(
            in: app,
            inspectorControl: app.descendants(matching: .any)["layerSelectionStrip"]
        )

        let simpleScreenshot = XCTAttachment(screenshot: app.screenshot())
        simpleScreenshot.name = "ipad-simple-regular-editor-layout"
        simpleScreenshot.lifetime = .keepAlways
        add(simpleScreenshot)

        switchToPremiumTab(in: app)

        let premiumRegularLayout = app.descendants(matching: .any)["premiumRegularEditorLayout"]
        XCTAssertTrue(premiumRegularLayout.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["premiumCompactEditorLayout"].exists)
        let premiumSettingsButton = app.buttons["settingsButton"]
        XCTAssertTrue(premiumSettingsButton.waitForExistence(timeout: 5))
        XCTAssertEqual(premiumSettingsButton.label, "Settings")
        assertInspectorStartsAfterCanvasMajority(
            in: app,
            inspectorControl: app.descendants(matching: .any)["layerSelectionStrip"]
        )

        let premiumScreenshot = XCTAttachment(screenshot: app.screenshot())
        premiumScreenshot.name = "ipad-premium-regular-editor-layout"
        premiumScreenshot.lifetime = .keepAlways
        add(premiumScreenshot)
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                let app = XCUIApplication()
                app.launchArguments = ["-UITestSkipHome", "-DisableDraftPersistence"]
                app.launch()
            }
        }
    }

    private func scrollToHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 4
    ) {
        for _ in 0..<maxSwipes where !element.isHittable {
            app.swipeUp()
        }
    }

    private func scrollLayerStripToVisible(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = 4,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let layerStrip = app.descendants(matching: .any)["layerSelectionStrip"]
        XCTAssertTrue(layerStrip.waitForExistence(timeout: 5), file: file, line: line)

        for _ in 0..<maxSwipes where !isVisibleInLayerStrip(element, layerStrip: layerStrip, app: app) {
            layerStrip.swipeLeft()
        }

        for _ in 0..<maxSwipes where !isVisibleInLayerStrip(element, layerStrip: layerStrip, app: app) {
            layerStrip.swipeRight()
        }

        XCTAssertTrue(isVisibleInLayerStrip(element, layerStrip: layerStrip, app: app), file: file, line: line)
    }

    private func isVisibleInLayerStrip(
        _ element: XCUIElement,
        layerStrip: XCUIElement,
        app: XCUIApplication
    ) -> Bool {
        guard element.exists else { return false }

        let frame = element.frame
        guard !frame.isNull, !frame.isEmpty, !frame.isInfinite else { return false }

        let clippedFrame = frame
            .intersection(layerStrip.frame)
            .intersection(app.frame)
        return !clippedFrame.isNull
            && !clippedFrame.isEmpty
            && clippedFrame.width >= 8
            && clippedFrame.height >= 8
    }

    private func assertMinimumHitTarget(
        _ element: XCUIElement,
        minimum: CGFloat = 44,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let roundingTolerance: CGFloat = 0.5
        XCTAssertGreaterThanOrEqual(element.frame.width + roundingTolerance, minimum, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height + roundingTolerance, minimum, file: file, line: line)
    }

    private func stringValue(of element: XCUIElement) -> String {
        element.value as? String ?? ""
    }

    private func stateValue(
        in app: XCUIApplication,
        identifier: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> String {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        let value = stringValue(of: element)
        XCTAssertFalse(value.isEmpty, "Expected \(identifier) to expose canvas state", file: file, line: line)
        return value
    }

    private func waitForStateValueChange(
        in app: XCUIApplication,
        identifier: String,
        from oldValue: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var latestValue = stateValue(in: app, identifier: identifier, file: file, line: line)

        while Date() < deadline {
            latestValue = stringValue(of: app.descendants(matching: .any)[identifier])
            if !latestValue.isEmpty && latestValue != oldValue {
                return latestValue
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        XCTFail(
            "Expected \(identifier) state to change from '\(oldValue)', latest '\(latestValue)'",
            file: file,
            line: line
        )
        return latestValue
    }

    private func waitForElementValueChange(
        in app: XCUIApplication,
        identifier: String,
        from oldValue: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var latestValue = stringValue(of: app.descendants(matching: .any)[identifier])

        while Date() < deadline {
            latestValue = stringValue(of: app.descendants(matching: .any)[identifier])
            if !latestValue.isEmpty && latestValue != oldValue {
                return latestValue
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        XCTFail(
            "Expected element value to change from '\(oldValue)', latest '\(latestValue)'",
            file: file,
            line: line
        )
        return latestValue
    }

    private func tap(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func drag(
        _ element: XCUIElement,
        by offset: CGVector,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.08, thenDragTo: start.withOffset(offset))
    }

    private func selectContentLayer(
        in app: XCUIApplication,
        buttonIdentifier: String,
        layerIdentifier: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let layerStrip = app.descendants(matching: .any)["layerSelectionStrip"]
        XCTAssertTrue(layerStrip.waitForExistence(timeout: 5), file: file, line: line)

        let layerButton = app.descendants(matching: .any)[buttonIdentifier]
        XCTAssertTrue(layerButton.waitForExistence(timeout: 5), file: file, line: line)
        scrollLayerStripToVisible(layerButton, in: app, file: file, line: line)
        tap(layerButton)

        let layer = app.descendants(matching: .any)[layerIdentifier]
        XCTAssertTrue(layer.waitForExistence(timeout: 5), file: file, line: line)
        return layer
    }

    private func waitForElementCount(
        in app: XCUIApplication,
        identifierPrefix: String,
        equals expectedCount: Int,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", identifierPrefix)
        let query = app.descendants(matching: .any).matching(predicate)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if query.count == expectedCount {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        return query.count == expectedCount
    }

    private func waitForElementToDisappear(
        in app: XCUIApplication,
        identifier: String,
        timeout: TimeInterval = 5
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if !app.descendants(matching: .any)[identifier].exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        return !app.descendants(matching: .any)[identifier].exists
    }

    private func waitForElementLabel(
        in app: XCUIApplication,
        identifier: String,
        containing expectedText: String,
        timeout: TimeInterval = 5
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if app.descendants(matching: .any)[identifier].label.contains(expectedText) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        return app.descendants(matching: .any)[identifier].label.contains(expectedText)
    }

    private func switchToPremiumTab(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // SHELL: the Premium editor is now reached from the Create home.
        let homeButton = app.buttons["showHomeButton"]
        XCTAssertTrue(homeButton.waitForExistence(timeout: 5), file: file, line: line)
        tap(homeButton)
        let proEditorButton = app.buttons["openProEditorButton"]
        XCTAssertTrue(proEditorButton.waitForExistence(timeout: 5), file: file, line: line)
        tap(proEditorButton)
    }

    private func assertInspectorStartsAfterCanvasMajority(
        in app: XCUIApplication,
        inspectorControl: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(inspectorControl.waitForExistence(timeout: 5), file: file, line: line)
        let canvasMajorityBoundary = app.frame.minX + app.frame.width * 0.6
        XCTAssertGreaterThan(inspectorControl.frame.minX, canvasMajorityBoundary, file: file, line: line)
    }
}
