//
//  ThumbnailShapeRecipe.swift
//  ThumbnailMaker
//
//  FEATURE-12: reversible geometry recipes for arrows, badges and callouts.
//
//  Every stored field is optional so documents only carry what the user
//  actually changed; `resolved(for:)` merges the recipe over per-kind
//  defaults and clamps each value, so corrupt or out-of-range JSON can never
//  produce a degenerate path.
//

import CoreGraphics
import Foundation

enum ThumbnailArrowheadStyle: String, Codable, CaseIterable, Identifiable {
    case none
    case triangle
    case open
    case dot

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "None"
        case .triangle: "Triangle"
        case .open: "Open"
        case .dot: "Dot"
        }
    }

    var systemImage: String {
        switch self {
        case .none: "minus"
        case .triangle: "arrowtriangle.right.fill"
        case .open: "chevron.right"
        case .dot: "circle.fill"
        }
    }
}

enum ThumbnailCalloutTailDirection: String, Codable, CaseIterable, Identifiable {
    case none
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
    case topLeft

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "No Tail"
        case .top: "Top"
        case .topRight: "Top Right"
        case .right: "Right"
        case .bottomRight: "Bottom Right"
        case .bottom: "Bottom"
        case .bottomLeft: "Bottom Left"
        case .left: "Left"
        case .topLeft: "Top Left"
        }
    }

    /// Unit direction in screen space (-1, 0 or 1 per axis; y grows down).
    var vector: (dx: Int, dy: Int) {
        switch self {
        case .none: (0, 0)
        case .top: (0, -1)
        case .topRight: (1, -1)
        case .right: (1, 0)
        case .bottomRight: (1, 1)
        case .bottom: (0, 1)
        case .bottomLeft: (-1, 1)
        case .left: (-1, 0)
        case .topLeft: (-1, -1)
        }
    }
}

struct ThumbnailShapeGeometryRecipe: Codable, Equatable {
    var startHeadRawValue: String?
    var endHeadRawValue: String?
    var shaftThickness: Double?
    var headLength: Double?
    var headWidth: Double?
    var curvature: Double?
    var cornerRadius: Double?
    var burstPoints: Int?
    var burstInnerRatio: Double?
    var tailDirectionRawValue: String?
    var tailLength: Double?
    var tailWidth: Double?

    init(
        startHead: ThumbnailArrowheadStyle? = nil,
        endHead: ThumbnailArrowheadStyle? = nil,
        shaftThickness: Double? = nil,
        headLength: Double? = nil,
        headWidth: Double? = nil,
        curvature: Double? = nil,
        cornerRadius: Double? = nil,
        burstPoints: Int? = nil,
        burstInnerRatio: Double? = nil,
        tailDirection: ThumbnailCalloutTailDirection? = nil,
        tailLength: Double? = nil,
        tailWidth: Double? = nil
    ) {
        startHeadRawValue = startHead?.rawValue
        endHeadRawValue = endHead?.rawValue
        self.shaftThickness = shaftThickness
        self.headLength = headLength
        self.headWidth = headWidth
        self.curvature = curvature
        self.cornerRadius = cornerRadius
        self.burstPoints = burstPoints
        self.burstInnerRatio = burstInnerRatio
        tailDirectionRawValue = tailDirection?.rawValue
        self.tailLength = tailLength
        self.tailWidth = tailWidth
    }

    var startHead: ThumbnailArrowheadStyle? {
        get { startHeadRawValue.flatMap(ThumbnailArrowheadStyle.init(rawValue:)) }
        set { startHeadRawValue = newValue?.rawValue }
    }

    var endHead: ThumbnailArrowheadStyle? {
        get { endHeadRawValue.flatMap(ThumbnailArrowheadStyle.init(rawValue:)) }
        set { endHeadRawValue = newValue?.rawValue }
    }

    var tailDirection: ThumbnailCalloutTailDirection? {
        get { tailDirectionRawValue.flatMap(ThumbnailCalloutTailDirection.init(rawValue:)) }
        set { tailDirectionRawValue = newValue?.rawValue }
    }

    static let shaftThicknessRange = 0.1...0.8
    static let headLengthRange = 0.1...0.6
    static let headWidthRange = 0.3...1.0
    static let curvatureRange = -1.0...1.0
    static let cornerRadiusRange = 0.0...0.5
    static let burstPointsRange = 5...24
    static let burstInnerRatioRange = 0.5...0.95
    static let tailLengthRange = 0.0...0.45
    static let tailWidthRange = 0.05...0.4

    /// The recipe merged over the kind's defaults, with every value clamped.
    func resolved(for kind: ThumbnailShapeKind) -> ThumbnailResolvedShapeGeometry {
        let defaults = ThumbnailResolvedShapeGeometry.defaults(for: kind)
        return ThumbnailResolvedShapeGeometry(
            startHead: startHead ?? defaults.startHead,
            endHead: endHead ?? defaults.endHead,
            shaftThickness: Self.clamp(shaftThickness, Self.shaftThicknessRange, defaults.shaftThickness),
            headLength: Self.clamp(headLength, Self.headLengthRange, defaults.headLength),
            headWidth: Self.clamp(headWidth, Self.headWidthRange, defaults.headWidth),
            curvature: Self.clamp(curvature, Self.curvatureRange, defaults.curvature),
            cornerRadius: Self.clamp(cornerRadius, Self.cornerRadiusRange, defaults.cornerRadius),
            burstPoints: Swift.min(
                Self.burstPointsRange.upperBound,
                Swift.max(Self.burstPointsRange.lowerBound, burstPoints ?? defaults.burstPoints)
            ),
            burstInnerRatio: Self.clamp(burstInnerRatio, Self.burstInnerRatioRange, defaults.burstInnerRatio),
            tailDirection: tailDirection ?? defaults.tailDirection,
            tailLength: Self.clamp(tailLength, Self.tailLengthRange, defaults.tailLength),
            tailWidth: Self.clamp(tailWidth, Self.tailWidthRange, defaults.tailWidth)
        )
    }

    static func clamp(_ value: Double?, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
        guard let value, value.isFinite else { return fallback }
        return Swift.min(range.upperBound, Swift.max(range.lowerBound, value))
    }
}

/// Fully-specified geometry used by the path builder and the inspector.
struct ThumbnailResolvedShapeGeometry: Equatable {
    var startHead: ThumbnailArrowheadStyle
    var endHead: ThumbnailArrowheadStyle
    var shaftThickness: Double
    var headLength: Double
    var headWidth: Double
    var curvature: Double
    var cornerRadius: Double
    var burstPoints: Int
    var burstInnerRatio: Double
    var tailDirection: ThumbnailCalloutTailDirection
    var tailLength: Double
    var tailWidth: Double

    static func defaults(for kind: ThumbnailShapeKind) -> ThumbnailResolvedShapeGeometry {
        var geometry = ThumbnailResolvedShapeGeometry(
            startHead: .none,
            endHead: .triangle,
            shaftThickness: 0.4,
            headLength: 0.35,
            headWidth: 1.0,
            curvature: 0,
            cornerRadius: 0.08,
            burstPoints: 12,
            burstInnerRatio: 0.78,
            tailDirection: .bottomLeft,
            tailLength: 0.25,
            tailWidth: 0.18
        )
        switch kind {
        case .pill:
            geometry.cornerRadius = 0.5
        case .callout:
            geometry.cornerRadius = 0.18
        case .line:
            geometry.headLength = 0.3
            geometry.headWidth = 0.7
        case .rectangle, .ellipse, .arrow, .burst:
            break
        }
        return geometry
    }
}

struct ThumbnailShapeLabel: Codable, Equatable {
    static let characterLimit = 24
    static let sizeFractionRange = 0.2...0.8

    var text: String
    var color: ThumbnailDocumentColor
    var fontRawValue: String
    var sizeFraction: Double
    var isBold: Bool

    init(
        text: String,
        color: ThumbnailDocumentColor = ThumbnailDocumentColor(red: 1, green: 1, blue: 1, alpha: 1),
        fontRawValue: String = CustomFont.goNoto.rawValue,
        sizeFraction: Double = 0.5,
        isBold: Bool = true
    ) {
        self.text = text
        self.color = color
        self.fontRawValue = fontRawValue
        self.sizeFraction = sizeFraction
        self.isBold = isBold
    }

    private enum CodingKeys: String, CodingKey {
        case text, color, fontRawValue, sizeFraction, isBold
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        color = try container.decodeIfPresent(ThumbnailDocumentColor.self, forKey: .color)
            ?? ThumbnailDocumentColor(red: 1, green: 1, blue: 1, alpha: 1)
        fontRawValue = try container.decodeIfPresent(String.self, forKey: .fontRawValue) ?? CustomFont.goNoto.rawValue
        sizeFraction = try container.decodeIfPresent(Double.self, forKey: .sizeFraction) ?? 0.5
        isBold = try container.decodeIfPresent(Bool.self, forKey: .isBold) ?? true
    }

    var font: CustomFont {
        get { CustomFont(rawValue: fontRawValue) ?? .goNoto }
        set { fontRawValue = newValue.rawValue }
    }

    var effectiveSizeFraction: Double {
        ThumbnailShapeGeometryRecipe.clamp(sizeFraction, Self.sizeFractionRange, 0.5)
    }

    /// Text trimmed to the label limit; empty labels are not drawn.
    var displayText: String {
        String(text.prefix(Self.characterLimit))
    }
}

extension ThumbnailShapeKind {
    var systemImage: String {
        switch self {
        case .rectangle: "rectangle"
        case .ellipse: "oval"
        case .arrow: "arrow.right"
        case .line: "line.diagonal.arrow"
        case .pill: "capsule"
        case .burst: "seal"
        case .callout: "bubble.left"
        }
    }

    var layerSubtitle: String {
        switch self {
        case .rectangle, .ellipse: "Shape Layer"
        case .arrow, .line: "Arrow Layer"
        case .pill, .burst: "Badge Layer"
        case .callout: "Callout Layer"
        }
    }

    /// Default layer-name prefix for newly added layers ("Arrow 1").
    var layerNamePrefix: String {
        switch self {
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .arrow, .line: "Arrow"
        case .pill, .burst: "Badge"
        case .callout: "Callout"
        }
    }

    /// `.line` is stroked only; every other kind is a filled outline.
    var usesFill: Bool { self != .line }

    var supportsLabel: Bool {
        switch self {
        case .line: false
        default: true
        }
    }

    var isArrowFamily: Bool { self == .arrow || self == .line }
}

extension ThumbnailShapeLayerContent {
    var resolvedGeometry: ThumbnailResolvedShapeGeometry {
        (geometry ?? ThumbnailShapeGeometryRecipe()).resolved(for: shapeKind)
    }

    /// Writes through a geometry edit, creating the recipe on first use.
    mutating func editGeometry(_ mutate: (inout ThumbnailShapeGeometryRecipe) -> Void) {
        var recipe = geometry ?? ThumbnailShapeGeometryRecipe()
        mutate(&recipe)
        geometry = recipe
    }

    /// The color used to draw a line arrow: its stroke color, else its fill.
    var lineColor: ThumbnailDocumentColor {
        strokeColor ?? fillColor
    }
}
