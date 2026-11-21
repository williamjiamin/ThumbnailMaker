//
//  ThumbnailShapeRenderingTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-12: renders arrows/callouts through SwiftUI ImageRenderer, the same
//  renderer ThumbnailExporter uses, and samples pixels.
//

import SwiftUI
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ThumbnailShapeRenderingTests {
    struct Bitmap {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            let i = (y * width + x) * 4
            return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]), Int(bytes[i + 3]))
        }

        func inkCount(in rect: CGRect, where predicate: ((r: Int, g: Int, b: Int, a: Int)) -> Bool) -> Int {
            var count = 0
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) where predicate(pixel(x, y)) {
                    count += 1
                }
            }
            return count
        }
    }

    private func render<V: View>(_ view: V, size: CGSize) throws -> Bitmap {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        renderer.colorMode = .nonLinear
        let cgImage = try #require(renderer.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Bitmap(width: width, height: height, bytes: bytes)
    }

    private let canvas = CGSize(width: 640, height: 360)

    @Test func blockArrowFillsItsShaftAndLeavesCornersEmpty() throws {
        var content = ThumbnailCalloutPreset.arrowRight.content()
        content.strokeColor = nil
        let size = CGSize(width: 200, height: 60)
        let bitmap = try render(ThumbnailShapeRenderView(content: content, canvasSize: canvas, size: size), size: size)
        let center = bitmap.pixel(60, 30)
        #expect(center.a > 240)
        #expect(center.r > 200 && center.g < 80 && center.b < 80, "Shaft is the red fill: \(center)")
        #expect(bitmap.pixel(4, 3).a == 0, "Top-left corner is outside the arrow")
        #expect(bitmap.pixel(4, 56).a == 0, "Bottom-left corner is outside the arrow")
        #expect(bitmap.pixel(195, 30).a > 128, "Tip is drawn")
    }

    @Test func calloutDrawsItsTailAndLabel() throws {
        var content = ThumbnailCalloutPreset.speechCallout.content()
        content.label = ThumbnailShapeLabel(text: "LOOK", color: ThumbnailCalloutPreset.black, sizeFraction: 0.6)
        let size = CGSize(width: 240, height: 160)
        let bitmap = try render(ThumbnailShapeRenderView(content: content, canvasSize: canvas, size: size), size: size)
        let rect = CGRect(origin: .zero, size: size)

        let body = ThumbnailShapePathBuilder.bodyRect(for: content, in: rect)
        let tailProbe = try #require(ThumbnailShapePathBuilder.calloutTailTip(for: content, in: rect))
        // Just inside the tip, along the tail.
        let probe = (Int(tailProbe.x + 12), Int(tailProbe.y - 14))
        #expect(bitmap.pixel(probe.0, probe.1).a > 128, "Tail below the body is drawn")
        #expect(Double(probe.1) > body.maxY)
        #expect(bitmap.pixel(236, 156).a == 0, "Opposite bottom corner stays transparent")

        let labelRect = ThumbnailShapePathBuilder.labelRect(for: content, in: rect)
        let darkInk = bitmap.inkCount(in: labelRect) { $0.a > 200 && $0.r < 90 && $0.g < 90 && $0.b < 90 }
        #expect(darkInk > 30, "Label text is rendered inside the label rect (\(darkInk) dark pixels)")
    }

    @Test func lineArrowStrokesWithItsColor() throws {
        let content = ThumbnailCalloutPreset.pointerLine.content()
        let size = CGSize(width: 200, height: 40)
        let bitmap = try render(ThumbnailShapeRenderView(content: content, canvasSize: canvas, size: size), size: size)
        let mid = bitmap.pixel(100, 20)
        #expect(mid.a > 240 && mid.r > 200 && mid.g < 80, "Line color is the red fill: \(mid)")
        #expect(bitmap.pixel(100, 2).a == 0, "Well above the line is empty")
    }

    @Test func labelViewDrawsNothingForUnlabelledShapes() throws {
        let content = ThumbnailShapeLayerContent(shapeKind: .rectangle)
        let size = CGSize(width: 120, height: 80)
        let bitmap = try render(
            ZStack(alignment: .topLeading) {
                Color.clear
                ThumbnailShapeLabelView(content: content, size: size)
            },
            size: size
        )
        #expect(bitmap.inkCount(in: CGRect(origin: .zero, size: size)) { $0.a > 0 } == 0)
        #expect(ThumbnailShapeAccessibility.label(name: "Rectangle 1", content: content) == "Rectangle 1")

        var labelled = ThumbnailCalloutPreset.speechCallout.content()
        labelled.label?.text = "LOOK"
        #expect(ThumbnailShapeAccessibility.label(name: "Callout 1", content: labelled) == "Callout 1: LOOK")
    }
}
