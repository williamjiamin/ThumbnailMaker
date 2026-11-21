//
//  ExportQueueEditorHooks.swift
//  ThumbnailMaker
//
//  FEATURE-10: the only coupling between the editors and the export queue.
//  Read-only: builds a snapshot of the live variant set (including unsaved
//  edits in the active variant). Callers commit editor state first.
//

import Foundation

extension SimpleMakerViewModel {
    var exportQueueContext: ThumbnailExportQueueContext {
        ThumbnailExportQueueContext(
            variantSet: liveVariantSet,
            projectID: activeProjectID,
            projectName: activeProjectName,
            fallbackBaseName: simpleMakerConfiguration.exportOptions.preset.id,
            currentOptions: simpleMakerConfiguration.exportOptions
        )
    }
}

extension PremiumMakerViewModel {
    var exportQueueContext: ThumbnailExportQueueContext {
        ThumbnailExportQueueContext(
            variantSet: liveVariantSet,
            projectID: activeProjectID,
            projectName: activeProjectName,
            fallbackBaseName: premiumMakerConfiguration.exportOptions.preset.id,
            currentOptions: premiumMakerConfiguration.exportOptions
        )
    }
}
