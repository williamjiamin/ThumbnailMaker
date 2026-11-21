//
//  ThumbnailAdjustmentsModifier.swift
//  ThumbnailMaker
//
//  FEATURE-14: renders a `ThumbnailImageAdjustments` recipe with SwiftUI
//  compositing filters. Preview and export rasterise the same view, so they
//  agree by construction; blur is scaled by the rendered size.
//
//  ORDER IS PART OF THE CONTRACT (saved looks depend on it):
//      saturation -> contrast -> brightness -> blur -> vignette -> alpha mask
//  The trailing mask re-applies the ORIGINAL alpha silhouette so brightness
//  and the vignette never paint into transparent pixels of a cutout. Blur
//  runs before the mask on purpose: it softens inside the silhouette rather
//  than bleeding a halo around it.
//
//  A nil / neutral recipe returns `content` untouched (exact identity), and
//  so does the "show original" compare state, which the export path never
//  sets.
//

import SwiftUI

private struct ThumbnailShowsOriginalAdjustmentsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// While true (Compare held in the adjustments panel) the interactive
    /// canvas draws every image without its recipe. Export views never set it.
    var thumbnailShowsOriginalAdjustments: Bool {
        get { self[ThumbnailShowsOriginalAdjustmentsKey.self] }
        set { self[ThumbnailShowsOriginalAdjustmentsKey.self] = newValue }
    }
}

struct ThumbnailAdjustmentsModifier: ViewModifier {
    let adjustments: ThumbnailImageAdjustments?
    let renderedSize: CGSize
    @Environment(\.thumbnailShowsOriginalAdjustments) private var showsOriginal

    func body(content: Content) -> some View {
        if let recipe = effectiveRecipe {
            content
                .saturation(recipe.saturation)
                .contrast(recipe.contrast)
                .brightness(recipe.brightness)
                .blur(radius: recipe.blurRadius(forRenderedSize: renderedSize), opaque: false)
                .overlay {
                    if recipe.vignette > 0 {
                        vignette(recipe)
                    }
                }
                .compositingGroup()
                .mask { content }
        } else {
            content
        }
    }

    private var effectiveRecipe: ThumbnailImageAdjustments? {
        guard !showsOriginal, let adjustments else { return nil }
        let recipe = adjustments.clamped()
        return recipe.isNeutral ? nil : recipe
    }

    private func vignette(_ recipe: ThumbnailImageAdjustments) -> some View {
        let halfDiagonal = max(1, hypot(renderedSize.width, renderedSize.height) / 2)
        return RadialGradient(
            colors: [.clear, .black.opacity(recipe.vignetteOpacity)],
            center: .center,
            startRadius: halfDiagonal * recipe.vignetteStartFraction,
            endRadius: halfDiagonal * recipe.vignetteEndFraction
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    func thumbnailAdjustments(_ adjustments: ThumbnailImageAdjustments?, renderedSize: CGSize) -> some View {
        modifier(ThumbnailAdjustmentsModifier(adjustments: adjustments, renderedSize: renderedSize))
    }
}
