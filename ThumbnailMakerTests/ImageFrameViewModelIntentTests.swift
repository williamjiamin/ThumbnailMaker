//
//  ImageFrameViewModelIntentTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-03: framing intents on both editors are single undo steps,
//  persist to the draft, survive image replacement, and leave pixels alone.
//

import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ImageFrameViewModelIntentTests {
    private let recipeA = ThumbnailImageFrameRecipe(fit: .fill, focusX: 0.2, focusY: 0.8, zoom: 2.5)
    private let recipeB = ThumbnailImageFrameRecipe(fit: .fill, focusX: 0.7, focusY: 0.3, zoom: 1.5)
    private let recipeC = ThumbnailImageFrameRecipe(fit: .stretch)

    // MARK: Simple editor

    @Test func simpleSetRecipeIsOneUndoStepAndPersists() throws {
        let (viewModel, store, directory) = try makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }

        let stepsBefore = try undoDepth(viewModel)
        #expect(viewModel.setImageFrameRecipe(recipeA))
        #expect(viewModel.simpleMakerConfiguration.imageRecipe == recipeA)
        #expect(viewModel.canUndo)
        #expect(try #require(try store.load()).imageRecipe == recipeA)

        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.imageRecipe == .identity)
        #expect(viewModel.simpleMakerConfiguration.selectedImage != nil, "Undoing the frame must not undo the image pick.")
        #expect(viewModel.canRedo)
        #expect(try undoDepth(viewModel) == stepsBefore)

        viewModel.redo()
        #expect(viewModel.simpleMakerConfiguration.imageRecipe == recipeA)
    }

    @Test func simpleConsecutiveRecipesAreSeparateUndoSteps() throws {
        let (viewModel, _, directory) = try makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }

        viewModel.setImageFrameRecipe(recipeA)
        viewModel.setImageFrameRecipe(recipeB)
        viewModel.setImageFrameRecipe(recipeC)
        #expect(!viewModel.setImageFrameRecipe(recipeC), "An unchanged recipe is not an edit.")

        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.imageRecipe == recipeB)
        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.imageRecipe == recipeA)
        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.imageRecipe == .identity)
        #expect(viewModel.simpleMakerConfiguration.selectedImage != nil)
    }

    @Test func simpleResetIsSingleUndoableStep() throws {
        let (viewModel, _, directory) = try makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }

        viewModel.setImageFrameRecipe(recipeA)
        #expect(viewModel.resetImageFrame())
        #expect(viewModel.simpleMakerConfiguration.imageRecipe == .identity)
        #expect(!viewModel.resetImageFrame())

        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.imageRecipe == recipeA)
    }

    @Test func simpleBindingWriteIsCommittedAsOneStep() throws {
        // The UI row writes through the configuration binding; the editor's
        // debounced commit turns that into exactly one history entry.
        let (viewModel, _, directory) = try makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }

        viewModel.simpleMakerConfiguration.imageRecipe = recipeB
        viewModel.commitEditorStateNow()
        #expect(viewModel.canUndo)
        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.imageRecipe == .identity)
        #expect(viewModel.simpleMakerConfiguration.selectedImage != nil)
        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.selectedImage == nil)
        #expect(!viewModel.canUndo)
    }

    @Test func simpleRecipeWithoutImageIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        #expect(!viewModel.setImageFrameRecipe(recipeA))
        #expect(viewModel.simpleMakerConfiguration.imageRecipe == .identity)
        #expect(!viewModel.canUndo)
    }

    @Test func simpleReplacingImageKeepsFrameUnlessAskedNotTo() throws {
        let (viewModel, _, directory) = try makeSimple(size: CGSize(width: 160, height: 40))
        defer { try? FileManager.default.removeItem(at: directory) }
        viewModel.setImageFrameRecipe(recipeA)

        let portrait = try #require(makeImage(size: CGSize(width: 30, height: 60)).pngData())
        let revision = viewModel.beginImageImport()
        #expect(viewModel.applyImportedImageData(portrait, revision: revision))
        #expect(viewModel.simpleMakerConfiguration.selectedImage?.size == CGSize(width: 30, height: 60))
        #expect(viewModel.simpleMakerConfiguration.imageRecipe == recipeA)

        let next = viewModel.beginImageImport()
        #expect(viewModel.applyImportedImageData(portrait, revision: next, preservingFrame: false))
        #expect(viewModel.simpleMakerConfiguration.imageRecipe == .identity)
    }

    @Test func simpleStaleOrUndecodableImportLeavesFrameAlone() throws {
        let (viewModel, _, directory) = try makeSimple(size: CGSize(width: 160, height: 40))
        defer { try? FileManager.default.removeItem(at: directory) }
        viewModel.setImageFrameRecipe(recipeA)

        let stale = viewModel.beginImageImport()
        let current = viewModel.beginImageImport()
        let payload = try #require(makeImage(size: CGSize(width: 8, height: 8)).pngData())
        #expect(!viewModel.applyImportedImageData(payload, revision: stale, preservingFrame: false))
        #expect(viewModel.simpleMakerConfiguration.imageRecipe == recipeA)
        #expect(viewModel.simpleMakerConfiguration.selectedImage?.size == CGSize(width: 160, height: 40))

        #expect(!viewModel.applyImportedImageData(Data([0x00]), revision: current, preservingFrame: false))
        #expect(viewModel.imageImportError == .decodeFailed)
        #expect(viewModel.simpleMakerConfiguration.imageRecipe == recipeA)
        #expect(viewModel.simpleMakerConfiguration.selectedImage?.size == CGSize(width: 160, height: 40))
    }

    @Test func simpleFramingDoesNotAlterImagePixels() throws {
        let (viewModel, _, directory) = try makeSimple(size: CGSize(width: 16, height: 9))
        defer { try? FileManager.default.removeItem(at: directory) }
        let before = try #require(viewModel.simpleMakerConfiguration.document.imageData)

        viewModel.setImageFrameRecipe(recipeA)
        viewModel.setImageFrameRecipe(recipeC)
        let image = try #require(viewModel.simpleMakerConfiguration.selectedImage)
        #expect(image.size == CGSize(width: 16, height: 9))
        let after = try #require(viewModel.simpleMakerConfiguration.document.imageData)
        #expect(UIImage(data: after)?.size == UIImage(data: before)?.size)
        let beforePixels = try pixels(#require(UIImage(data: before)))
        let afterPixels = try pixels(#require(UIImage(data: after)))
        #expect(beforePixels == afterPixels)
    }

    // MARK: Premium editor

    @Test func premiumSetRecipeIsOneUndoStepAndPersists() throws {
        let (viewModel, store, directory) = try makePremium()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(viewModel.setImageFrameRecipe(recipeA))
        #expect(viewModel.canUndo)
        #expect(try #require(try store.loadPremium()).imageRecipe == recipeA)

        viewModel.setImageFrameRecipe(recipeB)
        viewModel.undo()
        #expect(viewModel.premiumMakerConfiguration.imageRecipe == recipeA)
        viewModel.undo()
        #expect(viewModel.premiumMakerConfiguration.imageRecipe == .identity)
        viewModel.redo()
        #expect(viewModel.premiumMakerConfiguration.imageRecipe == recipeA)
    }

    @Test func premiumResetAndReplaceKeepFrameSemantics() throws {
        let (viewModel, _, directory) = try makePremium()
        defer { try? FileManager.default.removeItem(at: directory) }

        viewModel.setImageFrameRecipe(recipeA)
        let replacement = try #require(makeImage(size: CGSize(width: 30, height: 60)).pngData())
        let revision = viewModel.beginImageImport()
        #expect(viewModel.applyImportedImageData(replacement, revision: revision))
        #expect(viewModel.premiumMakerConfiguration.imageRecipe == recipeA)

        #expect(viewModel.resetImageFrame())
        #expect(viewModel.premiumMakerConfiguration.imageRecipe == .identity)
        viewModel.undo()
        #expect(viewModel.premiumMakerConfiguration.imageRecipe == recipeA)
    }

    @Test func premiumTemplateKeepsFrame() throws {
        let (viewModel, _, directory) = try makePremium()
        defer { try? FileManager.default.removeItem(at: directory) }
        viewModel.setImageFrameRecipe(recipeA)

        let template = try #require(ThumbnailTemplate.builtIns.first)
        viewModel.applyTemplate(template)
        #expect(viewModel.premiumMakerConfiguration.imageRecipe == recipeA)
    }

    // MARK: Helpers

    private func makeSimple(
        size: CGSize = CGSize(width: 32, height: 18)
    ) throws -> (SimpleMakerViewModel, ThumbnailDraftStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json"))
        let viewModel = SimpleMakerViewModel(
            draftStore: store,
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        viewModel.simpleMakerConfiguration.selectedImage = makeImage(size: size)
        // Settle the image pick as its own undo step so framing steps are isolated.
        viewModel.commitEditorStateNow()
        return (viewModel, store, directory)
    }

    private func makePremium(
        size: CGSize = CGSize(width: 32, height: 18)
    ) throws -> (PremiumMakerViewModel, ThumbnailDraftStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium.json"))
        let viewModel = PremiumMakerViewModel(
            draftStore: store,
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        viewModel.premiumMakerConfiguration.selectedImage = makeImage(size: size)
        viewModel.commitEditorStateNow()
        return (viewModel, store, directory)
    }

    /// Counts undo steps by undoing to the bottom and redoing back up, leaving
    /// the editor exactly where it was.
    private func undoDepth(_ viewModel: SimpleMakerViewModel) throws -> Int {
        var depth = 0
        while viewModel.canUndo {
            viewModel.undo()
            depth += 1
        }
        for _ in 0..<depth { viewModel.redo() }
        return depth
    }

    private func makeImage(size: CGSize) -> UIImage {
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

    private func pixels(_ image: UIImage) throws -> [UInt8] {
        let cgImage = try #require(image.cgImage)
        let context = try #require(CGContext(
            data: nil, width: cgImage.width, height: cgImage.height, bitsPerComponent: 8,
            bytesPerRow: cgImage.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        let data = try #require(context.data)
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self),
                                         count: cgImage.width * cgImage.height * 4))
    }
}
