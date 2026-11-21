//
//  ExportQueueViewModelTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-10: reversible recipe drafts, delete + undo, destination errors,
//  run and retry through the sheet's view model, and the editor hooks.
//

import Foundation
import Testing
@testable import ThumbnailMaker

@MainActor
struct ExportQueueViewModelTests {
    private typealias Support = ExportQueueTestSupport

    private func makeModel(
        context: ThumbnailExportQueueContext = ExportQueueTestSupport.context(),
        destination: ThumbnailExportDestinationWriting? = nil,
        renderer: CountingExportRenderer? = nil
    ) -> (ExportQueueViewModel, ThumbnailExportRecipeStore, URL) {
        let destination = destination ?? InMemoryExportDestination()
        let renderer = renderer ?? CountingExportRenderer()
        let directory = Support.makeTemporaryDirectory()
        let store = ThumbnailExportRecipeStore(directory: directory)
        let model = ExportQueueViewModel(
            context: context,
            store: store,
            runner: ThumbnailExportQueueRunner(renderer: renderer),
            destination: destination,
            loadsRememberedFolder: false,
            formatIsAvailable: { _ in true }
        )
        return (model, store, directory)
    }

    @Test func startsWithYouTubeABCForA16x9Design() {
        let (model, _, directory) = makeModel()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(model.selectedRecipeID == ThumbnailExportRecipe.youTubeABCID)
        #expect(model.plan.jobs.count == 9)
        #expect(model.plan.summary == "9 files · 0 will replace · 0 blocked")
        #expect(model.canRun)
        #expect(!model.hasUnsavedChanges)
    }

    @Test func draftEditsAreReversible() {
        let (model, _, directory) = makeModel()
        defer { try? FileManager.default.removeItem(at: directory) }

        model.toggleSlot(.c)
        #expect(model.hasUnsavedChanges)
        #expect(!model.isSlotSelected(.c))
        #expect(model.plan.jobs.count == 6)
        #expect(model.plan.summary.hasPrefix("6 files"))

        model.removeSize(model.draft.sizes[0])
        #expect(model.plan.jobs.count == 4)

        model.revertDraft()
        #expect(!model.hasUnsavedChanges)
        #expect(model.plan.jobs.count == 9)
        #expect(model.draft == ThumbnailExportRecipe.youTubeABC)
    }

    @Test func toggleBackToEverySlotMeansAll() {
        let (model, _, directory) = makeModel()
        defer { try? FileManager.default.removeItem(at: directory) }
        model.toggleSlot(.b)
        model.toggleSlot(.b)
        #expect(model.draft.variantSelection == .all)
        #expect(!model.hasUnsavedChanges)
    }

    @Test func invalidSizesAreRejectedWithAMessage() {
        let (model, _, directory) = makeModel()
        defer { try? FileManager.default.removeItem(at: directory) }
        model.addCustomSize(width: 100, height: 50)
        #expect(model.errorMessage != nil)
        #expect(model.draft.sizes.count == 3)
        model.errorMessage = nil
        model.addCustomSize(width: 1920, height: 1080)
        #expect(model.errorMessage?.contains("already") == true)
        #expect(model.draft.sizes.count == 3)
    }

    @Test func saveAsNewUpdateDeleteAndUndo() throws {
        let (model, store, directory) = makeModel()
        defer { try? FileManager.default.removeItem(at: directory) }

        model.setFormat(.png)
        model.saveDraftAsNew(named: "PNG Set")
        let savedID = model.selectedRecipeID
        #expect(savedID != ThumbnailExportRecipe.youTubeABCID)
        #expect(store.load().recipes.map(\.name) == ["PNG Set"])
        #expect(!model.hasUnsavedChanges)
        #expect(!model.isDraftReadOnly)
        // The built-in is untouched.
        #expect(ThumbnailExportRecipe.youTubeABC.format == .jpeg)

        model.setQuality(0.5)
        model.updateSelectedRecipe()
        #expect(store.load().recipes.first?.compressionQuality == 0.5)

        model.deleteSelectedRecipe()
        #expect(store.load().recipes.isEmpty)
        #expect(model.recentlyDeletedRecipe?.id == savedID)
        #expect(model.selectedRecipeID == ThumbnailExportRecipe.youTubeABCID)

        model.undoDeleteRecipe()
        #expect(store.load().recipes.map(\.id) == [savedID])
        #expect(model.selectedRecipeID == savedID)
        #expect(model.draft.compressionQuality == 0.5)
    }

    @Test func builtInCannotBeUpdatedOrDeleted() {
        let (model, store, directory) = makeModel()
        defer { try? FileManager.default.removeItem(at: directory) }
        model.setFormat(.png)
        model.updateSelectedRecipe()
        model.deleteSelectedRecipe()
        #expect(store.load().recipes.isEmpty)
        #expect(model.selectedRecipeID == ThumbnailExportRecipe.youTubeABCID)
    }

    @Test func runThenRetryFailed() async throws {
        let destination = InMemoryExportDestination()
        let renderer = CountingExportRenderer()
        let projectID = UUID()
        let (model, store, directory) = makeModel(
            context: Support.context(projectID: projectID),
            destination: destination,
            renderer: renderer
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        // Keep the test fast: small sizes.
        model.removeSize(model.draft.sizes[0])
        model.removeSize(model.draft.sizes[0])
        let failing = model.plan.jobs[1].targetFileName
        destination.failingFileNames = [failing]
        destination.failOnce = true

        await model.run()

        #expect(model.runner.resultSummary == "2 exported · 1 failed")
        #expect(model.canRetry)
        #expect(store.lastRecipeID(forProject: projectID) == ThumbnailExportRecipe.youTubeABCID)

        await model.retryFailed()
        #expect(model.runner.resultSummary == "3 exported")
        #expect(renderer.renderCount == 4)
        #expect(!model.canRetry)
        #expect(destination.data(named: failing) != nil)
    }

    @Test func destinationErrorDisablesRun() throws {
        let directory = Support.makeTemporaryDirectory()
        let missing = directory.appendingPathComponent("gone", isDirectory: true)
        let (model, _, storeDirectory) = makeModel(
            destination: FolderExportDestination(folderURL: missing, usesSecurityScope: false)
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: storeDirectory)
        }
        #expect(model.destinationError != nil)
        #expect(!model.canRun)
    }

    @Test func photosDestinationExplainsNames() {
        let (model, _, directory) = makeModel(destination: PhotosExportDestination())
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(model.destinationNote == PhotosExportDestination.namesNotKeptNote)
        #expect(!model.snapshot.supportsFileNames)
    }

    @Test func editorHookSnapshotsLiveVariants() {
        let root = Support.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: root.appendingPathComponent("Drafts/simple.json")),
            brandKitStore: BrandKitStore(fileURL: root.appendingPathComponent("brand.json"))
        )
        viewModel.simpleMakerConfiguration.overlayText = "Live edit"
        let context = viewModel.exportQueueContext
        #expect(context.variantSet.activeDocument.text.value == "Live edit")
        #expect(context.fallbackBaseName == viewModel.simpleMakerConfiguration.exportOptions.preset.id)

        let premium = PremiumMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: root.appendingPathComponent("Drafts/premium.json")),
            brandKitStore: BrandKitStore(fileURL: root.appendingPathComponent("brand.json"))
        )
        premium.premiumMakerConfiguration.overlayText = "Premium live"
        #expect(premium.exportQueueContext.variantSet.activeDocument.text.value == "Premium live")
    }
}
