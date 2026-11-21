//
//  ThumbnailDrawingPlacement.swift
//  ThumbnailMaker
//
//  DONOR (Simple Meme Maker Editor/DrawingMode.swift DrawingPlacement): the
//  pure maths that turns strokes drawn on a PencilKit surface into an
//  ordinary IMAGE layer — a transparent PNG of just the strokes, placed where
//  they were drawn. No new layer kind: it moves, scales, rotates, groups,
//  undoes and exports like any picture. Strokes are not re-editable once
//  placed; for a quick circle or arrow that is the right trade.
//
//  Adapted to ThumbnailMaker's image layer model: a layer is a normalized
//  centre (ThumbnailOverlayTransform) plus `size`, the longest side as a
//  fraction of the canvas's SHORTEST side (ContentLayerCanvasGeometry).
//

import CoreGraphics
import Foundation

enum ThumbnailDrawingPlacement {
    /// Room around the strokes so a round cap is not shaved off at the edge.
    static let strokeMargin: CGFloat = 4

    struct Placement: Equatable {
        var transform: ThumbnailOverlayTransform
        var size: Double
        /// True when the drawing had to be moved or shrunk to fit the layer
        /// limits (the image layer size range and the centre range).
        var wasClamped: Bool
    }

    /// Where strokes drawn at `bounds` on a surface of `surface` size land in
    /// a document of `document` size, in document coordinates (donor maths).
    static func frame(of bounds: CGRect, surface: CGSize, document: CGSize) -> CGRect {
        guard surface.width > 0, surface.height > 0 else { return .zero }
        let scale = document.width / surface.width
        return CGRect(
            x: bounds.minX * scale,
            y: bounds.minY * scale,
            width: bounds.width * scale,
            height: bounds.height * scale
        )
    }

    /// Pixel density the strokes are rendered at so the PNG matches the
    /// document resolution however small the surface they were drawn on.
    static func pixelsPerPoint(surface: CGSize, document: CGSize) -> CGFloat {
        guard surface.width > 0, document.width > 0 else { return 1 }
        return document.width / surface.width
    }

    /// The document resolution drawings are rendered at: twice the aspect
    /// ratio's reference dimensions (2048 on the long side), crisp at the
    /// common 1080p/1440p exports.
    static func documentPixelSize(for ratio: AspectRatio) -> CGSize {
        CGSize(width: ratio.dimensions.width * 2, height: ratio.dimensions.height * 2)
    }

    /// The surface size a canvas of `document` aspect gets inside `space`
    /// (aspect-fit, the same fit the editor preview uses).
    static func fittedSurface(for document: CGSize, in space: CGSize) -> CGSize {
        guard document.width > 0, document.height > 0, space.width > 0, space.height > 0 else { return .zero }
        let scale = min(space.width / document.width, space.height / document.height)
        return CGSize(width: document.width * scale, height: document.height * scale)
    }

    /// The image-layer placement that reproduces strokes drawn at `bounds` on
    /// `surface`. nil for an empty/degenerate drawing.
    static func placement(of bounds: CGRect, surface: CGSize) -> Placement? {
        guard surface.width > 0, surface.height > 0,
              bounds.width > 0, bounds.height > 0,
              bounds.minX.isFinite, bounds.minY.isFinite,
              bounds.width.isFinite, bounds.height.isFinite else { return nil }

        let rawX = bounds.midX / surface.width
        let rawY = bounds.midY / surface.height
        let centerRange = ThumbnailOverlayTransform.centerRange
        let x = min(centerRange.upperBound, max(centerRange.lowerBound, rawX))
        let y = min(centerRange.upperBound, max(centerRange.lowerBound, rawY))

        let rawSize = max(bounds.width, bounds.height) / min(surface.width, surface.height)
        let limits = ContentLayerCanvasGeometry.imageSizeLimits
        let size = min(limits.upperBound, max(limits.lowerBound, rawSize))

        let tolerance: CGFloat = 0.000_1
        let wasClamped = abs(x - rawX) > tolerance
            || abs(y - rawY) > tolerance
            || abs(size - rawSize) > tolerance
        return Placement(
            transform: ThumbnailOverlayTransform(x: x, y: y),
            size: Double(size),
            wasClamped: wasClamped
        )
    }

    /// Stroke bounds grown by `strokeMargin`, kept inside the surface.
    static func paddedBounds(_ bounds: CGRect, surface: CGSize) -> CGRect {
        guard !bounds.isNull, !bounds.isEmpty else { return .null }
        let padded = bounds.insetBy(dx: -strokeMargin, dy: -strokeMargin)
        let clipped = padded.intersection(CGRect(origin: .zero, size: surface))
        return clipped.isNull || clipped.isEmpty ? .null : clipped
    }
}
