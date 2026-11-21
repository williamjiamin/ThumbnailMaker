//
//  ThumbnailFormatReflow.swift
//  ThumbnailMaker
//
//  FEATURE-09: pure proposal of a new size from the original design. It
//  never mutates its input. Geometry rules:
//  - text keeps its on-screen size relative to the short side, then shrinks
//    until its natural width fits 90% of the new canvas width;
//  - image layers are already short-side relative and keep their size;
//  - the profile circle is width relative and is rescaled to the short side;
//  - shapes keep their pixel aspect, scaled by the short-side ratio;
//  - every centre is pulled inward so the layer fits the target preset's
//    safe zone when it can;
//  - the background keeps its focal point through the FEATURE-03 recipe.
//

import CoreGraphics
import Foundation

enum ThumbnailFormatReflow {
    static let textWidthBudget: CGFloat = 0.9
    /// A letterboxed (`.fit`) image stays letterboxed only if it still covers
    /// at least this share of the new canvas.
    static let minimumFitCoverage: CGFloat = 0.6

    static func canvasSize(of document: ThumbnailDocument) -> CGSize {
        let ratio = AspectRatio(rawValue: document.canvas.aspectRatioRawValue) ?? .ratio16_9
        let dimensions = ratio.dimensions
        return CGSize(width: dimensions.width, height: dimensions.height)
    }

    static func propose(
        master: ThumbnailDocument,
        kind: ThumbnailFormatKind,
        sourceImageSize: CGSize?,
        layerImageSizes: [String: CGSize] = [:],
        createdAt: Date = Date()
    ) -> ThumbnailAlternateFormat {
        var layout: [String: ThumbnailLayerGeometry] = [:]
        for id in master.formatGeometryLayerIDs {
            if let geometry = geometry(for: id, master: master, kind: kind, layerImageSizes: layerImageSizes) {
                layout[id] = geometry
            }
        }
        return ThumbnailAlternateFormat(
            kind: kind,
            createdAt: createdAt,
            imageRecipe: proposedRecipe(
                master.imageRecipe,
                from: canvasSize(of: master),
                to: kind.canvasSize,
                sourceImageSize: sourceImageSize
            ),
            layout: layout
        )
    }

    // MARK: Layers

    static func geometry(
        for layerID: String,
        master: ThumbnailDocument,
        kind: ThumbnailFormatKind,
        layerImageSizes: [String: CGSize] = [:]
    ) -> ThumbnailLayerGeometry? {
        guard var geometry = ThumbnailLayerGeometry.extract(layerID: layerID, from: master) else { return nil }
        let source = canvasSize(of: master)
        let target = kind.canvasSize
        let sourceMin = max(1, min(source.width, source.height))
        let targetMin = max(1, min(target.width, target.height))

        switch layerKind(layerID, in: master) {
        case .text(let value, let style):
            let original = CGFloat(geometry.size ?? 0.15)
            var size = clamp(
                original * (source.height / sourceMin) * (targetMin / max(1, target.height)),
                ContentLayerCanvasGeometry.textSizeLimits
            )
            for _ in 0..<4 {
                let width = naturalTextWidth(value: value, size: size, style: style, canvasSize: target)
                let budget = target.width * textWidthBudget
                guard width > budget, width > 0 else { break }
                let next = clamp(size * budget / width, ContentLayerCanvasGeometry.textSizeLimits)
                guard next < size else { break }
                size = next
            }
            geometry.size = Double(size)
        case .profile:
            let original = CGFloat(geometry.size ?? 0.2)
            geometry.size = Double(clamp(
                original * (source.width / sourceMin) * (targetMin / max(1, target.width)),
                ThumbnailLayerGeometry.profileSizeLimits
            ))
        case .image:
            break
        case .shape:
            let scale = targetMin / sourceMin
            geometry.width = Double(clamp(
                CGFloat(geometry.width ?? 0.34) * (source.width / max(1, target.width)) * scale,
                ContentLayerCanvasGeometry.shapeWidthLimits
            ))
            geometry.height = Double(clamp(
                CGFloat(geometry.height ?? 0.22) * (source.height / max(1, target.height)) * scale,
                ContentLayerCanvasGeometry.shapeHeightLimits
            ))
        case .none:
            return nil
        }

        geometry.transform = ThumbnailLayerGeometry.sanitized(geometry.transform)
        if let frame = frameSize(
            layerID: layerID,
            geometry: geometry,
            in: master,
            canvasSize: target,
            layerImageSizes: layerImageSizes
        ) {
            let bounds = kind.preset.safeZone?.contentRect(in: target) ?? CGRect(origin: .zero, size: target)
            geometry.transform = pulledInside(geometry.transform, frame: frame, bounds: bounds, canvasSize: target)
        }
        return geometry
    }

    /// Moves the centre so the rotated frame fits `bounds`; centres it in
    /// `bounds` on an axis where it cannot fit. Always clamped to 0.05...0.95.
    static func pulledInside(
        _ transform: ThumbnailOverlayTransform,
        frame: CGSize,
        bounds: CGRect,
        canvasSize: CGSize
    ) -> ThumbnailOverlayTransform {
        guard canvasSize.width > 0, canvasSize.height > 0, bounds.width > 0, bounds.height > 0 else { return transform }
        let box = rotatedBoundingSize(frame, degrees: transform.rotationDegrees)
        func axis(_ normalized: CGFloat, extent: CGFloat, length: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
            let center = normalized * length
            let resolved: CGFloat
            if extent >= upper - lower {
                resolved = (lower + upper) / 2
            } else {
                resolved = min(upper - extent / 2, max(lower + extent / 2, center))
            }
            return ThumbnailLayerGeometry.clampedPosition(resolved / length)
        }
        var result = transform
        result.x = axis(transform.x, extent: box.width, length: canvasSize.width, lower: bounds.minX, upper: bounds.maxX)
        result.y = axis(transform.y, extent: box.height, length: canvasSize.height, lower: bounds.minY, upper: bounds.maxY)
        return result
    }

    // MARK: Background image

    static func proposedRecipe(
        _ recipe: ThumbnailImageFrameRecipe,
        from masterCanvas: CGSize,
        to targetCanvas: CGSize,
        sourceImageSize: CGSize?
    ) -> ThumbnailImageFrameRecipe {
        guard let source = sourceImageSize, isUsable(source), isUsable(masterCanvas), isUsable(targetCanvas) else {
            return recipe
        }
        switch recipe.fit {
        case .stretch:
            return recipe
        case .fill:
            let focus = visibleFocus(recipe, source: source, frame: masterCanvas)
            return effectiveFill(focus: focus, zoom: recipe.zoom, source: source, frame: targetCanvas)
        case .fit:
            let solution = ThumbnailImageGeometry.solve(sourceSize: source, frameSize: targetCanvas, recipe: recipe)
            let covered = min(solution.renderSize.width, targetCanvas.width) * min(solution.renderSize.height, targetCanvas.height)
            let coverage = covered / (targetCanvas.width * targetCanvas.height)
            if coverage >= minimumFitCoverage {
                return recipe
            }
            let focus = visibleFocus(recipe, source: source, frame: masterCanvas)
            return effectiveFill(focus: focus, zoom: 1, source: source, frame: targetCanvas)
        }
    }

    /// Centre of the part of the source visible in the original.
    static func visibleFocus(
        _ recipe: ThumbnailImageFrameRecipe,
        source: CGSize,
        frame: CGSize
    ) -> CGPoint {
        let rect = ThumbnailImageGeometry.solve(sourceSize: source, frameSize: frame, recipe: recipe).sourceRect
        let horizontal = rect.width < 0.999 ? Double(rect.midX) : recipe.focusX
        let vertical = rect.height < 0.999 ? Double(rect.midY) : recipe.focusY
        return CGPoint(x: horizontal, y: vertical)
    }

    private static func effectiveFill(
        focus: CGPoint,
        zoom: Double,
        source: CGSize,
        frame: CGSize
    ) -> ThumbnailImageFrameRecipe {
        let candidate = ThumbnailImageFrameRecipe(fit: .fill, focusX: Double(focus.x), focusY: Double(focus.y), zoom: zoom)
        let solution = ThumbnailImageGeometry.solve(sourceSize: source, frameSize: frame, recipe: candidate)
        return candidate.with(
            focusX: ThumbnailImageFrameRecipe.effectiveFocus(candidate.focusX, render: solution.renderSize.width, frame: frame.width),
            focusY: ThumbnailImageFrameRecipe.effectiveFocus(candidate.focusY, render: solution.renderSize.height, frame: frame.height)
        )
    }

    // MARK: Frames (shared with clipping)

    enum LayerKind {
        case text(value: String, style: ThumbnailTextStyle?)
        case profile
        case image
        case shape
    }

    static func layerKind(_ layerID: String, in document: ThumbnailDocument) -> LayerKind? {
        switch layerID {
        case ThumbnailDocumentLayer.backgroundID:
            return nil
        case ThumbnailDocumentLayer.textID:
            return document.text.value.isEmpty ? nil : .text(value: document.text.value, style: document.text.style)
        case ThumbnailDocumentLayer.profileID:
            return document.profile == nil ? nil : .profile
        default:
            switch document.layers.record(id: layerID)?.content {
            case .text(let content): return .text(value: content.value, style: content.style)
            case .image: return .image
            case .shape: return .shape
            case nil: return nil
            }
        }
    }

    static func frameSize(
        layerID: String,
        in document: ThumbnailDocument,
        canvasSize: CGSize,
        layerImageSizes: [String: CGSize] = [:]
    ) -> CGSize? {
        guard let geometry = ThumbnailLayerGeometry.extract(layerID: layerID, from: document) else { return nil }
        return frameSize(layerID: layerID, geometry: geometry, in: document, canvasSize: canvasSize, layerImageSizes: layerImageSizes)
    }

    static func frameSize(
        layerID: String,
        geometry: ThumbnailLayerGeometry,
        in document: ThumbnailDocument,
        canvasSize: CGSize,
        layerImageSizes: [String: CGSize]
    ) -> CGSize? {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        switch layerKind(layerID, in: document) {
        case .text(let value, let style):
            let content = ThumbnailTextLayerContent(value: value, size: geometry.size ?? 0.15, style: style)
            return ContentLayerCanvasGeometry.textFrameSize(for: content, resizeTranslation: .zero, canvasSize: canvasSize)
        case .profile:
            let diameter = canvasSize.width * CGFloat(geometry.size ?? 0.2)
            return CGSize(width: diameter, height: diameter)
        case .image:
            let maxSide = min(canvasSize.width, canvasSize.height) * CGFloat(geometry.size ?? 0.32)
            guard let imageSize = layerImageSizes[layerID], isUsable(imageSize) else {
                return CGSize(width: maxSide, height: maxSide)
            }
            let aspect = imageSize.width / imageSize.height
            return aspect >= 1
                ? CGSize(width: maxSide, height: maxSide / aspect)
                : CGSize(width: maxSide * aspect, height: maxSide)
        case .shape:
            return CGSize(
                width: canvasSize.width * CGFloat(geometry.width ?? 0.34),
                height: canvasSize.height * CGFloat(geometry.height ?? 0.22)
            )
        case .none:
            return nil
        }
    }

    /// Width the text wants before any 90%-of-canvas cap is applied.
    static func naturalTextWidth(value: String, size: CGFloat, style: ThumbnailTextStyle?, canvasSize: CGSize) -> CGFloat {
        let fontSize = max(1, canvasSize.height * size)
        if let style {
            return ThumbnailTextStyleResolver.styledContentFrameSize(
                text: value,
                style: style,
                fontSize: fontSize,
                canvasSize: canvasSize
            ).width
        }
        let longestLine = value.components(separatedBy: .newlines).map(\.count).max() ?? 0
        return CGFloat(max(longestLine, 4)) * fontSize * 0.56
    }

    static func rotatedBoundingSize(_ size: CGSize, degrees: Double) -> CGSize {
        let radians = CGFloat((degrees.isFinite ? degrees : 0) * .pi / 180)
        let cosine = abs(cos(radians))
        let sine = abs(sin(radians))
        return CGSize(
            width: size.width * cosine + size.height * sine,
            height: size.width * sine + size.height * cosine
        )
    }

    static func isUsable(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    private static func clamp(_ value: CGFloat, _ limits: ClosedRange<CGFloat>) -> CGFloat {
        guard value.isFinite else { return limits.lowerBound }
        return min(limits.upperBound, max(limits.lowerBound, value))
    }
}
