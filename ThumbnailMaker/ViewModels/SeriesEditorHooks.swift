//
//  SeriesEditorHooks.swift
//  ThumbnailMaker
//
//  FEATURE-15: the only coupling between the editors and Series. Read-only:
//  it commits pending edits, then hands Series a snapshot of the open design.
//  Series never writes back into the editor or its undo history.
//

import Foundation

extension SimpleMakerViewModel {
    /// `<project>/series/` for a library project, else a per-editor folder.
    var seriesStore: ThumbnailSeriesStore {
        if let projectLibrary, let activeProjectID {
            return ThumbnailSeriesStore(projectDirectory: projectLibrary.store.projectDirectory(id: activeProjectID))
        }
        return ThumbnailSeriesStore(directory: ThumbnailSeriesStore.defaultDirectory(for: .simple))
    }

    var isSeriesAvailable: Bool { true }

    func makeSeriesContext() -> ThumbnailSeriesContext {
        commitEditorStateNow()
        return ThumbnailSeriesContext(
            editorMode: .simple,
            projectName: activeProjectName,
            currentDocument: simpleMakerConfiguration.document,
            store: seriesStore,
            currentExportOptions: simpleMakerConfiguration.exportOptions
        )
    }
}

extension PremiumMakerViewModel {
    var seriesStore: ThumbnailSeriesStore {
        if let projectLibrary, let activeProjectID {
            return ThumbnailSeriesStore(projectDirectory: projectLibrary.store.projectDirectory(id: activeProjectID))
        }
        return ThumbnailSeriesStore(directory: ThumbnailSeriesStore.defaultDirectory(for: .premium))
    }

    /// The legacy number batch mutates the live design; never overlap it.
    var isSeriesAvailable: Bool { !isBatchGenerating }

    func makeSeriesContext() -> ThumbnailSeriesContext {
        commitEditorStateNow()
        return ThumbnailSeriesContext(
            editorMode: .premium,
            projectName: activeProjectName,
            currentDocument: premiumMakerConfiguration.document,
            store: seriesStore,
            currentExportOptions: premiumMakerConfiguration.exportOptions
        )
    }
}
