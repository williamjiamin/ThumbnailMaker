//
//  LayerStyleApplicationTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-08: scoped brand kit / layer style application, provenance,
//  deletion safety, undo and persistence through both view models.
//

import Foundation
import SwiftUI
import Testing
@testable import ThumbnailMaker

@MainActor
struct LayerStyleApplicationTests {

    // MARK: Fixtures

    static let textLayerID = "content-text"
    static let shapeLayerID = "content-shape"
    static let strokelessShapeID = "content-shape-no-stroke"
    static let imageLayerID = "content-image"
    static let lockedTextLayerID = "content-text-locked"

    static func color(_ r: Double, _ g: Double, _ b: Double) -> ThumbnailDocumentColor {
        ThumbnailDocumentColor(red: r, green: g, blue: b, alpha: 1)
    }

    static let seedText = color(1, 1, 1)
    static let seedBackground = color(0.2, 0.2, 0.2)
    static let seedFill = color(1, 0.82, 0)

    static func brandKit(id: String = "kit-b", name: String = "Kit B") -> BrandKit {
        BrandKit(
            id: id,
            name: name,
            palette: [
                BrandColor(id: "t", name: "Text", color: color(1, 0.5, 0)),
                BrandColor(id: "b", name: "Background", color: color(0, 0, 0.5)),
                BrandColor(id: "a", name: "Accent", color: color(0, 0.75, 0.25))
            ],
            primaryFontRawValue: CustomFont.oswald.rawValue,
            secondaryFontRawValue: CustomFont.lato.rawValue,
            logoImageData: nil,
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
    }

    static func imageData() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }.pngData()!
    }

    static func seededLayers(_ layers: inout [ThumbnailDocumentLayer]) {
        layers.addTextLayer(
            value: "Layer",
            id: textLayerID,
            color: seedText,
            size: 0.12,
            selectedFontRawValue: CustomFont.roboto.rawValue
        )
        layers.addShapeLayer(id: shapeLayerID, fillColor: seedFill, strokeColor: color(1, 1, 1), strokeWidth: 0.01)
        layers.addShapeLayer(id: strokelessShapeID, fillColor: seedFill, strokeColor: nil, strokeWidth: 0.02)
        layers.addImageLayer(imageData: imageData(), id: imageLayerID, transform: .centered, size: 0.2)
        layers.addTextLayer(value: "Locked", id: lockedTextLayerID, color: seedText)
        if let index = layers.firstIndex(where: { $0.id == lockedTextLayerID }) {
            layers[index].isLocked = true
        }
    }

    static func seededDocument() -> ThumbnailDocument {
        var configuration = SimpleMakerConfigurationModel()
        configuration.overlayText = "Title"
        configuration.textColor = seedText.color
        configuration.backgroundColor = seedBackground.color
        configuration.selectedFont = .roboto
        seededLayers(&configuration.layers)
        return configuration.document
    }

    static func textContent(_ id: String, in document: ThumbnailDocument) -> ThumbnailTextLayerContent? {
        if case .text(let content) = document.layers.first(where: { $0.id == id })?.content { return content }
        return nil
    }

    static func shapeContent(_ id: String, in document: ThumbnailDocument) -> ThumbnailShapeLayerContent? {
        if case .shape(let content) = document.layers.first(where: { $0.id == id })?.content { return content }
        return nil
    }

    static func imageContent(_ id: String, in document: ThumbnailDocument) -> ThumbnailImageLayerContent? {
        if case .image(let content) = document.layers.first(where: { $0.id == id })?.content { return content }
        return nil
    }

    static func roundTrip(_ document: ThumbnailDocument) throws -> ThumbnailDocument {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ThumbnailDocument.self, from: encoder.encode(document))
    }

    // MARK: Acceptance: deleting a kit never changes a styled project

    @Test func deletingKitDoesNotChangeResolvedProjectStyling() throws {
        let kit = Self.brandKit()
        var library = BrandKitLibrary.empty
        library.upsert(Self.brandKit(id: "kit-a", name: "Kit A"))
        library.upsert(kit)

        let styled = kit.applied(to: Self.seededDocument(), scope: .projectWide)
        let before = try Self.roundTrip(styled)

        library.remove(id: kit.id)
        let after = try Self.roundTrip(before)

        #expect(after.canvas.backgroundColor == before.canvas.backgroundColor)
        #expect(after.text.color == before.text.color)
        #expect(after.text.selectedFontRawValue == before.text.selectedFontRawValue)
        #expect(after.layers == before.layers)
        #expect(after.text.color == Self.color(1, 0.5, 0))
        #expect(after.canvas.backgroundColor == Self.color(0, 0, 0.5))
        #expect(after.branding.appliedBrandKitID == kit.id)
        #expect(after.appliedBrandKitIsMissing(in: library))
        #expect(after.appliedBrandKitDisplayName(in: library) == "Kit B")
    }

    @Test func badgePrefersLiveKitNameAfterRename() {
        let kit = Self.brandKit()
        var library = BrandKitLibrary.empty
        library.upsert(kit)
        let styled = kit.applied(to: Self.seededDocument(), scope: .projectWide)
        library.rename(id: kit.id, to: "Renamed")
        #expect(styled.appliedBrandKitDisplayName(in: library) == "Renamed")
        #expect(!styled.appliedBrandKitIsMissing(in: library))
    }

    // MARK: Scope rules

    @Test func projectWideApplyStylesEveryUnlockedLayer() throws {
        let kit = Self.brandKit()
        let seed = Self.seededDocument()
        let styled = kit.applied(to: seed, scope: .projectWide)

        #expect(styled.text.color == Self.color(1, 0.5, 0))
        #expect(styled.text.selectedFontRawValue == CustomFont.oswald.rawValue)
        #expect(styled.canvas.backgroundColor == Self.color(0, 0, 0.5))

        let text = try #require(Self.textContent(Self.textLayerID, in: styled))
        #expect(text.color == Self.color(1, 0.5, 0))
        #expect(text.selectedFontRawValue == CustomFont.lato.rawValue)

        let shape = try #require(Self.shapeContent(Self.shapeLayerID, in: styled))
        #expect(shape.fillColor == Self.color(0, 0.75, 0.25))
        #expect(shape.strokeColor == Self.color(1, 0.5, 0))

        let strokeless = try #require(Self.shapeContent(Self.strokelessShapeID, in: styled))
        #expect(strokeless.strokeColor == nil)
        #expect(strokeless.fillColor == Self.color(0, 0.75, 0.25))

        #expect(Self.imageContent(Self.imageLayerID, in: styled) == Self.imageContent(Self.imageLayerID, in: seed))
        #expect(Self.textContent(Self.lockedTextLayerID, in: styled) == Self.textContent(Self.lockedTextLayerID, in: seed))
        #expect(styled.imageData == seed.imageData)
    }

    @Test func selectionScopeOnlyTouchesOneLayer() throws {
        let kit = Self.brandKit()
        let seed = Self.seededDocument()
        let styled = kit.applied(to: seed, scope: .layer(Self.textLayerID))

        #expect(styled.text == seed.text)
        #expect(styled.canvas == seed.canvas)
        for layer in styled.layers where layer.id != Self.textLayerID {
            #expect(layer == seed.layers.first { $0.id == layer.id })
        }
        #expect(Self.textContent(Self.textLayerID, in: styled)?.color == Self.color(1, 0.5, 0))
        #expect(styled.branding.appliedBrandKitID == nil)

        let background = kit.applied(to: seed, scope: .layer(ThumbnailDocumentLayer.backgroundID))
        #expect(background.canvas.backgroundColor == Self.color(0, 0, 0.5))
        #expect(background.text == seed.text)
        #expect(background.layers == seed.layers)

        #expect(kit.applied(to: seed, scope: .layer(Self.imageLayerID)) == seed)
        #expect(kit.applied(to: seed, scope: .layer(Self.lockedTextLayerID)) == seed)
        #expect(kit.applied(to: seed, scope: .layer("missing")) == seed)
    }

    @Test func styleAppliesOnlyNonNilAttributesAndKeepsStrokelessShapes() throws {
        let seed = Self.seededDocument()
        let style = ThumbnailLayerStyle(
            id: "fill-only",
            name: "Fill",
            target: .shape,
            fillColor: Self.color(0.3, 0.1, 0.9),
            strokeColor: Self.color(0, 0, 0)
        )
        let styled = style.applied(to: seed, scope: .projectWide)
        let seedShape = try #require(Self.shapeContent(Self.shapeLayerID, in: seed))
        let shape = try #require(Self.shapeContent(Self.shapeLayerID, in: styled))
        #expect(shape.fillColor == Self.color(0.3, 0.1, 0.9))
        #expect(shape.strokeColor == Self.color(0, 0, 0))
        #expect(shape.strokeWidth == seedShape.strokeWidth)
        #expect(shape.transform == seedShape.transform)
        #expect(shape.width == seedShape.width)
        #expect(shape.height == seedShape.height)

        let strokeless = try #require(Self.shapeContent(Self.strokelessShapeID, in: styled))
        #expect(strokeless.strokeColor == nil)

        // A shape style never touches text.
        #expect(styled.text == seed.text)
        #expect(Self.textContent(Self.textLayerID, in: styled) == Self.textContent(Self.textLayerID, in: seed))
        #expect(styled.branding.styleIDsByLayerID[Self.shapeLayerID] == "fill-only")
        #expect(styled.branding.styleNamesByLayerID[Self.strokelessShapeID] == "Fill")
    }

    @Test func captureRoundTripsALayerLookIncludingTextStyle() throws {
        var document = Self.seededDocument()
        let textStyle = ThumbnailTextStyle.legacyApproximation(for: .contentLayer)
        document.layers.updateTextContent(id: Self.textLayerID) { content in
            content.color = Self.color(0.9, 0.1, 0.1)
            content.selectedFontRawValue = CustomFont.poppins.rawValue
            content.size = 0.2
            content.style = textStyle
        }

        let captured = try #require(ThumbnailLayerStyle.capturing(layerID: Self.textLayerID, in: document, name: "  Red Headline "))
        #expect(captured.name == "Red Headline")
        #expect(captured.target == .text)

        let styled = captured.applied(to: document, scope: .layer(ThumbnailDocumentLayer.textID))
        #expect(styled.text.color == Self.color(0.9, 0.1, 0.1))
        #expect(styled.text.selectedFontRawValue == CustomFont.poppins.rawValue)
        #expect(styled.text.size == 0.2)
        #expect(styled.text.style == textStyle)

        #expect(ThumbnailLayerStyle.capturing(layerID: ThumbnailDocumentLayer.backgroundID, in: document, name: "x") == nil)
        #expect(ThumbnailLayerStyle.capturing(layerID: Self.imageLayerID, in: document, name: "x") == nil)
        #expect(ThumbnailLayerStyle.capturing(layerID: "missing", in: document, name: "x") == nil)
        #expect(ThumbnailLayerStyle.capturing(layerID: Self.shapeLayerID, in: document, name: "x")?.target == .shape)
    }

    @Test func textSizeFromStyleIsClamped() {
        let style = ThumbnailLayerStyle(name: "Huge", target: .text, textSize: 9)
        let styled = style.applied(to: Self.seededDocument(), scope: .layer(Self.textLayerID))
        #expect(Self.textContent(Self.textLayerID, in: styled)?.size == Double(ContentLayerCanvasGeometry.textSizeLimits.upperBound))
    }

    // MARK: Document compatibility

    @Test func documentBrandingSurvivesCodableAndIsBackCompat() throws {
        let seed = Self.seededDocument()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var json = try #require(JSONSerialization.jsonObject(with: encoder.encode(seed)) as? [String: Any])
        json.removeValue(forKey: "branding")
        json["version"] = 4
        let legacyData = try JSONSerialization.data(withJSONObject: json)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacy = try decoder.decode(ThumbnailDocument.self, from: legacyData)
        #expect(legacy.branding == ThumbnailDocumentBranding())
        #expect(legacy.layers == seed.layers)
        #expect(legacy.version == ThumbnailDocument.currentVersion)

        let styled = Self.brandKit().applied(to: seed, scope: .projectWide)
        var branded = ThumbnailLayerStyle(id: "s", name: "S", target: .shape, fillColor: Self.color(0, 0, 0))
            .applied(to: styled, scope: .layer(Self.shapeLayerID))
        branded.updatedAt = Date(timeIntervalSince1970: 1_000) // ISO-8601 drops sub-seconds
        #expect(!branded.branding.styleIDsByLayerID.isEmpty)
        #expect(try Self.roundTrip(branded) == branded)
    }

    @Test func brandingPrunesDeletedLayerIDs() {
        let style = ThumbnailLayerStyle(id: "s", name: "S", target: .shape, fillColor: Self.color(0, 0, 0))
        let styled = style.applied(to: Self.seededDocument(), scope: .layer(Self.shapeLayerID))
        #expect(styled.branding.styleIDsByLayerID[Self.shapeLayerID] == "s")

        var configuration = SimpleMakerConfigurationModel(document: styled)
        #expect(configuration.branding == styled.branding)
        configuration.layers.deleteContentLayer(id: Self.shapeLayerID)
        let rebuilt = ThumbnailDocument(configuration: configuration)
        #expect(rebuilt.branding.styleIDsByLayerID[Self.shapeLayerID] == nil)
        #expect(rebuilt.branding.styleNamesByLayerID[Self.shapeLayerID] == nil)
    }

    // MARK: View models: undo + persistence

    static func makeSimple(in directory: URL) -> (SimpleMakerViewModel, ThumbnailDraftStore, BrandKitStore) {
        let draftStore = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple-maker-draft.json"))
        let brandStore = BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        return (SimpleMakerViewModel(draftStore: draftStore, brandKitStore: brandStore), draftStore, brandStore)
    }

    static func makePremium(in directory: URL) -> (PremiumMakerViewModel, ThumbnailDraftStore, BrandKitStore) {
        let draftStore = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium-maker-draft.json"))
        let brandStore = BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        return (PremiumMakerViewModel(draftStore: draftStore, brandKitStore: brandStore), draftStore, brandStore)
    }

    static func seed(_ viewModel: SimpleMakerViewModel) {
        viewModel.simpleMakerConfiguration.overlayText = "Title"
        viewModel.simpleMakerConfiguration.textColor = seedText.color
        viewModel.simpleMakerConfiguration.backgroundColor = seedBackground.color
        viewModel.simpleMakerConfiguration.selectedFont = .roboto
        seededLayers(&viewModel.simpleMakerConfiguration.layers)
        viewModel.commitEditorStateNow()
    }

    static func seed(_ viewModel: PremiumMakerViewModel) {
        viewModel.premiumMakerConfiguration.overlayText = "Title"
        viewModel.premiumMakerConfiguration.textColor = seedText.color
        viewModel.premiumMakerConfiguration.backgroundColor = seedBackground.color
        viewModel.premiumMakerConfiguration.selectedFont = .roboto
        seededLayers(&viewModel.premiumMakerConfiguration.layers)
        viewModel.commitEditorStateNow()
    }

    @Test func projectWideApplyIsUndoableThroughSimpleViewModel() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (viewModel, draftStore, _) = Self.makeSimple(in: directory)
        Self.seed(viewModel)
        let seeded = ThumbnailDocumentHistory.snapshot(viewModel.stylingDocument)
        let kit = Self.brandKit()

        #expect(viewModel.applyBrandKit(kit, to: .projectWide))
        let styled = viewModel.stylingDocument
        #expect(styled.text.color == Self.color(1, 0.5, 0))
        #expect(viewModel.simpleMakerConfiguration.selectedFont == .oswald)
        #expect(Self.shapeContent(Self.shapeLayerID, in: styled)?.fillColor == Self.color(0, 0.75, 0.25))
        #expect(styled.branding.appliedBrandKitID == kit.id)
        #expect(viewModel.appliedBrandKitDisplayName == "Kit B")
        #expect(viewModel.canUndo)
        #expect(try draftStore.loadDocument()?.branding.appliedBrandKitID == kit.id)

        // Re-applying the same kit is a no-op (no extra undo step).
        #expect(!viewModel.applyBrandKit(kit, to: .projectWide))

        viewModel.undo()
        #expect(ThumbnailDocumentHistory.snapshot(viewModel.stylingDocument) == seeded)
        #expect(viewModel.currentBranding.appliedBrandKitID == nil)
        #expect(viewModel.canRedo)

        viewModel.redo()
        #expect(viewModel.currentBranding.appliedBrandKitID == kit.id)
    }

    @Test func selectionScopeApplyIsUndoableThroughSimpleViewModel() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (viewModel, _, _) = Self.makeSimple(in: directory)
        Self.seed(viewModel)
        let seeded = viewModel.stylingDocument

        #expect(viewModel.applyBrandKit(Self.brandKit(), to: .layer(Self.shapeLayerID)))
        let styled = viewModel.stylingDocument
        #expect(Self.shapeContent(Self.shapeLayerID, in: styled)?.fillColor == Self.color(0, 0.75, 0.25))
        #expect(styled.text == seeded.text)
        #expect(styled.canvas == seeded.canvas)
        #expect(Self.textContent(Self.textLayerID, in: styled) == Self.textContent(Self.textLayerID, in: seeded))
        #expect(viewModel.appliedBrandKitDisplayName == nil)
        #expect(viewModel.canUndo)

        viewModel.undo()
        #expect(Self.shapeContent(Self.shapeLayerID, in: viewModel.stylingDocument) == Self.shapeContent(Self.shapeLayerID, in: seeded))
    }

    @Test func savedLayerStyleAppliesUndoablyAndPersists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (viewModel, draftStore, brandStore) = Self.makeSimple(in: directory)
        Self.seed(viewModel)
        viewModel.simpleMakerConfiguration.layers.updateShapeContent(id: Self.shapeLayerID) { content in
            content.fillColor = Self.color(0.1, 0.2, 0.3)
            content.strokeWidth = 0.03
        }
        viewModel.commitEditorStateNow()

        // No kit yet: saving a style creates a default kit to hold it.
        let style = try #require(viewModel.saveLayerStyle(named: "Badge", fromLayerID: Self.shapeLayerID))
        #expect(viewModel.brandKitLibrary.kits.count == 1)
        #expect(viewModel.brandKit?.styles.map(\.id) == [style.id])
        #expect(viewModel.saveLayerStyle(named: "Nope", fromLayerID: Self.imageLayerID) == nil)
        #expect(viewModel.showingSaveAlert)
        viewModel.showingSaveAlert = false

        #expect(viewModel.applyLayerStyle(style, to: .layer(Self.strokelessShapeID)))
        let styled = try #require(Self.shapeContent(Self.strokelessShapeID, in: viewModel.stylingDocument))
        #expect(styled.fillColor == Self.color(0.1, 0.2, 0.3))
        #expect(styled.strokeWidth == 0.03)
        #expect(styled.strokeColor == nil)
        #expect(viewModel.appliedStyleName(forLayerID: Self.strokelessShapeID) == "Badge")
        #expect(viewModel.canUndo)

        // Style + provenance survive a relaunch.
        let restored = SimpleMakerViewModel(draftStore: draftStore, brandKitStore: brandStore)
        #expect(Self.shapeContent(Self.strokelessShapeID, in: restored.stylingDocument)?.fillColor == Self.color(0.1, 0.2, 0.3))
        #expect(restored.currentBranding.styleIDsByLayerID[Self.strokelessShapeID] == style.id)
        #expect(restored.brandKit?.styles.first?.name == "Badge")

        // Deleting the style (and the kit) leaves the resolved look intact.
        let kitID = try #require(restored.brandKit?.id)
        #expect(restored.deleteLayerStyle(id: style.id, fromKit: kitID))
        #expect(restored.deleteBrandKit(id: kitID) != nil)
        #expect(Self.shapeContent(Self.strokelessShapeID, in: restored.stylingDocument)?.fillColor == Self.color(0.1, 0.2, 0.3))
        #expect(restored.appliedStyleName(forLayerID: Self.strokelessShapeID) == "Badge")

        viewModel.undo()
        #expect(Self.shapeContent(Self.strokelessShapeID, in: viewModel.stylingDocument)?.fillColor == Self.seedFill)
    }

    @Test func premiumMirrorsSimpleForBothScopes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (viewModel, _, _) = Self.makePremium(in: directory)
        Self.seed(viewModel)
        let seeded = ThumbnailDocumentHistory.snapshot(viewModel.stylingDocument)
        let kit = Self.brandKit()

        #expect(viewModel.applyBrandKit(kit, to: .layer(Self.textLayerID)))
        #expect(Self.textContent(Self.textLayerID, in: viewModel.stylingDocument)?.color == Self.color(1, 0.5, 0))
        #expect(viewModel.stylingDocument.text == seeded.text)

        #expect(viewModel.applyBrandKit(kit, to: .projectWide))
        #expect(viewModel.premiumMakerConfiguration.selectedFont == .oswald)
        #expect(viewModel.appliedBrandKitDisplayName == "Kit B")

        viewModel.undo()
        #expect(viewModel.currentBranding.appliedBrandKitID == nil)
        #expect(Self.textContent(Self.textLayerID, in: viewModel.stylingDocument)?.color == Self.color(1, 0.5, 0))
        viewModel.undo()
        #expect(ThumbnailDocumentHistory.snapshot(viewModel.stylingDocument) == seeded)
    }

    @Test func legacyApplyBrandKitNowAlsoStampsBadgeAndStylesContentLayers() {
        var configuration = SimpleMakerConfigurationModel()
        configuration.overlayText = "Title"
        Self.seededLayers(&configuration.layers)
        let kit = Self.brandKit()

        let styled = kit.applied(to: configuration)
        #expect(styled.branding.appliedBrandKitID == kit.id)
        #expect(styled.selectedFont == .oswald)
        #expect(Self.shapeContent(Self.shapeLayerID, in: styled.document)?.fillColor == Self.color(0, 0.75, 0.25))
        #expect(Self.imageContent(Self.imageLayerID, in: styled.document) == Self.imageContent(Self.imageLayerID, in: configuration.document))
    }
}
