//
//  ThumbnailVariantExportNaming.swift
//  ThumbnailMaker
//
//  FEATURE-02: predictable, A-B-C sorting export names for variants.
//

import Foundation

enum ThumbnailVariantExportNaming {
    static let preferredSuffix = "preferred"

    /// Same rule as `ThumbnailExporter.sanitizedFileName`, plus lowercasing, so
    /// the exporter's own pass is a no-op and the name shown is the name on disk.
    static func sanitized(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"[^A-Za-z0-9_-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
            .lowercased()
    }

    /// `<project>-variant-<slot>[-preferred]`, or `fallback` verbatim when the
    /// design has a single variant (every pre-variant user keeps today's names).
    static func baseName(
        projectName: String,
        slot: ThumbnailVariantSlot,
        isPreferred: Bool,
        includeSlotToken: Bool,
        fallback: String
    ) -> String {
        guard includeSlotToken else { return fallback }

        var project = sanitized(projectName)
        if project.isEmpty {
            project = sanitized(fallback)
        }
        if project.isEmpty {
            project = "thumbnail"
        }

        var components = [project, slot.exportToken]
        if isPreferred {
            components.append(preferredSuffix)
        }
        return components.joined(separator: "-")
    }
}

struct ThumbnailVariantExportPlan: Equatable {
    struct Entry: Equatable, Identifiable {
        let slot: ThumbnailVariantSlot
        let name: String
        let baseFileName: String
        let isPreferred: Bool
        let document: ThumbnailDocument

        var id: ThumbnailVariantSlot { slot }
    }

    static let threeThumbnailNote = "YouTube Test & Compare accepts exactly three thumbnails."

    let entries: [Entry]

    var isReadyForThreeVariantUpload: Bool {
        entries.count == ThumbnailVariantSet.maxVariantCount
    }

    var readinessNote: String {
        if isReadyForThreeVariantUpload {
            return "\(Self.threeThumbnailNote) This design has three variants."
        }
        let count = entries.count
        return "\(Self.threeThumbnailNote) This design has \(count) variant\(count == 1 ? "" : "s")."
    }

    static func make(from set: ThumbnailVariantSet, fallbackBaseName: String) -> ThumbnailVariantExportPlan {
        let includeSlotToken = set.hasMultipleVariants
        let entries = set.variants.sorted { $0.slot < $1.slot }.map { variant in
            Entry(
                slot: variant.slot,
                name: variant.name,
                baseFileName: ThumbnailVariantExportNaming.baseName(
                    projectName: set.projectName,
                    slot: variant.slot,
                    isPreferred: set.preferredSlot == variant.slot,
                    includeSlotToken: includeSlotToken,
                    fallback: fallbackBaseName
                ),
                isPreferred: set.preferredSlot == variant.slot,
                document: variant.document
            )
        }
        return ThumbnailVariantExportPlan(entries: entries)
    }
}

// MARK: - FEATURE-10: batch export queue names

extension ThumbnailVariantExportNaming {
    /// `<base>-<w>x<h>.<ext>` (or `<base>.<ext>` without the size token). The
    /// base goes through the same sanitizer as single exports, so a queue file
    /// and a single export of the same variant share a stem.
    static func queueFileName(
        baseName: String,
        size: ThumbnailExportSize,
        format: ThumbnailExportFormat,
        includeSizeToken: Bool
    ) -> String {
        let stem = ThumbnailExporter.sanitizedFileName(baseName)
        let sized = includeSizeToken ? "\(stem)-\(size.width)x\(size.height)" : stem
        return "\(sized).\(format.fileExtension)"
    }

    /// `name.ext`, else `name-2.ext`, `name-3.ext`, ... compared
    /// case-insensitively against `taken` (which must hold lowercased names).
    static func uniqueName(_ fileName: String, taken: Set<String>) -> String {
        guard taken.contains(fileName.lowercased()) else { return fileName }

        let url = URL(fileURLWithPath: fileName)
        let ext = url.pathExtension
        let stem = ext.isEmpty ? fileName : String(fileName.dropLast(ext.count + 1))
        var counter = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
            if !taken.contains(candidate.lowercased()) {
                return candidate
            }
            counter += 1
        }
    }
}
