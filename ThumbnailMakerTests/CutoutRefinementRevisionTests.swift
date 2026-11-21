//
//  CutoutRefinementRevisionTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-11: the editors' cutout intents — non-destructive background
//  removal, stale-async rejection, one undo step per refinement session —
//  plus the refinement sheet's local state and canvas mapping.
//

import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct CutoutRefinementRevisionTests {
    // MARK: Stale async rejection

    @Test func staleCutoutResultCannotReplaceANewerSelection() throws {
        let (viewModel, directory) = makeSimple(imageSize: CGSize(width: 40, height: 20))
        defer { try? FileManager.default.removeItem(at: directory) }
        let before = ThumbnailDocumentHistory.snapshot(viewModel.simpleMakerConfiguration.document)
        let base = try CutoutFixtures.uniformBase(value: 0, sourceWidth: 40, sourceHeight: 20)

        let stale = viewModel.beginCutoutGeneration()
        let current = viewModel.beginCutoutGeneration()

        #expect(!viewModel.applyGeneratedCutoutBase(base, to: .baseImage, revision: stale))
        #expect(ThumbnailDocumentHistory.snapshot(viewModel.simpleMakerConfiguration.document) == before)
        #expect(viewModel.cutout(for: .baseImage) == nil)

        #expect(viewModel.applyGeneratedCutoutBase(base, to: .baseImage, revision: current))
        #expect(viewModel.cutout(for: .baseImage)?.automaticBase == base)
        viewModel.undo()
        #expect(viewModel.cutout(for: .baseImage) == nil)
        #expect(viewModel.simpleMakerConfiguration.selectedImage != nil, "Undo removes only the cutout step.")
    }

    @Test func cutoutBaseWhoseSourcePixelSizeNoLongerMatchesIsRejected() throws {
        let (viewModel, directory) = makePremium(imageSize: CGSize(width: 40, height: 20))
        defer { try? FileManager.default.removeItem(at: directory) }
        let mismatched = try CutoutFixtures.uniformBase(value: 0, sourceWidth: 41, sourceHeight: 20)

        let revision = viewModel.beginCutoutGeneration()
        #expect(!viewModel.applyGeneratedCutoutBase(mismatched, to: .baseImage, revision: revision))
        #expect(viewModel.cutout(for: .baseImage) == nil)
        viewModel.undo()
        #expect(viewModel.premiumMakerConfiguration.selectedImage == nil, "No cutout step was recorded.")
    }

    @Test func aResultForAReplacedLayerImageIsDropped() async throws {
        let (viewModel, directory) = makeSimple(imageSize: CGSize(width: 40, height: 20))
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try #require(CutoutFixtures.solidPNG(width: 30, height: 30))
        guard case .content(let layerID) = viewModel.addImageLayer(imageData: data) else {
            Issue.record("Expected a content layer")
            return
        }
        // The processor swaps the layer's bytes (same size) while it "runs".
        let replacement = try #require(CutoutFixtures.solidPNG(width: 30, height: 30, color: .blue))
        let processor = SwappingProcessor {
            viewModel.simpleMakerConfiguration.layers.updateImageContent(id: layerID) { $0.imageData = replacement }
        }
        await viewModel.generateAutomaticCutout(for: .contentLayer(layerID), using: processor)
        #expect(viewModel.simpleMakerConfiguration.layers.cutout(forLayerID: layerID) == nil)
        #expect(!viewModel.isProcessingSubject)
    }

    // MARK: Non-destructive background removal

    @Test func removeBackgroundNoLongerRewritesTheBasePhoto() async throws {
        let (viewModel, directory) = makeSimple(imageSize: CGSize(width: 40, height: 20))
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalBytes = viewModel.simpleMakerConfiguration.document.imageData
        let originalImage = viewModel.simpleMakerConfiguration.selectedImage

        await viewModel.removeBackground(from: .textOverlay)

        #expect(viewModel.simpleMakerConfiguration.selectedImage === originalImage)
        #expect(viewModel.simpleMakerConfiguration.document.imageData == originalBytes)
        let mask = try #require(viewModel.cutout(for: .baseImage))
        #expect(mask.automaticBase?.sourcePixelWidth == 40)
        #expect(!viewModel.isProcessingSubject)
        #expect(!viewModel.showingSaveAlert)

        viewModel.undo()
        #expect(viewModel.cutout(for: .baseImage) == nil)
        #expect(viewModel.simpleMakerConfiguration.document.imageData == originalBytes)
        viewModel.redo()
        #expect(viewModel.cutout(for: .baseImage)?.automaticBase == mask.automaticBase)
    }

    @Test func premiumRemoveBackgroundOnAnImageLayerIsNonDestructive() async throws {
        let (viewModel, directory) = makePremium(imageSize: CGSize(width: 40, height: 20))
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try #require(CutoutFixtures.solidPNG(width: 24, height: 12))
        let selection = viewModel.addImageLayer(imageData: data)
        guard case .content(let layerID) = selection,
              case .image(let added) = viewModel.premiumMakerConfiguration.layers.record(id: layerID)?.content else {
            Issue.record("Expected an image content layer")
            return
        }

        await viewModel.removeBackground(from: selection)

        let layer = try #require(viewModel.premiumMakerConfiguration.layers.record(id: layerID))
        guard case .image(let content) = layer.content else {
            Issue.record("Expected image content")
            return
        }
        #expect(content.imageData == added.imageData)
        #expect(layer.cutout?.automaticBase != nil)
        #expect(viewModel.cutout(for: .baseImage) == nil, "Only the selected layer is cut out.")
        viewModel.undo()
        #expect(viewModel.premiumMakerConfiguration.layers.cutout(forLayerID: layerID) == nil)
    }

    @Test func failedCutoutSurfacesAnErrorAndLeavesTheDocumentEqual() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json")),
            subjectProcessor: FailingProcessor()
        )
        viewModel.simpleMakerConfiguration.selectedImage = CutoutFixtures.solidImage(width: 20, height: 20)
        viewModel.commitEditorStateNow()
        let before = ThumbnailDocumentHistory.snapshot(viewModel.simpleMakerConfiguration.document)

        await viewModel.removeBackground(from: .textOverlay)

        #expect(viewModel.showingSaveAlert)
        #expect(viewModel.saveError?.contains("Failed to remove background") == true)
        #expect(!viewModel.isProcessingSubject)
        #expect(ThumbnailDocumentHistory.snapshot(viewModel.simpleMakerConfiguration.document) == before)
    }

    @Test func replacingThePhotoClearsItsCutout() throws {
        let (viewModel, directory) = makeSimple(imageSize: CGSize(width: 40, height: 20))
        defer { try? FileManager.default.removeItem(at: directory) }
        var mask = ThumbnailCutoutMask()
        mask.appendStroke(ThumbnailCutoutStroke(mode: .erase, points: [ThumbnailCutoutPoint(x: 0.5, y: 0.5)], radius: 0.1))
        #expect(viewModel.commitCutoutRefinement(mask, for: .baseImage))
        #expect(viewModel.cutout(for: .baseImage) != nil)

        let revision = viewModel.beginImageImport()
        let newPhoto = try #require(CutoutFixtures.solidPNG(width: 40, height: 20, color: .blue))
        #expect(viewModel.applyImportedImageData(newPhoto, revision: revision))
        #expect(viewModel.cutout(for: .baseImage) == nil)
    }

    // MARK: Refinement commit

    @Test func commitCutoutRefinementCreatesExactlyOneUndoEntry() throws {
        let (viewModel, directory) = makeSimple(imageSize: CGSize(width: 40, height: 20))
        defer { try? FileManager.default.removeItem(at: directory) }
        let before = ThumbnailDocumentHistory.snapshot(viewModel.simpleMakerConfiguration.document)

        let source = try #require(viewModel.cutoutSource(for: .baseImage))
        var state = ThumbnailCutoutRefinementState(stored: source.mask)
        for index in 0..<10 {
            state.beginStroke(at: ThumbnailCutoutPoint(x: Double(index) / 10, y: 0.2))
            state.continueStroke(to: ThumbnailCutoutPoint(x: Double(index) / 10, y: 0.8))
            let step1 = state.endStroke()
            #expect(step1)
        }
        #expect(viewModel.commitCutoutRefinement(state.result, for: .baseImage))
        let committed = try #require(viewModel.cutout(for: .baseImage))
        #expect(committed.strokes.count == 10)
        #expect(committed.sourcePixelWidth == 40 && committed.sourcePixelHeight == 20)

        viewModel.undo()
        #expect(ThumbnailDocumentHistory.snapshot(viewModel.simpleMakerConfiguration.document) == before)
        // Ten strokes are one undo step: the next undo already removes the photo pick.
        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.selectedImage == nil)
    }

    @Test func cancelledOrNoOpRefinementLeavesTheDocumentEqual() throws {
        let (viewModel, directory) = makePremium(imageSize: CGSize(width: 40, height: 20))
        defer { try? FileManager.default.removeItem(at: directory) }
        let before = ThumbnailDocumentHistory.snapshot(viewModel.premiumMakerConfiguration.document)

        var state = ThumbnailCutoutRefinementState(stored: nil)
        state.beginStroke(at: ThumbnailCutoutPoint(x: 0.5, y: 0.5))
        state.endStroke()
        state.undo()
        #expect(!state.hasChanges)
        #expect(!viewModel.commitCutoutRefinement(state.result, for: .baseImage))
        #expect(ThumbnailDocumentHistory.snapshot(viewModel.premiumMakerConfiguration.document) == before)
        // The only undo step left is the photo pick itself: no cutout step was recorded.
        viewModel.undo()
        #expect(viewModel.premiumMakerConfiguration.selectedImage == nil)
    }

    @Test func resetCutoutReturnsTheUntouchedOriginal() throws {
        let (viewModel, directory) = makeSimple(imageSize: CGSize(width: 16, height: 16))
        defer { try? FileManager.default.removeItem(at: directory) }
        var mask = ThumbnailCutoutMask()
        mask.appendStroke(ThumbnailCutoutStroke(mode: .erase, points: [ThumbnailCutoutPoint(x: 0.5, y: 0.5)], radius: 0.3))
        viewModel.commitCutoutRefinement(mask, for: .baseImage)
        let image = try #require(viewModel.simpleMakerConfiguration.selectedImage)
        let masked = try ThumbnailCutoutMaskRenderer.composited(image, mask: viewModel.cutout(for: .baseImage))
        #expect(masked !== image)

        #expect(viewModel.resetCutout(for: .baseImage))
        #expect(viewModel.cutout(for: .baseImage) == nil)
        #expect(try ThumbnailCutoutMaskRenderer.composited(image, mask: viewModel.cutout(for: .baseImage)) === image)
    }

    @Test func cutoutTargetMirrorsCanRemoveBackground() throws {
        let (viewModel, directory) = makeSimple(imageSize: CGSize(width: 16, height: 16))
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(viewModel.cutoutTarget(for: .textOverlay) == .baseImage)
        let data = try #require(CutoutFixtures.solidPNG(width: 8, height: 8))
        let selection = viewModel.addImageLayer(imageData: data)
        guard case .content(let layerID) = selection else {
            Issue.record("Expected a content layer")
            return
        }
        #expect(viewModel.cutoutTarget(for: selection) == .contentLayer(layerID))
        #expect(viewModel.canRefineCutout(.contentLayer(layerID)))
        #expect(!viewModel.canRefineCutout(.contentLayer("missing")))
        #expect(!viewModel.canRefineCutout(.profileImage))
    }

    // MARK: Refinement sheet state

    @Test func refinementStateUndoResetAndFeatherAreLocal() {
        var state = ThumbnailCutoutRefinementState(stored: nil)
        state.tool = .move
        state.beginStroke(at: ThumbnailCutoutPoint(x: 0.5, y: 0.5))
        let step2 = state.endStroke()
        #expect(!step2, "Move never paints.")

        state.tool = .restore
        state.setBrushRadius(5)
        #expect(state.brushRadius == ThumbnailCutoutRefinementState.brushRadiusRange.upperBound)
        state.beginStroke(at: ThumbnailCutoutPoint(x: 0.5, y: 0.5))
        state.continueStroke(to: ThumbnailCutoutPoint(x: 0.5005, y: 0.5)) // below spacing, dropped
        state.continueStroke(to: ThumbnailCutoutPoint(x: 0.6, y: 0.5))
        #expect(state.pendingPoints.count == 2)
        let step3 = state.endStroke()
        #expect(step3)
        #expect(state.working.strokes.first?.mode == .restore)

        state.beginFeatherEdit()
        state.setFeather(0.01)
        state.setFeather(0.02)
        state.setFeather(1)
        #expect(state.working.feather == ThumbnailCutoutMask.featherLimits.upperBound)
        let step4 = state.undo()
        #expect(step4)
        #expect(state.working.feather == 0, "A whole feather drag is one local undo step.")

        let step5 = state.reset()
        #expect(step5)
        #expect(state.result == nil)
        let step6 = state.undo()
        #expect(step6)
        #expect(state.working.strokes.count == 1)

        state.showsBefore = true
        #expect(state.previewMask == nil)
    }

    @Test func refinementStateStartsFromTheStoredRecipeEvenWhenHidden() {
        var stored = ThumbnailCutoutMask()
        stored.appendStroke(ThumbnailCutoutStroke(mode: .erase, points: [ThumbnailCutoutPoint(x: 0.2, y: 0.2)], radius: 0.1))
        stored.isEnabled = false
        let state = ThumbnailCutoutRefinementState(stored: stored)
        #expect(state.working.isEnabled)
        #expect(state.working.strokes == stored.strokes)
        #expect(!state.hasChanges)
    }

    @Test func canvasMappingConvertsViewPointsThroughZoomAndPan() throws {
        var mapping = ThumbnailCutoutCanvasMapping(
            canvasSize: CGSize(width: 400, height: 400),
            imagePixelSize: CGSize(width: 2000, height: 1000)
        )
        #expect(mapping.fittedRect == CGRect(x: 0, y: 100, width: 400, height: 200))
        let topLeft = try #require(mapping.normalizedPoint(for: CGPoint(x: 0, y: 100)))
        #expect(topLeft == ThumbnailCutoutPoint(x: 0, y: 0))
        let center = try #require(mapping.normalizedPoint(for: CGPoint(x: 200, y: 200)))
        #expect(center == ThumbnailCutoutPoint(x: 0.5, y: 0.5))
        #expect(mapping.normalizedPoint(for: CGPoint(x: 200, y: 20)) == nil, "Far outside the photo.")

        mapping.setZoom(2)
        mapping.offset = CGSize(width: 50, height: 0)
        let zoomedCenter = try #require(mapping.normalizedPoint(for: CGPoint(x: 250, y: 200)))
        #expect(abs(zoomedCenter.x - 0.5) < 1e-9 && abs(zoomedCenter.y - 0.5) < 1e-9)
        let roundTrip = mapping.viewPoint(for: ThumbnailCutoutPoint(x: 0.25, y: 0.75))
        let back = try #require(mapping.normalizedPoint(for: roundTrip))
        #expect(abs(back.x - 0.25) < 1e-9 && abs(back.y - 0.75) < 1e-9)
        #expect(mapping.viewRadius(forNormalizedRadius: 0.1) == 80)

        mapping.setZoom(100)
        #expect(mapping.zoom == ThumbnailCutoutCanvasMapping.zoomRange.upperBound)
        mapping.setZoom(0.1)
        #expect(mapping.zoom == 1)
        #expect(mapping.offset == .zero)
    }

    @Test func sliderPercentIsAccessible() {
        #expect(CutoutRefinementView<SimpleMakerViewModel>.percent(0.04, in: 0...0.08) == "50%")
        #expect(CutoutRefinementView<SimpleMakerViewModel>.percent(0, in: 0...1) == "0%")
    }

    // MARK: Helpers

    private func makeSimple(imageSize: CGSize) -> (SimpleMakerViewModel, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let viewModel = SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json")),
            subjectProcessor: HalfMaskProcessor()
        )
        viewModel.simpleMakerConfiguration.selectedImage = CutoutFixtures.solidImage(
            width: Int(imageSize.width),
            height: Int(imageSize.height)
        )
        viewModel.commitEditorStateNow()
        return (viewModel, directory)
    }

    private func makePremium(imageSize: CGSize) -> (PremiumMakerViewModel, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let viewModel = PremiumMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json")),
            subjectProcessor: HalfMaskProcessor()
        )
        viewModel.premiumMakerConfiguration.selectedImage = CutoutFixtures.solidImage(
            width: Int(imageSize.width),
            height: Int(imageSize.height)
        )
        viewModel.commitEditorStateNow()
        return (viewModel, directory)
    }
}

/// Uses the protocol's DEFAULT `foregroundAlphaMask` (alpha lifted from
/// `removeBackground`): left half kept, right half dropped.
private struct HalfMaskProcessor: ThumbnailSubjectProcessing {
    func removeBackground(from image: UIImage) async throws -> UIImage {
        CutoutFixtures.image(width: 16, height: 16) { x, _ in (255, 255, 255, x < 8 ? 255 : 0) }
    }

    func suggestedFaceCrop(in image: UIImage, padding: CGFloat) async throws -> CGRect? { nil }
}

private struct FailingProcessor: ThumbnailSubjectProcessing {
    func removeBackground(from image: UIImage) async throws -> UIImage {
        throw BackgroundRemovalError.foregroundMaskFailed
    }

    func suggestedFaceCrop(in image: UIImage, padding: CGFloat) async throws -> CGRect? { nil }
}

/// Runs `sideEffect` on the main actor while "processing", to simulate the
/// user replacing the image mid-flight.
private struct SwappingProcessor: ThumbnailSubjectProcessing {
    let sideEffect: @MainActor () -> Void

    func removeBackground(from image: UIImage) async throws -> UIImage { image }

    func suggestedFaceCrop(in image: UIImage, padding: CGFloat) async throws -> CGRect? { nil }

    func foregroundAlphaMask(from image: UIImage) async throws -> ThumbnailCutoutAutomaticBase {
        await sideEffect()
        let size = ThumbnailCutoutMaskRenderer.displayPixelSize(of: image)
        return try CutoutFixtures.uniformBase(value: 0, sourceWidth: size.width, sourceHeight: size.height)
    }
}
