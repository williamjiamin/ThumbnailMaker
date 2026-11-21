//
//  ThumbnailArrangeGeometry.swift
//  ThumbnailMaker
//
//  FEATURE-07: bounds and position writers shared by both editors. Everything
//  is in normalized canvas units (0...1 on each axis). Frame sizes reuse
//  ContentLayerCanvasGeometry, measured on a reference canvas of
//  1000 x (1000 / ratio) points, so results do not depend on screen size.
//

import CoreGraphics
import Foundation
import UIKit

/// What the arrange engine needs from an editor configuration.
protocol ThumbnailArrangeableConfiguration {
    var layers: [ThumbnailDocumentLayer] { get set }
    var overlayText: String { get }
    var textSize: CGFloat { get }
    var textStyle: ThumbnailTextStyle? { get }
    var textTransform: ThumbnailOverlayTransform { get set }
    var selectedRatio: AspectRatio { get }
    /// nil when the editor has no profile circle (Simple) or no profile image.
    var arrangeProfileTransform: ThumbnailOverlayTransform? { get set }
    var arrangeProfileSize: CGFloat? { get }
}

extension PremiumMakerConfigurationModel: ThumbnailArrangeableConfiguration {
    var arrangeProfileTransform: ThumbnailOverlayTransform? {
        get { circularProfile?.image == nil ? nil : profileTransform }
        set {
            if let newValue, circularProfile?.image != nil {
                profileTransform = newValue
            }
        }
    }

    var arrangeProfileSize: CGFloat? {
        circularProfile?.image == nil ? nil : circularProfile?.size
    }
}

extension SimpleMakerConfigurationModel: ThumbnailArrangeableConfiguration {
    var arrangeProfileTransform: ThumbnailOverlayTransform? {
        get { nil }
        set { }
    }

    var arrangeProfileSize: CGFloat? { nil }
}

/// One selectable layer's placement. `bounds` is the axis-aligned box of the
/// rotated frame.
struct ThumbnailArrangeItem: Equatable {
    var selection: ThumbnailLayerSelection
    var center: CGPoint
    var size: CGSize
    var rotationDegrees: Double
    var bounds: CGRect
}

enum ThumbnailArrangeGeometry {
    static let referenceWidth: CGFloat = 1000

    static func referenceCanvas(for ratio: AspectRatio) -> CGSize {
        CGSize(width: referenceWidth, height: referenceWidth / max(ratio.value, 0.01))
    }

    /// Axis-aligned bounds (normalized) of a frame of `size` points rotated by
    /// `degrees` about `center` (normalized), on `canvas`.
    static func rotatedBounds(
        center: CGPoint,
        size: CGSize,
        degrees: Double,
        canvas: CGSize
    ) -> CGRect {
        let radians = degrees * .pi / 180
        let cosine = abs(CGFloat(cos(radians)))
        let sine = abs(CGFloat(sin(radians)))
        let width = size.width * cosine + size.height * sine
        let height = size.width * sine + size.height * cosine
        let normalizedWidth = width / max(canvas.width, 1)
        let normalizedHeight = height / max(canvas.height, 1)
        return CGRect(
            x: center.x - normalizedWidth / 2,
            y: center.y - normalizedHeight / 2,
            width: normalizedWidth,
            height: normalizedHeight
        )
    }

    /// Same aspect logic as ContentLayerCanvasGeometry.imageFrameSize(for:maxSide:),
    /// from a pixel size instead of a decoded image.
    static func imageFrameSize(pixelSize: CGSize, maxSide: CGFloat) -> CGSize {
        guard pixelSize.width > 0, pixelSize.height > 0 else {
            return CGSize(width: maxSide, height: maxSide)
        }
        let aspectRatio = pixelSize.width / pixelSize.height
        if aspectRatio >= 1 {
            return CGSize(width: maxSide, height: maxSide / aspectRatio)
        }
        return CGSize(width: maxSide * aspectRatio, height: maxSide)
    }

    /// Image sizes are decoded once per layer id and data length.
    private static let imageSizeCache = NSCache<NSString, NSValue>()

    static func imagePixelSize(layerID: String, data: Data) -> CGSize {
        let key = "\(layerID)#\(data.count)" as NSString
        if let cached = imageSizeCache.object(forKey: key) {
            return cached.cgSizeValue
        }
        let size = UIImage(data: data)?.size ?? .zero
        imageSizeCache.setObject(NSValue(cgSize: size), forKey: key)
        return size
    }
}

extension ThumbnailArrangeableConfiguration {
    var arrangeReferenceCanvas: CGSize {
        ThumbnailArrangeGeometry.referenceCanvas(for: selectedRatio)
    }

    func arrangeTransform(for selection: ThumbnailLayerSelection) -> ThumbnailOverlayTransform? {
        switch selection {
        case .textOverlay:
            return overlayText.isEmpty ? nil : textTransform
        case .profileOverlay:
            return arrangeProfileTransform
        case .content(let id):
            switch layers.record(id: id)?.content {
            case .image(let content): return content.transform
            case .text(let content): return content.transform
            case .shape(let content): return content.transform
            case nil: return nil
            }
        }
    }

    func arrangeCenter(for selection: ThumbnailLayerSelection) -> CGPoint? {
        arrangeTransform(for: selection).map { CGPoint(x: $0.x, y: $0.y) }
    }

    /// Frame size in reference-canvas points (unrotated).
    func arrangeFrameSize(for selection: ThumbnailLayerSelection) -> CGSize? {
        let canvas = arrangeReferenceCanvas
        switch selection {
        case .textOverlay:
            guard !overlayText.isEmpty else { return nil }
            let content = ThumbnailTextLayerContent(
                value: overlayText,
                size: Double(textSize),
                transform: textTransform,
                style: textStyle
            )
            return ContentLayerCanvasGeometry.textFrameSize(for: content, resizeTranslation: .zero, canvasSize: canvas)
        case .profileOverlay:
            guard let size = arrangeProfileSize else { return nil }
            // Matches the preview: diameter = canvas width * size.
            let diameter = canvas.width * size
            return CGSize(width: diameter, height: diameter)
        case .content(let id):
            switch layers.record(id: id)?.content {
            case .image(let content):
                let maxSide = min(canvas.width, canvas.height) * CGFloat(content.size)
                return ThumbnailArrangeGeometry.imageFrameSize(
                    pixelSize: ThumbnailArrangeGeometry.imagePixelSize(layerID: id, data: content.imageData),
                    maxSide: maxSide
                )
            case .text(let content):
                return ContentLayerCanvasGeometry.textFrameSize(for: content, resizeTranslation: .zero, canvasSize: canvas)
            case .shape(let content):
                return ContentLayerCanvasGeometry.shapeFrameSize(for: content, resizeTranslation: .zero, canvasSize: canvas)
            case nil:
                return nil
            }
        }
    }

    func arrangeItem(for selection: ThumbnailLayerSelection) -> ThumbnailArrangeItem? {
        guard let transform = arrangeTransform(for: selection),
              let frame = arrangeFrameSize(for: selection) else { return nil }
        let canvas = arrangeReferenceCanvas
        let center = CGPoint(x: transform.x, y: transform.y)
        return ThumbnailArrangeItem(
            selection: selection,
            center: center,
            size: CGSize(width: frame.width / canvas.width, height: frame.height / canvas.height),
            rotationDegrees: transform.rotationDegrees,
            bounds: ThumbnailArrangeGeometry.rotatedBounds(
                center: center,
                size: frame,
                degrees: transform.rotationDegrees,
                canvas: canvas
            )
        )
    }

    /// Writes a centre (clamped to the shared centre range). Returns false when
    /// the layer has no position.
    @discardableResult
    mutating func setArrangeCenter(_ center: CGPoint, for selection: ThumbnailLayerSelection) -> Bool {
        let range = ThumbnailOverlayTransform.centerRange
        let x = min(range.upperBound, max(range.lowerBound, center.x))
        let y = min(range.upperBound, max(range.lowerBound, center.y))
        switch selection {
        case .textOverlay:
            guard !overlayText.isEmpty else { return false }
            textTransform.x = x
            textTransform.y = y
            return true
        case .profileOverlay:
            guard var transform = arrangeProfileTransform else { return false }
            transform.x = x
            transform.y = y
            arrangeProfileTransform = transform
            return true
        case .content(let id):
            guard let index = layers.firstIndex(where: { $0.id == id }) else { return false }
            switch layers[index].content {
            case .image(var content):
                content.transform.x = x
                content.transform.y = y
                layers[index].content = .image(content)
            case .text(var content):
                content.transform.x = x
                content.transform.y = y
                layers[index].content = .text(content)
            case .shape(var content):
                content.transform.x = x
                content.transform.y = y
                layers[index].content = .shape(content)
            case nil:
                return false
            }
            return true
        }
    }

    /// Moves every member by the same delta, shrunk (per axis) so no member's
    /// centre leaves the allowed range: relative layout never deforms.
    /// Returns the delta actually applied.
    @discardableResult
    mutating func translateRigidly(_ selections: [ThumbnailLayerSelection], by delta: CGVector) -> CGVector {
        let centers = selections.compactMap { selection in
            arrangeCenter(for: selection).map { (selection, $0) }
        }
        guard !centers.isEmpty else { return .zero }
        let range = ThumbnailOverlayTransform.centerRange
        var minDX = -CGFloat.infinity, maxDX = CGFloat.infinity
        var minDY = -CGFloat.infinity, maxDY = CGFloat.infinity
        for (_, center) in centers {
            minDX = max(minDX, range.lowerBound - center.x)
            maxDX = min(maxDX, range.upperBound - center.x)
            minDY = max(minDY, range.lowerBound - center.y)
            maxDY = min(maxDY, range.upperBound - center.y)
        }
        let applied = CGVector(
            dx: minDX <= maxDX ? min(maxDX, max(minDX, delta.dx)) : 0,
            dy: minDY <= maxDY ? min(maxDY, max(minDY, delta.dy)) : 0
        )
        guard abs(applied.dx) > 1e-9 || abs(applied.dy) > 1e-9 else { return .zero }
        for (selection, center) in centers {
            setArrangeCenter(CGPoint(x: center.x + applied.dx, y: center.y + applied.dy), for: selection)
        }
        return applied
    }

    /// Movable selections for a layer id (unlocked; hidden members still move
    /// with their group so relative layout is kept).
    func arrangeSelection(forLayerID id: String) -> ThumbnailLayerSelection? {
        switch id {
        case ThumbnailDocumentLayer.backgroundID: return nil
        case ThumbnailDocumentLayer.textID: return overlayText.isEmpty ? nil : .textOverlay
        case ThumbnailDocumentLayer.profileID: return arrangeProfileSize == nil ? nil : .profileOverlay
        default: return layers.record(id: id)?.content == nil ? nil : .content(id)
        }
    }

    /// Canvas drag hook: after `leader` was dragged from `start`, returns the
    /// configuration with the rest of the leader's group moved by the same
    /// delta (rigidly), or nil when there is nothing to do. Locked members stay.
    func followingGroupMove(of leader: ThumbnailLayerSelection, from start: CGPoint?) -> Self? {
        guard let start,
              let groupID = layers.groupID(for: leader),
              let end = arrangeCenter(for: leader) else { return nil }
        let delta = CGVector(dx: end.x - start.x, dy: end.y - start.y)
        guard abs(delta.dx) > 1e-9 || abs(delta.dy) > 1e-9 else { return nil }

        let members = layers.memberIDs(ofGroup: groupID)
            .compactMap(arrangeSelection(forLayerID:))
            .filter { !layers.isLocked($0) }
        guard members.count >= 2 else { return nil }

        var next = self
        next.setArrangeCenter(start, for: leader)
        next.translateRigidly(members, by: delta)
        return next
    }
}
