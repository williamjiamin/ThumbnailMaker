//
//  PremiumMakerViewModel.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/28.
//

import PhotosUI
import SwiftUI

@MainActor
class PremiumMakerViewModel: ObservableObject {
    @Published var premiumMakerConfiguration = PremiumMakerConfigurationModel() {
        didSet {
            scheduleDraftAutosave()
        }
    }
    @Published var imageSelection: PhotosPickerItem?
    @Published var layerImageSelection: PhotosPickerItem?
    @Published var stickerImageSelection: PhotosPickerItem?
    @Published var saveError: String?
    @Published var showingSaveAlert = false
    @Published private(set) var draftSaveState: DraftSaveState = .idle
    @Published private(set) var imageImportError: ImageImportError?
    @Published var isSaving = false
    @Published var isPreparingShare = false
    @Published var isPreparingFileExport = false
    @Published var isCheckingExportSize = false
    @Published var isProcessingSubject = false
    @Published var profileImageSelection: PhotosPickerItem?
    @Published var showingProfileCropper = false
    @Published var tempProfileImage: UIImage?
    @Published var isPermissionError = false
    @Published var batchProgress: Double = 0
    @Published var currentBatchNumber: Int = 0
    @Published var isBatchGenerating = false
    @Published var shareItem: ThumbnailShareItem?
    @Published var fileExport: ThumbnailPreparedFileExport?
    @Published var isFileExporterPresented = false
    @Published var exportReport: ThumbnailExportReport?
    @Published var successMessage = "Thumbnail saved to Photos"
    // FEATURE-13: confirmed exports only (Photos / Files / completed share).
    // checkExportSize never sets this; it is not part of the document or undo.
    @Published private(set) var lastExportEvent: ThumbnailExportEvent?
    func recordExportCompleted(_ kind: ThumbnailExportEventKind) {
        lastExportEvent = ThumbnailExportEvent(kind: kind, editorMode: .premium)
    }
    func recordShareCompleted(_ completed: Bool) {
        if completed { recordExportCompleted(.share) }
    }
    // FEATURE-08: brand kit library (many kits, one active).
    @Published private(set) var brandKitLibrary = BrandKitLibrary.empty
    var brandKit: BrandKit? { brandKitLibrary.activeKit }
    @Published private(set) var restoredDraft = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    // FEATURE-01 project library
    @Published private(set) var activeProjectID: UUID?
    @Published private(set) var activeProjectName = ""
    let projectLibrary: ThumbnailProjectLibrary?
    private var shouldCancelBatch = false
    @Published var showPhotoPicker = false
    private let draftStore: ThumbnailDraftStore
    private let brandKitStore: BrandKitStore
    private var isDraftPersistenceEnabled = true
    private var pendingDraftSave: DispatchWorkItem?
    private var imageImportRevision = 0
    var cutoutRevision = 0 // FEATURE-11: see CutoutViewModelIntents.swift
    private var layerImportRevision = 0
    private var stickerImportRevision = 0
    private var profileImportRevision = 0
    // FEATURE-02: variants. Undo history is kept per variant slot; these two
    // computed properties redirect every existing call site to the active slot.
    // Reassigned per project when the FEATURE-01 library is active.
    private var variantStore: ThumbnailVariantStore
    @Published private(set) var variantWorkspace = ThumbnailVariantWorkspace(
        seedDocument: PremiumMakerConfigurationModel().document,
        editorMode: .premium
    )
    @Published var variantWarning: String?
    private var history: ThumbnailDocumentHistory {
        get { variantWorkspace.activeHistory }
        set { variantWorkspace.activeHistory = newValue }
    }
    private var historyBaseline: ThumbnailDocument {
        get { variantWorkspace.activeBaseline }
        set { variantWorkspace.activeBaseline = newValue }
    }
    private var isApplyingHistory = false
    private var isHistoryTrackingEnabled = false
    private let suggestionProvider = LocalThumbnailSuggestionProvider()
    private let ideaProvider = LocalThumbnailIdeaProvider()
    private let subjectProcessor: ThumbnailSubjectProcessing
    
    // Add a constant for preview proportion
    let usableHeightProportion: CGFloat = 0.8  
    let previewHeightProportion: CGFloat = 0.35  // Match the simple maker's preview proportion
    let textFieldHeight: CGFloat = 50
    let overlayCharacterLimit = 120

    var actionableSuggestions: [ThumbnailSuggestion] {
        suggestionProvider.suggestions(
            for: premiumMakerConfiguration,
            brandKit: brandKit,
            templates: ThumbnailTemplate.builtIns
        )
        .filter(isActionableSuggestion)
    }

    var titleIdeas: [ThumbnailIdea] {
        ideaProvider.ideas(
            forTitle: premiumMakerConfiguration.overlayText,
            ratio: premiumMakerConfiguration.selectedRatio,
            brandKit: brandKit,
            templates: ThumbnailTemplate.builtIns
        )
    }

    var selectableLayerSelections: [ThumbnailLayerSelection] {
        premiumMakerConfiguration.layers.selectableLayerSelections(
            hasText: !premiumMakerConfiguration.overlayText.isEmpty,
            hasProfile: premiumMakerConfiguration.circularProfile?.image != nil
        )
    }

    var hasExportableContent: Bool {
        premiumMakerConfiguration.selectedImage != nil
            || !premiumMakerConfiguration.overlayText.isEmpty
            || premiumMakerConfiguration.circularProfile?.image != nil
            || premiumMakerConfiguration.layers.hasContentLayers
    }

    func reconcileLayersForCurrentOverlays() {
        let reconciledLayers = premiumMakerConfiguration.layers.reconciledForCurrentOverlays(
            hasText: !premiumMakerConfiguration.overlayText.isEmpty,
            hasProfile: premiumMakerConfiguration.circularProfile?.image != nil
        )

        if reconciledLayers != premiumMakerConfiguration.layers {
            premiumMakerConfiguration.layers = reconciledLayers
        }
    }

    func toggleLayerVisibility(_ selection: ThumbnailLayerSelection) {
        var configuration = premiumMakerConfiguration
        configuration.layers = configuration.layers.reconciledForCurrentOverlays(
            hasText: !configuration.overlayText.isEmpty,
            hasProfile: configuration.circularProfile?.image != nil
        )
        configuration.layers.toggleVisibility(for: selection)
        premiumMakerConfiguration = configuration
    }

    func toggleLayerLock(_ selection: ThumbnailLayerSelection) {
        var configuration = premiumMakerConfiguration
        configuration.layers = configuration.layers.reconciledForCurrentOverlays(
            hasText: !configuration.overlayText.isEmpty,
            hasProfile: configuration.circularProfile?.image != nil
        )
        configuration.layers.toggleLock(for: selection)
        premiumMakerConfiguration = configuration
    }

    func canRemoveBackground(from selection: ThumbnailLayerSelection) -> Bool {
        if case .content(let layerID) = selection,
           let layer = premiumMakerConfiguration.layers.record(id: layerID),
           case .image = layer.content {
            return true
        }

        return premiumMakerConfiguration.selectedImage != nil
    }
    
    init(
        draftStore: ThumbnailDraftStore = ThumbnailDraftStore(kind: .premium),
        brandKitStore: BrandKitStore = BrandKitStore(),
        subjectProcessor: ThumbnailSubjectProcessing = BackgroundRemovalService(),
        projectLibrary: ThumbnailProjectLibrary? = nil,
        variantStore: ThumbnailVariantStore? = nil
    ) {
        self.projectLibrary = projectLibrary
        self.draftStore = draftStore
        self.variantStore = variantStore ?? ThumbnailVariantStore(siblingOf: draftStore.fileURL, kind: .premium) // FEATURE-02
        self.brandKitStore = brandKitStore
        self.subjectProcessor = subjectProcessor

        let launchArguments = ProcessInfo.processInfo.arguments
        if launchArguments.contains("-DisableDraftPersistence") {
            isDraftPersistenceEnabled = false
        }

        if isDraftPersistenceEnabled {
            do { // FEATURE-08: a corrupt library surfaces instead of vanishing.
                brandKitLibrary = try brandKitStore.loadLibrary()
            } catch {
                saveError = "Failed to load brand kits: \(error.localizedDescription)"
            }
        }

        #if DEBUG
        if launchArguments.contains("-UITestSeedPremiumEditor") {
            isDraftPersistenceEnabled = false
            premiumMakerConfiguration.selectedImage = Self.makeUITestBackgroundImage()
            premiumMakerConfiguration.overlayText = "Layer pick"
            premiumMakerConfiguration.textTransform = ThumbnailOverlayTransform(x: 0.5, y: 0.62)
            premiumMakerConfiguration.circularProfile = CircularProfileConfig(
                image: Self.makeUITestProfileImage(),
                size: 0.2
            )
            premiumMakerConfiguration.profileTransform = ThumbnailOverlayTransform.profileDefault
            resetHistoryBaseline()
            isHistoryTrackingEnabled = true
            return
        }

        if launchArguments.contains("-UITestSeedPremiumTextLayer") {
            isDraftPersistenceEnabled = false
            premiumMakerConfiguration.selectedImage = Self.makeUITestBackgroundImage()
            premiumMakerConfiguration.overlayText = "Premium title"
            premiumMakerConfiguration.layers.addTextLayer(
                value: "Premium Layer",
                id: "ui-test-premium-text-layer",
                color: ThumbnailDocumentColor(red: 1, green: 0.92, blue: 0.18, alpha: 1),
                size: 0.15,
                selectedFontRawValue: CustomFont.montserrat.rawValue,
                transform: ThumbnailOverlayTransform(
                    x: 0.58,
                    y: 0.42,
                    rotationDegrees: 6
                )
            )
            resetHistoryBaseline()
            isHistoryTrackingEnabled = true
            return
        }
        #endif

        if isDraftPersistenceEnabled, !openInitialProjectIfAvailable() {
            restoreDraftIfAvailable()
        }

        resetHistoryBaseline()
        isHistoryTrackingEnabled = true
    }
    
    func updateImage() async {
        let revision = beginImageImport()
        do {
            let data = try await loadImageData(from: imageSelection)
            applyImportedImageData(data, revision: revision)
        } catch is CancellationError {
            imageImportError = .cancelled
        } catch {
            imageImportError = .transferFailed(error.localizedDescription)
        }
    }

    /// Starts a new image import and returns its revision tag. A later import
    /// bumps the counter, so any in-flight load tagged with an older revision
    /// is stale and must not be applied.
    @discardableResult
    func beginImageImport() -> Int {
        imageImportRevision += 1
        return imageImportRevision
    }

    /// Applies imported bytes only if `revision` is still current. A stale
    /// revision is discarded silently — the newer import owns the document and
    /// the user has no failure to act on. A current revision that cannot be
    /// decoded publishes `.decodeFailed` and leaves the document untouched.
    @discardableResult
    func applyImportedImageData(_ data: Data, revision: Int, preservingFrame: Bool = true) -> Bool {
        guard revision == imageImportRevision else { return false }
        guard let uiImage = UIImage(data: data) else {
            imageImportError = .decodeFailed
            return false
        }
        premiumMakerConfiguration.selectedImage = uiImage
        premiumMakerConfiguration.layers.resetCutout(forLayerID: ThumbnailDocumentLayer.backgroundID) // FEATURE-11: a cutout belongs to its photo
        // FEATURE-03: replacing the photo keeps its normalized frame recipe
        // unless the caller asks for a fresh, letterboxed frame.
        if !preservingFrame { premiumMakerConfiguration.imageRecipe = .identity }
        return true
    }

    func loadImageData(from selection: PhotosPickerItem?) async throws -> Data {
        guard let selection else {
            throw CancellationError()
        }
        if let data = try? await selection.loadTransferable(type: Data.self), !data.isEmpty {
            return data
        }
        throw NSError(
            domain: "ThumbnailMaker.ImageImport",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "transfer returned no data"]
        )
    }

    func addImageLayerFromSelection() async -> ThumbnailLayerSelection? {
        layerImportRevision += 1
        let revision = layerImportRevision
        defer {
            if revision == layerImportRevision {
                layerImageSelection = nil
            }
        }

        guard let data = try? await layerImageSelection?.loadTransferable(type: Data.self),
              UIImage(data: data) != nil else {
            return nil
        }

        guard revision == layerImportRevision else { return nil }
        return addImageLayer(imageData: data)
    }

    func addStickerLayerFromSelection() async -> ThumbnailLayerSelection? {
        stickerImportRevision += 1
        let revision = stickerImportRevision
        defer {
            if revision == stickerImportRevision {
                stickerImageSelection = nil
            }
        }

        guard let data = try? await stickerImageSelection?.loadTransferable(type: Data.self),
              UIImage(data: data) != nil else {
            return nil
        }

        guard revision == stickerImportRevision else { return nil }
        return addStickerLayer(imageData: data)
    }

    @discardableResult
    func addImageLayer(imageData: Data) -> ThumbnailLayerSelection {
        commitEditorStateNow()

        let previousDocument = premiumMakerConfiguration.document
        isApplyingHistory = true
        let layerID = premiumMakerConfiguration.layers.addImageLayer(imageData: imageData)
        finishImmediateEditorMutation(previousDocument: previousDocument)
        return .content(layerID)
    }

    @discardableResult
    func addStickerLayer(imageData: Data) -> ThumbnailLayerSelection {
        commitEditorStateNow()

        let previousDocument = premiumMakerConfiguration.document
        isApplyingHistory = true
        let layerID = premiumMakerConfiguration.layers.addStickerLayer(imageData: imageData)
        finishImmediateEditorMutation(previousDocument: previousDocument)
        return .content(layerID)
    }

    @discardableResult
    func addTextLayer(value: String = "New text") -> ThumbnailLayerSelection {
        commitEditorStateNow()

        let previousDocument = premiumMakerConfiguration.document
        isApplyingHistory = true
        let layerID = premiumMakerConfiguration.layers.addTextLayer(
            value: value,
            color: ThumbnailDocumentColor(color: premiumMakerConfiguration.textColor),
            size: Double(premiumMakerConfiguration.textSize),
            selectedFontRawValue: premiumMakerConfiguration.selectedFont.rawValue,
            transform: premiumMakerConfiguration.textTransform
        )
        finishImmediateEditorMutation(previousDocument: previousDocument)
        return .content(layerID)
    }

    @discardableResult
    func addShapeLayer(_ shapeKind: ThumbnailShapeKind) -> ThumbnailLayerSelection {
        commitEditorStateNow()

        let previousDocument = premiumMakerConfiguration.document
        isApplyingHistory = true
        let layerID = premiumMakerConfiguration.layers.addShapeLayer(shapeKind: shapeKind)
        finishImmediateEditorMutation(previousDocument: previousDocument)
        return .content(layerID)
    }

    func duplicateLayer(_ selection: ThumbnailLayerSelection) -> ThumbnailLayerSelection? {
        guard case .content(let layerID) = selection else { return nil }
        commitEditorStateNow()

        let previousDocument = premiumMakerConfiguration.document
        isApplyingHistory = true
        guard let duplicatedLayerID = premiumMakerConfiguration.layers.duplicateContentLayer(id: layerID) else {
            isApplyingHistory = false
            return nil
        }
        finishImmediateEditorMutation(previousDocument: previousDocument)
        return .content(duplicatedLayerID)
    }

    func moveLayerBackward(
        _ selection: ThumbnailLayerSelection,
        within selections: [ThumbnailLayerSelection]
    ) {
        guard premiumMakerConfiguration.layers.canMoveBackward(selection, within: selections) else { return }
        commitEditorStateNow()

        let previousDocument = premiumMakerConfiguration.document
        isApplyingHistory = true
        premiumMakerConfiguration.layers.moveBackward(selection, within: selections)
        finishImmediateEditorMutation(previousDocument: previousDocument)
    }

    func moveLayerForward(
        _ selection: ThumbnailLayerSelection,
        within selections: [ThumbnailLayerSelection]
    ) {
        guard premiumMakerConfiguration.layers.canMoveForward(selection, within: selections) else { return }
        commitEditorStateNow()

        let previousDocument = premiumMakerConfiguration.document
        isApplyingHistory = true
        premiumMakerConfiguration.layers.moveForward(selection, within: selections)
        finishImmediateEditorMutation(previousDocument: previousDocument)
    }

    func deleteLayer(_ selection: ThumbnailLayerSelection) -> ThumbnailLayerSelection? {
        guard case .content(let layerID) = selection else { return nil }
        commitEditorStateNow()

        let previousDocument = premiumMakerConfiguration.document
        isApplyingHistory = true
        premiumMakerConfiguration.layers.deleteContentLayer(id: layerID)
        finishImmediateEditorMutation(previousDocument: previousDocument)
        return selectableLayerSelections.last
    }

    func restoreDraftIfAvailable() {
        let legacyDraft: ThumbnailDocument?
        do {
            legacyDraft = try draftStore.loadDocument()
        } catch {
            print("Failed to restore Premium Maker draft: \(error.localizedDescription)")
            legacyDraft = nil
        }
        // FEATURE-02: open the variant set, migrating a pre-variant draft.
        guard let restored = variantStore.restoreSet(legacyDraft: legacyDraft, editorMode: .premium) else { return }
        variantWorkspace.replaceSet(restored.set)
        variantWarning = restored.warning
        premiumMakerConfiguration = PremiumMakerConfigurationModel(document: restored.set.activeDocument)
        restoredDraft = true
        if isHistoryTrackingEnabled {
            resetHistoryBaseline()
        }
    }

    func saveDraftNow() {
        guard isDraftPersistenceEnabled else { return }
        let perfSpan = ThumbnailPerformanceProbe.begin(.draftSave); defer { perfSpan.end() } // APP-09

        draftSaveState = .saving
        do {
            let savedProjectDocument = try saveActiveProjectDocument()
            let document = savedProjectDocument ?? premiumMakerConfiguration.document
            if savedProjectDocument == nil {
                try draftStore.save(document)
            }
            variantWorkspace.syncActiveDocument(document) // FEATURE-02
            try variantStore.save(variantWorkspace.variantSet) // FEATURE-02
            draftSaveState = .saved(Date())
            if let savedProjectDocument, let activeProjectID {
                projectLibrary?.schedulePreviewRefresh(for: activeProjectID, document: savedProjectDocument)
            }
        } catch {
            draftSaveState = .failed(
                message: error.localizedDescription,
                attemptedAt: Date()
            )
            saveError = "Failed to save draft: \(error.localizedDescription)"
        }
    }

    func retryDraftSave() {
        saveDraftNow()
    }

    /// Non-nil upserts and activates the kit; nil removes every kit.
    func saveBrandKit(_ kit: BrandKit?) {
        guard let kit else {
            brandKitLibrary = .empty
            guard isDraftPersistenceEnabled else { return }
            do {
                try brandKitStore.delete()
            } catch {
                saveError = "Failed to save brand kit: \(error.localizedDescription)"
                showingSaveAlert = true
            }
            return
        }
        var library = brandKitLibrary
        guard library.upsert(kit, activate: true) else {
            reportBrandKitError(BrandKitStoreError.libraryFull.localizedDescription)
            return
        }
        commitBrandKitLibrary(library)
    }

    private func scheduleDraftAutosave() {
        guard isHistoryTrackingEnabled, !isApplyingHistory else { return }

        pendingDraftSave?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.commitEditorStateNow()
        }
        pendingDraftSave = workItem

        // The edit is undoable immediately: undo() commits the pending step before
        // reverting it. Without this, Undo stayed disabled for the 0.6s debounce and a
        // quick tap or Cmd-Z right after an edit was silently ignored. A new edit also
        // invalidates the redo stack once committed, so redo is unavailable meanwhile.
        canUndo = true
        canRedo = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
    }

    func commitEditorStateNow() {
        guard isHistoryTrackingEnabled, !isBatchGenerating else { return }

        pendingDraftSave?.cancel()
        pendingDraftSave = nil
        let perfSpan = ThumbnailPerformanceProbe.begin(.historyCommit); defer { perfSpan.end() } // APP-09

        let currentSnapshot = ThumbnailDocumentHistory.snapshot(premiumMakerConfiguration.document)
        if !ThumbnailDocumentPayloads.isEquivalent(currentSnapshot, historyBaseline) { // APP-09
            history.record(historyBaseline)
            historyBaseline = currentSnapshot
            refreshHistoryAvailability()
        }

        saveDraftNow()
    }

    func undo() {
        commitEditorStateNow()
        let perfSpan = ThumbnailPerformanceProbe.begin(.undoRedo); defer { perfSpan.end() } // APP-09

        let currentSnapshot = ThumbnailDocumentHistory.snapshot(premiumMakerConfiguration.document)
        guard let previous = history.undo(current: currentSnapshot) else {
            refreshHistoryAvailability()
            return
        }

        applyHistoryDocument(previous)
    }

    func redo() {
        let perfSpan = ThumbnailPerformanceProbe.begin(.undoRedo); defer { perfSpan.end() } // APP-09
        let currentSnapshot = ThumbnailDocumentHistory.snapshot(premiumMakerConfiguration.document)
        guard let next = history.redo(current: currentSnapshot) else {
            refreshHistoryAvailability()
            return
        }

        applyHistoryDocument(next)
    }

    private func applyHistoryDocument(_ document: ThumbnailDocument) {
        isApplyingHistory = true
        premiumMakerConfiguration = PremiumMakerConfigurationModel(document: document)
        historyBaseline = ThumbnailDocumentHistory.snapshot(document)
        isApplyingHistory = false
        refreshHistoryAvailability()
        saveDraftNow()
    }

    private func resetHistoryBaseline() {
        let document = premiumMakerConfiguration.document
        variantWorkspace.syncActiveDocument(document) // FEATURE-02
        history = ThumbnailDocumentHistory()
        historyBaseline = ThumbnailDocumentHistory.snapshot(document)
        refreshHistoryAvailability()
    }

    private func refreshHistoryAvailability() {
        canUndo = history.canUndo
        canRedo = history.canRedo
    }

    private func finishImmediateEditorMutation(previousDocument: ThumbnailDocument) {
        let previousSnapshot = ThumbnailDocumentHistory.snapshot(previousDocument)
        let nextSnapshot = ThumbnailDocumentHistory.snapshot(premiumMakerConfiguration.document)
        defer {
            isApplyingHistory = false
        }

        guard previousSnapshot != nextSnapshot else { return }

        history.record(previousDocument)
        historyBaseline = nextSnapshot
        refreshHistoryAvailability()
        exportReport = nil
        saveDraftNow()
    }

    @discardableResult
    func applyTemplate(
        _ template: ThumbnailTemplate,
        mode: ThumbnailTemplateApplicationMode = .composition // FEATURE-05
    ) -> [ThumbnailTemplateWarning] {
        commitEditorStateNow()

        let previousDocument = premiumMakerConfiguration.document
        let previousImage = premiumMakerConfiguration.selectedImage
        let previousProfileImage = premiumMakerConfiguration.circularProfile?.image
        // FEATURE-05: built-ins keep the legacy path; personal templates get
        // fresh layer ids + slot resolution; style-only keeps the layout.
        let application = template.application(over: previousDocument, mode: mode)
        let nextDocument = application.document
        var nextConfiguration = PremiumMakerConfigurationModel(document: nextDocument)
        if nextDocument.imageData == previousDocument.imageData {
            nextConfiguration.selectedImage = previousImage ?? nextConfiguration.selectedImage
        }
        if let previousProfileImage, nextConfiguration.circularProfile != nil,
           nextDocument.profile?.imageData == previousDocument.profile?.imageData {
            nextConfiguration.circularProfile?.image = previousProfileImage
        }

        let previousSnapshot = ThumbnailDocumentHistory.snapshot(previousDocument)
        let nextSnapshot = ThumbnailDocumentHistory.snapshot(nextConfiguration.document)
        guard previousSnapshot != nextSnapshot else { return application.warnings }

        isApplyingHistory = true
        premiumMakerConfiguration = nextConfiguration
        history.record(previousDocument)
        historyBaseline = nextSnapshot
        isApplyingHistory = false
        refreshHistoryAvailability()
        exportReport = nil
        saveDraftNow()
        return application.warnings
    }

    func apply(idea: ThumbnailIdea) {
        applyTemplate(idea.template)
    }

    func applyBrandKit(_ kit: BrandKit? = nil) {
        guard let kit = kit ?? brandKit else { return }
        commitEditorStateNow()

        let previousDocument = premiumMakerConfiguration.document
        let nextConfiguration = kit.applied(to: premiumMakerConfiguration)
        let previousSnapshot = ThumbnailDocumentHistory.snapshot(previousDocument)
        let nextSnapshot = ThumbnailDocumentHistory.snapshot(nextConfiguration.document)
        guard previousSnapshot != nextSnapshot else { return }

        isApplyingHistory = true
        premiumMakerConfiguration = nextConfiguration
        history.record(previousDocument)
        historyBaseline = nextSnapshot
        isApplyingHistory = false
        refreshHistoryAvailability()
        exportReport = nil
        saveDraftNow()
    }

    func apply(_ suggestion: ThumbnailSuggestion) {
        switch suggestion.action {
        case .shortenText:
            shortenOverlayText()
        case .applyTemplate(let id):
            guard let template = ThumbnailTemplate.builtIns.first(where: { $0.id == id }) else {
                return
            }
            applyTemplate(template)
        case .applyBrandColor:
            applyBrandKit()
        case .cropToDetectedFace, .none:
            return
        }
    }

    func applyAsync(_ suggestion: ThumbnailSuggestion) async {
        switch suggestion.action {
        case .cropToDetectedFace:
            await cropSelectedImageToDetectedFace()
        default:
            apply(suggestion)
        }
    }

    func cropSelectedImageToDetectedFace() async {
        await processSelectedImage(
            failurePrefix: "Failed to crop around faces"
        ) { [subjectProcessor] image in
            guard let crop = try await subjectProcessor.suggestedFaceCrop(in: image, padding: 0.28),
                  let croppedImage = BackgroundRemovalService.croppedImage(
                    image,
                    toNormalizedVisionRect: crop
                  ) else {
                throw BackgroundRemovalError.faceNotDetected
            }

            return croppedImage
        }
    }

    func removeBackgroundFromSelectedImage() async {
        // FEATURE-11: stores a mask recipe; the photo bytes stay untouched.
        await generateAutomaticCutout(for: .baseImage, using: subjectProcessor)
    }

    func removeBackground(from selection: ThumbnailLayerSelection) async {
        // FEATURE-11: non-destructive, revision-guarded (CutoutViewModelIntents.swift).
        await generateAutomaticCutout(for: cutoutTarget(for: selection), using: subjectProcessor)
    }

    private func isActionableSuggestion(_ suggestion: ThumbnailSuggestion) -> Bool {
        guard suggestion.isCurrentlyActionableInEditor else { return false }

        if case .applyTemplate(let id) = suggestion.action,
           let template = ThumbnailTemplate.builtIns.first(where: { $0.id == id }) {
            let currentDocument = ThumbnailDocumentHistory.snapshot(premiumMakerConfiguration.document)
            let templateConfiguration = PremiumMakerConfigurationModel(
                document: template.makeDocument(preservingImagesFrom: premiumMakerConfiguration.document)
            )
            let templateDocument = ThumbnailDocumentHistory.snapshot(
                templateConfiguration.document
            )
            return currentDocument != templateDocument
        }

        if case .applyBrandColor = suggestion.action {
            guard let brandKit else { return false }
            let currentDocument = ThumbnailDocumentHistory.snapshot(premiumMakerConfiguration.document)
            let brandDocument = ThumbnailDocumentHistory.snapshot(
                brandKit.applied(to: premiumMakerConfiguration).document
            )
            return currentDocument != brandDocument
        }

        return true
    }

    private func shortenOverlayText() {
        commitEditorStateNow()

        let previousDocument = premiumMakerConfiguration.document
        let shortenedText = ThumbnailSuggestionTextShortener.shortened(
            premiumMakerConfiguration.overlayText
        )
        guard shortenedText != premiumMakerConfiguration.overlayText else { return }

        isApplyingHistory = true
        premiumMakerConfiguration.overlayText = shortenedText
        let nextSnapshot = ThumbnailDocumentHistory.snapshot(premiumMakerConfiguration.document)
        history.record(previousDocument)
        historyBaseline = nextSnapshot
        isApplyingHistory = false
        refreshHistoryAvailability()
        exportReport = nil
        saveDraftNow()
    }

    private func processSelectedImage(
        failurePrefix: String,
        operation: @escaping (UIImage) async throws -> UIImage
    ) async {
        guard let image = premiumMakerConfiguration.selectedImage else { return }

        isProcessingSubject = true
        defer {
            isProcessingSubject = false
        }

        do {
            let processedImage = try await operation(image)
            applyProcessedSelectedImage(processedImage)
            saveError = nil
            isPermissionError = false
        } catch {
            isPermissionError = false
            saveError = "\(failurePrefix): \(error.localizedDescription)"
            showingSaveAlert = true
        }
    }

    private func applyProcessedSelectedImage(_ image: UIImage) {
        commitEditorStateNow()

        let previousDocument = premiumMakerConfiguration.document
        let previousSnapshot = ThumbnailDocumentHistory.snapshot(previousDocument)
        isApplyingHistory = true
        premiumMakerConfiguration.selectedImage = image
        let nextSnapshot = ThumbnailDocumentHistory.snapshot(premiumMakerConfiguration.document)
        defer {
            isApplyingHistory = false
        }

        guard previousSnapshot != nextSnapshot else { return }

        history.record(previousDocument)
        historyBaseline = nextSnapshot
        refreshHistoryAvailability()
        exportReport = nil
        saveDraftNow()
    }

    func saveImageWithOverlay(content: some View, showSuccessAlert: Bool = true) async {
        guard hasExportableContent else { return }
        
        await MainActor.run {
            isSaving = true
        }

        let exportOptions = premiumMakerConfiguration.exportOptions

        do {
            let renderedImage = try ThumbnailExporter.render(
                content: content,
                options: exportOptions
            )
            let data = try ThumbnailExporter.encodedData(for: renderedImage, options: exportOptions)
            try await ThumbnailExporter.saveEncodedDataToPhotoLibrary(data, options: exportOptions)

            if !PurchaseManager.shared.isPremium {
                PurchaseManager.shared.useFreeTrial()
            }

            await MainActor.run {
                saveError = nil
                exportReport = ThumbnailExportReport(byteCount: data.count, options: exportOptions)
                successMessage = "Thumbnail saved to Photos"
                recordExportCompleted(.photos) // FEATURE-13
                showingSaveAlert = showSuccessAlert
                isSaving = false
                imageSelection = nil
                profileImageSelection = nil
            }
        } catch {
            await MainActor.run {
                isPermissionError = (error as? ThumbnailExportError) == .photoPermissionDenied
                saveError = "Save failed: \(error.localizedDescription)"
                showingSaveAlert = true
                isSaving = false
            }
        }
    }

    func shareImageWithOverlay(content: some View) async {
        guard hasExportableContent else { return }

        await MainActor.run {
            isPreparingShare = true
        }

        let exportOptions = premiumMakerConfiguration.exportOptions

        do {
            let renderedImage = try ThumbnailExporter.render(
                content: content,
                options: exportOptions
            )
            let data = try ThumbnailExporter.encodedData(for: renderedImage, options: exportOptions)
            let exportURL = try ThumbnailExporter.writeTemporaryExport(
                data: data,
                options: exportOptions,
                baseFileName: variantExportBaseName
            )

            await MainActor.run {
                saveError = nil
                exportReport = ThumbnailExportReport(byteCount: data.count, options: exportOptions)
                shareItem = ThumbnailShareItem(url: exportURL)
                isPreparingShare = false
            }
        } catch {
            await MainActor.run {
                isPermissionError = false
                saveError = "Failed to prepare share: \(error.localizedDescription)"
                showingSaveAlert = true
                isPreparingShare = false
            }
        }
    }

    func prepareFileExport(content: some View) async {
        guard hasExportableContent else { return }

        await MainActor.run {
            isPreparingFileExport = true
        }

        let exportOptions = premiumMakerConfiguration.exportOptions

        do {
            let preparedExport = try ThumbnailExporter.preparedFileExport(
                content: content,
                options: exportOptions,
                baseFileName: variantExportBaseName
            )

            await MainActor.run {
                saveError = nil
                fileExport = preparedExport
                exportReport = ThumbnailExportReport(
                    byteCount: preparedExport.data.count,
                    options: exportOptions
                )
                isFileExporterPresented = true
                isPreparingFileExport = false
            }
        } catch {
            await MainActor.run {
                isPermissionError = false
                saveError = "Failed to prepare file: \(error.localizedDescription)"
                showingSaveAlert = true
                isPreparingFileExport = false
            }
        }
    }

    func checkExportSize(content: some View) async {
        guard hasExportableContent else { return }

        await MainActor.run {
            isCheckingExportSize = true
        }

        let exportOptions = premiumMakerConfiguration.exportOptions

        do {
            let renderedImage = try ThumbnailExporter.render(
                content: content,
                options: exportOptions
            )
            let data = try ThumbnailExporter.encodedData(for: renderedImage, options: exportOptions)

            await MainActor.run {
                saveError = nil
                exportReport = ThumbnailExportReport(byteCount: data.count, options: exportOptions)
                isCheckingExportSize = false
            }
        } catch {
            await MainActor.run {
                isPermissionError = false
                saveError = "Failed to check export size: \(error.localizedDescription)"
                showingSaveAlert = true
                isCheckingExportSize = false
            }
        }
    }

    func handleFileExportCompletion(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            saveError = nil
            recordExportCompleted(.files) // FEATURE-13
            successMessage = "Thumbnail exported to Files"
            showingSaveAlert = true
        case .failure(let error):
            let nsError = error as NSError
            guard nsError.code != NSUserCancelledError else { return }

            isPermissionError = false
            saveError = "File export failed: \(error.localizedDescription)"
            showingSaveAlert = true
        }
    }
    
    func updateProfileImage() async {
        profileImportRevision += 1
        let revision = profileImportRevision
        if let data = try? await profileImageSelection?.loadTransferable(type: Data.self) {
            if let uiImage = UIImage(data: data) {
                guard revision == profileImportRevision else { return }
                tempProfileImage = uiImage
                showingProfileCropper = true
            }
        }
    }
    
    func setProfileImage(_ image: UIImage) {
        if premiumMakerConfiguration.circularProfile == nil {
            premiumMakerConfiguration.circularProfile = CircularProfileConfig(
                image: image,
                size: 0.2
            )
        } else {
            premiumMakerConfiguration.circularProfile?.image = image
        }
    }
    
    func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    func cancelBatchGeneration() {
        shouldCancelBatch = true
    }

    #if DEBUG
    private static func makeUITestBackgroundImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 320, height: 180)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
            UIColor.systemYellow.setFill()
            context.fill(CGRect(x: 48, y: 42, width: 128, height: 64))
        }
    }

    private static func makeUITestProfileImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96)).image { context in
            UIColor.systemCyan.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
            UIColor.systemPurple.setFill()
            context.fill(CGRect(x: 24, y: 24, width: 48, height: 48))
        }
    }
    #endif
    
    func generateBatchImages(content: @escaping (String) -> some View) async {
        guard premiumMakerConfiguration.macroConfig.isEnabled,
              premiumMakerConfiguration.macroConfig.isValid else { return }
        
        let start = premiumMakerConfiguration.macroConfig.startNumber
        let end = premiumMakerConfiguration.macroConfig.endNumber
        let baseText = premiumMakerConfiguration.overlayText
        let totalCount = premiumMakerConfiguration.macroConfig.totalCount
        shouldCancelBatch = false
        
        await MainActor.run {
            isSaving = true
            isBatchGenerating = true
            batchProgress = 0
            currentBatchNumber = 0
        }
        defer {
            isBatchGenerating = false
        }
        
        let range: any Sequence<Int> = start < end ? start...end : stride(from: start, through: end, by: -1)
        
        for number in range {
            if shouldCancelBatch {
                break
            }
            
            let text = premiumMakerConfiguration.macroConfig.appendPosition == .after ?
                "\(baseText) \(number)" : "\(number) \(baseText)"
            
            await MainActor.run {
                premiumMakerConfiguration.overlayText = text
                currentBatchNumber += 1
                batchProgress = Double(currentBatchNumber) / Double(totalCount)
            }
            
            await saveImageWithOverlay(content: content(text), showSuccessAlert: false)
            
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        await MainActor.run {
            premiumMakerConfiguration.overlayText = baseText
            isSaving = false
            batchProgress = 0
            currentBatchNumber = 0
            saveError = nil
            showingSaveAlert = true
        }
    }
}

// MARK: - FEATURE-02: A/B/C variants
//
// Thin hooks into `ThumbnailVariantWorkspace`, which owns the rules. Switching
// variants never resets the incoming variant's undo stack.
extension PremiumMakerViewModel {
    var variantSet: ThumbnailVariantSet { variantWorkspace.variantSet }
    var canAddVariant: Bool { variantWorkspace.variantSet.canAddVariant }

    var variantExportBaseName: String {
        variantWorkspace.exportBaseName(fallback: premiumMakerConfiguration.exportOptions.preset.id)
    }

    /// The set including unsaved edits in the active variant.
    var liveVariantSet: ThumbnailVariantSet {
        variantWorkspace.setIncluding(liveDocument: premiumMakerConfiguration.document)
    }

    var variantExportPlan: ThumbnailVariantExportPlan {
        .make(from: liveVariantSet, fallbackBaseName: premiumMakerConfiguration.exportOptions.preset.id)
    }

    func variantComparison(previewSize: ThumbnailSmallPreviewSize) -> ThumbnailVariantComparison? {
        .make(set: liveVariantSet, previewSize: previewSize)
    }

    func selectVariant(_ slot: ThumbnailVariantSlot) {
        guard !isBatchGenerating, slot != variantWorkspace.activeSlot, variantWorkspace.variantSet.contains(slot) else { return }
        let perfSpan = ThumbnailPerformanceProbe.begin(.variantSwitch); defer { perfSpan.end() } // APP-09
        commitEditorStateNow()
        guard let document = variantWorkspace.select(slot, committing: premiumMakerConfiguration.document) else { return }
        loadVariantDocument(document)
    }

    @discardableResult
    func duplicateActiveVariant() -> ThumbnailVariantSlot? {
        guard !isBatchGenerating, variantWorkspace.variantSet.canAddVariant else { return nil }
        commitEditorStateNow()
        guard let document = variantWorkspace.duplicateActive(committing: premiumMakerConfiguration.document) else { return nil }
        loadVariantDocument(document)
        return variantWorkspace.activeSlot
    }

    func removeVariant(_ slot: ThumbnailVariantSlot) {
        guard !isBatchGenerating, variantWorkspace.variantSet.variants.count > 1 else { return }
        commitEditorStateNow()
        let result = variantWorkspace.remove(slot, committing: premiumMakerConfiguration.document)
        guard result.removed else { return }
        if let document = result.documentToLoad {
            loadVariantDocument(document)
        } else {
            saveDraftNow()
        }
    }

    func renameVariant(_ slot: ThumbnailVariantSlot, to name: String) {
        variantWorkspace.rename(slot, to: name)
        saveDraftNow()
    }

    /// User gesture only. `nil` clears the pick.
    func setPreferredVariant(_ slot: ThumbnailVariantSlot?) {
        variantWorkspace.setPreferred(slot)
        saveDraftNow()
    }

    func setVariantProjectName(_ name: String) {
        variantWorkspace.setProjectName(name)
        saveDraftNow()
    }

    func dismissVariantWarning() {
        variantWarning = nil
    }

    private func loadVariantDocument(_ document: ThumbnailDocument) {
        // Drop in-flight imports so they cannot land in the wrong variant.
        imageImportRevision += 1
        layerImportRevision += 1
        stickerImportRevision += 1
        profileImportRevision += 1
        imageSelection = nil
        layerImageSelection = nil
        stickerImageSelection = nil
        profileImageSelection = nil
        isApplyingHistory = true
        premiumMakerConfiguration = PremiumMakerConfigurationModel(document: document)
        isApplyingHistory = false
        historyBaseline = ThumbnailDocumentHistory.snapshot(premiumMakerConfiguration.document)
        refreshHistoryAvailability()
        exportReport = nil
        saveDraftNow()
    }
}

// MARK: - FEATURE-01 project library hooks
// Primitives for ThumbnailProjectEditing; they live here because they touch
// private history/autosave state. Shared behaviour is in ThumbnailProjectEditing.swift.
extension PremiumMakerViewModel: ThumbnailProjectEditing {
    static var projectEditorMode: ThumbnailDocumentEditorMode { .premium }

    func makeBlankProjectDocument() -> ThumbnailDocument {
        PremiumMakerConfigurationModel().document
    }

    /// Returns true when a project was opened (migrating the legacy draft
    /// once). False means no library: the caller uses the legacy draft path.
    func openInitialProjectIfAvailable() -> Bool {
        guard let projectLibrary,
              let result = projectLibrary.openInitialProject(
                for: .premium,
                legacyStore: draftStore,
                defaultDocument: { PremiumMakerConfigurationModel().document }
              ) else {
            return false
        }
        adoptProject(result)
        restoredDraft = result.metadata.origin != .created
        return true
    }

    /// Saves through the library when a project is active. Returns the saved
    /// document, or nil when no project is active (legacy draft path).
    func saveActiveProjectDocument() throws -> ThumbnailDocument? {
        guard let projectLibrary, let activeProjectID else { return nil }
        var document = premiumMakerConfiguration.document
        document.updatedAt = Date()
        try projectLibrary.saveDocument(document, for: activeProjectID)
        return document
    }

    func commitBeforeLeavingProject() -> Bool {
        if isBatchGenerating {
            reportProjectError("Wait for batch generation to finish before switching projects.")
            return false
        }
        commitEditorStateNow()
        if case .failed = draftSaveState {
            reportProjectError("Could not save \"\(activeProjectName)\". Your work is still open here.")
            return false
        }
        return true
    }

    func adoptProject(_ result: ThumbnailProjectOpenResult) {
        pendingDraftSave?.cancel()
        pendingDraftSave = nil
        // Any in-flight import belongs to the previous project.
        imageImportRevision += 1
        layerImportRevision += 1
        stickerImportRevision += 1
        profileImportRevision += 1

        adoptProjectVariants(result) // FEATURE-01 x FEATURE-02

        isApplyingHistory = true
        premiumMakerConfiguration = PremiumMakerConfigurationModel(document: result.document)
        isApplyingHistory = false

        activeProjectID = result.metadata.id
        activeProjectName = result.metadata.name
        exportReport = nil
        // Undo/redo never crosses a project boundary.
        resetHistoryBaseline()
        draftSaveState = .saved(result.metadata.updatedAt)
        projectLibrary?.setActiveProjectID(result.metadata.id, for: .premium)
    }

    func updateActiveProjectName(_ name: String) {
        activeProjectName = name
    }

    /// FEATURE-01 x FEATURE-02: each project keeps its own A/B/C variant set
    /// next to its document, so variants never leak between projects. The
    /// project document is the active variant's latest saved state.
    private func adoptProjectVariants(_ result: ThumbnailProjectOpenResult) {
        guard let projectLibrary else { return }
        variantStore = ThumbnailVariantStore(
            fileURL: projectLibrary.store.projectDirectory(id: result.metadata.id)
                .appendingPathComponent(ThumbnailVariantStore.fileName(for: .premium))
        )
        let restored = variantStore.restoreSet(legacyDraft: result.document, editorMode: .premium)
        variantWorkspace.replaceSet(
            restored?.set ?? ThumbnailVariantSet(seedDocument: result.document, editorMode: .premium)
        )
        variantWarning = restored?.warning
    }

    func reportProjectError(_ message: String) {
        saveError = message
        showingSaveAlert = true
    }
}

// MARK: - FEATURE-08 brand kit library hook
// The only primitive that touches private state (store + persistence flag).
// Shared behaviour lives in BrandKitLibraryEditing.swift.
extension PremiumMakerViewModel {
    /// Persists first; publishes only on success (complete-or-visibly-fail).
    @discardableResult
    func commitBrandKitLibrary(_ library: BrandKitLibrary) -> Bool {
        if isDraftPersistenceEnabled {
            do {
                try brandKitStore.saveLibrary(library)
            } catch {
                reportBrandKitError("Failed to save brand kit: \(error.localizedDescription)")
                return false
            }
        }
        brandKitLibrary = library
        return true
    }
}
