//
//  ThumbnailFormatClipping.swift
//  ThumbnailMaker
//
//  FEATURE-09: informational flags for content a size change pushes off the
//  canvas, out of the platform safe zone, down to the minimum text size, or
//  crops out of the background photo. Frames come from the same estimates
//  the editor uses, so the flags are approximate and never scored.
//

import CoreGraphics
import Foundation

struct ThumbnailFormatClipFlag: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case outsideCanvas
        case outsideSafeZone
        case textAtMinimumSize
        case imageSubjectCropped
    }

    let layerID: String
    let layerName: String
    let kind: Kind

    var id: String { "\(layerID)-\(kind.rawValue)" }

    var message: String {
        switch kind {
        case .outsideCanvas:
            "\(layerName) runs past the edge of this size."
        case .outsideSafeZone:
            "\(layerName) sits outside the platform safe zone."
        case .textAtMinimumSize:
            "\(layerName) is at the smallest text size and still too wide. Consider unlinking and shortening it."
        case .imageSubjectCropped:
            "Most of the original photo framing is cropped out in this size."
        }
    }

    var systemImage: String {
        switch kind {
        case .outsideCanvas: "rectangle.dashed"
        case .outsideSafeZone: "exclamationmark.triangle"
        case .textAtMinimumSize: "textformat.size.smaller"
        case .imageSubjectCropped: "crop"
        }
    }
}

enum ThumbnailFormatClipping {
    static let edgeTolerance: CGFloat = 0.5
    static let minimumSubjectCoverage: CGFloat = 0.5

    /// - Parameters:
    ///   - resolved: the size's renderable document (see `ThumbnailFormatResolver`).
    ///   - master: the original, used to measure how much photo framing is lost.
    static func analyze(
        resolved: ThumbnailDocument,
        master: ThumbnailDocument? = nil,
        backgroundImageSize: CGSize? = nil,
        layerImageSizes: [String: CGSize] = [:],
        safeZone: ThumbnailSafeZone? = nil
    ) -> [ThumbnailFormatClipFlag] {
        let canvas = ThumbnailFormatReflow.canvasSize(of: resolved)
        guard ThumbnailFormatReflow.isUsable(canvas) else { return [] }
        let canvasRect = CGRect(origin: .zero, size: canvas).insetBy(dx: -edgeTolerance, dy: -edgeTolerance)
        let safeRect = safeZone.flatMap { zone -> CGRect? in
            guard zone.hasValidNormalizedInsets else { return nil }
            return zone.contentRect(in: canvas).insetBy(dx: -edgeTolerance, dy: -edgeTolerance)
        }

        var flags: [ThumbnailFormatClipFlag] = []
        for layer in resolved.layers where layer.kind != .background && layer.isVisible {
            guard let geometry = ThumbnailLayerGeometry.extract(layerID: layer.id, from: resolved),
                  let frame = ThumbnailFormatReflow.frameSize(
                    layerID: layer.id,
                    geometry: geometry,
                    in: resolved,
                    canvasSize: canvas,
                    layerImageSizes: layerImageSizes
                  ),
                  ThumbnailFormatReflow.isUsable(frame) else { continue }

            let box = ThumbnailFormatReflow.rotatedBoundingSize(frame, degrees: geometry.transform.rotationDegrees)
            let center = CGPoint(x: geometry.transform.x * canvas.width, y: geometry.transform.y * canvas.height)
            let rect = CGRect(x: center.x - box.width / 2, y: center.y - box.height / 2, width: box.width, height: box.height)
            let name = layer.name.isEmpty ? "Layer" : layer.name

            if !canvasRect.contains(rect) {
                flags.append(ThumbnailFormatClipFlag(layerID: layer.id, layerName: name, kind: .outsideCanvas))
            } else if let safeRect, !safeRect.contains(rect) {
                flags.append(ThumbnailFormatClipFlag(layerID: layer.id, layerName: name, kind: .outsideSafeZone))
            }

            if case .text(let value, let style) = ThumbnailFormatReflow.layerKind(layer.id, in: resolved),
               let size = geometry.size,
               CGFloat(size) <= ContentLayerCanvasGeometry.textSizeLimits.lowerBound + 0.000_1 {
                let natural = ThumbnailFormatReflow.naturalTextWidth(value: value, size: CGFloat(size), style: style, canvasSize: canvas)
                if natural > canvas.width * ThumbnailFormatReflow.textWidthBudget {
                    flags.append(ThumbnailFormatClipFlag(layerID: layer.id, layerName: name, kind: .textAtMinimumSize))
                }
            }
        }

        if let master,
           let source = backgroundImageSize,
           ThumbnailFormatReflow.isUsable(source),
           subjectCoverage(master: master, resolved: resolved, sourceSize: source) < minimumSubjectCoverage {
            flags.append(ThumbnailFormatClipFlag(
                layerID: ThumbnailDocumentLayer.backgroundID,
                layerName: "Background photo",
                kind: .imageSubjectCropped
            ))
        }
        return flags
    }

    /// Share of the original's visible photo region still visible in the size.
    static func subjectCoverage(master: ThumbnailDocument, resolved: ThumbnailDocument, sourceSize: CGSize) -> CGFloat {
        let original = ThumbnailImageGeometry.solve(
            sourceSize: sourceSize,
            frameSize: ThumbnailFormatReflow.canvasSize(of: master),
            recipe: master.imageRecipe
        ).sourceRect
        let target = ThumbnailImageGeometry.solve(
            sourceSize: sourceSize,
            frameSize: ThumbnailFormatReflow.canvasSize(of: resolved),
            recipe: resolved.imageRecipe
        ).sourceRect
        let originalArea = original.width * original.height
        guard originalArea > 0, originalArea.isFinite else { return 1 }
        let overlap = original.intersection(target)
        guard !overlap.isNull else { return 0 }
        let coverage = (overlap.width * overlap.height) / originalArea
        return coverage.isFinite ? coverage : 1
    }
}
