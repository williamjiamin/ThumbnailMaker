//
//  ThumbnailFormatClippingTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-09: informational flags for content a size pushes out of view.
//

import CoreGraphics
import Foundation
import Testing
@testable import ThumbnailMaker

@MainActor
struct ThumbnailFormatClippingTests {
    private func document(ratio: AspectRatio, text: String = "") -> ThumbnailDocument {
        ProjectTestSupport.simpleDocument(text: text, ratio: ratio)
    }

    private func kinds(_ flags: [ThumbnailFormatClipFlag], layerID: String) -> [ThumbnailFormatClipFlag.Kind] {
        flags.filter { $0.layerID == layerID }.map(\.kind)
    }

    @Test func aLayerRunningPastTheEdgeIsFlagged() {
        var resolved = document(ratio: .ratio1_1)
        let id = resolved.layers.addShapeLayer(transform: ThumbnailOverlayTransform(x: 0.95, y: 0.5), width: 0.5, height: 0.2)
        let flags = ThumbnailFormatClipping.analyze(resolved: resolved)
        #expect(kinds(flags, layerID: id) == [.outsideCanvas])
        #expect(flags.first?.message.isEmpty == false)
    }

    @Test func aCenteredLayerHasNoFlags() {
        var resolved = document(ratio: .ratio1_1, text: "Hi")
        resolved.layers.addShapeLayer(width: 0.2, height: 0.2)
        let flags = ThumbnailFormatClipping.analyze(
            resolved: resolved,
            safeZone: ThumbnailFormatKind.square.preset.safeZone
        )
        #expect(flags.isEmpty)
    }

    @Test func insideTheCanvasButOutsideTheSafeZoneIsFlagged() {
        var resolved = document(ratio: .ratio9_16)
        let id = resolved.layers.addShapeLayer(transform: ThumbnailOverlayTransform(x: 0.9, y: 0.5), width: 0.1, height: 0.1)
        let flags = ThumbnailFormatClipping.analyze(
            resolved: resolved,
            safeZone: ThumbnailFormatKind.vertical.preset.safeZone
        )
        #expect(kinds(flags, layerID: id) == [.outsideSafeZone])
    }

    @Test func textStuckAtTheMinimumSizeIsFlagged() {
        var resolved = document(ratio: .ratio9_16, text: "A title that is far too long for a vertical cover")
        resolved.text.size = Double(ContentLayerCanvasGeometry.textSizeLimits.lowerBound)
        let flags = ThumbnailFormatClipping.analyze(resolved: resolved)
        #expect(kinds(flags, layerID: ThumbnailDocumentLayer.textID).contains(.textAtMinimumSize))
    }

    @Test func rotationIsMeasuredWithTheRotatedBoundingBox() {
        var upright = document(ratio: .ratio16_9)
        let id = upright.layers.addShapeLayer(width: 0.9, height: 0.3)
        #expect(ThumbnailFormatClipping.analyze(resolved: upright).isEmpty)

        var rotated = upright
        rotated.layers.updateShapeContent(id: id) { $0.transform.rotationDegrees = 90 }
        #expect(kinds(ThumbnailFormatClipping.analyze(resolved: rotated), layerID: id) == [.outsideCanvas])
    }

    @Test func aLandscapePhotoCroppedIntoAVerticalFillIsFlagged() {
        let master = document(ratio: .ratio16_9)
        var resolved = document(ratio: .ratio9_16)
        resolved.imageRecipe = .fillCentered
        let source = CGSize(width: 1600, height: 900)

        let flags = ThumbnailFormatClipping.analyze(resolved: resolved, master: master, backgroundImageSize: source)
        #expect(kinds(flags, layerID: ThumbnailDocumentLayer.backgroundID) == [.imageSubjectCropped])

        var letterboxed = resolved
        letterboxed.imageRecipe = .identity
        #expect(ThumbnailFormatClipping.analyze(resolved: letterboxed, master: master, backgroundImageSize: source).isEmpty)
    }

    @Test func degenerateInputsProduceNoFlagsAndNoNaN() {
        let master = document(ratio: .ratio16_9)
        let resolved = document(ratio: .ratio9_16)
        #expect(ThumbnailFormatClipping.analyze(resolved: resolved, master: master, backgroundImageSize: .zero).isEmpty)
        #expect(ThumbnailFormatClipping.analyze(resolved: resolved, master: master, backgroundImageSize: nil).isEmpty)
        let coverage = ThumbnailFormatClipping.subjectCoverage(master: master, resolved: resolved, sourceSize: .zero)
        #expect(coverage.isFinite)

        var hidden = document(ratio: .ratio1_1)
        let id = hidden.layers.addShapeLayer(transform: ThumbnailOverlayTransform(x: 0.95, y: 0.5), width: 0.9, height: 0.2)
        hidden.layers.setVisible(false, for: .content(id))
        #expect(ThumbnailFormatClipping.analyze(resolved: hidden).isEmpty, "Hidden layers cannot clip.")
    }
}
