//
//  ThumbnailImageFrameRecipe.swift
//  ThumbnailMaker
//
//  A reversible, non-destructive framing recipe for an image: how the
//  original pixels are fitted into a frame (fit / fill / stretch), which
//  point of the source stays in focus, and how far it is zoomed in. The
//  original image bytes are never re-encoded or cropped; preview and export
//  both derive the visible region from this recipe through
//  `ThumbnailImageGeometry.solve`.
//

import CoreGraphics
import Foundation

enum ThumbnailImageFitMode: String, Codable, CaseIterable, Equatable, Identifiable {
    /// Letterbox the whole image inside the frame. Today's behaviour and the
    /// back-compat default for every existing document.
    case fit
    /// Aspect-fill the frame and crop the overflow around the focal point.
    case fill
    /// Explicit, opt-in distortion to the frame. Never a default.
    case stretch

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fit: "Fit"
        case .fill: "Fill"
        case .stretch: "Stretch"
        }
    }
}

struct ThumbnailImageFrameRecipe: Codable, Equatable {
    static let zoomLimits: ClosedRange<Double> = 1.0...8.0
    static let focusLimits: ClosedRange<Double> = 0.0...1.0

    /// Letterbox, centred, no zoom: byte-for-byte the pre-recipe rendering.
    static let identity = ThumbnailImageFrameRecipe(fit: .fit, focusX: 0.5, focusY: 0.5, zoom: 1)
    /// Aspect-fill, centre crop.
    static let fillCentered = ThumbnailImageFrameRecipe(fit: .fill, focusX: 0.5, focusY: 0.5, zoom: 1)

    private(set) var fitRawValue: String
    /// Normalized focal point in display-oriented source space (0 = left/top).
    private(set) var focusX: Double
    private(set) var focusY: Double
    /// Multiplier over the fit/fill baseline scale.
    private(set) var zoom: Double

    init(fit: ThumbnailImageFitMode, focusX: Double = 0.5, focusY: Double = 0.5, zoom: Double = 1) {
        self.fitRawValue = fit.rawValue
        self.focusX = Self.clampedFocus(focusX)
        self.focusY = Self.clampedFocus(focusY)
        self.zoom = Self.clampedZoom(zoom)
    }

    var fit: ThumbnailImageFitMode {
        get { ThumbnailImageFitMode(rawValue: fitRawValue) ?? .fit }
        set { fitRawValue = newValue.rawValue }
    }

    var isIdentity: Bool {
        self == .identity
    }

    func with(fit: ThumbnailImageFitMode) -> ThumbnailImageFrameRecipe {
        ThumbnailImageFrameRecipe(fit: fit, focusX: focusX, focusY: focusY, zoom: zoom)
    }

    func with(zoom: Double) -> ThumbnailImageFrameRecipe {
        ThumbnailImageFrameRecipe(fit: fit, focusX: focusX, focusY: focusY, zoom: zoom)
    }

    func with(focusX: Double, focusY: Double) -> ThumbnailImageFrameRecipe {
        ThumbnailImageFrameRecipe(fit: fit, focusX: focusX, focusY: focusY, zoom: zoom)
    }

    // MARK: Codable (clamps corrupt / hand-edited values; never yields NaN)

    private enum CodingKeys: String, CodingKey {
        case fitRawValue
        case focusX
        case focusY
        case zoom
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawFit = try container.decodeIfPresent(String.self, forKey: .fitRawValue)
        self.init(
            fit: rawFit.flatMap(ThumbnailImageFitMode.init(rawValue:)) ?? .fit,
            focusX: try container.decodeIfPresent(Double.self, forKey: .focusX) ?? 0.5,
            focusY: try container.decodeIfPresent(Double.self, forKey: .focusY) ?? 0.5,
            zoom: try container.decodeIfPresent(Double.self, forKey: .zoom) ?? 1
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fit.rawValue, forKey: .fitRawValue)
        try container.encode(focusX, forKey: .focusX)
        try container.encode(focusY, forKey: .focusY)
        try container.encode(zoom, forKey: .zoom)
    }

    static func clampedFocus(_ value: Double) -> Double {
        guard value.isFinite else { return 0.5 }
        return min(focusLimits.upperBound, max(focusLimits.lowerBound, value))
    }

    static func clampedZoom(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(zoomLimits.upperBound, max(zoomLimits.lowerBound, value))
    }
}

// MARK: - Pure recipe transforms

extension ThumbnailImageFrameRecipe {
    /// Converts one completed pan (points, in `frameSize` space) plus a pinch
    /// magnification into a new recipe. Dragging the image right moves the
    /// focal point left. The focal point is clamped to the range that can
    /// actually move the visible region, so there is no dead zone when the
    /// user drags back.
    static func applying(
        panTranslation: CGSize,
        magnification: CGFloat,
        to base: ThumbnailImageFrameRecipe,
        sourceSize: CGSize,
        frameSize: CGSize
    ) -> ThumbnailImageFrameRecipe {
        let safeMagnification = magnification.isFinite && magnification > 0 ? Double(magnification) : 1
        let zoomed = base.with(zoom: base.zoom * safeMagnification)
        guard zoomed.fit != .stretch else { return zoomed }

        let solution = ThumbnailImageGeometry.solve(
            sourceSize: sourceSize,
            frameSize: frameSize,
            recipe: zoomed
        )
        guard solution.renderSize.width > 0, solution.renderSize.height > 0 else { return zoomed }

        let deltaX = panTranslation.width.isFinite ? Double(panTranslation.width / solution.renderSize.width) : 0
        let deltaY = panTranslation.height.isFinite ? Double(panTranslation.height / solution.renderSize.height) : 0
        let focusX = effectiveFocus(
            zoomed.focusX - deltaX,
            render: solution.renderSize.width,
            frame: solution.frameSize.width
        )
        let focusY = effectiveFocus(
            zoomed.focusY - deltaY,
            render: solution.renderSize.height,
            frame: solution.frameSize.height
        )
        return zoomed.with(focusX: focusX, focusY: focusY)
    }

    /// Clamps a focal coordinate to the range where the visible window is not
    /// pinned against an image edge. When the image does not overflow the
    /// frame on this axis the focal point has no effect and is left as is.
    static func effectiveFocus(_ focus: Double, render: CGFloat, frame: CGFloat) -> Double {
        guard render > frame, render > 0 else { return clampedFocus(focus) }
        let half = Double(frame / render) / 2
        return min(1 - half, max(half, clampedFocus(focus)))
    }
}
