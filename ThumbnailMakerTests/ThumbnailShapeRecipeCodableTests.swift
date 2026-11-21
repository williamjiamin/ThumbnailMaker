//
//  ThumbnailShapeRecipeCodableTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-12: arrows/badges/callouts are back-compatible shape layers.
//

import Foundation
import Testing
@testable import ThumbnailMaker

@MainActor
struct ThumbnailShapeRecipeCodableTests {
    private func keys(of data: Data) throws -> Set<String> {
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Set(object.keys)
    }

    @Test func legacyShapeJSONDecodesWithoutRecipeAndReencodesSameKeys() throws {
        for raw in ["rectangle", "ellipse"] {
            let json = """
            {"shapeRawValue":"\(raw)","fillColor":{"red":1,"green":0.82,"blue":0,"alpha":1},\
            "strokeColor":{"red":1,"green":1,"blue":1,"alpha":1},"strokeWidth":0.01,\
            "transform":{"x":0.5,"y":0.5,"rotationDegrees":0,"isFlippedHorizontally":false},\
            "width":0.34,"height":0.22}
            """
            let data = Data(json.utf8)
            let decoded = try JSONDecoder().decode(ThumbnailShapeLayerContent.self, from: data)
            #expect(decoded.geometry == nil)
            #expect(decoded.label == nil)
            #expect(decoded.shapeKind.rawValue == raw)

            let reencoded = try JSONEncoder().encode(decoded)
            let reencodedKeys = try keys(of: reencoded)
            #expect(!reencodedKeys.contains("geometry"))
            #expect(!reencodedKeys.contains("label"))
            #expect(reencodedKeys == (try keys(of: data)))
        }
    }

    @Test func unknownKindFallsBackToRectangleButKeepsRawValue() throws {
        var content = ThumbnailShapeLayerContent()
        content.shapeRawValue = "hexagon"
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(ThumbnailShapeLayerContent.self, from: data)
        #expect(decoded.shapeKind == .rectangle)
        #expect(decoded.shapeRawValue == "hexagon")
    }

    @Test func everyNewKindRoundTripsWithRecipeAndLabel() throws {
        let kinds: [ThumbnailShapeKind] = [.arrow, .line, .pill, .burst, .callout]
        for kind in kinds {
            let content = ThumbnailShapeLayerContent(
                shapeKind: kind,
                strokeColor: nil,
                geometry: ThumbnailShapeGeometryRecipe(
                    startHead: .dot, endHead: .open, shaftThickness: 0.3, headLength: 0.2, headWidth: 0.8,
                    curvature: -0.4, cornerRadius: 0.3, burstPoints: 9, burstInnerRatio: 0.6,
                    tailDirection: .topRight, tailLength: 0.2, tailWidth: 0.1
                ),
                label: ThumbnailShapeLabel(text: "Hi", fontRawValue: CustomFont.oswald.rawValue, sizeFraction: 0.3, isBold: false)
            )
            let decoded = try JSONDecoder().decode(
                ThumbnailShapeLayerContent.self,
                from: try JSONEncoder().encode(content)
            )
            #expect(decoded == content, "kind \(kind.rawValue) must round-trip")
        }
    }

    @Test func partialLabelJSONFillsDefaults() throws {
        let label = try JSONDecoder().decode(ThumbnailShapeLabel.self, from: Data(#"{"text":"NEW"}"#.utf8))
        #expect(label.text == "NEW")
        #expect(label.font == .goNoto)
        #expect(label.isBold)
        let badFont = try JSONDecoder().decode(ThumbnailShapeLabel.self, from: Data(#"{"text":"x","fontRawValue":"Nope"}"#.utf8))
        #expect(badFont.font == .goNoto)
    }

    @Test func outOfRangeRecipeValuesClamp() {
        var recipe = ThumbnailShapeGeometryRecipe(
            curvature: 5, burstPoints: 99, tailLength: -1
        )
        recipe.shaftThickness = .nan
        recipe.startHeadRawValue = "laser"
        let resolved = recipe.resolved(for: .line)
        #expect(resolved.burstPoints == 24)
        #expect(resolved.curvature == 1)
        #expect(resolved.tailLength == 0)
        #expect(resolved.shaftThickness == ThumbnailResolvedShapeGeometry.defaults(for: .line).shaftThickness)
        #expect(resolved.startHead == .none, "Unknown head styles fall back to the kind default.")
        #expect(ThumbnailShapeGeometryRecipe(burstPoints: 1).resolved(for: .burst).burstPoints == 5)
    }

    @Test func documentWithCalloutRoundTripsThroughProjectStore() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }

        var configuration = SimpleMakerConfigurationModel()
        let calloutID = configuration.layers.addShapeLayer(content: ThumbnailCalloutPreset.speechCallout.content())
        let arrowID = configuration.layers.addShapeLayer(content: ThumbnailCalloutPreset.curvedArrow.content())
        let document = configuration.document

        let json = try JSONDecoder().decode(ThumbnailDocument.self, from: try JSONEncoder().encode(document))
        #expect(json == document)

        let store = ThumbnailProjectStore(rootDirectory: root.appendingPathComponent("Projects", isDirectory: true))
        let id = UUID()
        try store.saveDocument(document, id: id)
        let loaded = try store.loadDocument(id: id)
        #expect(loaded.layers == document.layers)

        let callout = try #require(loaded.layers.record(id: calloutID))
        guard case .shape(let calloutContent) = callout.content else {
            Issue.record("Callout layer must stay a shape")
            return
        }
        #expect(calloutContent.shapeKind == .callout)
        #expect(calloutContent.label?.text == "Wait...")
        #expect(calloutContent.resolvedGeometry.tailDirection == .bottomLeft)

        let arrow = try #require(loaded.layers.record(id: arrowID))
        guard case .shape(let arrowContent) = arrow.content else {
            Issue.record("Arrow layer must stay a shape")
            return
        }
        #expect(arrowContent.resolvedGeometry.curvature == 0.45)
    }

    @Test func legacyAddShapeLayerStillHasNoRecipe() {
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: false, hasProfile: false)
        let id = layers.addShapeLayer(shapeKind: .rectangle)
        guard case .shape(let content) = layers.record(id: id)?.content else {
            Issue.record("expected a shape")
            return
        }
        #expect(content.geometry == nil)
        #expect(content.label == nil)
        #expect(layers.record(id: id)?.name == "Rectangle 1")
    }
}
