//
//  ThumbnailFormatReflowTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-09: the proposal engine keeps visual intent across sizes.
//

import CoreGraphics
import Foundation
import Testing
@testable import ThumbnailMaker

@MainActor
struct ThumbnailFormatReflowTests {
    private func master(
        text: String = "Hi",
        ratio: AspectRatio = .ratio16_9,
        recipe: ThumbnailImageFrameRecipe = .identity
    ) -> ThumbnailDocument {
        var document = ProjectTestSupport.simpleDocument(text: text, ratio: ratio)
        document.imageRecipe = recipe
        return document
    }

    @Test func legacyTextKeepsItsSizeRelativeToTheShortSide() throws {
        let format = ThumbnailFormatReflow.propose(master: master(), kind: .vertical, sourceImageSize: nil)
        let size = try #require(format.layout[ThumbnailDocumentLayer.textID]?.size)
        // 0.15 of a 576pt-high landscape == 0.084375 of a 1024pt-high vertical.
        #expect(abs(size - 0.084375) < 0.0001)
    }

    @Test func longTitlesShrinkToFitButNeverBelowTheMinimum() throws {
        let medium = ThumbnailFormatReflow.propose(master: master(text: "Medium title here"), kind: .square, sourceImageSize: nil)
        let mediumSize = try #require(medium.layout[ThumbnailDocumentLayer.textID]?.size)
        let canvas = ThumbnailFormatKind.square.canvasSize
        let width = ThumbnailFormatReflow.naturalTextWidth(value: "Medium title here", size: CGFloat(mediumSize), style: nil, canvasSize: canvas)
        #expect(mediumSize < 0.15)
        #expect(CGFloat(mediumSize) > ContentLayerCanvasGeometry.textSizeLimits.lowerBound)
        #expect(width <= canvas.width * ThumbnailFormatReflow.textWidthBudget + 0.5)

        let long = ThumbnailFormatReflow.propose(
            master: master(text: "This is a very long thumbnail title that cannot fit"),
            kind: .vertical,
            sourceImageSize: nil
        )
        let longSize = try #require(long.layout[ThumbnailDocumentLayer.textID]?.size)
        #expect(CGFloat(longSize) == ContentLayerCanvasGeometry.textSizeLimits.lowerBound)
    }

    @Test func imageLayersKeepSizeAndShapesKeepPixelAspect() throws {
        var document = master()
        let imageData = try #require(ProjectTestSupport.makeImage(size: CGSize(width: 40, height: 20)).pngData())
        let imageID = document.layers.addImageLayer(imageData: imageData, size: 0.3)
        let shapeID = document.layers.addShapeLayer(width: 0.34, height: 0.22)

        let format = ThumbnailFormatReflow.propose(
            master: document,
            kind: .vertical,
            sourceImageSize: nil,
            layerImageSizes: [imageID: CGSize(width: 40, height: 20)]
        )
        #expect(format.layout[imageID]?.size == 0.3)

        let shape = try #require(format.layout[shapeID])
        let source = ThumbnailFormatReflow.canvasSize(of: document)
        let target = ThumbnailFormatKind.vertical.canvasSize
        let sourceAspect = (0.34 * source.width) / (0.22 * source.height)
        let targetAspect = (CGFloat(shape.width ?? 0) * target.width) / (CGFloat(shape.height ?? 1) * target.height)
        #expect(abs(sourceAspect - targetAspect) < 0.001)
        #expect(ContentLayerCanvasGeometry.shapeWidthLimits.contains(CGFloat(shape.width ?? 0)))
        #expect(ContentLayerCanvasGeometry.shapeHeightLimits.contains(CGFloat(shape.height ?? 0)))
    }

    @Test func positionsArePulledInsideTheTargetSafeZone() throws {
        var document = master()
        let shapeID = document.layers.addShapeLayer(
            transform: ThumbnailOverlayTransform(x: 0.95, y: 0.95),
            width: 0.2,
            height: 0.2
        )
        let format = ThumbnailFormatReflow.propose(master: document, kind: .square, sourceImageSize: nil)
        let geometry = try #require(format.layout[shapeID])
        let canvas = ThumbnailFormatKind.square.canvasSize
        let safe = try #require(ThumbnailFormatKind.square.preset.safeZone).contentRect(in: canvas)
        let frame = CGSize(width: canvas.width * CGFloat(geometry.width ?? 0), height: canvas.height * CGFloat(geometry.height ?? 0))
        let rect = CGRect(
            x: geometry.transform.x * canvas.width - frame.width / 2,
            y: geometry.transform.y * canvas.height - frame.height / 2,
            width: frame.width,
            height: frame.height
        )
        #expect(safe.insetBy(dx: -0.5, dy: -0.5).contains(rect))
        #expect(geometry.transform.x < 0.95)
    }

    @Test func profileIsRescaledFromWidthToShortSide() throws {
        var premium = PremiumMakerConfigurationModel()
        premium.overlayText = "Premium"
        premium.circularProfile = CircularProfileConfig(image: ProjectTestSupport.makeImage(), size: 0.12)
        let document = premium.document
        let format = ThumbnailFormatReflow.propose(master: document, kind: .vertical, sourceImageSize: nil)
        let size = try #require(format.layout[ThumbnailDocumentLayer.profileID]?.size)
        // 0.12 of a 1024-wide canvas == 0.2133 of a 576-wide canvas.
        #expect(abs(size - 0.12 * 1024 / 576) < 0.0001)
    }

    @Test func fillRecipesKeepTheirFocalPoint() {
        let recipe = ThumbnailImageFrameRecipe(fit: .fill, focusX: 0.8, focusY: 0.3, zoom: 1)
        let format = ThumbnailFormatReflow.propose(
            master: master(recipe: recipe),
            kind: .vertical,
            sourceImageSize: CGSize(width: 1600, height: 900)
        )
        #expect(format.imageRecipe.fit == .fill)
        #expect(abs(format.imageRecipe.focusX - 0.8) < 0.0001)
        #expect(abs(format.imageRecipe.focusY - 0.3) < 0.0001)
        #expect(format.imageRecipe.zoom == 1)
    }

    @Test func letterboxedPhotosSwitchToFillOnlyWhenTheyWouldLookEmpty() {
        let vertical = ThumbnailFormatReflow.propose(
            master: master(),
            kind: .vertical,
            sourceImageSize: CGSize(width: 1600, height: 900)
        )
        #expect(vertical.imageRecipe.fit == .fill, "A landscape photo letterboxed in 9:16 covers too little of the canvas.")
        #expect(abs(vertical.imageRecipe.focusX - 0.5) < 0.0001)

        let landscape = ThumbnailFormatReflow.propose(
            master: master(ratio: .ratio1_1),
            kind: .landscape,
            sourceImageSize: CGSize(width: 1200, height: 900)
        )
        #expect(landscape.imageRecipe == .identity, "A 4:3 photo still fills 75% of 16:9, so it stays letterboxed.")

        let stretch = ThumbnailImageFrameRecipe(fit: .stretch)
        #expect(ThumbnailFormatReflow.propose(
            master: master(recipe: stretch),
            kind: .square,
            sourceImageSize: CGSize(width: 1600, height: 900)
        ).imageRecipe == stretch)

        #expect(ThumbnailFormatReflow.propose(
            master: master(recipe: .fillCentered),
            kind: .square,
            sourceImageSize: nil
        ).imageRecipe == .fillCentered, "Without an image the recipe is carried over unchanged.")
    }

    @Test func proposingNeverChangesTheOriginal() {
        var document = master(text: "Original")
        document.layers.addShapeLayer(transform: ThumbnailOverlayTransform(x: 0.9, y: 0.9))
        let before = ThumbnailDocumentHistory.snapshot(document)
        for kind in ThumbnailFormatKind.allCases {
            _ = ThumbnailFormatReflow.propose(master: document, kind: kind, sourceImageSize: CGSize(width: 10, height: 10))
        }
        #expect(ThumbnailDocumentHistory.snapshot(document) == before)
    }

    @Test func theOriginalsOwnRatioIsNeverOffered() {
        #expect(master(ratio: .ratio16_9).formatKindsAvailableToAdd == [.square, .vertical])
        #expect(master(ratio: .ratio1_1).formatKindsAvailableToAdd == [.landscape, .vertical])
        #expect(master(ratio: .ratio4_3).formatKindsAvailableToAdd == ThumbnailFormatKind.allCases)

        var withSquare = master()
        withSquare.formats = ThumbnailFormatSet(formats: [ThumbnailAlternateFormat(kind: .square)])
        #expect(withSquare.formatKindsAvailableToAdd == [.vertical])
    }
}
