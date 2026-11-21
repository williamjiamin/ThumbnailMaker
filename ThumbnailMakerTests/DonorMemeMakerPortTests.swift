//
//  DonorMemeMakerPortTests.swift
//  ThumbnailMakerTests
//
//  DONOR ports from Simple Meme Maker: auto-fit text + overflow warning,
//  emoji stickers, and the PencilKit drawing placement maths.
//

import Foundation
import PencilKit
import SwiftUI
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct DonorAutoFitTests {
    private let canvas = CGSize(width: 1024, height: 576)
    private let longText = "THIS IS A VERY LONG TITLE THAT DEFINITELY DOES NOT FIT ON ONE LINE AT ALL"

    @Test func autoFitIsOffByDefaultAndOmittedFromJSON() throws {
        let content = ThumbnailTextLayerContent(value: "Hello")
        #expect(content.autoFit == nil)
        #expect(!content.isAutoFitEnabled)
        let json = try #require(String(data: try JSONEncoder().encode(content), encoding: .utf8))
        #expect(!json.contains("autoFit"))
    }

    @Test func autoFitDecodesFromOldAndNewJSON() throws {
        let old = #"{"value":"Hi","color":{"red":1,"green":1,"blue":1,"alpha":1},"size":0.15,"transform":{"x":0.5,"y":0.5,"rotationDegrees":0,"isFlippedHorizontally":false},"selectedFontRawValue":"GoNoto"}"#
        let decodedOld = try JSONDecoder().decode(ThumbnailTextLayerContent.self, from: Data(old.utf8))
        #expect(!decodedOld.isAutoFitEnabled)

        var content = ThumbnailTextLayerContent(value: "Hi")
        content.isAutoFitEnabled = true
        let roundTripped = try JSONDecoder().decode(
            ThumbnailTextLayerContent.self,
            from: try JSONEncoder().encode(content)
        )
        #expect(roundTripped.isAutoFitEnabled)
        #expect(roundTripped == content)
    }

    @Test func turningAutoFitOffStoresNil() {
        var content = ThumbnailTextLayerContent(value: "Hi")
        content.isAutoFitEnabled = true
        #expect(content.autoFit == true)
        content.isAutoFitEnabled = false
        #expect(content.autoFit == nil)
    }

    @Test func measurementGrowsWithFontSizeAndWraps() {
        let small = ThumbnailTextAutoFit.measure(text: longText, font: .goNoto, fontSize: 20, width: 400)
        let large = ThumbnailTextAutoFit.measure(text: longText, font: .goNoto, fontSize: 60, width: 400)
        #expect(large.height > small.height)
        #expect(large.lineCount > small.lineCount)
        #expect(ThumbnailTextAutoFit.measure(text: "", font: .goNoto, fontSize: 60, width: 400).lineCount == 0)
    }

    @Test func shortTextKeepsRequestedSize() {
        let box = CGSize(width: 600, height: 200)
        let fitted = ThumbnailTextAutoFit.fittedFontSize(
            text: "Hi",
            font: .goNoto,
            requested: 80,
            style: nil,
            canvasSize: canvas,
            boxSize: box
        )
        #expect(fitted == 80)
    }

    @Test func longTextShrinksUntilItFits() {
        let box = CGSize(width: 500, height: 150)
        let fitted = ThumbnailTextAutoFit.fittedFontSize(
            text: longText,
            font: .goNoto,
            requested: 90,
            style: nil,
            canvasSize: canvas,
            boxSize: box
        )
        #expect(fitted < 90)
        #expect(fitted >= 90 * ThumbnailTextAutoFit.minimumScale)
        #expect(ThumbnailTextAutoFit.fits(
            text: longText, font: .goNoto, fontSize: fitted, style: nil, canvasSize: canvas, boxSize: box
        ))
        // The search finds the LARGEST size that fits, to its precision.
        let slightlyLarger = fitted + 90 * ThumbnailTextAutoFit.precision * 2
        #expect(!ThumbnailTextAutoFit.fits(
            text: longText, font: .goNoto, fontSize: slightlyLarger, style: nil, canvasSize: canvas, boxSize: box
        ))
    }

    @Test func fittedSizeScalesWithCanvasForExportParity() {
        let editorCanvas = CGSize(width: 400, height: 225)
        let exportCanvas = CGSize(width: 1600, height: 900)
        var content = ThumbnailTextLayerContent(value: longText, size: 0.2)
        content.isAutoFitEnabled = true
        func ratio(_ canvasSize: CGSize) -> CGFloat {
            let box = ContentLayerCanvasGeometry.textFrameSize(
                for: content, resizeTranslation: .zero, canvasSize: canvasSize
            )
            return content.renderedFontSize(normalizedSize: 0.2, canvasSize: canvasSize, boxSize: box)
                / canvasSize.height
        }
        #expect(abs(ratio(editorCanvas) - ratio(exportCanvas)) < 0.02)
    }

    @Test func autoFitBoxBudgetsWrappedLines() {
        let singleLine = ThumbnailTextAutoFit.autoFitBoxSize(text: "Hi", style: nil, fontSize: 60, canvasSize: canvas)
        let wrapped = ThumbnailTextAutoFit.autoFitBoxSize(text: longText, style: nil, fontSize: 60, canvasSize: canvas)
        #expect(wrapped.height > singleLine.height)
        #expect(wrapped.width <= canvas.width * 0.9 + 0.5)
        #expect(wrapped.height <= canvas.height * 0.48 + 0.5)
    }

    @Test func textFrameUsesAutoFitBoxOnlyWhenEnabled() {
        var content = ThumbnailTextLayerContent(value: longText, size: 0.15)
        let legacy = ContentLayerCanvasGeometry.textFrameSize(for: content, resizeTranslation: .zero, canvasSize: canvas)
        content.isAutoFitEnabled = true
        let fitted = ContentLayerCanvasGeometry.textFrameSize(for: content, resizeTranslation: .zero, canvasSize: canvas)
        #expect(fitted.height > legacy.height)
    }

    @Test func overflowDetectsTextThatCannotFit() {
        let tiny = CGSize(width: 120, height: 40)
        #expect(ThumbnailTextAutoFit.overflowsBox(
            text: String(repeating: longText + " ", count: 4),
            font: .goNoto,
            requested: 60,
            style: nil,
            autoFit: true,
            canvasSize: canvas,
            boxSize: tiny
        ))
        #expect(!ThumbnailTextAutoFit.overflowsBox(
            text: "Hi",
            font: .goNoto,
            requested: 20,
            style: nil,
            autoFit: false,
            canvasSize: canvas,
            boxSize: CGSize(width: 400, height: 100)
        ))
        #expect(!ThumbnailTextAutoFit.overflowsBox(
            text: "   ",
            font: .goNoto,
            requested: 60,
            style: nil,
            autoFit: true,
            canvasSize: canvas,
            boxSize: tiny
        ))
    }

    @Test func autoFitRescuesTextThatOverflowsWithoutIt() {
        var content = ThumbnailTextLayerContent(value: longText, size: 0.2)
        #expect(content.overflowsBox(canvasSize: canvas), "Legacy one-line box truncates a long title")
        content.isAutoFitEnabled = true
        #expect(!content.overflowsBox(canvasSize: canvas))
    }

    @Test func autoFitHonoursStyledLineLimit() {
        let style = ThumbnailTextStyle(maxWidthFraction: 0.9, lineLimit: 1, minimumScaleFactor: 1)
        let box = CGSize(width: 500, height: 300)
        let fitted = ThumbnailTextAutoFit.fittedFontSize(
            text: "Two words here that wrap",
            font: .goNoto,
            requested: 120,
            style: style,
            canvasSize: canvas,
            boxSize: box
        )
        let resolved = ThumbnailTextStyleResolver.resolve(
            style: style, role: .contentLayer, fontSize: fitted, canvasSize: canvas, contentBoxSize: box
        )
        let measured = ThumbnailTextAutoFit.measure(
            text: "Two words here that wrap", font: .goNoto, fontSize: fitted, width: resolved.maxWidth
        )
        #expect(measured.lineCount <= 1)
    }

    @Test func readinessWarnsAboutOverflowingTextLayer() {
        var configuration = SimpleMakerConfigurationModel()
        configuration.overlayText = "Title"
        configuration.textSize = 0.24
        configuration.textColor = .black
        configuration.backgroundColor = .white
        configuration.layers.addTextLayer(value: String(repeating: longText + " ", count: 3))

        #expect(configuration.overflowingTextLayerNames == ["Text 1"])
        let report = ThumbnailReadinessAnalyzer.analyze(configuration)
        #expect(report.findings.contains {
            $0.severity == .warning && $0.message.contains("too long for its box")
        })

        // Hidden layers do not export, so they do not warn.
        let id = configuration.layers.first { $0.name == "Text 1" }?.id ?? ""
        configuration.layers.setVisible(false, for: .content(id))
        #expect(configuration.overflowingTextLayerNames.isEmpty)
    }

    @Test func readinessIsQuietForShortTextLayers() {
        var configuration = PremiumMakerConfigurationModel()
        configuration.layers.addTextLayer(value: "New text")
        #expect(configuration.overflowingTextLayerNames.isEmpty)
        #expect(!ThumbnailReadinessAnalyzer.analyze(configuration).findings.contains {
            $0.message.contains("too long for its box")
        })
    }

    @Test func overflowFindingNamesSingleLayerOrCountsMany() {
        var findings: [ThumbnailReadinessFinding] = []
        #expect(ThumbnailReadinessAnalyzer.appendTextOverflowFindings(for: [], to: &findings) == 0)
        #expect(findings.isEmpty)
        #expect(ThumbnailReadinessAnalyzer.appendTextOverflowFindings(for: ["Headline"], to: &findings) < 0)
        #expect(findings.last?.message.contains("\"Headline\"") == true)
        _ = ThumbnailReadinessAnalyzer.appendTextOverflowFindings(for: ["A", "B"], to: &findings)
        #expect(findings.last?.message.contains("2 text layers") == true)
    }
}

@MainActor
struct DonorEmojiStickerTests {
    @Test func favouritesMatchDonorSet() {
        #expect(ThumbnailEmojiSticker.favourites.count == 32)
        #expect(Set(ThumbnailEmojiSticker.favourites).count == 32)
    }

    @Test func sanitizeTrimsAndCaps() {
        #expect(ThumbnailEmojiSticker.sanitized("  😂 ") == "😂")
        #expect(ThumbnailEmojiSticker.sanitized("   ") == nil)
        #expect(ThumbnailEmojiSticker.sanitized("") == nil)
        #expect(ThumbnailEmojiSticker.sanitized("🔥🔥🔥🔥🔥🔥") == "🔥🔥🔥🔥")
        // Multi-scalar graphemes count as one character.
        #expect(ThumbnailEmojiSticker.sanitized("👍🏽❤️") == "👍🏽❤️")
    }

    @Test func pngIsTransparentAndSized() throws {
        let data = try #require(ThumbnailEmojiSticker.pngData(for: "🔥"))
        let image = try #require(UIImage(data: data))
        let cgImage = try #require(image.cgImage)
        #expect(max(cgImage.width, cgImage.height) <= Int(ThumbnailEmojiSticker.renderedPixelSize) + 1)
        #expect(max(cgImage.width, cgImage.height) >= Int(ThumbnailEmojiSticker.renderedPixelSize) - 1)
        let alpha = cgImage.alphaInfo
        #expect(alpha != .none && alpha != .noneSkipLast && alpha != .noneSkipFirst)
        #expect(ThumbnailEmojiSticker.pngData(for: "  ") == nil)
    }

    @Test func addEmojiStickerLayerAddsNamedSticker() throws {
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: false, hasProfile: false)
        let addedID = layers.addEmojiStickerLayer("😎")
        let id = try #require(addedID)
        let layer = try #require(layers.first { $0.id == id })
        #expect(layer.kind == .image)
        #expect(layer.name == "Sticker 😎")
        guard case .image(let content) = layer.content else {
            Issue.record("expected an image layer")
            return
        }
        #expect(content.isSticker)
        #expect(UIImage(data: content.imageData) != nil)
        let rejected = layers.addEmojiStickerLayer("  ")
        #expect(rejected == nil)
    }

    @Test func simpleEditorEmojiIsOneUndoStep() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        let added = viewModel.addEmojiSticker("🎉")
        let selection = try #require(added)
        guard case .content(let id) = selection else {
            Issue.record("expected a content selection")
            return
        }
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: id) != nil)
        #expect(viewModel.canUndo)
        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: id) == nil)
        viewModel.redo()
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: id)?.name == "Sticker 🎉")
        #expect(viewModel.addEmojiSticker("") == nil)
    }

    @Test func premiumEditorEmojiIsOneUndoStep() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = PremiumMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        let added = viewModel.addEmojiSticker("💯")
        let selection = try #require(added)
        guard case .content(let id) = selection else {
            Issue.record("expected a content selection")
            return
        }
        #expect(viewModel.premiumMakerConfiguration.layers.record(id: id) != nil)
        viewModel.undo()
        #expect(viewModel.premiumMakerConfiguration.layers.record(id: id) == nil)
    }
}

@MainActor
struct DonorDrawingPlacementTests {
    @Test func frameScalesSurfaceToDocument() {
        let frame = ThumbnailDrawingPlacement.frame(
            of: CGRect(x: 10, y: 20, width: 30, height: 40),
            surface: CGSize(width: 100, height: 50),
            document: CGSize(width: 1000, height: 500)
        )
        #expect(frame == CGRect(x: 100, y: 200, width: 300, height: 400))
        #expect(ThumbnailDrawingPlacement.frame(
            of: CGRect(x: 1, y: 1, width: 1, height: 1), surface: .zero, document: CGSize(width: 10, height: 10)
        ) == .zero)
    }

    @Test func pixelsPerPointMatchesDocumentWidth() {
        #expect(ThumbnailDrawingPlacement.pixelsPerPoint(
            surface: CGSize(width: 256, height: 144), document: CGSize(width: 2048, height: 1152)
        ) == 8)
        #expect(ThumbnailDrawingPlacement.pixelsPerPoint(surface: .zero, document: CGSize(width: 10, height: 10)) == 1)
    }

    @Test func documentPixelSizeDoublesReferenceDimensions() {
        #expect(ThumbnailDrawingPlacement.documentPixelSize(for: .ratio16_9) == CGSize(width: 2048, height: 1152))
        #expect(ThumbnailDrawingPlacement.documentPixelSize(for: .ratio9_16) == CGSize(width: 1152, height: 2048))
    }

    @Test func fittedSurfaceKeepsAspect() {
        let surface = ThumbnailDrawingPlacement.fittedSurface(
            for: CGSize(width: 1600, height: 900), in: CGSize(width: 400, height: 800)
        )
        #expect(surface == CGSize(width: 400, height: 225))
        #expect(ThumbnailDrawingPlacement.fittedSurface(for: .zero, in: CGSize(width: 1, height: 1)) == .zero)
    }

    @Test func placementReproducesWhereStrokesWereDrawn() throws {
        let surface = CGSize(width: 400, height: 225)
        // A 90x45 scribble centred at (100, 60).
        let placement = try #require(ThumbnailDrawingPlacement.placement(
            of: CGRect(x: 55, y: 37.5, width: 90, height: 45),
            surface: surface
        ))
        #expect(abs(placement.transform.x - 0.25) < 0.000_1)
        #expect(abs(placement.transform.y - 60.0 / 225.0) < 0.000_1)
        #expect(abs(placement.size - 90.0 / 225.0) < 0.000_1)
        #expect(!placement.wasClamped)

        // Round-trip through the image layer geometry: same on-canvas size.
        let frame = ContentLayerCanvasGeometry.imageFrameSize(
            for: UIGraphicsImageRenderer(size: CGSize(width: 90, height: 45)).image { _ in },
            maxSide: min(surface.width, surface.height) * CGFloat(placement.size)
        )
        #expect(abs(frame.width - 90) < 0.01)
        #expect(abs(frame.height - 45) < 0.01)
    }

    @Test func placementClampsToLayerLimits() throws {
        let surface = CGSize(width: 400, height: 225)
        let wide = try #require(ThumbnailDrawingPlacement.placement(
            of: CGRect(x: 0, y: 0, width: 400, height: 20), surface: surface
        ))
        #expect(wide.size == Double(ContentLayerCanvasGeometry.imageSizeLimits.upperBound))
        #expect(wide.transform.y == ThumbnailOverlayTransform.centerRange.lowerBound)
        #expect(wide.wasClamped)

        let dot = try #require(ThumbnailDrawingPlacement.placement(
            of: CGRect(x: 200, y: 100, width: 2, height: 2), surface: surface
        ))
        #expect(dot.size == Double(ContentLayerCanvasGeometry.imageSizeLimits.lowerBound))
        #expect(ThumbnailDrawingPlacement.placement(of: .zero, surface: surface) == nil)
        #expect(ThumbnailDrawingPlacement.placement(of: CGRect(x: 0, y: 0, width: 5, height: 5), surface: .zero) == nil)
    }

    @Test func paddedBoundsAddsMarginInsideSurface() {
        let surface = CGSize(width: 100, height: 100)
        #expect(ThumbnailDrawingPlacement.paddedBounds(CGRect(x: 10, y: 10, width: 20, height: 20), surface: surface)
            == CGRect(x: 6, y: 6, width: 28, height: 28))
        #expect(ThumbnailDrawingPlacement.paddedBounds(CGRect(x: 0, y: 0, width: 10, height: 10), surface: surface)
            == CGRect(x: 0, y: 0, width: 14, height: 14))
        #expect(ThumbnailDrawingPlacement.paddedBounds(.null, surface: surface).isNull)
    }

    @Test func rendererTurnsStrokesIntoTransparentPNG() throws {
        let points = [
            PKStrokePoint(location: CGPoint(x: 50, y: 50), timeOffset: 0, size: CGSize(width: 8, height: 8),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
            PKStrokePoint(location: CGPoint(x: 150, y: 100), timeOffset: 0.1, size: CGSize(width: 8, height: 8),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
        ]
        let stroke = PKStroke(
            ink: PKInk(.pen, color: .red),
            path: PKStrokePath(controlPoints: points, creationDate: Date())
        )
        let surface = CGSize(width: 256, height: 144)
        let document = CGSize(width: 2048, height: 1152)
        let result = try #require(ThumbnailDrawingRenderer.render(
            PKDrawing(strokes: [stroke]), surface: surface, document: document
        ))
        let image = try #require(UIImage(data: result.pngData)?.cgImage)
        // Rendered at document resolution: 8 pixels per surface point.
        #expect(image.width > 100 * 8 - 1)
        #expect(result.placement.size > 0)
        #expect(ThumbnailDrawingRenderer.render(PKDrawing(), surface: surface, document: document) == nil)
    }

    @Test func addDrawingLayerIsOneUndoStepOnBothEditors() throws {
        let data = try #require(UIGraphicsImageRenderer(size: CGSize(width: 20, height: 10)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        }.pngData())
        let placement = ThumbnailDrawingPlacement.Placement(
            transform: ThumbnailOverlayTransform(x: 0.3, y: 0.4), size: 0.4, wasClamped: false
        )
        let result = ThumbnailDrawingResult(pngData: data, placement: placement)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        let simple = SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        guard case .content(let id) = simple.addDrawing(result) else {
            Issue.record("expected a content selection")
            return
        }
        let layer = try #require(simple.simpleMakerConfiguration.layers.record(id: id))
        #expect(layer.name == "Drawing 1")
        guard case .image(let content) = layer.content else {
            Issue.record("expected an image layer")
            return
        }
        #expect(content.transform == placement.transform)
        #expect(content.size == 0.4)
        #expect(!content.isSticker)
        simple.undo()
        #expect(simple.simpleMakerConfiguration.layers.record(id: id) == nil)

        let premium = PremiumMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit2.json"))
        )
        guard case .content(let premiumID) = premium.addDrawing(result) else {
            Issue.record("expected a content selection")
            return
        }
        #expect(premium.premiumMakerConfiguration.layers.record(id: premiumID) != nil)
        _ = premium.addDrawing(result)
        #expect(premium.premiumMakerConfiguration.layers.contains { $0.name == "Drawing 2" })
    }
}
