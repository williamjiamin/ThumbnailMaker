//
//  ThumbnailShapePathBuilderTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-12: pure path geometry for every shape kind.
//

import CoreGraphics
import SwiftUI
import Testing
@testable import ThumbnailMaker

@MainActor
struct ThumbnailShapePathBuilderTests {
    private func content(
        _ kind: ThumbnailShapeKind,
        _ geometry: ThumbnailShapeGeometryRecipe? = nil
    ) -> ThumbnailShapeLayerContent {
        ThumbnailShapeLayerContent(shapeKind: kind, geometry: geometry)
    }

    private func isFinite(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite
    }

    @Test func everyKindStaysInsideItsBoxAtEverySize() {
        let sizes = [CGSize(width: 1, height: 1), CGSize(width: 8, height: 8),
                     CGSize(width: 200, height: 60), CGSize(width: 60, height: 200)]
        var contents = ThumbnailShapeKind.allCases.map { content($0) }
        contents += ThumbnailCalloutPreset.allCases.map { $0.content() }
        contents.append(content(.line, ThumbnailShapeGeometryRecipe(startHead: .open, endHead: .dot, curvature: -1)))
        contents.append(content(.callout, ThumbnailShapeGeometryRecipe(tailDirection: .topRight, tailLength: 0.45)))
        for size in sizes {
            let rect = CGRect(origin: CGPoint(x: 10, y: 20), size: size)
            for item in contents {
                let path = ThumbnailShapePathBuilder.path(for: item, in: rect, lineWidth: 2)
                let bounds = path.boundingRect
                #expect(!path.isEmpty, "\(item.shapeRawValue) at \(size.width)x\(size.height) must draw")
                #expect(isFinite(bounds), "\(item.shapeRawValue) at \(size.width)x\(size.height) has NaN")
                #expect(rect.insetBy(dx: -0.5, dy: -0.5).contains(bounds),
                        "\(item.shapeRawValue) at \(size.width)x\(size.height) escapes: \(bounds.debugDescription)")
                let label = ThumbnailShapePathBuilder.labelRect(for: item, in: rect)
                #expect(isFinite(label) && label.width > 0 && label.height > 0)
            }
        }
    }

    @Test func blockArrowTipAndShaft() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 60)
        let arrow = content(.arrow, ThumbnailShapeGeometryRecipe(shaftThickness: 0.4, headLength: 0.3, headWidth: 1))
        let path = ThumbnailShapePathBuilder.path(for: arrow, in: rect)
        #expect(path.contains(CGPoint(x: 198, y: 30)), "Near the tip is inside")
        #expect(path.contains(CGPoint(x: 20, y: 30)), "Shaft center is inside")
        #expect(!path.contains(CGPoint(x: 20, y: 5)), "Above the shaft, before the head, is outside")
        #expect(path.contains(CGPoint(x: 145, y: 5)), "The head is wider than the shaft")

        let single = path.boundingRect
        #expect(single.minX == 0 && single.maxX == 200)

        let double = ThumbnailShapePathBuilder.path(
            for: content(.arrow, ThumbnailShapeGeometryRecipe(startHead: .triangle, endHead: .triangle)),
            in: rect
        )
        #expect(double.contains(CGPoint(x: 2, y: 30)))
        #expect(!double.contains(CGPoint(x: 2, y: 5)), "The start head is pointed, not square")
    }

    @Test func lineCurvatureBendsTheMidpoint() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let straight = ThumbnailShapePathBuilder.paths(
            for: content(.line, ThumbnailShapeGeometryRecipe(startHead: ThumbnailArrowheadStyle.none, endHead: ThumbnailArrowheadStyle.none, curvature: 0)),
            in: rect, lineWidth: 4
        ).body
        #expect(abs(straight.boundingRect.midY - 50) < 0.01)
        #expect(straight.boundingRect.height < 0.01)

        let curved = ThumbnailShapePathBuilder.paths(
            for: content(.line, ThumbnailShapeGeometryRecipe(startHead: ThumbnailArrowheadStyle.none, endHead: ThumbnailArrowheadStyle.none, curvature: 0.5)),
            in: rect, lineWidth: 4
        ).body
        // Midpoint of a quadratic sits halfway to the control point: 0.5 * 0.45 * height above the chord.
        #expect(abs(curved.boundingRect.minY - (50 - 0.5 * 0.45 * 100)) < 1)
        #expect(abs(curved.boundingRect.maxY - 50) < 0.5)
    }

    @Test func lineHeadStylesChangeHeads() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 60)
        let none = ThumbnailShapePathBuilder.paths(
            for: content(.line, ThumbnailShapeGeometryRecipe(startHead: ThumbnailArrowheadStyle.none, endHead: ThumbnailArrowheadStyle.none)),
            in: rect, lineWidth: 4
        )
        #expect(none.filledHeads.isEmpty && none.strokedHeads.isEmpty)

        let triangle = ThumbnailShapePathBuilder.paths(
            for: content(.line, ThumbnailShapeGeometryRecipe(startHead: ThumbnailArrowheadStyle.none, endHead: .triangle)),
            in: rect, lineWidth: 4
        )
        #expect(!triangle.filledHeads.isEmpty)
        #expect(triangle.filledHeads.boundingRect.maxX > 190)
        #expect(triangle.body.boundingRect.maxX < triangle.filledHeads.boundingRect.maxX,
                "The shaft is trimmed under a solid head")

        let open = ThumbnailShapePathBuilder.paths(
            for: content(.line, ThumbnailShapeGeometryRecipe(startHead: .open, endHead: .dot)),
            in: rect, lineWidth: 4
        )
        #expect(!open.strokedHeads.isEmpty)
        #expect(!open.filledHeads.isEmpty)
        #expect(open.strokedHeads.boundingRect.minX < 10)
    }

    @Test func burstHasTwoVerticesPerPoint() {
        for points in [5, 12, 24] {
            let path = ThumbnailShapePathBuilder.path(
                for: content(.burst, ThumbnailShapeGeometryRecipe(burstPoints: points)),
                in: CGRect(x: 0, y: 0, width: 100, height: 100)
            )
            var vertices = 0
            path.forEach { element in
                switch element {
                case .move, .line: vertices += 1
                default: break
                }
            }
            #expect(vertices == points * 2)
        }
    }

    @Test func calloutTailPointsTheRightWay() throws {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 120)
        let callout = content(.callout, ThumbnailShapeGeometryRecipe(tailDirection: .bottomLeft, tailLength: 0.25))
        let body = ThumbnailShapePathBuilder.bodyRect(for: callout, in: rect)
        let tip = try #require(ThumbnailShapePathBuilder.calloutTailTip(for: callout, in: rect))
        #expect(tip.y > body.maxY)
        #expect(tip.x <= body.minX + 0.001)
        #expect(abs(body.height - 90) < 0.001)

        let label = ThumbnailShapePathBuilder.labelRect(for: callout, in: rect)
        #expect(body.contains(label))

        let path = ThumbnailShapePathBuilder.path(for: callout, in: rect)
        #expect(path.contains(CGPoint(x: 100, y: 45)), "Body center is filled")
        #expect(path.boundingRect.maxY > 118, "Tail reaches the bottom of the box")
        #expect(!path.contains(CGPoint(x: 195, y: 115)), "Opposite bottom corner is empty")

        let noTail = content(.callout, ThumbnailShapeGeometryRecipe(tailDirection: ThumbnailCalloutTailDirection.none))
        #expect(ThumbnailShapePathBuilder.bodyRect(for: noTail, in: rect) == rect)
        #expect(ThumbnailShapePathBuilder.calloutTailTip(for: noTail, in: rect) == nil)

        let top = content(.callout, ThumbnailShapeGeometryRecipe(tailDirection: .top))
        let topTip = try #require(ThumbnailShapePathBuilder.calloutTailTip(for: top, in: rect))
        #expect(topTip == CGPoint(x: 100, y: 0))
        #expect(ThumbnailShapePathBuilder.bodyRect(for: top, in: rect).minY > 0)
    }
}
