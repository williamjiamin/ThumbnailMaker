//
//  ThumbnailSeriesExportPlan.swift
//  ThumbnailMaker
//
//  FEATURE-15: turns a validated series into a FEATURE-10
//  `ThumbnailExportQueuePlan` (one job per renderable row x recipe size), so a
//  series renders, encodes, fits file-size budgets, handles name conflicts,
//  cancels and retries through the SAME queue runner and destinations as
//  "Export All". There is no series-specific exporter.
//

import Foundation

struct ThumbnailSeriesExportPlan {
    let queuePlan: ThumbnailExportQueuePlan
    /// Queue job id -> series row id.
    let rowIDByJobID: [String: UUID]
    /// Rows left out because they have errors (table order).
    let skippedRowIDs: [UUID]

    func jobIDs(for rowID: UUID) -> [String] {
        queuePlan.jobs.map(\.id).filter { rowIDByJobID[$0] == rowID }
    }

    static func make(
        series: ThumbnailSeries,
        source: ThumbnailSeriesSource,
        report: ThumbnailSeriesValidationReport,
        recipe: ThumbnailExportRecipe,
        destination: ThumbnailExportDestinationSnapshot,
        imageData: (String) -> Data?,
        formatIsAvailable: (ThumbnailExportFormat) -> Bool = { $0.canEncodeOnCurrentPlatform }
    ) -> ThumbnailSeriesExportPlan {
        let renderable = Set(report.renderableRowIDs)
        let rows = series.rows.filter { renderable.contains($0.id) }
        let skipped = series.rows.filter { !renderable.contains($0.id) }.map(\.id)

        let emptyReason: String?
        if series.rows.isEmpty {
            emptyReason = "Add rows or import a CSV first."
        } else if rows.isEmpty {
            emptyReason = "Every row needs fixing before it can render."
        } else if recipe.sizes.isEmpty {
            emptyReason = "Add at least one size."
        } else {
            emptyReason = nil
        }

        let format = recipe.format ?? .jpeg
        let formatBlock: ThumbnailExportJobBlockedReason?
        if let recipeFormat = recipe.format {
            formatBlock = formatIsAvailable(recipeFormat) ? nil : .formatUnavailable(recipeFormat.displayName)
        } else {
            formatBlock = .formatUnavailable(recipe.formatRawValue)
        }
        let canvasRatio = AspectRatio(rawValue: source.template.document.canvas.aspectRatioRawValue) ?? .ratio16_9
        let includeSizeToken = recipe.namingIncludesSizeToken || recipe.sizes.count > 1

        var jobs: [ThumbnailExportQueueJob] = []
        var rowIDByJobID: [String: UUID] = [:]
        var plannedNames = Set<String>()

        for row in rows {
            let document = ThumbnailSeriesRecipe.document(
                for: row,
                in: source,
                imageData: row.imageRef.flatMap { imageData($0.digest) }
            )
            let stem = report.outputStems[row.id] ?? "series"
            let hasContent = ThumbnailExportQueuePlan.documentHasContent(document)

            for size in recipe.sizes {
                let id = "\(row.id.uuidString)-\(size.token)"
                let fileName = ThumbnailVariantExportNaming.queueFileName(
                    baseName: stem,
                    size: size.exportSize,
                    format: format,
                    includeSizeToken: includeSizeToken
                )

                let blocked: ThumbnailExportJobBlockedReason?
                if !hasContent {
                    blocked = .noContent
                } else if let formatBlock {
                    blocked = formatBlock
                } else if !size.isWithinAllowedRange {
                    blocked = .sizeOutOfRange
                } else if !ThumbnailExportQueuePlan.aspectMatches(canvas: canvasRatio, size: size) {
                    blocked = .aspectMismatch(canvasRatio: canvasRatio.rawValue, size: "\(size.width) x \(size.height)")
                } else {
                    blocked = nil
                }

                var conflict = ThumbnailExportJobConflict.none
                if blocked == nil && destination.supportsFileNames {
                    let key = fileName.lowercased()
                    if plannedNames.contains(key) {
                        conflict = .duplicateInQueue
                    } else if destination.existingFileNames.contains(key) {
                        switch recipe.overwritePolicy {
                        case .replace:
                            conflict = .existsWillReplace
                        case .skip:
                            conflict = .existsWillSkip
                        case .keepBoth:
                            let renamed = ThumbnailVariantExportNaming.uniqueName(
                                fileName,
                                taken: destination.existingFileNames.union(plannedNames)
                            )
                            conflict = .existsWillRename(renamed)
                            plannedNames.insert(renamed.lowercased())
                        }
                    }
                    plannedNames.insert(key)
                }

                jobs.append(
                    ThumbnailExportQueueJob(
                        id: id,
                        slot: .a,
                        variantName: row.title,
                        isPreferred: false,
                        document: document,
                        size: size.exportSize,
                        format: format,
                        quality: recipe.compressionQuality,
                        budget: recipe.fileSizeBudget,
                        overwritePolicy: recipe.overwritePolicy,
                        fileName: fileName,
                        destinationDisplayName: destination.displayName,
                        conflict: conflict,
                        blockedReason: blocked
                    )
                )
                rowIDByJobID[id] = row.id
            }
        }

        return ThumbnailSeriesExportPlan(
            queuePlan: ThumbnailExportQueuePlan(jobs: jobs, destination: destination, emptyReason: emptyReason),
            rowIDByJobID: rowIDByJobID,
            skippedRowIDs: skipped
        )
    }
}
