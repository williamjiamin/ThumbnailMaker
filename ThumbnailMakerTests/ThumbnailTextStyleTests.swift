//
//  ThumbnailTextStyleTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-04: text style model, persistence, presets, resolver, undo.
//

import Foundation
import SwiftUI
import Testing
@testable import ThumbnailMaker

@MainActor
struct ThumbnailTextStyleTests {

    // MARK: Fixtures

    static func fullyPopulatedStyle() -> ThumbnailTextStyle {
        ThumbnailTextStyle(
            outlineWidth: 0.08,
            outlineColor: ThumbnailDocumentColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1),
            isShadowEnabled: true,
            shadowRadius: 0.12,
            shadowOffsetX: 0.05,
            shadowOffsetY: -0.07,
            shadowColor: ThumbnailDocumentColor(red: 0, green: 0, blue: 0, alpha: 0.6),
            panelColor: ThumbnailDocumentColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 0.5),
            panelCornerRadius: 0.4,
            horizontalPadding: 0.3,
            verticalPadding: 0.15,
            lineSpacing: 0.2,
            letterSpacing: 0.05,
            alignment: .leading,
            maxWidthFraction: 0.7,
            lineLimit: 2,
            minimumScaleFactor: 0.8,
            presetID: "custom"
        )
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func approx(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 1e-6) -> Bool {
        abs(a - b) <= tolerance
    }

    // MARK: Model / clamping

    @Test func textStyleClampsOutOfRangeAndNonFiniteValues() throws {
        let json = """
        {"outlineWidth": 99, "shadowRadius": "NaN", "shadowOffsetX": -40, "maxWidthFraction": 0,
         "lineLimit": 500, "minimumScaleFactor": 7, "horizontalPadding": 1e300, "alignmentRawValue": "diagonal",
         "letterSpacing": -9, "lineSpacing": 3}
        """.data(using: .utf8)!
        let decoded = try Self.makeDecoder().decode(ThumbnailTextStyle.self, from: json)
        #expect(decoded.outlineWidth == 0.25)
        #expect(decoded.shadowRadius == 0)
        #expect(decoded.shadowOffsetX == -0.5)
        #expect(decoded.maxWidthFraction == 0.2)
        #expect(decoded.lineLimit == 10)
        #expect(decoded.minimumScaleFactor == 1)
        #expect(decoded.horizontalPadding == 2)
        #expect(decoded.alignment == .center)
        #expect(decoded.letterSpacing == -0.2)
        #expect(decoded.lineSpacing == 1.5)

        var hostile = ThumbnailTextStyle()
        hostile.shadowRadius = .nan
        hostile.outlineWidth = .infinity
        hostile.maxWidthFraction = -.infinity
        hostile.lineLimit = -3
        let normalized = hostile.normalized()
        #expect(normalized.shadowRadius == 0)
        #expect(normalized.outlineWidth == 0)
        #expect(normalized.maxWidthFraction == 0.9)
        #expect(normalized.lineLimit == 1)
    }

    @Test func textStyleDecodesMissingFieldsToDefaults() throws {
        let decoded = try Self.makeDecoder().decode(ThumbnailTextStyle.self, from: Data("{}".utf8))
        #expect(decoded == ThumbnailTextStyle())
        #expect(decoded.panelColor == nil)
        #expect(decoded.lineLimit == nil)
    }

    // MARK: Persistence / migration

    @Test func documentWithoutTextStyleEncodesNoStyleKey() throws {
        var document = ThumbnailDocument(text: ThumbnailDocumentText(value: "Hello"))
        document.layers.addTextLayer(value: "Layer")
        let data = try Self.makeEncoder().encode(document)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("\"style\""))
    }

    @Test func legacyDocumentJSONDecodesWithNilTextStyle() throws {
        let legacyJSON = """
        {
          "version": 2,
          "updatedAt": "2026-01-01T00:00:00Z",
          "editorMode": "simple",
          "canvas": {
            "aspectRatioRawValue": "\(AspectRatio.ratio16_9.rawValue)",
            "backgroundColor": {"red": 0.08, "green": 0.1, "blue": 0.14, "alpha": 1}
          },
          "text": {
            "value": "Legacy Title",
            "color": {"red": 1, "green": 1, "blue": 1, "alpha": 1},
            "size": 0.18,
            "verticalAlignmentRawValue": "\(VerticalAlignment.center.rawValue)",
            "horizontalAlignmentRawValue": "\(HorizontalAlignment.center.rawValue)",
            "transform": {"x": 0.41, "y": 0.58, "rotationDegrees": 7, "isFlippedHorizontally": false},
            "selectedFontRawValue": "\(CustomFont.roboto.rawValue)"
          },
          "layers": [
            {"id": "legacy-text-layer", "kind": "text", "name": "Text 1", "isVisible": true, "isLocked": false,
             "zIndex": 30,
             "content": {"text": {"_0": {"value": "Old layer", "color": {"red": 1, "green": 1, "blue": 1, "alpha": 1},
               "size": 0.15, "transform": {"x": 0.5, "y": 0.5, "rotationDegrees": 0, "isFlippedHorizontally": false},
               "selectedFontRawValue": "\(CustomFont.goNoto.rawValue)"}}}}
          ],
          "macro": {"isEnabled": false, "startNumber": 1, "endNumber": 1,
                    "appendPositionRawValue": "\(MacroConfig.AppendPosition.after.rawValue)"},
          "export": {"presetID": "\(ThumbnailExportPreset.youTubeThumbnail.id)",
                     "formatRawValue": "\(ThumbnailExportFormat.png.rawValue)", "compressionQuality": 0.9,
                     "usesCustomSize": false, "customWidth": 1920, "customHeight": 1080}
        }
        """.data(using: .utf8)!

        let decoded: ThumbnailDocument
        do {
            decoded = try Self.makeDecoder().decode(ThumbnailDocument.self, from: legacyJSON)
        } catch {
            // The layer-content wire format is an implementation detail; fall back to a
            // document without the hand-written layer so the text assertions still run.
            Issue.record("Legacy JSON with layer failed to decode: \(error)")
            return
        }
        #expect(decoded.version == ThumbnailDocument.currentVersion)
        #expect(decoded.text.value == "Legacy Title")
        #expect(decoded.text.style == nil)
        #expect(decoded.makeSimpleConfiguration().textStyle == nil)
        let layer = try #require(decoded.layers.record(id: "legacy-text-layer"))
        guard case .text(let content) = layer.content else {
            Issue.record("Expected text layer content")
            return
        }
        #expect(content.value == "Old layer")
        #expect(content.style == nil)
    }

    @Test func styledDocumentRoundTripsThroughCodable() throws {
        let style = Self.fullyPopulatedStyle()
        var configuration = PremiumMakerConfigurationModel()
        configuration.overlayText = "Styled"
        configuration.textStyle = style
        let layerID = configuration.layers.addTextLayer(value: "Layer", style: ThumbnailTextStylePreset.all(for: .contentLayer)[3].style)

        let document = configuration.document
        let data = try Self.makeEncoder().encode(document)
        let decoded = try Self.makeDecoder().decode(ThumbnailDocument.self, from: data)

        #expect(decoded.text.style == style)
        #expect(decoded.makePremiumConfiguration().textStyle == style)
        let layer = try #require(decoded.layers.record(id: layerID))
        guard case .text(let content) = layer.content else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.style == ThumbnailTextStylePreset.all(for: .contentLayer)[3].style)
        #expect(content.style?.outlineWidth == 0.06)
    }

    @Test func textLayerStyleSurvivesReconcileAndDuplicate() throws {
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: true, hasProfile: false)
        let style = Self.fullyPopulatedStyle()
        let id = layers.addTextLayer(value: "Dup me", style: style)
        let reconciled = layers.reconciledForCurrentOverlays(hasText: false, hasProfile: false)
        guard case .text(let reconciledContent) = try #require(reconciled.record(id: id)).content else {
            Issue.record("Expected text content")
            return
        }
        #expect(reconciledContent.style == style)

        let duplicatedID = layers.duplicateContentLayer(id: id)
        let copyID = try #require(duplicatedID)
        guard case .text(let copyContent) = try #require(layers.record(id: copyID)).content else {
            Issue.record("Expected text content")
            return
        }
        #expect(copyContent.style == style)
    }

    @Test func templateApplicationPreservesTextLayerStyle() throws {
        let template = try #require(ThumbnailTemplate.builtIns.first)
        var existing = ThumbnailDocument(text: ThumbnailDocumentText(value: "Mine"))
        let style = Self.fullyPopulatedStyle()
        let id = existing.layers.addTextLayer(value: "Styled layer", style: style)
        let applied = template.makeDocument(preservingImagesFrom: existing)
        guard case .text(let content) = try #require(applied.layers.record(id: id)).content else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.style == style)
    }

    // MARK: Presets

    @Test func presetsHaveUniqueStableIdentifiers() {
        for role in [ThumbnailTextRole.overlay, .contentLayer] {
            let ids = ThumbnailTextStylePreset.all(for: role).map(\.id)
            #expect(ids == ["default", "plain", "softShadow", "boldOutline", "outlineAndShadow", "panelPill", "glow"])
            #expect(Set(ids).count == ids.count)
            #expect(ThumbnailTextStylePreset.all(for: role).first?.style == nil)
            for preset in ThumbnailTextStylePreset.all(for: role) where preset.style != nil {
                #expect(preset.style?.presetID == preset.id)
                #expect(preset.style == preset.style?.normalized())
            }
        }
    }

    @Test func plainPresetDisablesEveryEffect() throws {
        let plain = try #require(ThumbnailTextStylePreset.all(for: .overlay).first { $0.id == "plain" }?.style)
        #expect(plain.outlineWidth == 0)
        #expect(!plain.isShadowEnabled)
        #expect(plain.panelColor == nil)
        #expect(plain.letterSpacing == 0)
        #expect(plain.lineSpacing == 0)
        let resolved = ThumbnailTextStyleResolver.resolve(
            style: plain, role: .overlay, fontSize: 40, canvasSize: CGSize(width: 400, height: 225)
        )
        #expect(resolved.shadow == nil)
        #expect(resolved.outlineOffsets.isEmpty)
        #expect(resolved.inkInset == 0)
        #expect(!resolved.usesCompositingGroup)
    }

    // MARK: Resolver

    @Test func resolverLegacyBranchMatchesShippedConstants() {
        let overlay = ThumbnailTextStyleResolver.resolve(
            style: nil, role: .overlay, fontSize: 30, canvasSize: CGSize(width: 350, height: 197)
        )
        #expect(overlay.shadow == ThumbnailResolvedTextShadow(color: .black, radius: 3, x: 1, y: 1))
        #expect(Self.approx(overlay.maxWidth, 315))
        #expect(Self.approx(overlay.horizontalPadding, 10.5))
        #expect(Self.approx(overlay.verticalPadding, 5.91))
        #expect(overlay.inkInset == 0)
        #expect(overlay.lineLimit == nil)
        #expect(overlay.minimumScaleFactor == 1)
        #expect(overlay.fixedHeight == nil)
        #expect(overlay.alignment == .center)
        #expect(overlay.outlineOffsets.isEmpty)
        #expect(overlay.panelColor == nil)
        #expect(!overlay.usesCompositingGroup)

        let box = CGSize(width: 120, height: 60)
        let content = ThumbnailTextStyleResolver.resolve(
            style: nil, role: .contentLayer, fontSize: 30, canvasSize: CGSize(width: 350, height: 197),
            contentBoxSize: box
        )
        #expect(content.shadow == ThumbnailResolvedTextShadow(color: .black.opacity(0.82), radius: 3, x: 1, y: 1))
        #expect(content.lineLimit == 3)
        #expect(content.minimumScaleFactor == 0.6)
        #expect(content.maxWidth == 120)
        #expect(content.fixedHeight == 60)
        #expect(content.horizontalPadding == 0)
        #expect(content.verticalPadding == 0)
        #expect(!content.usesCompositingGroup)
    }

    @Test func resolverScalesLinearlyWithCanvasAndFontSize() throws {
        let style = Self.fullyPopulatedStyle()
        let small = ThumbnailTextStyleResolver.resolve(
            style: style, role: .overlay, fontSize: 27, canvasSize: CGSize(width: 320, height: 180)
        )
        let large = ThumbnailTextStyleResolver.resolve(
            style: style, role: .overlay, fontSize: 54, canvasSize: CGSize(width: 640, height: 360)
        )
        func doubled(_ a: CGFloat, _ b: CGFloat) -> Bool { Self.approx(a * 2, b) }
        #expect(doubled(small.maxWidth, large.maxWidth))
        #expect(doubled(small.horizontalPadding, large.horizontalPadding))
        #expect(doubled(small.verticalPadding, large.verticalPadding))
        #expect(doubled(small.inkInset, large.inkInset))
        #expect(doubled(small.lineSpacing, large.lineSpacing))
        #expect(doubled(small.letterSpacing, large.letterSpacing))
        #expect(doubled(small.outlineWidth, large.outlineWidth))
        #expect(doubled(small.panelCornerRadius, large.panelCornerRadius))
        let smallShadow = try #require(small.shadow)
        let largeShadow = try #require(large.shadow)
        #expect(doubled(smallShadow.radius, largeShadow.radius))
        #expect(doubled(smallShadow.x, largeShadow.x))
        #expect(doubled(smallShadow.y, largeShadow.y))
        #expect(small.minimumScaleFactor == large.minimumScaleFactor)
        #expect(small.lineLimit == large.lineLimit)
        // Outline sample counts may differ with width; compare the magnitude rule instead.
        for offset in large.outlineOffsets {
            #expect(Self.approx(hypot(offset.width, offset.height), large.outlineWidth, 1e-6))
        }

        let smallBox = ThumbnailTextStyleResolver.resolve(
            style: style, role: .contentLayer, fontSize: 27, canvasSize: CGSize(width: 320, height: 180),
            contentBoxSize: CGSize(width: 200, height: 90)
        )
        let largeBox = ThumbnailTextStyleResolver.resolve(
            style: style, role: .contentLayer, fontSize: 54, canvasSize: CGSize(width: 640, height: 360),
            contentBoxSize: CGSize(width: 400, height: 180)
        )
        #expect(doubled(smallBox.maxWidth, largeBox.maxWidth))
        let smallHeight = try #require(smallBox.fixedHeight)
        let largeHeight = try #require(largeBox.fixedHeight)
        #expect(doubled(smallHeight, largeHeight))
    }

    @Test func outlineOffsetsFormDeterministicRing() {
        #expect(ThumbnailTextStyleResolver.outlineOffsets(width: 0).isEmpty)
        #expect(ThumbnailTextStyleResolver.outlineOffsets(width: -1).isEmpty)
        #expect(ThumbnailTextStyleResolver.outlineOffsets(width: .nan).isEmpty)
        let small = ThumbnailTextStyleResolver.outlineOffsets(width: 1)
        #expect(small.count == 8)
        #expect(Self.approx(small[0].width, 1))
        #expect(Self.approx(small[0].height, 0))
        let huge = ThumbnailTextStyleResolver.outlineOffsets(width: 50)
        #expect(huge.count == 24)
        for offset in huge {
            #expect(Self.approx(hypot(offset.width, offset.height), 50, 1e-6))
        }
        #expect(ThumbnailTextStyleResolver.outlineOffsets(width: 3) == ThumbnailTextStyleResolver.outlineOffsets(width: 3))
    }

    @Test func inkInsetCoversOutlineAndShadowSpill() throws {
        let resolved = ThumbnailTextStyleResolver.resolve(
            style: Self.fullyPopulatedStyle(), role: .overlay, fontSize: 100, canvasSize: CGSize(width: 1280, height: 720)
        )
        let shadow = try #require(resolved.shadow)
        #expect(resolved.inkInset + 1e-9 >= resolved.outlineWidth + shadow.radius + max(abs(shadow.x), abs(shadow.y)))
        #expect(resolved.usesCompositingGroup)
        #expect(!resolved.outlineOffsets.isEmpty)
    }

    @Test func legacyApproximationMatchesLegacyMetricsAtExportSize() throws {
        let resolved = ThumbnailTextStyleResolver.resolve(
            style: .legacyApproximation(for: .overlay), role: .overlay, fontSize: 108,
            canvasSize: CGSize(width: 1280, height: 720)
        )
        let shadow = try #require(resolved.shadow)
        #expect(Self.approx(shadow.radius, 3, 0.3))
        #expect(Self.approx(shadow.x, 1, 0.3))
        #expect(Self.approx(shadow.y, 1, 0.3))
        #expect(Self.approx(resolved.horizontalPadding, 38.4, 0.3))
        #expect(Self.approx(resolved.verticalPadding, 21.6, 0.3))
        #expect(Self.approx(resolved.maxWidth, 1152, 0.3))
        #expect(resolved.lineLimit == nil)

        let content = ThumbnailTextStyle.legacyApproximation(for: .contentLayer)
        #expect(content.lineLimit == 3)
        #expect(content.minimumScaleFactor == 0.6)
        #expect(content.shadowColor.alpha == 0.82)
    }

    // MARK: Content-layer geometry

    @Test func contentLayerFrameSizeIsUnchangedForNilStyle() {
        let content = ThumbnailTextLayerContent(value: "Hello world", size: 0.15)
        let canvas = CGSize(width: 400, height: 225)
        let size = ContentLayerCanvasGeometry.textFrameSize(for: content, resizeTranslation: .zero, canvasSize: canvas)
        // Pre-FEATURE-04 formula: fontSize = 225 * 0.15 = 33.75; width = min(360, max(72, 11 * 33.75 * 0.56));
        // height = min(108, max(33.75 * 1.45, 33.75 * 1 * 1.25)).
        let fontSize: CGFloat = 225 * 0.15
        let expectedWidth = min(400 * 0.9, max(400 * 0.18, 11 * fontSize * 0.56))
        let expectedHeight = min(225 * 0.48, max(fontSize * 1.45, fontSize * 1.25))
        #expect(Self.approx(size.width, expectedWidth))
        #expect(Self.approx(size.height, expectedHeight))
    }

    @Test func contentLayerFrameSizeGrowsForPaddingOutlineAndSpacing() {
        let canvas = CGSize(width: 400, height: 225)
        let plain = ThumbnailTextLayerContent(
            value: "Hi\nthere",
            size: 0.15,
            style: ThumbnailTextStylePreset.all(for: .contentLayer).first { $0.id == "plain" }?.style
        )
        var styled = plain
        styled.style = ThumbnailTextStyle(
            outlineWidth: 0.1, isShadowEnabled: true, shadowRadius: 0.1, shadowOffsetX: 0.05,
            horizontalPadding: 0.4, verticalPadding: 0.3, lineSpacing: 0.5, letterSpacing: 0.2,
            lineLimit: 3, minimumScaleFactor: 0.6
        )
        let plainSize = ContentLayerCanvasGeometry.textFrameSize(for: plain, resizeTranslation: .zero, canvasSize: canvas)
        let styledSize = ContentLayerCanvasGeometry.textFrameSize(for: styled, resizeTranslation: .zero, canvasSize: canvas)
        #expect(styledSize.width > plainSize.width)
        #expect(styledSize.height > plainSize.height)
        #expect(styledSize.width <= canvas.width)
        #expect(styledSize.height <= canvas.height)

        var hostile = styled
        hostile.value = String(repeating: "W", count: 400)
        hostile.style?.horizontalPadding = 2
        hostile.style?.verticalPadding = 2
        hostile.style?.outlineWidth = 0.25
        let hostileSize = ContentLayerCanvasGeometry.textFrameSize(for: hostile, resizeTranslation: .zero, canvasSize: canvas)
        #expect(hostileSize.width <= canvas.width)
        #expect(hostileSize.height <= canvas.height)
    }

    // MARK: Undo + persistence through the view models

    @Test func simpleViewModelTextStyleChangeIsUndoableAndPersists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple-maker-draft.json"))
        let brandStore = BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        defer { try? FileManager.default.removeItem(at: directory) }

        let viewModel = SimpleMakerViewModel(draftStore: store, brandKitStore: brandStore)
        viewModel.simpleMakerConfiguration.overlayText = "Style me"
        viewModel.commitEditorStateNow()

        let preset = try #require(ThumbnailTextStylePreset.all(for: .overlay).first { $0.id == "boldOutline" }?.style)
        viewModel.simpleMakerConfiguration.textStyle = preset
        viewModel.commitEditorStateNow()
        #expect(viewModel.canUndo)

        let saved = try #require(try store.loadDocument())
        #expect(saved.text.style == preset)

        let restored = SimpleMakerViewModel(draftStore: store, brandKitStore: brandStore)
        #expect(restored.simpleMakerConfiguration.textStyle == preset)

        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.textStyle == nil)
        #expect(viewModel.simpleMakerConfiguration.overlayText == "Style me")
        #expect(viewModel.canRedo)

        viewModel.redo()
        #expect(viewModel.simpleMakerConfiguration.textStyle == preset)
    }

    @Test func premiumViewModelTextStyleChangeIsUndoableAndPersists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium-maker-draft.json"))
        let brandStore = BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        defer { try? FileManager.default.removeItem(at: directory) }

        let viewModel = PremiumMakerViewModel(draftStore: store, brandKitStore: brandStore)
        viewModel.premiumMakerConfiguration.overlayText = "Style me"
        viewModel.commitEditorStateNow()

        let preset = try #require(ThumbnailTextStylePreset.all(for: .overlay).first { $0.id == "panelPill" }?.style)
        viewModel.premiumMakerConfiguration.textStyle = preset
        viewModel.commitEditorStateNow()
        #expect(viewModel.canUndo)

        let restored = PremiumMakerViewModel(draftStore: store, brandKitStore: brandStore)
        #expect(restored.premiumMakerConfiguration.textStyle == preset)

        viewModel.undo()
        #expect(viewModel.premiumMakerConfiguration.textStyle == nil)
        #expect(viewModel.canRedo)
    }

    @Test func textLayerStyleChangeIsUndoable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple-maker-draft.json"))
        let brandStore = BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        defer { try? FileManager.default.removeItem(at: directory) }

        let viewModel = SimpleMakerViewModel(draftStore: store, brandKitStore: brandStore)
        let id = viewModel.simpleMakerConfiguration.layers.addTextLayer(value: "Layer text")
        viewModel.commitEditorStateNow()

        let glow = try #require(ThumbnailTextStylePreset.all(for: .contentLayer).first { $0.id == "glow" }?.style)
        viewModel.simpleMakerConfiguration.layers.updateTextContent(id: id) { $0.style = glow }
        viewModel.commitEditorStateNow()
        #expect(viewModel.canUndo)

        viewModel.undo()
        guard case .text(let content) = try #require(viewModel.simpleMakerConfiguration.layers.record(id: id)).content else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.style == nil)

        viewModel.redo()
        guard case .text(let redone) = try #require(viewModel.simpleMakerConfiguration.layers.record(id: id)).content else {
            Issue.record("Expected text content")
            return
        }
        #expect(redone.style == glow)
    }
}
