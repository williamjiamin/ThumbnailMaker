//
//  ImmediateUndoTests.swift
//  ThumbnailMakerTests
//
//  Regression: edits are recorded into history on a 0.6s debounce, and Undo used to stay
//  disabled until that commit landed, so a tap or Cmd-Z right after an edit did nothing.
//  Found by an intermittent failure in testUndoRedoKeyboardShortcutsRevertOverlayText.
//

import Foundation
import Testing
@testable import ThumbnailMaker

@MainActor
struct ImmediateUndoTests {
    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @Test func simpleEditorEnablesUndoImmediatelyAndRevertsPendingEdit() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand.json"))
        )
        let original = viewModel.simpleMakerConfiguration.overlayText

        viewModel.simpleMakerConfiguration.overlayText = "Typed just now"

        // No waiting for the debounce: undo must already be available.
        #expect(viewModel.canUndo)
        #expect(!viewModel.canRedo)
        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.overlayText == original)
        #expect(viewModel.canRedo)
    }

    @Test func premiumEditorEnablesUndoImmediatelyAndRevertsPendingEdit() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = PremiumMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand.json"))
        )
        let original = viewModel.premiumMakerConfiguration.overlayText

        viewModel.premiumMakerConfiguration.overlayText = "Typed just now"

        #expect(viewModel.canUndo)
        viewModel.undo()
        #expect(viewModel.premiumMakerConfiguration.overlayText == original)
    }
}
