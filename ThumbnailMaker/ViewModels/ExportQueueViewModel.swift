//
//  ExportQueueViewModel.swift
//  ThumbnailMaker
//
//  FEATURE-10: state behind the "Export All" sheet. Owns a DRAFT copy of the
//  selected recipe (edits are reversible until saved), the destination, the
//  reviewed plan and the queue runner. It never touches the editor's document
//  or undo history: it works on a snapshot of the live variant set.
//

import Combine
import Foundation

struct ThumbnailExportQueueContext {
    var variantSet: ThumbnailVariantSet
    var projectID: UUID?
    var projectName: String
    var fallbackBaseName: String
    var currentOptions: ThumbnailExportOptions
}

@MainActor
final class ExportQueueViewModel: ObservableObject {
    let context: ThumbnailExportQueueContext
    let runner: ThumbnailExportQueueRunner

    @Published private(set) var savedRecipes: [ThumbnailExportRecipe] = []
    @Published private(set) var selectedRecipeID: UUID
    @Published private(set) var draft: ThumbnailExportRecipe
    @Published private(set) var destination: ThumbnailExportDestinationWriting?
    @Published private(set) var snapshot: ThumbnailExportDestinationSnapshot = .none
    @Published private(set) var destinationError: String?
    @Published private(set) var plan: ThumbnailExportQueuePlan
    @Published var errorMessage: String?
    /// Set right after a delete, so the sheet can offer Undo.
    @Published private(set) var recentlyDeletedRecipe: ThumbnailExportRecipe?

    private let store: ThumbnailExportRecipeStore
    private let formatIsAvailable: (ThumbnailExportFormat) -> Bool
    private var runnerObservation: AnyCancellable?

    init(
        context: ThumbnailExportQueueContext,
        store: ThumbnailExportRecipeStore = ThumbnailExportRecipeStore(),
        runner: ThumbnailExportQueueRunner? = nil,
        destination: ThumbnailExportDestinationWriting? = nil,
        loadsRememberedFolder: Bool = true,
        formatIsAvailable: @escaping (ThumbnailExportFormat) -> Bool = { $0.canEncodeOnCurrentPlatform }
    ) {
        self.context = context
        self.store = store
        self.runner = runner ?? ThumbnailExportQueueRunner()
        self.formatIsAvailable = formatIsAvailable

        let library = store.load()
        let currentRecipe = ThumbnailExportRecipe.fromCurrentOptions(context.currentOptions)
        let available = ThumbnailExportRecipe.builtIns + [currentRecipe] + library.recipes
        let lastUsed = context.projectID
            .flatMap { library.lastRecipeIDByProject[$0.uuidString] }
            .flatMap { id in available.first { $0.id == id } }
        let canvas = AspectRatio(rawValue: context.variantSet.activeDocument.canvas.aspectRatioRawValue) ?? .ratio16_9
        let initial = lastUsed ?? (canvas == .ratio16_9 ? .youTubeABC : currentRecipe)

        savedRecipes = library.recipes
        selectedRecipeID = initial.id
        draft = initial
        plan = ThumbnailExportQueuePlan(jobs: [], destination: .none, emptyReason: nil)

        if let destination {
            self.destination = destination
        } else if loadsRememberedFolder, let remembered = FolderExportDestination.rememberedFolder() {
            self.destination = remembered
        } else {
            self.destination = PhotosExportDestination()
        }

        runnerObservation = self.runner.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        refreshDestination()
    }

    // MARK: Recipes

    var availableRecipes: [ThumbnailExportRecipe] {
        ThumbnailExportRecipe.builtIns
            + [ThumbnailExportRecipe.fromCurrentOptions(context.currentOptions)]
            + savedRecipes
    }

    var selectedRecipe: ThumbnailExportRecipe? {
        availableRecipes.first { $0.id == selectedRecipeID }
    }

    var isDraftReadOnly: Bool { selectedRecipe?.isReadOnly ?? draft.isReadOnly }

    var hasUnsavedChanges: Bool {
        guard let selectedRecipe else { return true }
        return !Self.sameSettings(selectedRecipe, draft)
    }

    var isEditingLocked: Bool { runner.isRunning }

    func selectRecipe(_ id: UUID) {
        guard !isEditingLocked, let recipe = availableRecipes.first(where: { $0.id == id }) else { return }
        selectedRecipeID = id
        draft = recipe
        draftDidChange()
    }

    /// Throws away unsaved edits to the selected recipe.
    func revertDraft() {
        guard !isEditingLocked, let selectedRecipe else { return }
        draft = selectedRecipe
        draftDidChange()
    }

    func saveDraftAsNew(named name: String) {
        guard !isEditingLocked else { return }
        let now = Date()
        var recipe = draft
        recipe.id = UUID()
        recipe.version = ThumbnailExportRecipe.currentVersion
        recipe.name = ThumbnailExportRecipe.cleanedName(name)
        recipe.createdAt = now
        do {
            let stored = try store.save(recipe, now: now)
            reloadSavedRecipes()
            selectedRecipeID = stored.id
            draft = stored
            recentlyDeletedRecipe = nil
            draftDidChange(resetsRun: false)
        } catch {
            errorMessage = "Couldn't save the recipe: \(ThumbnailExportQueueRunner.message(for: error))"
        }
    }

    func updateSelectedRecipe() {
        guard !isEditingLocked, !isDraftReadOnly else { return }
        do {
            let stored = try store.save(draft)
            reloadSavedRecipes()
            draft = stored
            draftDidChange(resetsRun: false)
        } catch {
            errorMessage = "Couldn't update the recipe: \(ThumbnailExportQueueRunner.message(for: error))"
        }
    }

    func deleteSelectedRecipe() {
        guard !isEditingLocked, let selectedRecipe, !selectedRecipe.isBuiltIn else { return }
        do {
            recentlyDeletedRecipe = try store.delete(id: selectedRecipe.id)
            reloadSavedRecipes()
            selectRecipe(ThumbnailExportRecipe.youTubeABCID)
        } catch {
            errorMessage = "Couldn't delete the recipe: \(ThumbnailExportQueueRunner.message(for: error))"
        }
    }

    func undoDeleteRecipe() {
        guard let recipe = recentlyDeletedRecipe else { return }
        do {
            try store.restore(recipe)
            recentlyDeletedRecipe = nil
            reloadSavedRecipes()
            selectRecipe(recipe.id)
        } catch {
            errorMessage = "Couldn't restore the recipe: \(ThumbnailExportQueueRunner.message(for: error))"
        }
    }

    // MARK: Draft edits

    var variantSlots: [ThumbnailVariantSlot] { context.variantSet.variants.map(\.slot).sorted() }

    func isSlotSelected(_ slot: ThumbnailVariantSlot) -> Bool {
        draft.variantSelection.selectedSlots(in: context.variantSet).contains(slot)
    }

    func toggleSlot(_ slot: ThumbnailVariantSlot) {
        var selected = Set(draft.variantSelection.selectedSlots(in: context.variantSet))
        if selected.contains(slot) {
            selected.remove(slot)
        } else {
            selected.insert(slot)
        }
        let all = Set(variantSlots)
        editDraft {
            $0.variantSelection = selected == all ? .all : .only(Array(selected))
        }
    }

    func setPreferredOnly(_ preferredOnly: Bool) {
        editDraft { $0.variantSelection = preferredOnly ? .preferredOnly : .all }
    }

    func addSize(preset: ThumbnailExportPreset) {
        addSize(ThumbnailExportRecipeSize(preset: preset))
    }

    func addCustomSize(width: Int, height: Int) {
        addSize(ThumbnailExportRecipeSize(width: width, height: height))
    }

    private func addSize(_ size: ThumbnailExportRecipeSize) {
        guard size.isWithinAllowedRange else {
            errorMessage = ThumbnailExportJobBlockedReason.sizeOutOfRange.message
            return
        }
        guard !draft.sizes.contains(where: { $0.exportSize == size.exportSize }) else {
            errorMessage = "\(size.width) x \(size.height) is already in this recipe."
            return
        }
        editDraft { $0.sizes.append(size) }
    }

    func removeSize(_ size: ThumbnailExportRecipeSize) {
        editDraft { $0.sizes.removeAll { $0.exportSize == size.exportSize } }
    }

    func setFormat(_ format: ThumbnailExportFormat) {
        editDraft { $0.formatRawValue = format.rawValue }
    }

    func setQuality(_ quality: Double) {
        editDraft { $0.compressionQuality = ThumbnailExportRecipe.clampedQuality(quality) }
    }

    func setBudgetEnabled(_ enabled: Bool) {
        editDraft {
            $0.fileSizeBudget = enabled
                ? ($0.fileSizeBudget ?? ThumbnailExportFileSizeBudget(maxBytes: 2_000_000))
                : nil
        }
    }

    /// Megabytes in 0.1 steps (decimal MB, like the upload limits).
    func setBudgetMegabytes(_ megabytes: Double) {
        let clamped = min(max(megabytes, 0.1), 50)
        editDraft {
            let floor = $0.fileSizeBudget?.qualityFloor ?? ThumbnailExportFileSizeBudget.defaultQualityFloor
            $0.fileSizeBudget = ThumbnailExportFileSizeBudget(maxBytes: Int((clamped * 1_000_000).rounded()), qualityFloor: floor)
        }
    }

    func setQualityFloor(_ floor: Double) {
        editDraft {
            guard var budget = $0.fileSizeBudget else { return }
            budget.qualityFloor = min(max(floor, ThumbnailExportFileSizeBudget.minimumQualityFloor), 1.0)
            $0.fileSizeBudget = budget
        }
    }

    func setOverwritePolicy(_ policy: ThumbnailExportOverwritePolicy) {
        editDraft { $0.overwritePolicy = policy }
    }

    func setIncludesSizeToken(_ include: Bool) {
        editDraft { $0.namingIncludesSizeToken = include }
    }

    private func editDraft(_ change: (inout ThumbnailExportRecipe) -> Void) {
        guard !isEditingLocked else { return }
        var copy = draft
        change(&copy)
        guard copy != draft else { return }
        draft = copy
        draftDidChange()
    }

    // MARK: Destination

    var destinationNote: String? {
        destination is PhotosExportDestination ? PhotosExportDestination.namesNotKeptNote : nil
    }

    func chooseFolder(_ url: URL) {
        guard !isEditingLocked else { return }
        FolderExportDestination.remember(url)
        destination = FolderExportDestination(folderURL: url)
        runner.reset()
        refreshDestination()
    }

    func usePhotos() {
        guard !isEditingLocked else { return }
        destination = PhotosExportDestination()
        runner.reset()
        refreshDestination()
    }

    /// Re-reads what is in the destination and re-plans (conflicts recomputed).
    func refreshDestination() {
        guard let destination else {
            snapshot = .none
            destinationError = "Choose where to export."
            replan()
            return
        }
        do {
            snapshot = try destination.snapshot()
            destinationError = nil
        } catch {
            snapshot = ThumbnailExportDestinationSnapshot(displayName: destination.displayName, supportsFileNames: true)
            destinationError = ThumbnailExportQueueRunner.message(for: error)
        }
        replan()
    }

    // MARK: Running

    var canRun: Bool {
        !runner.isRunning && destination != nil && destinationError == nil && !plan.runnableJobs.isEmpty
    }

    var canRetry: Bool {
        !runner.isRunning && runner.hasFinishedRun && !runner.retryableJobIDs.isEmpty
    }

    func run() async {
        refreshDestination()
        guard canRun, let destination else { return }
        if let projectID = context.projectID {
            try? store.setLastRecipeID(selectedRecipeID, forProject: projectID)
        }
        await runner.run(plan, destination: destination)
        refreshSnapshotKeepingRunState()
    }

    func cancel() {
        runner.cancel()
    }

    /// Re-plans against a fresh snapshot and runs only failed / not-run jobs.
    func retryFailed() async {
        guard canRetry else { return }
        let ids = runner.retryableJobIDs
        refreshDestination()
        guard destinationError == nil, let destination else { return }
        await runner.run(plan, destination: destination, onlyJobIDs: ids)
        refreshSnapshotKeepingRunState()
    }

    private func refreshSnapshotKeepingRunState() {
        guard let destination, let fresh = try? destination.snapshot() else { return }
        snapshot = fresh
        replan()
    }

    // MARK: Plumbing

    private func draftDidChange(resetsRun: Bool = true) {
        if resetsRun { runner.reset() }
        replan()
    }

    private func replan() {
        plan = ThumbnailExportQueuePlan.make(
            set: context.variantSet,
            recipe: draft,
            projectName: context.projectName,
            fallbackBaseName: context.fallbackBaseName,
            destination: snapshot,
            formatIsAvailable: formatIsAvailable
        )
    }

    private func reloadSavedRecipes() {
        savedRecipes = store.load().recipes
    }

    /// Compares what a recipe DOES, ignoring bookkeeping (dates, name).
    private static func sameSettings(_ lhs: ThumbnailExportRecipe, _ rhs: ThumbnailExportRecipe) -> Bool {
        lhs.variantSelection == rhs.variantSelection
            && lhs.sizes == rhs.sizes
            && lhs.formatRawValue == rhs.formatRawValue
            && abs(lhs.compressionQuality - rhs.compressionQuality) < 0.0001
            && lhs.fileSizeBudget == rhs.fileSizeBudget
            && lhs.overwritePolicy == rhs.overwritePolicy
            && lhs.namingIncludesSizeToken == rhs.namingIncludesSizeToken
    }
}
