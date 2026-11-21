//
//  ThumbnailAdjustmentViewModelTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-14: adjustment intents on both editors - one undo step per
//  discrete action, one per slider drag, persisted to the draft, and the
//  image bytes never change.
//

import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ThumbnailAdjustmentViewModelTests {
    private let recipe = ThumbnailImageAdjustments(brightness: 0.1, contrast: 1.25, saturation: 0.6, blur: 0.02, vignette: 0.4)

    @Test func simpleSetIsOneUndoStepAndPersists() throws {
        let (viewModel, store, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageDataBefore = viewModel.simpleMakerConfiguration.document.imageData

        #expect(viewModel.canAdjust(.baseImage))
        #expect(viewModel.setAdjustments(recipe, for: .baseImage))
        #expect(viewModel.adjustments(for: .baseImage) == recipe)
        #expect(viewModel.canUndo)
        #expect(try #require(try store.load()).layers.adjustments(forLayerID: ThumbnailDocumentLayer.backgroundID) == recipe)
        #expect(viewModel.simpleMakerConfiguration.document.imageData == imageDataBefore)

        viewModel.undo()
        #expect(viewModel.adjustments(for: .baseImage).isNeutral)
        #expect(viewModel.simpleMakerConfiguration.selectedImage != nil, "Undoing the adjustment must not undo the image pick.")
        viewModel.redo()
        #expect(viewModel.adjustments(for: .baseImage) == recipe)
    }

    @Test func resetIsOneStepAndNeutralResetRecordsNothing() throws {
        let (viewModel, _, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }
        let baseline = viewModel.simpleMakerConfiguration.document.imageData

        #expect(!viewModel.resetAdjustments(for: .baseImage), "Resetting an unadjusted photo is not an edit.")
        viewModel.setAdjustments(recipe, for: .baseImage)
        #expect(!viewModel.setAdjustments(recipe, for: .baseImage), "An unchanged recipe is not an edit.")
        #expect(viewModel.resetAdjustments(for: .baseImage))
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: ThumbnailDocumentLayer.backgroundID)?.adjustments == nil)
        #expect(viewModel.simpleMakerConfiguration.document.imageData == baseline)

        viewModel.undo()
        #expect(viewModel.adjustments(for: .baseImage) == recipe)
        viewModel.undo()
        #expect(viewModel.adjustments(for: .baseImage).isNeutral)
        #expect(viewModel.simpleMakerConfiguration.selectedImage != nil)
    }

    @Test func sliderDragIsASingleUndoStep() throws {
        let (viewModel, _, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }

        var value = ThumbnailImageAdjustments.neutral
        for tick in 1...25 {
            value.brightness = Double(tick) * 0.01
            viewModel.updateAdjustments(value, for: .baseImage)
        }
        viewModel.commitAdjustmentsEdit()
        #expect(viewModel.adjustments(for: .baseImage).brightness == 0.25)

        viewModel.undo()
        #expect(viewModel.adjustments(for: .baseImage).isNeutral, "One drag must undo in one step.")
        #expect(viewModel.simpleMakerConfiguration.selectedImage != nil)
    }

    @Test func applyLookUsesTheExactRecipe() throws {
        let (viewModel, _, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }
        let look = try #require(ThumbnailLookLibrary.builtIns.first { $0.id == "look-mono" })

        #expect(viewModel.applyLook(look, to: .baseImage))
        #expect(viewModel.adjustments(for: .baseImage) == look.adjustments)
        #expect(!viewModel.applyLook(look, to: .baseImage))
    }

    @Test func nothingToAdjustChangesNothing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        #expect(!viewModel.hasAdjustableImages)
        #expect(!viewModel.canAdjust(.baseImage))
        #expect(!viewModel.setAdjustments(recipe, for: .baseImage))
        viewModel.updateAdjustments(recipe, for: .baseImage)
        #expect(viewModel.simpleMakerConfiguration.layers.allSatisfy { $0.adjustments == nil })
        #expect(!viewModel.canUndo)
    }

    @Test func contentImageLayerAdjustsWithoutTouchingItsBytes() throws {
        let (viewModel, _, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }
        let layerData = try #require(makeImage().pngData())
        let selection = viewModel.addImageLayer(imageData: layerData)
        guard case .content(let layerID) = selection else {
            Issue.record("Expected a content layer selection")
            return
        }

        #expect(viewModel.adjustableImages.map(\.target) == [.baseImage, .contentLayer(layerID)])
        #expect(viewModel.setAdjustments(recipe, for: .contentLayer(layerID)))
        #expect(viewModel.adjustments(for: .baseImage).isNeutral)
        let layer = try #require(viewModel.simpleMakerConfiguration.layers.record(id: layerID))
        #expect(layer.adjustments == recipe)
        if case .image(let content) = layer.content {
            #expect(content.imageData == layerData)
        } else {
            Issue.record("Layer lost its image content")
        }

        // Duplicating an adjusted layer copies its look.
        let duplicate = try #require(viewModel.duplicateLayer(selection))
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: duplicate.documentLayerID)?.adjustments == recipe)
    }

    @Test func premiumProfileAndPhotoAdjustmentsPersistAndUndo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium.json"))
        let viewModel = PremiumMakerViewModel(
            draftStore: store,
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        viewModel.premiumMakerConfiguration.selectedImage = makeImage()
        viewModel.premiumMakerConfiguration.circularProfile = CircularProfileConfig(image: makeImage(), size: 0.2)
        viewModel.reconcileLayersForCurrentOverlays()
        viewModel.commitEditorStateNow()

        #expect(viewModel.adjustableImages.map(\.target) == [.baseImage, .profileImage])
        #expect(viewModel.setAdjustments(recipe, for: .profileImage))
        let look = try #require(ThumbnailLookLibrary.builtIns.first)
        #expect(viewModel.applyLook(look, to: .baseImage))

        let restored = try #require(try store.loadPremium())
        #expect(restored.layers.adjustments(forLayerID: ThumbnailDocumentLayer.profileID) == recipe)
        #expect(restored.layers.adjustments(forLayerID: ThumbnailDocumentLayer.backgroundID) == look.adjustments)

        viewModel.undo()
        #expect(viewModel.adjustments(for: .baseImage).isNeutral)
        #expect(viewModel.adjustments(for: .profileImage) == recipe)
        viewModel.undo()
        #expect(viewModel.adjustments(for: .profileImage).isNeutral)
        #expect(viewModel.premiumMakerConfiguration.circularProfile?.image != nil)
    }

    // MARK: Helpers

    private func makeSimple() -> (SimpleMakerViewModel, ThumbnailDraftStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json"))
        let viewModel = SimpleMakerViewModel(
            draftStore: store,
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        viewModel.simpleMakerConfiguration.selectedImage = makeImage()
        // Settle the image pick as its own undo step so adjustment steps are isolated.
        viewModel.commitEditorStateNow()
        return (viewModel, store, directory)
    }

    private func makeImage() -> UIImage {
        let size = CGSize(width: 32, height: 18)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.orange.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height / 2))
        }
    }
}
