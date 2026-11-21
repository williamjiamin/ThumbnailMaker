//
//  CompactEditorLayoutPolicy.swift
//  ThumbnailMaker
//
//  APP-08: sizing and density rules for the compact (phone) editor. Pure so
//  the numbers are unit tested instead of eyeballed.
//

import CoreGraphics

enum CompactEditorLayoutPolicy {
    static let horizontalInset: CGFloat = 20
    static let maxCanvasHeightFraction: CGFloat = 0.36
    static let minimumCanvasHeight: CGFloat = 120

    /// The canvas fills the available width and is capped at 36% of the
    /// viewport height (never below 120 pt), replacing the old
    /// "60% x 35% of the height" heuristic that left phones with a tiny canvas.
    static func canvasSize(viewport: CGSize, aspectRatio: Double) -> CGSize {
        let ratio = aspectRatio.isFinite && aspectRatio > 0 ? CGFloat(aspectRatio) : 16.0 / 9.0
        let width = viewport.width.isFinite ? viewport.width : 0
        let height = viewport.height.isFinite ? viewport.height : 0
        let availableWidth = max(1, width - horizontalInset * 2)
        let cap = max(minimumCanvasHeight, height * maxCanvasHeightFraction)

        var canvasHeight = min(availableWidth / ratio, cap)
        var canvasWidth = canvasHeight * ratio
        if canvasWidth > availableWidth {
            canvasWidth = availableWidth
            canvasHeight = availableWidth / ratio
        }
        return CGSize(width: max(1, canvasWidth), height: max(1, canvasHeight))
    }

    /// Secondary sections start collapsed on a phone unless they already hold
    /// work the creator should see (more than one variant, or extra sizes).
    static func expandsVariantsSectionByDefault(variantCount: Int, alternateSizeCount: Int) -> Bool {
        variantCount > 1 || alternateSizeCount > 0
    }

    /// Arrange tools are for multi-layer work; on a phone they stay collapsed
    /// until asked for, so the layer strip and inspector stay near the canvas.
    static let expandsArrangePanelByDefault = false
}
