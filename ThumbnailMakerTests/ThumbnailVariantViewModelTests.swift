//
//  ThumbnailVariantViewModelTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-02: variants wired through both editors — isolation, independent
//  undo, persistence, migration and export naming.
//

import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ThumbnailVariantViewModelTests {
    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func simpleViewModel(in directory: URL) -> SimpleMakerViewModel {
        SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
    }

    private func premiumViewModel(in directory: URL) -> PremiumMakerViewModel {
        PremiumMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
    }

    private func text(_ viewModel: SimpleMakerViewModel, _ slot: ThumbnailVariantSlot) -> String? {
        viewModel.variantSet.document(for: slot)?.text.value
    }

    private func edit(_ viewModel: SimpleMakerViewModel, to value: String) {
        viewModel.simpleMakerConfiguration.overlayText = value
        viewModel.commitEditorStateNow()
    }

    @Test func editingVariantBDoesNotAlterAOrC() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = simpleViewModel(in: directory)
        edit(viewModel, to: "Alpha")
        #expect(viewModel.duplicateActiveVariant() == .b)
        edit(viewModel, to: "Bravo")
        #expect(viewModel.duplicateActiveVariant() == .c)
        edit(viewModel, to: "Charlie")
        #expect(viewModel.canAddVariant == false)
        #expect(viewModel.duplicateActiveVariant() == nil)

        let snapshotA = try #require(viewModel.variantSet.document(for: .a)).text
        let snapshotC = try #require(viewModel.variantSet.document(for: .c)).text

        viewModel.selectVariant(.b)
        #expect(viewModel.simpleMakerConfiguration.overlayText == "Bravo")
        edit(viewModel, to: "Bravo 2")
        viewModel.simpleMakerConfiguration.backgroundColor = .purple
        viewModel.commitEditorStateNow()

        #expect(viewModel.variantSet.document(for: .a)?.text == snapshotA)
        #expect(viewModel.variantSet.document(for: .c)?.text == snapshotC)
        #expect(text(viewModel, .b) == "Bravo 2")

        viewModel.selectVariant(.a)
        #expect(viewModel.simpleMakerConfiguration.overlayText == "Alpha")
        viewModel.selectVariant(.c)
        #expect(viewModel.simpleMakerConfiguration.overlayText == "Charlie")
    }

    @Test func undoAfterSwitchingVariantsAffectsOnlyTheActiveVariant() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = simpleViewModel(in: directory)
        edit(viewModel, to: "A1")
        edit(viewModel, to: "A2")
        viewModel.duplicateActiveVariant()
        #expect(viewModel.canUndo == false)
        edit(viewModel, to: "B1")
        #expect(viewModel.canUndo)

        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.overlayText == "A2")
        #expect(viewModel.canUndo == false)
        #expect(viewModel.canRedo)
        #expect(text(viewModel, .a) == "A2")

        viewModel.selectVariant(.a)
        #expect(viewModel.canUndo)
        #expect(viewModel.canRedo == false)
        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.overlayText == "A1")
        #expect(text(viewModel, .b) == "A2")
    }

    @Test func switchingVariantsDoesNotResetUndoAvailability() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = simpleViewModel(in: directory)
        edit(viewModel, to: "A1")
        viewModel.duplicateActiveVariant()
        viewModel.selectVariant(.a)
        #expect(viewModel.canUndo)
        viewModel.selectVariant(.b)
        #expect(viewModel.canUndo == false)
        viewModel.selectVariant(.a)
        #expect(viewModel.canUndo)
    }

    @Test func preVariantDraftOpensAsASingleVariantSet() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var legacy = SimpleMakerConfigurationModel()
        legacy.overlayText = "Legacy draft"
        legacy.selectedRatio = .ratio4_3
        try ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json")).save(legacy)

        let viewModel = simpleViewModel(in: directory)
        #expect(viewModel.restoredDraft)
        #expect(viewModel.variantSet.slots == [.a])
        #expect(viewModel.variantSet.preferredSlot == nil)
        #expect(viewModel.simpleMakerConfiguration.overlayText == "Legacy draft")
        #expect(viewModel.simpleMakerConfiguration.selectedRatio == .ratio4_3)
        #expect(viewModel.variantWarning == nil)
        #expect(viewModel.canUndo == false)
    }

    @Test func reopeningRestoresAllThreeVariantsAndTheActiveAndPreferredSlots() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let viewModel = simpleViewModel(in: directory)
            edit(viewModel, to: "One")
            viewModel.duplicateActiveVariant()
            edit(viewModel, to: "Two")
            viewModel.duplicateActiveVariant()
            edit(viewModel, to: "Three")
            viewModel.renameVariant(.c, to: "Big face")
            viewModel.setPreferredVariant(.c)
            viewModel.selectVariant(.b)
        }

        let reopened = simpleViewModel(in: directory)
        #expect(reopened.restoredDraft)
        #expect(reopened.variantSet.slots == [.a, .b, .c])
        #expect(reopened.variantSet.activeSlot == .b)
        #expect(reopened.variantSet.preferredSlot == .c)
        #expect(reopened.variantSet.variant(for: .c)?.name == "Big face")
        #expect(reopened.simpleMakerConfiguration.overlayText == "Two")
        #expect(text(reopened, .a) == "One")
        #expect(text(reopened, .c) == "Three")
    }

    @Test func removingAVariantPersistsAndKeepsLetters() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = simpleViewModel(in: directory)
        edit(viewModel, to: "One")
        viewModel.duplicateActiveVariant()
        edit(viewModel, to: "Two")
        viewModel.duplicateActiveVariant()
        edit(viewModel, to: "Three")
        viewModel.selectVariant(.b)
        viewModel.removeVariant(.b)
        #expect(viewModel.variantSet.slots == [.a, .c])
        #expect(viewModel.simpleMakerConfiguration.overlayText == "One")
        viewModel.removeVariant(.a)
        viewModel.removeVariant(.c)
        #expect(viewModel.variantSet.slots == [.c])

        let reopened = simpleViewModel(in: directory)
        #expect(reopened.variantSet.slots == [.c])
        #expect(reopened.simpleMakerConfiguration.overlayText == "Three")
    }

    @Test func exportBaseNameIsUnchangedForSingleVariantUsers() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = simpleViewModel(in: directory)
        #expect(viewModel.variantExportBaseName == viewModel.simpleMakerConfiguration.exportOptions.preset.id)
        let premium = premiumViewModel(in: directory)
        #expect(premium.variantExportBaseName == premium.premiumMakerConfiguration.exportOptions.preset.id)
    }

    @Test func exportBaseNameCarriesTheActiveSlot() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = simpleViewModel(in: directory)
        viewModel.setVariantProjectName("Episode 7")
        viewModel.duplicateActiveVariant()
        viewModel.duplicateActiveVariant()
        #expect(viewModel.variantExportBaseName == "episode-7-variant-c")
        viewModel.selectVariant(.a)
        #expect(viewModel.variantExportBaseName == "episode-7-variant-a")
        viewModel.setPreferredVariant(.a)
        #expect(viewModel.variantExportBaseName == "episode-7-variant-a-preferred")
        viewModel.selectVariant(.b)
        #expect(viewModel.variantExportBaseName == "episode-7-variant-b")
        #expect(viewModel.variantExportPlan.entries.map(\.baseFileName) == [
            "episode-7-variant-a-preferred", "episode-7-variant-b", "episode-7-variant-c"
        ])
    }

    @Test func comparisonUsesTheLiveActiveEditAndOneSize() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = simpleViewModel(in: directory)
        edit(viewModel, to: "A")
        viewModel.duplicateActiveVariant()
        viewModel.simpleMakerConfiguration.overlayText = "B unsaved"
        let comparison = try #require(viewModel.variantComparison(previewSize: .mobile))
        #expect(comparison.panes.map(\.document.text.value) == ["A", "B unsaved"])
        #expect(comparison.renderSize == ThumbnailSmallPreviewSize.mobile.size(for: .ratio16_9))
    }

    @Test func variantSaveFailureSurfacesAnErrorAndKeepsTheActiveDesign() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // The variant file path is an existing directory, so its write fails
        // while the legacy draft write succeeds.
        let blocked = directory.appendingPathComponent("blocked")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        let viewModel = SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json")),
            variantStore: ThumbnailVariantStore(fileURL: blocked)
        )
        edit(viewModel, to: "Keep me")
        viewModel.duplicateActiveVariant()

        #expect(viewModel.draftSaveState.failureMessage != nil)
        #expect(viewModel.saveError != nil)
        #expect(viewModel.variantSet.slots == [.a, .b])
        #expect(viewModel.simpleMakerConfiguration.overlayText == "Keep me")
        let legacy = try #require(try ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json")).load())
        #expect(legacy.overlayText == "Keep me")
    }

    @Test func premiumVariantsAreIsolatedAndUndoIndependently() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = premiumViewModel(in: directory)
        viewModel.premiumMakerConfiguration.overlayText = "PA"
        viewModel.commitEditorStateNow()
        #expect(viewModel.duplicateActiveVariant() == .b)
        viewModel.premiumMakerConfiguration.overlayText = "PB"
        viewModel.commitEditorStateNow()
        #expect(viewModel.variantSet.document(for: .a)?.text.value == "PA")

        viewModel.undo()
        #expect(viewModel.premiumMakerConfiguration.overlayText == "PA")
        #expect(viewModel.canUndo == false)
        viewModel.selectVariant(.a)
        #expect(viewModel.canUndo)
        viewModel.setPreferredVariant(.b)

        let reopened = premiumViewModel(in: directory)
        #expect(reopened.variantSet.slots == [.a, .b])
        #expect(reopened.variantSet.activeSlot == .a)
        #expect(reopened.variantSet.preferredSlot == .b)
        #expect(reopened.premiumMakerConfiguration.overlayText == "PA")
        #expect(reopened.variantSet.editorMode == .premium)
    }
}
