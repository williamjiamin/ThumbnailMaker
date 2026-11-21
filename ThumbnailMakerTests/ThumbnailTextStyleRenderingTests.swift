//
//  ThumbnailTextStyleRenderingTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-04: renders StyledThumbnailTextView through SwiftUI ImageRenderer,
//  the same renderer ThumbnailExporter uses for export.
//

import SwiftUI
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ThumbnailTextStyleRenderingTests {

    struct Bitmap {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            let i = (y * width + x) * 4
            return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]), Int(bytes[i + 3]))
        }

        /// Bounding box of pixels whose alpha exceeds `threshold`.
        func inkBounds(alphaThreshold threshold: Int = 32) -> CGRect? {
            var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
            for y in 0..<height {
                for x in 0..<width where pixel(x, y).a > threshold {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            guard maxX >= 0 else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }
    }

    static func render<V: View>(_ view: V, proposed: CGSize? = nil) throws -> Bitmap {
        let renderer = ImageRenderer(content: view)
        if let proposed {
            renderer.proposedSize = ProposedViewSize(proposed)
        }
        renderer.scale = 1
        renderer.colorMode = .nonLinear
        let cgImage = try #require(renderer.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        #expect(drawn)
        return Bitmap(width: width, height: height, bytes: bytes)
    }

    static func preset(_ id: String, role: ThumbnailTextRole = .overlay) throws -> ThumbnailTextStyle {
        try #require(ThumbnailTextStylePreset.all(for: role).first { $0.id == id }?.style)
    }

    // MARK: Legacy exactness

    @Test func legacyOverlayRenderIsUnchanged() throws {
        let canvas = CGSize(width: 350, height: 197)
        let fontSize: CGFloat = 30
        let text = "Legacy Title"

        let styled = ZStack {
            Color.blue
            StyledThumbnailTextView.overlay(
                text: text, font: .goNoto, color: .white, fontSize: fontSize, style: nil, canvasSize: canvas
            )
            .position(x: canvas.width / 2, y: canvas.height / 2)
        }
        .frame(width: canvas.width, height: canvas.height)

        // Literal reconstruction of the pre-FEATURE-04 modifier chain.
        let literal = ZStack {
            Color.blue
            Text(FontManager.shared.getAttributedText(text, selectedFont: .goNoto, size: fontSize, color: .white))
                .truncationMode(.tail)
                .shadow(color: .black, radius: 3, x: 1, y: 1)
                .multilineTextAlignment(.center)
                .frame(width: canvas.width * 0.9)
                .padding(.horizontal, canvas.width * 0.03)
                .padding(.vertical, canvas.height * 0.03)
                .position(x: canvas.width / 2, y: canvas.height / 2)
        }
        .frame(width: canvas.width, height: canvas.height)

        let styledBitmap = try Self.render(styled)
        let literalBitmap = try Self.render(literal)
        #expect(styledBitmap.width == literalBitmap.width)
        #expect(styledBitmap.height == literalBitmap.height)
        #expect(styledBitmap.bytes == literalBitmap.bytes)
    }

    @Test func legacyContentLayerRenderIsUnchanged() throws {
        let canvas = CGSize(width: 400, height: 225)
        let content = ThumbnailTextLayerContent(value: "Layer words", size: 0.15)
        let box = ContentLayerCanvasGeometry.textFrameSize(for: content, resizeTranslation: .zero, canvasSize: canvas)
        let fontSize = canvas.height * 0.15

        let styled = ZStack {
            Color.green
            StyledThumbnailTextView.contentLayer(
                text: content.value, font: .goNoto, color: .white, fontSize: fontSize,
                style: nil, canvasSize: canvas, boxSize: box
            )
        }
        .frame(width: canvas.width, height: canvas.height)

        let literal = ZStack {
            Color.green
            Text(FontManager.shared.getAttributedText(content.value, selectedFont: .goNoto, size: fontSize, color: .white))
                .truncationMode(.tail)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.82), radius: 3, x: 1, y: 1)
                .frame(width: box.width, height: box.height)
        }
        .frame(width: canvas.width, height: canvas.height)

        #expect(try Self.render(styled).bytes == Self.render(literal).bytes)
    }

    @Test func resetRestoresLegacyRenderAndStyleChangesIt() throws {
        let canvas = CGSize(width: 320, height: 180)
        func view(_ style: ThumbnailTextStyle?) -> some View {
            ZStack {
                Color.gray
                StyledThumbnailTextView.overlay(
                    text: "Reset me", font: .roboto, color: .white, fontSize: 30, style: style, canvasSize: canvas
                )
            }
            .frame(width: canvas.width, height: canvas.height)
        }
        let legacy = try Self.render(view(nil))
        let outlined = try Self.render(view(Self.preset("boldOutline")))
        let reset = try Self.render(view(nil))
        #expect(outlined.bytes != legacy.bytes)
        #expect(reset.bytes == legacy.bytes)
    }

    // MARK: Parity + clipping

    @Test func styledRenderScalesWithCanvas() throws {
        let style = try Self.preset("outlineAndShadow")
        func bitmap(scale: CGFloat) throws -> Bitmap {
            let canvas = CGSize(width: 320 * scale, height: 180 * scale)
            return try Self.render(
                StyledThumbnailTextView.overlay(
                    text: "HELLO", font: .roboto, color: .white, fontSize: canvas.height * 0.15,
                    style: style, canvasSize: canvas
                )
            )
        }
        let small = try bitmap(scale: 1)
        let large = try bitmap(scale: 4)
        let widthRatio = Double(large.width) / Double(small.width)
        let heightRatio = Double(large.height) / Double(small.height)
        #expect(abs(widthRatio - 4) < 0.05, "width ratio \(widthRatio)")
        #expect(abs(heightRatio - 4) < 0.15, "height ratio \(heightRatio)")

        let smallInk = try #require(small.inkBounds())
        let largeInk = try #require(large.inkBounds())
        #expect(abs(Double(largeInk.width / smallInk.width) - 4) < 0.25, "ink width ratio")
        #expect(abs(Double(largeInk.height / smallInk.height) - 4) < 0.35, "ink height ratio")
    }

    @Test func outlineAndShadowAreNotClipped() throws {
        var style = try Self.preset("outlineAndShadow")
        style.outlineWidth = 0.15
        style.shadowRadius = 0.2
        style.shadowOffsetX = 0.15
        style.shadowOffsetY = 0.15
        let samples = ["HELLO", "中文標題", "제목", "見出し", "🔥🎉", "Mix 中文 🔥"]
        for sample in samples {
            let bitmap = try Self.render(
                StyledThumbnailTextView.overlay(
                    text: sample, font: .roboto, color: .white, fontSize: 40,
                    style: style, canvasSize: CGSize(width: 640, height: 360)
                )
            )
            let ink = try #require(bitmap.inkBounds(), "no ink for \(sample)")
            #expect(ink.minX > 0, "left clip for \(sample)")
            #expect(ink.minY > 0, "top clip for \(sample)")
            #expect(ink.maxX < CGFloat(bitmap.width), "right clip for \(sample)")
            #expect(ink.maxY < CGFloat(bitmap.height), "bottom clip for \(sample)")
            var borderInk = 0
            for x in 0..<bitmap.width {
                if bitmap.pixel(x, 0).a > 32 { borderInk += 1 }
                if bitmap.pixel(x, bitmap.height - 1).a > 32 { borderInk += 1 }
            }
            for y in 0..<bitmap.height {
                if bitmap.pixel(0, y).a > 32 { borderInk += 1 }
                if bitmap.pixel(bitmap.width - 1, y).a > 32 { borderInk += 1 }
            }
            #expect(borderInk == 0, "ink touches the border for \(sample)")
        }
    }

    @Test func fallbackFontStringStillRendersOutline() throws {
        var style = try Self.preset("boldOutline")
        style.outlineColor = ThumbnailDocumentColor(red: 1, green: 0, blue: 0, alpha: 1)
        style.outlineWidth = 0.1
        let bitmap = try Self.render(
            ZStack {
                Color.black
                StyledThumbnailTextView.overlay(
                    text: "中文", font: .meowScript, color: .white, fontSize: 60,
                    style: style, canvasSize: CGSize(width: 640, height: 360)
                )
            }
        )
        var redPixels = 0
        var whitePixels = 0
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width {
                let p = bitmap.pixel(x, y)
                if p.r > 200 && p.g < 60 && p.b < 60 { redPixels += 1 }
                if p.r > 220 && p.g > 220 && p.b > 220 { whitePixels += 1 }
            }
        }
        #expect(redPixels > 50, "outline pixels \(redPixels)")
        #expect(whitePixels > 50, "fill pixels \(whitePixels)")
    }

    @Test func veryLargeTextRespectsMaxWidthAndLineLimit() throws {
        var style = try Self.preset("outlineAndShadow")
        style.lineLimit = 3
        style.maxWidthFraction = 0.8
        let canvas = CGSize(width: 1280, height: 720)
        let fontSize = canvas.height * ContentLayerCanvasGeometry.textSizeLimits.upperBound
        let view = StyledThumbnailTextView.overlay(
            text: String(repeating: "Long title words ", count: 12),
            font: .roboto, color: .white, fontSize: fontSize, style: style, canvasSize: canvas
        )
        let bitmap = try Self.render(view)
        let expectedWidth = view.resolved.maxWidth + 2 * view.resolved.outerHorizontalInset
        #expect(abs(CGFloat(bitmap.width) - expectedWidth) <= 1)
        // Three lines at most: height stays below 3 line boxes + insets (generous 1.6x line box).
        let maxHeight = fontSize * 1.6 * 3 + 2 * view.resolved.outerVerticalInset
        #expect(CGFloat(bitmap.height) <= maxHeight)
    }

    @Test func panelPresetDrawsBackgroundBehindGlyphs() throws {
        let canvas = CGSize(width: 640, height: 360)
        func bitmap(_ style: ThumbnailTextStyle?) throws -> (Bitmap, ThumbnailResolvedTextStyle) {
            let view = StyledThumbnailTextView.overlay(
                text: "Panel", font: .roboto, color: .white, fontSize: 40, style: style, canvasSize: canvas
            )
            return (try Self.render(view), view.resolved)
        }
        let (panelled, resolved) = try bitmap(Self.preset("panelPill"))
        let sampleX = Int(resolved.outerHorizontalInset / 2)
        let sampleY = panelled.height / 2
        let panelPixel = panelled.pixel(sampleX, sampleY)
        #expect(panelPixel.a > 100, "panel alpha \(panelPixel.a)")
        #expect(panelPixel.r < 20)

        let (legacy, legacyResolved) = try bitmap(nil)
        let legacyPixel = legacy.pixel(Int(legacyResolved.horizontalPadding / 2), legacy.height / 2)
        #expect(legacyPixel.a == 0)
    }
}
