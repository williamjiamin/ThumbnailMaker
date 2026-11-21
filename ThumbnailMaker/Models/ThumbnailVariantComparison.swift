//
//  ThumbnailVariantComparison.swift
//  ThumbnailMaker
//
//  FEATURE-02: side-by-side comparison of 2-3 variants at one identical size.
//

import CoreGraphics
import Foundation

struct ThumbnailVariantComparison: Equatable {
    struct Pane: Equatable, Identifiable {
        let slot: ThumbnailVariantSlot
        let name: String
        let isPreferred: Bool
        let isActive: Bool
        let document: ThumbnailDocument
        /// The variant's own aspect ratio differs from the comparison ratio.
        let hasMismatchedAspectRatio: Bool
        let ownAspectRatio: AspectRatio

        var id: ThumbnailVariantSlot { slot }
    }

    let panes: [Pane]
    /// One ratio for every pane, taken from the active variant.
    let aspectRatio: AspectRatio
    let previewSize: ThumbnailSmallPreviewSize

    /// Identical for every pane: that is the point of the comparison.
    var renderSize: CGSize { previewSize.size(for: aspectRatio) }

    var mismatchedSlots: [ThumbnailVariantSlot] {
        panes.filter(\.hasMismatchedAspectRatio).map(\.slot)
    }

    static func make(
        set: ThumbnailVariantSet,
        previewSize: ThumbnailSmallPreviewSize
    ) -> ThumbnailVariantComparison? {
        guard set.canCompare else { return nil }

        let ratio = aspectRatio(of: set.activeDocument)
        let panes = set.variants.sorted { $0.slot < $1.slot }.map { variant in
            let ownRatio = aspectRatio(of: variant.document)
            return Pane(
                slot: variant.slot,
                name: variant.name,
                isPreferred: set.preferredSlot == variant.slot,
                isActive: set.activeSlot == variant.slot,
                document: variant.document,
                hasMismatchedAspectRatio: ownRatio != ratio,
                ownAspectRatio: ownRatio
            )
        }
        return ThumbnailVariantComparison(panes: panes, aspectRatio: ratio, previewSize: previewSize)
    }

    static func aspectRatio(of document: ThumbnailDocument) -> AspectRatio {
        AspectRatio(rawValue: document.canvas.aspectRatioRawValue) ?? .ratio16_9
    }
}

extension ThumbnailVariantComparison.Pane {
    /// A factual note for a pane whose own ratio differs; never a judgement.
    var aspectRatioNote: String? {
        guard hasMismatchedAspectRatio else { return nil }
        return "\(slot.displayLetter) is set to \(ownAspectRatio.rawValue)"
    }
}
