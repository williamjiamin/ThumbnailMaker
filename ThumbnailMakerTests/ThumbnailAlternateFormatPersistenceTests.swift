//
//  ThumbnailAlternateFormatPersistenceTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-09: alternate sizes are optional, lossless and tolerant of bad data.
//

import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ThumbnailAlternateFormatPersistenceTests {
    private func sampleFormat(_ kind: ThumbnailFormatKind) -> ThumbnailAlternateFormat {
        ThumbnailAlternateFormat(
            kind: kind,
            createdAt: Date(timeIntervalSince1970: 1_000),
            imageRecipe: ThumbnailImageFrameRecipe(fit: .fill, focusX: 0.3, focusY: 0.7, zoom: 1.5),
            layout: [
                ThumbnailDocumentLayer.textID: ThumbnailLayerGeometry(
                    transform: ThumbnailOverlayTransform(x: 0.4, y: 0.2, rotationDegrees: 5),
                    size: 0.1
                ),
                "shape-1": ThumbnailLayerGeometry(transform: .centered, width: 0.5, height: 0.2)
            ],
            hiddenLayerIDs: ["shape-1"],
            detachedText: [ThumbnailDocumentLayer.textID: "Own title"]
        )
    }

    private func documentJSON(_ document: ThumbnailDocument) throws -> [String: Any] {
        let data = try JSONEncoder().encode(document)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func documentsWithoutSizesDecodeToNilAndEncodeNoKey() throws {
        let document = ProjectTestSupport.simpleDocument(text: "Old design")
        #expect(document.formats == nil)
        let json = try documentJSON(document)
        #expect(json["formats"] == nil, "A design without sizes must serialize exactly like before FEATURE-09.")

        let decoded = try JSONDecoder().decode(ThumbnailDocument.self, from: JSONEncoder().encode(document))
        #expect(decoded.formats == nil)
        #expect(decoded.version == ThumbnailDocument.currentVersion)
    }

    @Test func threeSizesRoundTripLosslessly() throws {
        var document = ProjectTestSupport.simpleDocument(text: "Title")
        document.updatedAt = Date(timeIntervalSince1970: 1_000_000)
        document.formats = ThumbnailFormatSet(formats: [
            sampleFormat(.vertical),
            sampleFormat(.landscape),
            sampleFormat(.square)
        ])
        let decoded = try JSONDecoder().decode(ThumbnailDocument.self, from: JSONEncoder().encode(document))
        #expect(decoded == document)
        #expect(decoded.formats?.formats.map(\.kind) == [.landscape, .square, .vertical], "Sizes are kept in kind order.")
    }

    @Test func unknownDuplicateAndCorruptEntriesAreNormalized() throws {
        let json = """
        {"formats": [
          {"kindRawValue": "square", "imageRecipe": "garbage", "layout": {"text": {"transform": {"x": 0.3, "y": 0.4, "rotationDegrees": 0, "isFlippedHorizontally": false}, "size": 0.2}}},
          {"kindRawValue": "banana"},
          {"kindRawValue": "square", "detachedText": {"text": "second copy"}},
          {"kindRawValue": "vertical", "hiddenLayerIDs": ["a", "a", "b"]},
          {"layout": 42}
        ]}
        """
        let set = try JSONDecoder().decode(ThumbnailFormatSet.self, from: Data(json.utf8))
        #expect(set.formats.map(\.kind) == [.square, .vertical])
        let square = try #require(set.format(id: "square"))
        #expect(square.imageRecipe == .identity, "A corrupt recipe falls back to the identity framing.")
        #expect(square.detachedText.isEmpty, "The first duplicate wins.")
        #expect(square.layout[ThumbnailDocumentLayer.textID]?.size == 0.2)
        #expect(set.format(id: "vertical")?.hiddenLayerIDs == ["a", "b"])
        #expect(set.formats.count <= ThumbnailFormatSet.maximumCount)
    }

    @Test func aCorruptSizesBlockNeverMakesTheDesignUnopenable() throws {
        let document = ProjectTestSupport.simpleDocument(text: "Keep me")
        var json = try documentJSON(document)
        json["formats"] = 42
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(ThumbnailDocument.self, from: data)
        #expect(decoded.text.value == "Keep me")
        #expect(decoded.formats == nil)
    }

    @Test func nonFiniteGeometryIsClampedWhenApplied() {
        var document = ProjectTestSupport.simpleDocument(text: "Title")
        let geometry = ThumbnailLayerGeometry(
            transform: ThumbnailOverlayTransform(x: .nan, y: 3, rotationDegrees: .infinity),
            size: .nan
        )
        geometry.apply(to: &document, layerID: ThumbnailDocumentLayer.textID)
        #expect(document.text.transform.x == 0.5)
        #expect(document.text.transform.y == 0.95)
        #expect(document.text.transform.rotationDegrees == 0)
        #expect(document.text.size == 0.15, "A non-finite size keeps the current value.")

        ThumbnailLayerGeometry(transform: .centered, size: 9).apply(to: &document, layerID: ThumbnailDocumentLayer.textID)
        #expect(CGFloat(document.text.size) == ContentLayerCanvasGeometry.textSizeLimits.upperBound)
    }

    @Test func simpleAndPremiumConfigurationsCarrySizesVerbatim() {
        let set = ThumbnailFormatSet(formats: [sampleFormat(.square)])

        var simple = SimpleMakerConfigurationModel()
        simple.overlayText = "Simple"
        simple.formatSet = set
        #expect(simple.document.formats == set)
        #expect(SimpleMakerConfigurationModel(document: simple.document).formatSet == set)

        var premium = PremiumMakerConfigurationModel()
        premium.overlayText = "Premium"
        premium.formatSet = set
        #expect(premium.document.formats == set)
        #expect(PremiumMakerConfigurationModel(document: premium.document).formatSet == set)
    }

    @Test func duplicatingAVariantCopiesItsSizes() throws {
        var document = ProjectTestSupport.simpleDocument(text: "Variant")
        document.formats = ThumbnailFormatSet(formats: [sampleFormat(.vertical)])
        var variantSet = ThumbnailVariantSet(seedDocument: document, editorMode: .simple)
        let duplicated = variantSet.duplicateVariant(from: .a)
        let slot = try #require(duplicated)
        #expect(variantSet.document(for: slot)?.formats == document.formats)
    }

    @Test func templatesNeverCaptureSizes() {
        var document = ProjectTestSupport.simpleDocument(text: "Template me")
        document.formats = ThumbnailFormatSet(formats: [sampleFormat(.square)])
        #expect(document.removingFormats().formats == nil)
        #expect(document.removingFormats().text == document.text)

        let template = ThumbnailTemplate.capture(from: document, name: "Mine", category: .youtube)
        #expect(template.document.formats == nil)
    }

    @Test func setMutationsKeepKindsUnique() {
        var set = ThumbnailFormatSet()
        let insertedSquare = set.insert(sampleFormat(.square))
        let insertedDuplicate = set.insert(sampleFormat(.square))
        let insertedLandscape = set.insert(sampleFormat(.landscape))
        #expect(insertedSquare)
        #expect(!insertedDuplicate)
        #expect(insertedLandscape)
        #expect(set.formats.map(\.kind) == [.landscape, .square])
        var edited = sampleFormat(.square)
        edited.hiddenLayerIDs = []
        let replaced = set.replace(edited)
        #expect(replaced)
        #expect(set.format(id: "square")?.hiddenLayerIDs == [])
        let removed = set.remove(id: "square")
        let removedAgain = set.remove(id: "square")
        #expect(removed)
        #expect(!removedAgain)
        #expect(set.formats.count == 1)
    }
}
