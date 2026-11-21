//
//  ThumbnailFormatResolverLinkerTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-09: sizes resolve from the original (linked content, own layout)
//  and folding an edit back can never change the original.
//

import CoreGraphics
import Foundation
import Testing
@testable import ThumbnailMaker

@MainActor
struct ThumbnailFormatResolverLinkerTests {
    private struct Fixture {
        var master: ThumbnailDocument
        let shapeID: String
        let textLayerID: String
    }

    private func makeFixture(kind: ThumbnailFormatKind = .vertical) -> Fixture {
        var master = ProjectTestSupport.simpleDocument(text: "Hello")
        let shapeID = master.layers.addShapeLayer(transform: ThumbnailOverlayTransform(x: 0.3, y: 0.7))
        let textLayerID = master.layers.addTextLayer(value: "Sub", transform: ThumbnailOverlayTransform(x: 0.5, y: 0.85))
        let format = ThumbnailFormatReflow.propose(master: master, kind: kind, sourceImageSize: CGSize(width: 1600, height: 900))
        master.formats = ThumbnailFormatSet(formats: [format])
        return Fixture(master: master, shapeID: shapeID, textLayerID: textLayerID)
    }

    @Test func resolvedSizeUsesItsOwnCanvasRecipeAndLayout() throws {
        let fixture = makeFixture()
        let format = try #require(fixture.master.formats?.format(id: "vertical"))
        let resolved = try #require(ThumbnailFormatResolver.resolvedDocument(master: fixture.master, formatID: "vertical"))

        #expect(resolved.formats == nil)
        #expect(resolved.canvas.aspectRatioRawValue == AspectRatio.ratio9_16.rawValue)
        #expect(resolved.imageRecipe == format.imageRecipe)
        #expect(resolved.export.presetID == ThumbnailExportPreset.shortFormCover.id)
        #expect(ThumbnailLayerGeometry.extract(layerID: ThumbnailDocumentLayer.textID, from: resolved) == format.layout[ThumbnailDocumentLayer.textID])
        #expect(ThumbnailLayerGeometry.extract(layerID: fixture.shapeID, from: resolved) == format.layout[fixture.shapeID])
        #expect(resolved.canvas.backgroundColor == fixture.master.canvas.backgroundColor)
        #expect(ThumbnailFormatResolver.resolvedDocument(master: fixture.master, formatID: "square") == nil)
    }

    @Test func linkedContentFollowsTheOriginal() throws {
        var fixture = makeFixture()
        fixture.master.text.value = "Changed in the original"
        fixture.master.text.color = ThumbnailDocumentColor(red: 1, green: 0, blue: 0, alpha: 1)
        fixture.master.layers.updateTextContent(id: fixture.textLayerID) { $0.value = "New sub" }

        let resolved = try #require(ThumbnailFormatResolver.resolvedDocument(master: fixture.master, formatID: "vertical"))
        #expect(resolved.text.value == "Changed in the original")
        #expect(resolved.text.color == fixture.master.text.color)
        #expect(ThumbnailFormatLinker.textValue(fixture.textLayerID, in: resolved) == "New sub")
    }

    @Test func unlinkedTextOverridesTheOriginalUntilRelinked() throws {
        var fixture = makeFixture()
        var set = try #require(fixture.master.formats)
        var format = try #require(set.format(id: "vertical"))
        format.detachedText = [ThumbnailDocumentLayer.textID: "Short", fixture.textLayerID: "Own sub"]
        set.replace(format)
        fixture.master.formats = set

        let detached = try #require(ThumbnailFormatResolver.resolvedDocument(master: fixture.master, formatID: "vertical"))
        #expect(detached.text.value == "Short")
        #expect(ThumbnailFormatLinker.textValue(fixture.textLayerID, in: detached) == "Own sub")
        #expect(fixture.master.text.value == "Hello")

        format.detachedText = [:]
        set.replace(format)
        fixture.master.formats = set
        let relinked = try #require(ThumbnailFormatResolver.resolvedDocument(master: fixture.master, formatID: "vertical"))
        #expect(relinked.text.value == "Hello")
        #expect(ThumbnailFormatLinker.textValue(fixture.textLayerID, in: relinked) == "Sub")
    }

    @Test func hiddenLayersAreHiddenOnlyInTheSize() throws {
        var fixture = makeFixture()
        var set = try #require(fixture.master.formats)
        var format = try #require(set.format(id: "vertical"))
        format.hiddenLayerIDs = [fixture.shapeID]
        set.replace(format)
        fixture.master.formats = set

        let resolved = try #require(ThumbnailFormatResolver.resolvedDocument(master: fixture.master, formatID: "vertical"))
        #expect(resolved.layers.record(id: fixture.shapeID)?.isVisible == false)
        #expect(fixture.master.layers.record(id: fixture.shapeID)?.isVisible == true)
    }

    @Test func layersAddedLaterAreReflowedOnTheFlyAndStaleIDsAreIgnored() throws {
        var fixture = makeFixture()
        let lateID = fixture.master.layers.addShapeLayer(transform: ThumbnailOverlayTransform(x: 0.9, y: 0.1))
        var set = try #require(fixture.master.formats)
        var format = try #require(set.format(id: "vertical"))
        format.layout["deleted-layer"] = ThumbnailLayerGeometry(transform: .centered, width: 0.5, height: 0.5)
        set.replace(format)
        fixture.master.formats = set

        let resolved = try #require(ThumbnailFormatResolver.resolvedDocument(master: fixture.master, formatID: "vertical"))
        let expected = ThumbnailFormatReflow.geometry(for: lateID, master: fixture.master, kind: .vertical)
        #expect(ThumbnailLayerGeometry.extract(layerID: lateID, from: resolved) == expected)
        #expect(resolved.layers.record(id: "deleted-layer") == nil)
    }

    @Test func foldingBackAnyEditNeverChangesTheOriginal() throws {
        let fixture = makeFixture()
        let originalSnapshot = ThumbnailDocumentHistory.snapshot(fixture.master)
        var edited = try #require(ThumbnailFormatResolver.resolvedDocument(master: fixture.master, formatID: "vertical"))
        edited.text.transform = ThumbnailOverlayTransform(x: 0.3, y: 0.2, rotationDegrees: 12)
        edited.text.value = "Typed into a linked layer"
        edited.text.color = ThumbnailDocumentColor(red: 0, green: 1, blue: 0, alpha: 1)
        edited.imageRecipe = ThumbnailImageFrameRecipe(fit: .fill, focusX: 0.1, focusY: 0.9, zoom: 2)
        edited.layers.setVisible(false, for: .content(fixture.shapeID))
        edited.canvas.backgroundColor = ThumbnailDocumentColor(red: 0, green: 0, blue: 1, alpha: 1)
        edited.layers.addShapeLayer(id: "edited-only")

        let set = try #require(ThumbnailFormatLinker.foldBack(master: fixture.master, formatID: "vertical", edited: edited))
        #expect(ThumbnailDocumentHistory.snapshot(fixture.master) == originalSnapshot)

        var next = fixture.master
        next.formats = set
        #expect(
            ThumbnailDocumentHistory.snapshot(next.removingFormats())
                == ThumbnailDocumentHistory.snapshot(fixture.master.removingFormats()),
            "Only the size overrides may change."
        )

        let format = try #require(set.format(id: "vertical"))
        #expect(format.layout[ThumbnailDocumentLayer.textID]?.transform.rotationDegrees == 12)
        #expect(format.imageRecipe == edited.imageRecipe)
        #expect(format.hiddenLayerIDs == [fixture.shapeID])
        #expect(format.detachedText.isEmpty, "A linked text edit is not stored.")
        #expect(format.layout["edited-only"] == nil)

        let resolved = try #require(ThumbnailFormatResolver.resolvedDocument(master: next, formatID: "vertical"))
        #expect(resolved.text.value == "Hello")
        #expect(resolved.text.color == fixture.master.text.color)
        #expect(resolved.canvas.backgroundColor == fixture.master.canvas.backgroundColor)
    }

    @Test func unlinkedTextEditsAreStoredAndClearingRelinks() throws {
        var fixture = makeFixture()
        var edited = try #require(ThumbnailFormatResolver.resolvedDocument(master: fixture.master, formatID: "vertical"))
        edited.text.value = "Vertical title"

        let detachedSet = try #require(ThumbnailFormatLinker.foldBack(
            master: fixture.master,
            formatID: "vertical",
            edited: edited,
            detachedTextLayerIDs: [ThumbnailDocumentLayer.textID]
        ))
        #expect(detachedSet.format(id: "vertical")?.detachedText == [ThumbnailDocumentLayer.textID: "Vertical title"])

        fixture.master.formats = detachedSet
        edited.text.value = ""
        let cleared = try #require(ThumbnailFormatLinker.foldBack(
            master: fixture.master,
            formatID: "vertical",
            edited: edited,
            detachedTextLayerIDs: [ThumbnailDocumentLayer.textID]
        ))
        let format = try #require(cleared.format(id: "vertical"))
        #expect(format.detachedText.isEmpty)
        #expect(!format.isHidden(ThumbnailDocumentLayer.textID), "Clearing unlinked text relinks it instead of hiding the title.")
    }

    @Test func foldBackOfAMissingSizeReturnsNil() {
        let fixture = makeFixture()
        #expect(ThumbnailFormatLinker.foldBack(master: fixture.master, formatID: "square", edited: fixture.master) == nil)
    }
}
