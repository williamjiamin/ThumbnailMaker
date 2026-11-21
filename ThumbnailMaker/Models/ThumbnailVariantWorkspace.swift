//
//  ThumbnailVariantWorkspace.swift
//  ThumbnailMaker
//
//  FEATURE-02: the editor-agnostic state machine behind A/B/C variants.
//  Both view models hold one of these and call into it through small hooks, so
//  the variant rules (independent undo, no re-lettering, user-only preferred)
//  live in one tested place instead of being mirrored in two editors.
//

import Foundation

struct ThumbnailVariantWorkspace: Equatable {
    private(set) var variantSet: ThumbnailVariantSet
    private(set) var historyBook: ThumbnailVariantHistoryBook
    /// APP-09: cap on distinct image bytes kept alive by undo/redo across all
    /// slots; nil disables the cap.
    var historyPayloadByteBudget: Int? = ThumbnailPerformanceBudget.historyPayloadByteBudget

    init(seedDocument: ThumbnailDocument, editorMode: ThumbnailDocumentEditorMode) {
        self.init(variantSet: ThumbnailVariantSet(seedDocument: seedDocument, editorMode: editorMode))
    }

    init(variantSet: ThumbnailVariantSet) {
        let normalized = variantSet.normalized()
        self.variantSet = normalized
        historyBook = ThumbnailVariantHistoryBook(defaultBaseline: normalized.activeDocument)
        for variant in normalized.variants {
            historyBook.resetSlot(variant.slot, to: variant.document)
        }
    }

    var activeSlot: ThumbnailVariantSlot { variantSet.activeSlot }

    /// Undo history of the ACTIVE variant. Settable so existing
    /// `history.record(...)` / `history.undo(...)` call sites work unchanged.
    var activeHistory: ThumbnailDocumentHistory {
        get { historyBook.history(for: variantSet.activeSlot) }
        set {
            historyBook.setHistory(newValue, for: variantSet.activeSlot)
            enforceHistoryPayloadBudget() // APP-09
        }
    }

    /// APP-09: trims history to `historyPayloadByteBudget` and publishes the
    /// resulting payload size to the diagnostics recorder.
    mutating func enforceHistoryPayloadBudget() {
        let bytes: Int
        if let historyPayloadByteBudget {
            bytes = historyBook.enforcePayloadBudget(historyPayloadByteBudget, activeSlot: variantSet.activeSlot)
        } else {
            bytes = historyBook.totalPayloadBytes()
        }
        ThumbnailPerformanceRecorder.emitHistoryPayload(bytes: bytes)
    }

    var activeBaseline: ThumbnailDocument {
        get { historyBook.baseline(for: variantSet.activeSlot) }
        set { historyBook.setBaseline(newValue, for: variantSet.activeSlot) }
    }

    /// Clears the active variant's stacks (used when a draft is restored or a
    /// UI-test seed replaces the document).
    mutating func resetActiveHistory(to document: ThumbnailDocument) {
        historyBook.resetSlot(variantSet.activeSlot, to: document)
    }

    /// Replaces the whole workspace with a restored set; every slot gets fresh
    /// stacks.
    mutating func replaceSet(_ newSet: ThumbnailVariantSet) {
        let budget = historyPayloadByteBudget
        self = ThumbnailVariantWorkspace(variantSet: newSet)
        historyPayloadByteBudget = budget
    }

    mutating func syncActiveDocument(_ document: ThumbnailDocument, now: Date = Date()) {
        variantSet.updateDocument(document, for: variantSet.activeSlot, now: now)
    }

    /// Stores the outgoing live document, activates `slot`, and returns the
    /// incoming document to load. The incoming slot keeps its own undo stack.
    mutating func select(
        _ slot: ThumbnailVariantSlot,
        committing liveDocument: ThumbnailDocument
    ) -> ThumbnailDocument? {
        guard slot != variantSet.activeSlot, variantSet.contains(slot) else { return nil }
        syncActiveDocument(liveDocument)
        variantSet.activate(slot)
        return variantSet.activeDocument
    }

    /// Copies the active (live) document into the next free slot, activates it
    /// and returns the document to load. `nil` when three variants exist.
    mutating func duplicateActive(
        committing liveDocument: ThumbnailDocument,
        now: Date = Date()
    ) -> ThumbnailDocument? {
        guard variantSet.canAddVariant else { return nil }
        syncActiveDocument(liveDocument, now: now)
        guard let newSlot = variantSet.duplicateVariant(from: variantSet.activeSlot, now: now) else { return nil }
        historyBook.resetSlot(newSlot, to: variantSet.activeDocument)
        return variantSet.activeDocument
    }

    /// Removes a variant. Returns the document to load when the active variant
    /// changed as a result, otherwise `nil`.
    mutating func remove(
        _ slot: ThumbnailVariantSlot,
        committing liveDocument: ThumbnailDocument
    ) -> (removed: Bool, documentToLoad: ThumbnailDocument?) {
        syncActiveDocument(liveDocument)
        let wasActive = slot == variantSet.activeSlot
        guard variantSet.removeVariant(slot) else { return (false, nil) }
        historyBook.discardSlot(slot)
        return (true, wasActive ? variantSet.activeDocument : nil)
    }

    mutating func rename(_ slot: ThumbnailVariantSlot, to name: String) {
        variantSet.rename(slot: slot, to: name)
    }

    mutating func setPreferred(_ slot: ThumbnailVariantSlot?) {
        if let slot {
            variantSet.setPreferred(slot)
        } else {
            variantSet.clearPreferred()
        }
    }

    mutating func setProjectName(_ name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard trimmed != variantSet.projectName else { return }
        variantSet.projectName = trimmed
        variantSet.updatedAt = Date()
    }

    /// The set as it would be persisted right now, with the live document in the
    /// active slot.
    func setIncluding(liveDocument: ThumbnailDocument) -> ThumbnailVariantSet {
        var copy = variantSet
        copy.updateDocument(liveDocument, for: copy.activeSlot)
        return copy
    }

    func exportBaseName(fallback: String) -> String {
        ThumbnailVariantExportNaming.baseName(
            projectName: variantSet.projectName,
            slot: variantSet.activeSlot,
            isPreferred: variantSet.preferredSlot == variantSet.activeSlot,
            includeSlotToken: variantSet.hasMultipleVariants,
            fallback: fallback
        )
    }
}
