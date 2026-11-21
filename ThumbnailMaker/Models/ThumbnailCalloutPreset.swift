//
//  ThumbnailCalloutPreset.swift
//  ThumbnailMaker
//
//  FEATURE-12: the catalog of one-tap arrows, badges and callouts. Every
//  preset produces an ordinary `.shape` layer content, so it inherits move,
//  rotate, resize, duplicate, z-order, variants, history and export.
//

import Foundation

enum ThumbnailCalloutPreset: String, CaseIterable, Identifiable {
    case arrowRight
    case doubleArrow
    case pointerLine
    case curvedArrow
    case highlightCircle
    case newBadge
    case burstBadge
    case speechCallout
    case rectCallout

    var id: String { rawValue }

    enum Family: String, CaseIterable {
        case arrows
        case badges
        case callouts
    }

    var family: Family {
        switch self {
        case .arrowRight, .doubleArrow, .pointerLine, .curvedArrow: .arrows
        case .highlightCircle, .newBadge, .burstBadge: .badges
        case .speechCallout, .rectCallout: .callouts
        }
    }

    var title: String {
        switch self {
        case .arrowRight: "Arrow"
        case .doubleArrow: "Double Arrow"
        case .pointerLine: "Pointer Line"
        case .curvedArrow: "Curved Arrow"
        case .highlightCircle: "Highlight Circle"
        case .newBadge: "\"NEW\" Badge"
        case .burstBadge: "Burst Badge"
        case .speechCallout: "Speech Bubble"
        case .rectCallout: "Box Callout"
        }
    }

    var systemImage: String {
        switch self {
        case .arrowRight: "arrow.right"
        case .doubleArrow: "arrow.left.and.right"
        case .pointerLine: "line.diagonal.arrow"
        case .curvedArrow: "arrow.turn.up.right"
        case .highlightCircle: "circle.dashed"
        case .newBadge: "capsule"
        case .burstBadge: "seal"
        case .speechCallout: "bubble.left"
        case .rectCallout: "text.bubble"
        }
    }

    var kind: ThumbnailShapeKind {
        switch self {
        case .arrowRight, .doubleArrow: .arrow
        case .pointerLine, .curvedArrow: .line
        case .highlightCircle: .ellipse
        case .newBadge: .pill
        case .burstBadge: .burst
        case .speechCallout, .rectCallout: .callout
        }
    }

    /// Accent color applies to the stroke (not the fill) for these presets.
    var accentTargetsStroke: Bool {
        self == .highlightCircle
    }

    static let red = ThumbnailDocumentColor(red: 0.95, green: 0.16, blue: 0.16, alpha: 1)
    static let yellow = ThumbnailDocumentColor(red: 1, green: 0.82, blue: 0, alpha: 1)
    static let white = ThumbnailDocumentColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let black = ThumbnailDocumentColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1)
    static let clear = ThumbnailDocumentColor(red: 1, green: 1, blue: 1, alpha: 0)

    /// Builds the content for a new layer. A brand accent replaces the main
    /// color (the fill, or the stroke of the highlight circle).
    func content(accent: ThumbnailDocumentColor? = nil) -> ThumbnailShapeLayerContent {
        var content: ThumbnailShapeLayerContent
        switch self {
        case .arrowRight:
            content = ThumbnailShapeLayerContent(
                shapeKind: .arrow, fillColor: Self.red, strokeColor: Self.white, strokeWidth: 0.006,
                width: 0.3, height: 0.16,
                geometry: ThumbnailShapeGeometryRecipe(startHead: ThumbnailArrowheadStyle.none, endHead: .triangle)
            )
        case .doubleArrow:
            content = ThumbnailShapeLayerContent(
                shapeKind: .arrow, fillColor: Self.yellow, strokeColor: Self.black, strokeWidth: 0.006,
                width: 0.36, height: 0.14,
                geometry: ThumbnailShapeGeometryRecipe(startHead: .triangle, endHead: .triangle, headLength: 0.22)
            )
        case .pointerLine:
            content = ThumbnailShapeLayerContent(
                shapeKind: .line, fillColor: Self.red, strokeColor: nil, strokeWidth: 0.02,
                width: 0.32, height: 0.12,
                geometry: ThumbnailShapeGeometryRecipe(startHead: .dot, endHead: .triangle, curvature: 0)
            )
        case .curvedArrow:
            content = ThumbnailShapeLayerContent(
                shapeKind: .line, fillColor: Self.yellow, strokeColor: nil, strokeWidth: 0.02,
                width: 0.34, height: 0.24,
                geometry: ThumbnailShapeGeometryRecipe(startHead: ThumbnailArrowheadStyle.none, endHead: .triangle, curvature: 0.45)
            )
        case .highlightCircle:
            content = ThumbnailShapeLayerContent(
                shapeKind: .ellipse, fillColor: Self.clear, strokeColor: Self.red, strokeWidth: 0.018,
                width: 0.28, height: 0.36
            )
        case .newBadge:
            content = ThumbnailShapeLayerContent(
                shapeKind: .pill, fillColor: Self.red, strokeColor: Self.white, strokeWidth: 0.006,
                width: 0.2, height: 0.12,
                geometry: ThumbnailShapeGeometryRecipe(cornerRadius: 0.5),
                label: ThumbnailShapeLabel(text: "NEW", sizeFraction: 0.55)
            )
        case .burstBadge:
            content = ThumbnailShapeLayerContent(
                shapeKind: .burst, fillColor: Self.yellow, strokeColor: Self.black, strokeWidth: 0.006,
                width: 0.22, height: 0.36,
                geometry: ThumbnailShapeGeometryRecipe(burstPoints: 14, burstInnerRatio: 0.8),
                label: ThumbnailShapeLabel(text: "WOW", color: Self.black, sizeFraction: 0.45)
            )
        case .speechCallout:
            content = ThumbnailShapeLayerContent(
                shapeKind: .callout, fillColor: Self.white, strokeColor: Self.black, strokeWidth: 0.006,
                width: 0.34, height: 0.28,
                geometry: ThumbnailShapeGeometryRecipe(cornerRadius: 0.4, tailDirection: .bottomLeft, tailLength: 0.28),
                label: ThumbnailShapeLabel(text: "Wait...", color: Self.black, sizeFraction: 0.42)
            )
        case .rectCallout:
            content = ThumbnailShapeLayerContent(
                shapeKind: .callout, fillColor: Self.yellow, strokeColor: Self.black, strokeWidth: 0.006,
                width: 0.36, height: 0.24,
                geometry: ThumbnailShapeGeometryRecipe(cornerRadius: 0.08, tailDirection: .bottom, tailLength: 0.25),
                label: ThumbnailShapeLabel(text: "LOOK!", color: Self.black, sizeFraction: 0.45)
            )
        }

        if let accent {
            if accentTargetsStroke {
                content.strokeColor = accent
            } else {
                content.fillColor = accent
                if var label = content.label {
                    label.color = Self.contrastingLabelColor(on: accent)
                    content.label = label
                }
            }
        }
        return content
    }

    /// Swaps a layer to this preset's kind and geometry, keeping the user's
    /// colors, placement, size and label text.
    func restyle(_ content: ThumbnailShapeLayerContent) -> ThumbnailShapeLayerContent {
        let template = self.content()
        var next = content
        next.shapeKind = template.shapeKind
        next.geometry = template.geometry
        if template.shapeKind == .line {
            next.strokeColor = nil
            next.strokeWidth = template.strokeWidth
        } else if content.shapeKind == .line {
            next.strokeColor = template.strokeColor
            next.strokeWidth = template.strokeWidth
        }
        if !template.shapeKind.supportsLabel {
            next.label = nil
        } else if next.label == nil, let templateLabel = template.label {
            next.label = templateLabel
        }
        return next
    }

    static func presets(in family: Family) -> [ThumbnailCalloutPreset] {
        allCases.filter { $0.family == family }
    }

    /// Presets offered as "swap style" chips for a layer of this kind.
    static func restylePresets(for kind: ThumbnailShapeKind) -> [ThumbnailCalloutPreset] {
        switch kind {
        case .arrow, .line: presets(in: .arrows)
        case .pill, .burst: [.newBadge, .burstBadge]
        case .callout: presets(in: .callouts)
        case .rectangle, .ellipse: []
        }
    }

    /// White or near-black, whichever reads better on the fill.
    static func contrastingLabelColor(on fill: ThumbnailDocumentColor) -> ThumbnailDocumentColor {
        let luminance = 0.2126 * fill.red + 0.7152 * fill.green + 0.0722 * fill.blue
        return luminance > 0.6 ? black : white
    }
}

extension Array where Element == ThumbnailDocumentLayer {
    /// FEATURE-12: adds a fully specified shape (arrow, badge, callout) on top.
    @discardableResult
    mutating func addShapeLayer(
        content: ThumbnailShapeLayerContent,
        name: String? = nil,
        id: String = UUID().uuidString
    ) -> String {
        let prefix = content.shapeKind.layerNamePrefix
        let sameFamilyCount = filter { layer in
            guard case .shape(let existing) = layer.content else { return false }
            return existing.shapeKind.layerNamePrefix == prefix
        }.count
        let layerID = addShapeLayer(
            shapeKind: content.shapeKind,
            id: id,
            fillColor: content.fillColor,
            strokeColor: content.strokeColor,
            strokeWidth: content.strokeWidth,
            transform: content.transform,
            width: content.width,
            height: content.height
        )
        if let index = firstIndex(where: { $0.id == layerID }) {
            self[index].content = .shape(content)
            self[index].name = name ?? "\(prefix) \(sameFamilyCount + 1)"
        }
        return layerID
    }
}
