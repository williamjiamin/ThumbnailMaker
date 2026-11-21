//
//  ThumbnailProjectEditing.swift
//  ThumbnailMaker
//
//  FEATURE-01: shared project-library behaviour for both editors.
//
//  Each view model supplies a handful of primitives (in a clearly marked
//  extension at the bottom of its own file, because they touch private
//  history/autosave state). Everything else - switching, creating,
//  renaming, duplicating, trash - lives here once.
//

import Foundation

@MainActor
protocol ThumbnailProjectEditing: AnyObject {
    static var projectEditorMode: ThumbnailDocumentEditorMode { get }
    var projectLibrary: ThumbnailProjectLibrary? { get }
    var activeProjectID: UUID? { get }
    var activeProjectName: String { get }
    var draftSaveState: DraftSaveState { get }
    var saveError: String? { get set }
    var showingSaveAlert: Bool { get set }

    /// A blank document for a new project in this editor.
    func makeBlankProjectDocument() -> ThumbnailDocument
    /// Cancels the debounce and saves synchronously. Returns false (and has
    /// already shown an error) when the save failed, so the caller must stay.
    func commitBeforeLeavingProject() -> Bool
    /// Replaces the editor content with a project's document without
    /// recording an undo step or scheduling an autosave.
    func adoptProject(_ result: ThumbnailProjectOpenResult)
    func updateActiveProjectName(_ name: String)
    func reportProjectError(_ message: String)
    func retryDraftSave()
}

extension ThumbnailProjectEditing {
    var isProjectLibraryAvailable: Bool {
        projectLibrary != nil && activeProjectID != nil
    }

    /// Complete-or-visibly-fail: the pending edit is saved first; if that
    /// fails we stay on the current project and say so.
    @discardableResult
    func switchToProject(_ id: UUID) -> Bool {
        guard let projectLibrary else { return false }
        guard id != activeProjectID else { return true }
        guard commitBeforeLeavingProject() else { return false }

        do {
            let document = try projectLibrary.document(for: id)
            guard let metadata = projectLibrary.metadata(id: id) else {
                throw ThumbnailProjectLibraryError.projectNotFound(id)
            }
            adoptProject(ThumbnailProjectOpenResult(metadata: metadata, document: document, warning: nil))
            return true
        } catch {
            reportProjectError(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func createNewProject(named name: String = ThumbnailProjectMetadata.defaultName) -> Bool {
        guard let projectLibrary else { return false }
        guard commitBeforeLeavingProject() else { return false }

        var document = makeBlankProjectDocument()
        document.editorMode = Self.projectEditorMode
        do {
            let metadata = try projectLibrary.createProject(
                name: name,
                editorMode: Self.projectEditorMode,
                document: document
            )
            adoptProject(ThumbnailProjectOpenResult(metadata: metadata, document: document, warning: nil))
            return true
        } catch {
            reportProjectError(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func renameProject(_ id: UUID, to name: String) -> Bool {
        guard let projectLibrary else { return false }
        do {
            try projectLibrary.rename(id: id, to: name)
            if id == activeProjectID, let metadata = projectLibrary.metadata(id: id) {
                updateActiveProjectName(metadata.name)
            }
            return true
        } catch {
            reportProjectError(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func duplicateProject(_ id: UUID) -> ThumbnailProjectMetadata? {
        guard let projectLibrary else { return nil }
        if id == activeProjectID, !commitBeforeLeavingProject() {
            return nil
        }
        do {
            return try projectLibrary.duplicate(id: id)
        } catch {
            reportProjectError(error.localizedDescription)
            return nil
        }
    }

    /// Moving the open project to the trash opens the newest remaining
    /// project (or a new blank one). Nothing is deleted from disk.
    @discardableResult
    func trashProject(_ id: UUID) -> Bool {
        guard let projectLibrary else { return false }
        let isActive = id == activeProjectID
        if isActive, !commitBeforeLeavingProject() {
            return false
        }

        do {
            try projectLibrary.moveToTrash(id: id)
        } catch {
            reportProjectError(error.localizedDescription)
            return false
        }

        guard isActive else { return true }
        guard let fallback = projectLibrary.openFallbackProject(
            for: Self.projectEditorMode,
            excluding: id,
            defaultDocument: { makeBlankProjectDocument() }
        ) else {
            // Could not open anything else: put the project back rather than
            // leave the editor bound to a trashed project.
            try? projectLibrary.restoreFromTrash(id: id)
            projectLibrary.setActiveProjectID(id, for: Self.projectEditorMode)
            reportProjectError(projectLibrary.libraryError ?? "Could not open another project.")
            return false
        }
        adoptProject(fallback)
        return true
    }

    @discardableResult
    func restoreProject(_ id: UUID) -> Bool {
        guard let projectLibrary else { return false }
        do {
            try projectLibrary.restoreFromTrash(id: id)
            return true
        } catch {
            reportProjectError(error.localizedDescription)
            return false
        }
    }

    /// Permanent. Only reachable from an explicit, confirmed user action.
    @discardableResult
    func purgeProject(_ id: UUID) -> Bool {
        guard let projectLibrary, id != activeProjectID else { return false }
        do {
            try projectLibrary.purge(id: id)
            return true
        } catch {
            reportProjectError(error.localizedDescription)
            return false
        }
    }
}
