//
//  ThumbnailAccessibilityText.swift
//  ThumbnailMaker
//
//  APP-07: spoken labels and values derived from model types, kept out of
//  the views so they can be unit tested.
//

import Foundation

enum ThumbnailAccessibilityText {
    /// Custom Size wins: while it is on, no preset reads as selected.
    static func isExportPresetSelected(
        _ preset: ThumbnailExportPreset,
        options: ThumbnailExportOptions
    ) -> Bool {
        !options.usesCustomSize && options.preset == preset
    }

    static func exportPresetValue(
        preset: ThumbnailExportPreset,
        options: ThumbnailExportOptions
    ) -> String {
        let state = isExportPresetSelected(preset, options: options) ? "Selected" : "Not selected"
        return "\(state), \(preset.summary)"
    }

    /// Spoken summary for the collapsed Variants & Sizes section.
    static func variantsSectionSummary(
        variantCount: Int,
        activeVariantName: String,
        alternateSizeCount: Int
    ) -> String {
        let count = max(1, variantCount)
        var parts = [count == 1 ? "1 variant" : "\(count) variants"]
        let name = activeVariantName.trimmingCharacters(in: .whitespacesAndNewlines)
        if count > 1, !name.isEmpty {
            parts.append("editing \(name)")
        }
        let sizes = max(0, alternateSizeCount)
        if sizes > 0 {
            parts.append(sizes == 1 ? "1 extra size" : "\(sizes) extra sizes")
        }
        return parts.joined(separator: ", ")
    }

    static func disclosureValue(isExpanded: Bool, summary: String?) -> String {
        let state = isExpanded ? "Expanded" : "Collapsed"
        guard let summary, !summary.isEmpty else { return state }
        return "\(state), \(summary)"
    }
}
