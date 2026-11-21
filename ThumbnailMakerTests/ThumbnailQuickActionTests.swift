//
//  ThumbnailQuickActionTests.swift
//  ThumbnailMakerTests
//
//  EDITOR (1.1.0 parity): quick actions are single undo steps that reuse the
//  existing intents, respect locks, and record nothing when they change
//  nothing; the asset library dedupes project images and brand logos.
//

import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ThumbnailQuickActionTests {
    private func makeSimple() -> (SimpleMakerViewModel, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let viewModel = SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        return (viewModel, directory)
    }

    private func makePremium() -> (PremiumMakerViewModel, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let viewModel = PremiumMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        return (viewModel, directory)
    }

    private func depth(canUndo: () -> Bool, undo: () -> Void, redo: () -> Void) -> Int {
        var count = 0
        while canUndo() {
            undo()
            count += 1
        }
        for _ in 0..<count { redo() }
        return count
    }

    private func simpleDepth(_ viewModel: SimpleMakerViewModel) -> Int {
        depth(canUndo: { viewModel.canUndo }, undo: viewModel.undo, redo: viewModel.redo)
    }

    private func premiumDepth(_ viewModel: PremiumMakerViewModel) -> Int {
        depth(canUndo: { viewModel.canUndo }, undo: viewModel.undo, redo: viewModel.redo)
    }

    private func pngData(_ color: UIColor, side: CGFloat = 8) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
            .image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            }
            .pngData() ?? Data()
    }

    // MARK: Center, flip, reset

    @Test func centerHorizontallyIsOneUndoStepAndThenANoOp() throws {
        let (viewModel, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }

        let shape = viewModel.addShapeLayer(.rectangle)
        viewModel.nudgeSelection([shape], dx: 0.2, dy: 0.1)
        let before = try #require(viewModel.simpleMakerConfiguration.arrangeTransform(for: shape))
        #expect(abs(before.x - 0.7) < 0.001)
        let startDepth = simpleDepth(viewModel)

        let outcome = viewModel.performQuickAction(.centerHorizontally, on: shape)
        #expect(outcome.applied)
        let centered = try #require(viewModel.simpleMakerConfiguration.arrangeTransform(for: shape))
        #expect(abs(centered.x - 0.5) < 0.001)
        #expect(abs(centered.y - before.y) < 0.001, "Centering horizontally keeps the vertical position")
        #expect(simpleDepth(viewModel) == startDepth + 1)

        let again = viewModel.performQuickAction(.centerHorizontally, on: shape)
        #expect(!again.applied)
        #expect(simpleDepth(viewModel) == startDepth + 1, "A no-op records no history")

        #expect(viewModel.performQuickAction(.centerVertically, on: shape).applied)
        let both = try #require(viewModel.simpleMakerConfiguration.arrangeTransform(for: shape))
        #expect(abs(both.y - 0.5) < 0.001)

        viewModel.undo()
        viewModel.undo()
        let restored = try #require(viewModel.simpleMakerConfiguration.arrangeTransform(for: shape))
        #expect(abs(restored.x - before.x) < 0.001)
    }

    @Test func flipAndResetTransformAreSingleUndoSteps() throws {
        let (viewModel, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sticker = viewModel.addStickerLayer(imageData: pngData(.red))
        viewModel.nudgeSelection([sticker], dx: -0.2, dy: 0.2)
        let startDepth = simpleDepth(viewModel)

        #expect(viewModel.performQuickAction(.flip, on: sticker).applied)
        let flipped = try #require(viewModel.simpleMakerConfiguration.arrangeTransform(for: sticker))
        #expect(flipped.isFlippedHorizontally)
        #expect(simpleDepth(viewModel) == startDepth + 1)

        #expect(viewModel.performQuickAction(.resetTransform, on: sticker).applied)
        let reset = try #require(viewModel.simpleMakerConfiguration.arrangeTransform(for: sticker))
        #expect(reset == .centered)
        #expect(simpleDepth(viewModel) == startDepth + 2)

        #expect(!viewModel.performQuickAction(.resetTransform, on: sticker).applied)
        #expect(simpleDepth(viewModel) == startDepth + 2)

        viewModel.undo()
        let undone = try #require(viewModel.simpleMakerConfiguration.arrangeTransform(for: sticker))
        #expect(undone.isFlippedHorizontally)
        #expect(abs(undone.x - 0.3) < 0.001)
    }

    @Test func lockedLayersRefuseTransformActions() throws {
        let (viewModel, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }

        let shape = viewModel.addShapeLayer(.ellipse)
        viewModel.nudgeSelection([shape], dx: 0.1, dy: 0)
        viewModel.toggleLayerLock(shape)
        viewModel.commitEditorStateNow()
        let startDepth = simpleDepth(viewModel)

        for action in [ThumbnailQuickAction.flip, .resetTransform, .centerHorizontally, .centerVertically] {
            #expect(!viewModel.canPerformQuickAction(action, on: shape))
            let outcome = viewModel.performQuickAction(action, on: shape)
            #expect(!outcome.applied)
            #expect(outcome.announcement == "Layer is locked.")
        }
        #expect(simpleDepth(viewModel) == startDepth)
        #expect(viewModel.canPerformQuickAction(.duplicate, on: shape), "Duplicating a locked layer is still allowed")
    }

    @Test func textOverlayCanFlipButNotDuplicateOrDelete() throws {
        let (viewModel, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }

        viewModel.simpleMakerConfiguration.overlayText = "Hello"
        viewModel.reconcileLayersForCurrentOverlays()
        viewModel.commitEditorStateNow()

        #expect(!viewModel.canPerformQuickAction(.duplicate, on: .textOverlay))
        #expect(!viewModel.canPerformQuickAction(.delete, on: .textOverlay))
        #expect(viewModel.performQuickAction(.flip, on: .textOverlay).applied)
        #expect(viewModel.simpleMakerConfiguration.textTransform.isFlippedHorizontally)
    }

    // MARK: Order, duplicate, delete

    @Test func bringToFrontAndSendToBackMoveAllTheWayInOneStep() throws {
        let (viewModel, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }

        let a = viewModel.addShapeLayer(.rectangle)
        let b = viewModel.addShapeLayer(.ellipse)
        let c = viewModel.addShapeLayer(.rectangle)
        let startDepth = simpleDepth(viewModel)

        #expect(!viewModel.canPerformQuickAction(.bringToFront, on: c))
        #expect(viewModel.performQuickAction(.sendToBack, on: c).applied)
        var order = viewModel.simpleMakerConfiguration.layers.sortedSelections(viewModel.selectableLayerSelections)
        #expect(order == [c, a, b])
        #expect(simpleDepth(viewModel) == startDepth + 1)

        #expect(viewModel.performQuickAction(.bringToFront, on: c).applied)
        order = viewModel.simpleMakerConfiguration.layers.sortedSelections(viewModel.selectableLayerSelections)
        #expect(order.last == c)
        #expect(simpleDepth(viewModel) == startDepth + 2)

        viewModel.undo()
        order = viewModel.simpleMakerConfiguration.layers.sortedSelections(viewModel.selectableLayerSelections)
        #expect(order.first == c)
    }

    @Test func duplicateAndDeleteReuseViewModelIntents() throws {
        let (viewModel, directory) = makePremium()
        defer { try? FileManager.default.removeItem(at: directory) }

        let shape = viewModel.addShapeLayer(.rectangle)
        let startDepth = premiumDepth(viewModel)

        let duplicated = viewModel.performQuickAction(.duplicate, on: shape)
        #expect(duplicated.applied)
        #expect(duplicated.selection != shape)
        #expect(viewModel.premiumMakerConfiguration.layers.filter { $0.content != nil }.count == 2)
        #expect(premiumDepth(viewModel) == startDepth + 1)

        let deleted = viewModel.performQuickAction(.delete, on: duplicated.selection)
        #expect(deleted.applied)
        #expect(viewModel.premiumMakerConfiguration.layers.filter { $0.content != nil }.count == 1)
        #expect(premiumDepth(viewModel) == startDepth + 2)
    }

    @Test func premiumFlipIsOneUndoStep() throws {
        let (viewModel, directory) = makePremium()
        defer { try? FileManager.default.removeItem(at: directory) }

        let text = viewModel.addTextLayer(value: "Wow")
        let startDepth = premiumDepth(viewModel)
        #expect(viewModel.performQuickAction(.flip, on: text).applied)
        #expect(viewModel.premiumMakerConfiguration.arrangeTransform(for: text)?.isFlippedHorizontally == true)
        #expect(premiumDepth(viewModel) == startDepth + 1)
        viewModel.undo()
        #expect(viewModel.premiumMakerConfiguration.arrangeTransform(for: text)?.isFlippedHorizontally == false)
    }

    // MARK: Asset library

    @Test func builtInStickersDecodeAndInsertAsStickerLayers() throws {
        let (viewModel, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }

        let stickers = ThumbnailAssetLibrary.builtInStickers
        #expect(stickers.count == ThumbnailAssetLibrary.stickerEmoji.count)
        #expect(Set(stickers.map(\.id)).count == stickers.count, "Sticker ids are unique")
        let first = try #require(stickers.first)
        #expect(UIImage(data: first.imageData) != nil)

        let startDepth = simpleDepth(viewModel)
        let inserted = try #require(viewModel.insertLibraryAsset(first))
        guard case .content(let id) = inserted,
              case .image(let content) = viewModel.simpleMakerConfiguration.layers.record(id: id)?.content else {
            Issue.record("Expected an image content layer")
            return
        }
        #expect(content.isSticker)
        #expect(simpleDepth(viewModel) == startDepth + 1)
    }

    @Test func invalidAssetDataIsRejectedWithoutHistory() {
        let (viewModel, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }

        let startDepth = simpleDepth(viewModel)
        let bogus = ThumbnailAssetLibraryItem(
            id: "bogus",
            title: "Bogus",
            source: .recent,
            insertKind: .image,
            imageData: Data([0, 1, 2])
        )
        #expect(viewModel.insertLibraryAsset(bogus) == nil)
        #expect(simpleDepth(viewModel) == startDepth)
    }

    @Test func recentAssetsDedupeAndKeepKind() {
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: false, hasProfile: false)
        let red = pngData(.red)
        let blue = pngData(.blue)
        layers.addImageLayer(imageData: red)
        layers.addImageLayer(imageData: red)
        layers.addStickerLayer(imageData: blue)

        let recent = ThumbnailAssetLibrary.recentAssets(in: layers)
        #expect(recent.count == 2)
        #expect(recent.first?.insertKind == .sticker, "Newest (top) layer first")
        #expect(recent.last?.insertKind == .image)
        #expect(Set(recent.map(\.id)).count == 2)
    }

    @Test func brandAssetsListActiveKitLogoFirstAndSkipKitsWithoutLogos() {
        let logoA = pngData(.green)
        let logoB = pngData(.orange)
        let library = BrandKitLibrary(
            kits: [
                BrandKit(id: "a", name: "Alpha", logoImageData: logoA),
                BrandKit(id: "b", name: "Beta", logoImageData: logoB),
                BrandKit(id: "c", name: "Gamma"),
                BrandKit(id: "d", name: "Delta", logoImageData: logoA)
            ],
            activeKitID: "b"
        )

        let assets = ThumbnailAssetLibrary.brandAssets(in: library)
        #expect(assets.map(\.title) == ["Beta logo", "Alpha logo"])
        #expect(assets.allSatisfy { $0.insertKind == .image })
        #expect(ThumbnailAssetLibrary.brandAssets(in: .empty).isEmpty)
    }
}
