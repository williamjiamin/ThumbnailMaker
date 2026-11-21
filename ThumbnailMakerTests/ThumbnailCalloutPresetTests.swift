//
//  ThumbnailCalloutPresetTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-12: preset catalog invariants.
//

import Foundation
import Testing
@testable import ThumbnailMaker

@MainActor
struct ThumbnailCalloutPresetTests {
    @Test func everyPresetIsValidAndFitsTheCanvasLimits() {
        let ids = ThumbnailCalloutPreset.allCases.map(\.id)
        #expect(Set(ids).count == ids.count)
        for preset in ThumbnailCalloutPreset.allCases {
            let content = preset.content()
            #expect(content.shapeKind == preset.kind, "\(preset.id) kind")
            #expect(ContentLayerCanvasGeometry.shapeWidthLimits.contains(CGFloat(content.width)), "\(preset.id) width")
            #expect(ContentLayerCanvasGeometry.shapeHeightLimits.contains(CGFloat(content.height)), "\(preset.id) height")
            #expect(content.transform == .centered)
            if let label = content.label {
                #expect(content.shapeKind.supportsLabel)
                #expect(label.text.count <= ThumbnailShapeLabel.characterLimit)
            }
        }
        for family in ThumbnailCalloutPreset.Family.allCases {
            #expect(!ThumbnailCalloutPreset.presets(in: family).isEmpty)
        }
    }

    @Test func brandAccentReplacesTheMainColor() {
        let accent = ThumbnailDocumentColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 1)
        for preset in ThumbnailCalloutPreset.allCases {
            let content = preset.content(accent: accent)
            if preset.accentTargetsStroke {
                #expect(content.strokeColor == accent, "\(preset.id) stroke")
                #expect(content.fillColor != accent)
            } else {
                #expect(content.fillColor == accent, "\(preset.id) fill")
            }
            if let label = content.label {
                #expect(label.color == ThumbnailCalloutPreset.white, "Dark accent gets a white label")
            }
        }
        let light = ThumbnailDocumentColor(red: 1, green: 0.95, blue: 0.6, alpha: 1)
        #expect(ThumbnailCalloutPreset.newBadge.content(accent: light).label?.color == ThumbnailCalloutPreset.black)
    }

    @Test func highlightCircleUsesOnlyLegacyRendering() {
        let content = ThumbnailCalloutPreset.highlightCircle.content()
        #expect(content.shapeKind == .ellipse)
        #expect(content.geometry == nil)
        #expect(content.label == nil)
        #expect(content.fillColor.alpha == 0)
    }

    @Test func restyleKeepsColorsPlacementAndLabel() {
        var content = ThumbnailCalloutPreset.speechCallout.content()
        content.transform = ThumbnailOverlayTransform(x: 0.2, y: 0.7, rotationDegrees: 12)
        content.fillColor = ThumbnailCalloutPreset.red
        content.label?.text = "Mine"
        let restyled = ThumbnailCalloutPreset.rectCallout.restyle(content)
        #expect(restyled.transform == content.transform)
        #expect(restyled.fillColor == ThumbnailCalloutPreset.red)
        #expect(restyled.label?.text == "Mine")
        #expect(restyled.resolvedGeometry.tailDirection == .bottom)

        let toLine = ThumbnailCalloutPreset.pointerLine.restyle(ThumbnailCalloutPreset.arrowRight.content())
        #expect(toLine.shapeKind == .line)
        #expect(toLine.strokeColor == nil)
        let backToArrow = ThumbnailCalloutPreset.doubleArrow.restyle(toLine)
        #expect(backToArrow.shapeKind == .arrow)
        #expect(backToArrow.strokeColor != nil)
    }

    @Test func addShapeLayerNamesByFamilyAndStacksOnTop() throws {
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: true, hasProfile: false)
        let topBefore = layers.map(\.zIndex).max() ?? 0
        let first = layers.addShapeLayer(content: ThumbnailCalloutPreset.arrowRight.content())
        let second = layers.addShapeLayer(content: ThumbnailCalloutPreset.curvedArrow.content())
        let badge = layers.addShapeLayer(content: ThumbnailCalloutPreset.burstBadge.content())
        #expect(layers.record(id: first)?.name == "Arrow 1")
        #expect(layers.record(id: second)?.name == "Arrow 2")
        #expect(layers.record(id: badge)?.name == "Badge 1")
        let firstLayer = try #require(layers.record(id: first))
        #expect(firstLayer.kind == .shape)
        #expect(firstLayer.zIndex > topBefore)
        #expect(firstLayer.content == .shape(ThumbnailCalloutPreset.arrowRight.content()))
        #expect(layers.last?.id == badge)
    }

    @Test func duplicateKeepsRecipeAndLabel() throws {
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: false, hasProfile: false)
        let id = layers.addShapeLayer(content: ThumbnailCalloutPreset.newBadge.content())
        let duplicatedID = layers.duplicateContentLayer(id: id)
        let copyID = try #require(duplicatedID)
        guard case .shape(let original) = layers.record(id: id)?.content,
              case .shape(let copy) = layers.record(id: copyID)?.content else {
            Issue.record("expected shapes")
            return
        }
        #expect(copy.geometry == original.geometry)
        #expect(copy.label == original.label)
        #expect(copy.shapeKind == .pill)
    }

    @Test func layerStyleApplicationKeepsRecipe() {
        let content = ThumbnailCalloutPreset.speechCallout.content()
        let style = ThumbnailLayerStyle(id: "s", name: "Red", target: .shape, fillColor: ThumbnailCalloutPreset.red)
        let styled = style.applied(to: content)
        #expect(styled.fillColor == ThumbnailCalloutPreset.red)
        #expect(styled.geometry == content.geometry)
        #expect(styled.label == content.label)
    }
}
