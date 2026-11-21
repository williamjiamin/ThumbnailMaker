//
//  QuickCreateEditorHooks.swift
//  ThumbnailMaker
//
//  SHELL (1.1.0 rebuild): how the Quick Create wizard and "Start from
//  Scratch" hand work to the Simple editor. Both go through the editor's
//  existing primitives (project library + template application), so the
//  result is a normal project: saved, undoable (Undo returns to the blank
//  canvas), and never overwriting the project that was open before.
//

import Foundation

extension SimpleMakerViewModel {
    /// True when the open design has anything worth keeping.
    var hasWorkInProgress: Bool {
        hasExportableContent
    }

    /// Opens a fresh project (when the project library is active) and
    /// applies the wizard's document to it as one undoable step.
    /// Returns false (with an error already reported) if the new project
    /// could not be created; the previous project then stays open.
    @discardableResult
    func finishQuickCreate(_ draft: QuickCreateDraft, now: Date = Date()) -> Bool {
        let brandKit = draft.brandKitID.flatMap { brandKitLibrary.kit(id: $0) }
        let document = draft.makeDocument(brandKit: brandKit, now: now)

        if isProjectLibraryAvailable {
            guard createNewProject(named: draft.projectName) else { return false }
        }

        let template = ThumbnailTemplate(
            id: "quick-create-\(draft.templateID)",
            name: draft.projectName,
            category: .youtube,
            document: document
        )
        applyTemplate(template)
        commitEditorStateNow()
        return true
    }

    /// "Start from Scratch": keeps an untouched canvas, otherwise opens a new
    /// blank project so earlier work is never replaced.
    @discardableResult
    func startFromScratch() -> Bool {
        guard hasWorkInProgress, isProjectLibraryAvailable else {
            commitEditorStateNow()
            return true
        }
        return createNewProject()
    }
}
