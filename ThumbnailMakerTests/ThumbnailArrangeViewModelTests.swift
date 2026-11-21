//
//  ThumbnailArrangeViewModelTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-07: arrange commands on both editors are single undo steps, record
//  nothing when they change nothing, and persist groups in the draft.
//

import CoreGraphics
import Foundation
import Testing
@testable import ThumbnailMaker

@MainActor
struct ThumbnailArrangeViewModelTests {
    private func makeSimple() -> (SimpleMakerViewModel, ThumbnailDraftStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json"))
        let viewModel = SimpleMakerViewModel(
            draftStore: store,
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        return (viewModel, store, directory)
    }

    private func makePremium() -> (PremiumMakerViewModel, ThumbnailDraftStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium.json"))
        let viewModel = PremiumMakerViewModel(
            draftStore: store,
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        return (viewModel, store, directory)
    }

    private func undoDepth<Editor: ThumbnailArrangeEditing>(_ editor: Editor, canUndo: () -> Bool, undo: () -> Void, redo: () -> Void) -> Int {
        var depth = 0
        while canUndo() {
            undo()
            depth += 1
        }
        for _ in 0..<depth { redo() }
        return depth
    }

    private func premiumDepth(_ viewModel: PremiumMakerViewModel) -> Int {
        undoDepth(viewModel, canUndo: { viewModel.canUndo }, undo: viewModel.undo, redo: viewModel.redo)
    }

    private func simpleDepth(_ viewModel: SimpleMakerViewModel) -> Int {
        undoDepth(viewModel, canUndo: { viewModel.canUndo }, undo: viewModel.undo, redo: viewModel.redo)
    }

    // MARK: Premium

    @Test func premiumGroupAndUngroupAreSingleUndoSteps() throws {
        let (viewModel, store, directory) = makePremium()
        defer { try? FileManager.default.removeItem(at: directory) }

        let a = viewModel.addShapeLayer(.rectangle)
        let b = viewModel.addShapeLayer(.ellipse)
        let depth = premiumDepth(viewModel)

        let result = viewModel.groupSelection([a, b])
        #expect(result.applied)
        #expect(result.announcement.contains("Group 1"))
        let groupID = try #require(viewModel.premiumMakerConfiguration.layers.groupID(for: a))
        #expect(viewModel.premiumMakerConfiguration.layers.groupID(for: b) == groupID)
        #expect(premiumDepth(viewModel) == depth + 1)

        let saved = try #require(try store.load())
        #expect(saved.layers.groupID(forLayerID: a.documentLayerID) == groupID, "The draft keeps the group")

        let again = viewModel.groupSelection([a, b])
        #expect(!again.applied, "Regrouping the same group is a no-op")
        #expect(premiumDepth(viewModel) == depth + 1)

        #expect(viewModel.ungroupSelection([a]).applied)
        #expect(viewModel.premiumMakerConfiguration.layers.groupID(for: b) == nil)
        #expect(premiumDepth(viewModel) == depth + 2)

        viewModel.undo()
        #expect(viewModel.premiumMakerConfiguration.layers.groupID(for: b) == groupID)
        viewModel.undo()
        #expect(viewModel.premiumMakerConfiguration.layers.groupID(for: a) == nil)
        viewModel.redo()
        #expect(viewModel.premiumMakerConfiguration.layers.groupID(for: a) == groupID)
    }

    @Test func premiumAlignMovesAGroupRigidlyInOneStep() throws {
        let (viewModel, _, directory) = makePremium()
        defer { try? FileManager.default.removeItem(at: directory) }

        let a = viewModel.addShapeLayer(.rectangle)
        let b = viewModel.addShapeLayer(.rectangle)
        viewModel.premiumMakerConfiguration.setArrangeCenter(CGPoint(x: 0.3, y: 0.5), for: a)
        viewModel.premiumMakerConfiguration.setArrangeCenter(CGPoint(x: 0.4, y: 0.6), for: b)
        viewModel.commitEditorStateNow()
        viewModel.groupSelection([a, b])
        let before = viewModel.premiumMakerConfiguration.layers
        let depth = premiumDepth(viewModel)

        let result = viewModel.alignSelection([a], edge: .left, reference: .canvas)
        #expect(result.applied)
        #expect(premiumDepth(viewModel) == depth + 1)
        let centerA = try #require(viewModel.premiumMakerConfiguration.arrangeCenter(for: a))
        let centerB = try #require(viewModel.premiumMakerConfiguration.arrangeCenter(for: b))
        #expect(abs((centerB.x - centerA.x) - 0.1) < 0.0001, "Offsets inside the group are kept")
        #expect(abs((centerB.y - centerA.y) - 0.1) < 0.0001)

        viewModel.undo()
        #expect(viewModel.premiumMakerConfiguration.layers == before, "Undo restores the previous layout exactly")
    }

    @Test func premiumLockedLayerIsNotMovedAndNoOpRecordsNothing() throws {
        let (viewModel, _, directory) = makePremium()
        defer { try? FileManager.default.removeItem(at: directory) }

        let a = viewModel.addShapeLayer(.rectangle)
        viewModel.toggleLayerLock(a)
        viewModel.commitEditorStateNow()
        let depth = premiumDepth(viewModel)
        let before = viewModel.premiumMakerConfiguration.layers

        let result = viewModel.nudgeSelection([a], dx: 0.05, dy: 0)
        #expect(!result.applied)
        #expect(result.announcement.contains("Locked"))
        #expect(viewModel.premiumMakerConfiguration.layers == before)
        #expect(premiumDepth(viewModel) == depth)
    }

    // MARK: Simple

    @Test func simpleDistributeIncludesTheTextOverlay() throws {
        let (viewModel, store, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }

        viewModel.simpleMakerConfiguration.overlayText = "Hi"
        viewModel.simpleMakerConfiguration.textTransform = ThumbnailOverlayTransform(x: 0.2, y: 0.5)
        viewModel.commitEditorStateNow()
        let middle = viewModel.addShapeLayer(.rectangle)
        let right = viewModel.addShapeLayer(.rectangle)
        viewModel.simpleMakerConfiguration.setArrangeCenter(CGPoint(x: 0.3, y: 0.5), for: middle)
        viewModel.simpleMakerConfiguration.setArrangeCenter(CGPoint(x: 0.8, y: 0.5), for: right)
        viewModel.commitEditorStateNow()
        let depth = simpleDepth(viewModel)

        let result = viewModel.distributeSelection([.textOverlay, middle, right], mode: .horizontalCenters)
        #expect(result.applied)
        #expect(simpleDepth(viewModel) == depth + 1)
        let center = try #require(viewModel.simpleMakerConfiguration.arrangeCenter(for: middle))
        #expect(abs(center.x - 0.5) < 0.0001)
        #expect(viewModel.simpleMakerConfiguration.textTransform.x == 0.2, "Extremes stay fixed")

        let saved = try #require(try store.load())
        let savedCenter = try #require(saved.arrangeCenter(for: middle))
        #expect(abs(savedCenter.x - 0.5) < 0.0001)
    }

    @Test func simpleNudgeMovesTextOverlayAndGroupedContentTogether() throws {
        let (viewModel, _, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }

        viewModel.simpleMakerConfiguration.overlayText = "Title"
        viewModel.commitEditorStateNow()
        let shape = viewModel.addShapeLayer(.rectangle)
        #expect(viewModel.groupSelection([.textOverlay, shape]).applied)
        let textBefore = viewModel.simpleMakerConfiguration.textTransform.x
        let shapeBefore = try #require(viewModel.simpleMakerConfiguration.arrangeCenter(for: shape)).x

        #expect(viewModel.nudgeSelection([shape], dx: 0.01, dy: 0).applied)
        #expect(abs(viewModel.simpleMakerConfiguration.textTransform.x - (textBefore + 0.01)) < 0.0001)
        let shapeAfter = try #require(viewModel.simpleMakerConfiguration.arrangeCenter(for: shape)).x
        #expect(abs(shapeAfter - (shapeBefore + 0.01)) < 0.0001)
        #expect(viewModel.arrangeSummary(for: [shape]).contains("1 group"))
    }

    @Test func deletingAGroupMemberDissolvesTheGroupInTheEditor() throws {
        let (viewModel, _, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }

        let a = viewModel.addShapeLayer(.rectangle)
        let b = viewModel.addShapeLayer(.rectangle)
        viewModel.groupSelection([a, b])
        _ = viewModel.deleteLayer(a)
        #expect(viewModel.simpleMakerConfiguration.layers.record(for: b)?.groupID == nil)
        #expect(!viewModel.canUngroup([b]))
    }
}
