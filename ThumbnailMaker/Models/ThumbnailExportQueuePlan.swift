//
//  ThumbnailExportQueuePlan.swift
//  ThumbnailMaker
//
//  FEATURE-10: the pure planner behind "Export All". Given the live variant
//  set, a recipe and a snapshot of the destination, it lists every file that
//  will be written, with its exact name, size, format and any conflict, BEFORE
//  anything renders. It never changes a size or format to make a job fit:
//  a job that cannot be honoured is blocked with a reason instead.
//

import CoreGraphics
import Foundation

struct ThumbnailExportDestinationSnapshot: Equatable {
    var displayName: String
    /// Lowercased file names already in the destination.
    var existingFileNames: Set<String>
    /// False for Photos: names are not kept and nothing is ever overwritten.
    var supportsFileNames: Bool

    init(displayName: String, existingFileNames: Set<String> = [], supportsFileNames: Bool) {
        self.displayName = displayName
        self.existingFileNames = Set(existingFileNames.map { $0.lowercased() })
        self.supportsFileNames = supportsFileNames
    }

    static let none = ThumbnailExportDestinationSnapshot(displayName: "No destination", supportsFileNames: false)
}

enum ThumbnailExportJobConflict: Equatable {
    case none
    case existsWillReplace
    case existsWillSkip
    case existsWillRename(String)
    case duplicateInQueue

    var badge: String? {
        switch self {
        case .none: return nil
        case .existsWillReplace: return "Will replace existing file"
        case .existsWillSkip: return "Exists, will skip"
        case .existsWillRename(let name): return "Exists, saving as \(name)"
        case .duplicateInQueue: return "Duplicate of an earlier row"
        }
    }
}

enum ThumbnailExportJobBlockedReason: Equatable {
    case aspectMismatch(canvasRatio: String, size: String)
    case formatUnavailable(String)
    case noContent
    case sizeOutOfRange

    var message: String {
        switch self {
        case let .aspectMismatch(canvasRatio, size):
            return "\(size) does not match this variant's \(canvasRatio) canvas. Nothing is cropped or stretched: duplicate the variant and change its canvas ratio instead."
        case .formatUnavailable(let format):
            return "\(format) export is not available on this device."
        case .noContent:
            return "This variant is empty."
        case .sizeOutOfRange:
            return "Sizes must be between \(ThumbnailExportRecipeSize.allowedDimensionRange.lowerBound) and \(ThumbnailExportRecipeSize.allowedDimensionRange.upperBound) pixels per side."
        }
    }
}

struct ThumbnailExportQueueJob: Identifiable, Equatable {
    let id: String
    let slot: ThumbnailVariantSlot
    let variantName: String
    let isPreferred: Bool
    let document: ThumbnailDocument
    let size: ThumbnailExportSize
    let format: ThumbnailExportFormat
    let quality: Double
    let budget: ThumbnailExportFileSizeBudget?
    /// Re-applied by the destination at write time.
    let overwritePolicy: ThumbnailExportOverwritePolicy
    /// The planned name before conflict handling.
    let fileName: String
    let destinationDisplayName: String
    let conflict: ThumbnailExportJobConflict
    let blockedReason: ThumbnailExportJobBlockedReason?

    /// The name the file will get, after "Keep Both" renaming.
    var targetFileName: String {
        if case .existsWillRename(let renamed) = conflict { return renamed }
        return fileName
    }

    var isBlocked: Bool { blockedReason != nil }

    /// Jobs the runner renders. Planned skips and duplicate rows are not rendered.
    var isRunnable: Bool {
        guard blockedReason == nil else { return false }
        switch conflict {
        case .existsWillSkip, .duplicateInQueue: return false
        default: return true
        }
    }

    var exportOptions: ThumbnailExportOptions {
        var options = ThumbnailExportOptions()
        options.format = format
        options.compressionQuality = quality
        options.usesCustomSize = true
        options.customSize = size
        return options
    }
}

struct ThumbnailExportQueuePlan: Equatable {
    static let aspectTolerance = 0.005

    let jobs: [ThumbnailExportQueueJob]
    let destination: ThumbnailExportDestinationSnapshot
    /// Set when the selection itself yields nothing (e.g. no preferred variant).
    let emptyReason: String?

    var runnableJobs: [ThumbnailExportQueueJob] { jobs.filter(\.isRunnable) }
    var blockedJobs: [ThumbnailExportQueueJob] { jobs.filter(\.isBlocked) }
    var plannedSkipJobs: [ThumbnailExportQueueJob] {
        jobs.filter { !$0.isBlocked && $0.conflict == .existsWillSkip }
    }

    var conflictCount: Int {
        jobs.filter { !$0.isBlocked && $0.conflict != .none }.count
    }

    var replaceCount: Int { jobs.filter { !$0.isBlocked && $0.conflict == .existsWillReplace }.count }

    var summary: String {
        if jobs.isEmpty {
            return emptyReason ?? "Nothing to export"
        }
        let files = runnableJobs.count
        var parts = ["\(files) file\(files == 1 ? "" : "s")"]
        if destination.supportsFileNames {
            parts.append("\(replaceCount) will replace")
            let skips = plannedSkipJobs.count
            if skips > 0 { parts.append("\(skips) will skip") }
        }
        parts.append("\(blockedJobs.count) blocked")
        return parts.joined(separator: " · ")
    }

    // MARK: Planning

    static func make(
        set: ThumbnailVariantSet,
        recipe: ThumbnailExportRecipe,
        projectName: String,
        fallbackBaseName: String,
        destination: ThumbnailExportDestinationSnapshot,
        formatIsAvailable: (ThumbnailExportFormat) -> Bool = { $0.canEncodeOnCurrentPlatform }
    ) -> ThumbnailExportQueuePlan {
        let slots = recipe.variantSelection.selectedSlots(in: set)
        let emptyReason: String?
        if slots.isEmpty {
            emptyReason = recipe.variantSelection.mode == .preferredOnly
                ? "No variant is marked as preferred. Mark one, or choose variants below."
                : "No variants selected."
        } else if recipe.sizes.isEmpty {
            emptyReason = "Add at least one size."
        } else {
            emptyReason = nil
        }

        let effectiveProjectName = set.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? projectName
            : set.projectName
        let includeSlotToken = set.hasMultipleVariants
        let recipeFormat = recipe.format
        let format = recipeFormat ?? .jpeg
        let formatBlock: ThumbnailExportJobBlockedReason?
        if let recipeFormat {
            formatBlock = formatIsAvailable(recipeFormat) ? nil : .formatUnavailable(recipeFormat.displayName)
        } else {
            formatBlock = .formatUnavailable(recipe.formatRawValue)
        }

        var jobs: [ThumbnailExportQueueJob] = []
        var usedIDs = Set<String>()
        var plannedNames = Set<String>()

        for slot in slots {
            guard let variant = set.variant(for: slot) else { continue }
            let isPreferred = set.preferredSlot == slot
            let base = ThumbnailVariantExportNaming.baseName(
                projectName: effectiveProjectName,
                slot: slot,
                isPreferred: isPreferred,
                includeSlotToken: includeSlotToken,
                fallback: fallbackBaseName
            )
            let canvasRatio = AspectRatio(rawValue: variant.document.canvas.aspectRatioRawValue) ?? .ratio16_9
            let hasContent = documentHasContent(variant.document)

            for size in recipe.sizes {
                var id = "\(slot.rawValue)-\(size.token)"
                var duplicateIndex = 2
                while usedIDs.contains(id) {
                    id = "\(slot.rawValue)-\(size.token)-\(duplicateIndex)"
                    duplicateIndex += 1
                }
                usedIDs.insert(id)

                let fileName = ThumbnailVariantExportNaming.queueFileName(
                    baseName: base,
                    size: size.exportSize,
                    format: format,
                    includeSizeToken: recipe.namingIncludesSizeToken
                )

                let blocked: ThumbnailExportJobBlockedReason?
                if !hasContent {
                    blocked = .noContent
                } else if let formatBlock {
                    blocked = formatBlock
                } else if !size.isWithinAllowedRange {
                    blocked = .sizeOutOfRange
                } else if !aspectMatches(canvas: canvasRatio, size: size) {
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
                        slot: slot,
                        variantName: variant.name,
                        isPreferred: isPreferred,
                        document: variant.document,
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
            }
        }

        return ThumbnailExportQueuePlan(jobs: jobs, destination: destination, emptyReason: emptyReason)
    }

    static func aspectMatches(canvas: AspectRatio, size: ThumbnailExportRecipeSize) -> Bool {
        let canvasValue = Double(canvas.value)
        guard canvasValue > 0, size.aspectValue > 0 else { return false }
        return abs(canvasValue - size.aspectValue) / canvasValue <= aspectTolerance
    }

    /// Cheap check that mirrors the editors' `hasExportableContent` without
    /// decoding any image data.
    static func documentHasContent(_ document: ThumbnailDocument) -> Bool {
        document.imageData != nil
            || !document.text.value.isEmpty
            || (document.editorMode == .premium && document.profile?.imageData != nil)
            || document.layers.contains { $0.content != nil }
    }
}
