//
//  ThumbnailTextStyle.swift
//  ThumbnailMaker
//
//  FEATURE-04: serializable text styling (outline, shadow, background panel,
//  spacing, alignment, max width) shared by the legacy overlay text and by
//  added text layers.
//
//  UNIT RULE: every metric except `maxWidthFraction` is a fraction of the
//  resolved FONT SIZE. `maxWidthFraction` is a fraction of CANVAS WIDTH.
//  Because the font size is itself `canvasHeight * textSize`, every resolved
//  point value scales linearly with the canvas. That is the canvas/export
//  parity guarantee (see ThumbnailTextStyleResolver).
//

import Foundation
import SwiftUI

enum ThumbnailTextAlignment: String, Codable, CaseIterable, Equatable {
    case leading
    case center
    case trailing

    var displayName: String {
        switch self {
        case .leading: "Left"
        case .center: "Center"
        case .trailing: "Right"
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

/// Which render site a style is applied to. The legacy (nil-style) look differs per role.
enum ThumbnailTextRole: Equatable {
    case overlay
    case contentLayer
}

struct ThumbnailTextStyle: Codable, Equatable {
    // Outline (fraction of font size), 0 == none.
    var outlineWidth: Double
    var outlineColor: ThumbnailDocumentColor
    // Shadow (fractions of font size; alpha lives in the colour).
    var isShadowEnabled: Bool
    var shadowRadius: Double
    var shadowOffsetX: Double
    var shadowOffsetY: Double
    var shadowColor: ThumbnailDocumentColor
    // Background panel (fractions of font size). nil colour == no panel.
    var panelColor: ThumbnailDocumentColor?
    var panelCornerRadius: Double
    var horizontalPadding: Double
    var verticalPadding: Double
    // Spacing (fractions of font size).
    var lineSpacing: Double
    var letterSpacing: Double
    // Layout.
    var alignmentRawValue: String
    /// Fraction of CANVAS WIDTH (the one exception to the unit rule).
    var maxWidthFraction: Double
    /// nil == unlimited.
    var lineLimit: Int?
    var minimumScaleFactor: Double
    /// Provenance only; never affects rendering.
    var presetID: String?

    // MARK: Ranges

    enum Limits {
        static let outlineWidth: ClosedRange<Double> = 0...0.25
        static let shadowRadius: ClosedRange<Double> = 0...0.5
        static let shadowOffset: ClosedRange<Double> = -0.5...0.5
        static let panelCornerRadius: ClosedRange<Double> = 0...2
        static let padding: ClosedRange<Double> = 0...2
        static let lineSpacing: ClosedRange<Double> = -0.2...1.5
        static let letterSpacing: ClosedRange<Double> = -0.2...1.0
        static let maxWidthFraction: ClosedRange<Double> = 0.2...1.0
        static let lineLimit: ClosedRange<Int> = 1...10
        static let minimumScaleFactor: ClosedRange<Double> = 0.2...1.0
    }

    static let black = ThumbnailDocumentColor(red: 0, green: 0, blue: 0, alpha: 1)

    init(
        outlineWidth: Double = 0,
        outlineColor: ThumbnailDocumentColor = ThumbnailTextStyle.black,
        isShadowEnabled: Bool = false,
        shadowRadius: Double = 0,
        shadowOffsetX: Double = 0,
        shadowOffsetY: Double = 0,
        shadowColor: ThumbnailDocumentColor = ThumbnailTextStyle.black,
        panelColor: ThumbnailDocumentColor? = nil,
        panelCornerRadius: Double = 0,
        horizontalPadding: Double = 0,
        verticalPadding: Double = 0,
        lineSpacing: Double = 0,
        letterSpacing: Double = 0,
        alignment: ThumbnailTextAlignment = .center,
        maxWidthFraction: Double = 0.9,
        lineLimit: Int? = nil,
        minimumScaleFactor: Double = 1,
        presetID: String? = nil
    ) {
        self.outlineWidth = outlineWidth
        self.outlineColor = outlineColor
        self.isShadowEnabled = isShadowEnabled
        self.shadowRadius = shadowRadius
        self.shadowOffsetX = shadowOffsetX
        self.shadowOffsetY = shadowOffsetY
        self.shadowColor = shadowColor
        self.panelColor = panelColor
        self.panelCornerRadius = panelCornerRadius
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.lineSpacing = lineSpacing
        self.letterSpacing = letterSpacing
        self.alignmentRawValue = alignment.rawValue
        self.maxWidthFraction = maxWidthFraction
        self.lineLimit = lineLimit
        self.minimumScaleFactor = minimumScaleFactor
        self.presetID = presetID
        self = normalized()
    }

    var alignment: ThumbnailTextAlignment {
        get { ThumbnailTextAlignment(rawValue: alignmentRawValue) ?? .center }
        set { alignmentRawValue = newValue.rawValue }
    }

    var hasPanel: Bool { panelColor != nil }

    // MARK: Normalization

    /// Maps NaN/inf to `fallback` and clamps everything else into `range`.
    static func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return Swift.min(range.upperBound, Swift.max(range.lowerBound, value))
    }

    static func clampColor(_ color: ThumbnailDocumentColor) -> ThumbnailDocumentColor {
        func unit(_ value: Double, _ fallback: Double) -> Double {
            clamp(value, 0...1, fallback: fallback)
        }
        return ThumbnailDocumentColor(
            red: unit(color.red, 0),
            green: unit(color.green, 0),
            blue: unit(color.blue, 0),
            alpha: unit(color.alpha, 1)
        )
    }

    /// Returns a copy with every field inside its documented range. A corrupt or
    /// hostile style never throws and never produces an unbounded render.
    func normalized() -> ThumbnailTextStyle {
        var copy = self
        copy.outlineWidth = Self.clamp(outlineWidth, Limits.outlineWidth, fallback: 0)
        copy.outlineColor = Self.clampColor(outlineColor)
        copy.shadowRadius = Self.clamp(shadowRadius, Limits.shadowRadius, fallback: 0)
        copy.shadowOffsetX = Self.clamp(shadowOffsetX, Limits.shadowOffset, fallback: 0)
        copy.shadowOffsetY = Self.clamp(shadowOffsetY, Limits.shadowOffset, fallback: 0)
        copy.shadowColor = Self.clampColor(shadowColor)
        copy.panelColor = panelColor.map(Self.clampColor)
        copy.panelCornerRadius = Self.clamp(panelCornerRadius, Limits.panelCornerRadius, fallback: 0)
        copy.horizontalPadding = Self.clamp(horizontalPadding, Limits.padding, fallback: 0)
        copy.verticalPadding = Self.clamp(verticalPadding, Limits.padding, fallback: 0)
        copy.lineSpacing = Self.clamp(lineSpacing, Limits.lineSpacing, fallback: 0)
        copy.letterSpacing = Self.clamp(letterSpacing, Limits.letterSpacing, fallback: 0)
        if ThumbnailTextAlignment(rawValue: alignmentRawValue) == nil {
            copy.alignmentRawValue = ThumbnailTextAlignment.center.rawValue
        }
        copy.maxWidthFraction = Self.clamp(maxWidthFraction, Limits.maxWidthFraction, fallback: 0.9)
        copy.lineLimit = lineLimit.map {
            Swift.min(Limits.lineLimit.upperBound, Swift.max(Limits.lineLimit.lowerBound, $0))
        }
        copy.minimumScaleFactor = Self.clamp(minimumScaleFactor, Limits.minimumScaleFactor, fallback: 1)
        return copy
    }

    // MARK: Codable (every field optional so partial / old / hostile JSON decodes)

    private enum CodingKeys: String, CodingKey {
        case outlineWidth, outlineColor
        case isShadowEnabled, shadowRadius, shadowOffsetX, shadowOffsetY, shadowColor
        case panelColor, panelCornerRadius, horizontalPadding, verticalPadding
        case lineSpacing, letterSpacing
        case alignmentRawValue, maxWidthFraction, lineLimit, minimumScaleFactor
        case presetID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ThumbnailTextStyle()
        func double(_ key: CodingKeys, _ fallback: Double) -> Double {
            // A non-number (e.g. "NaN" string) degrades to the default rather than throwing.
            (try? c.decodeIfPresent(Double.self, forKey: key)) ?? fallback
        }
        func color(_ key: CodingKeys, _ fallback: ThumbnailDocumentColor) -> ThumbnailDocumentColor {
            (try? c.decodeIfPresent(ThumbnailDocumentColor.self, forKey: key)) ?? fallback
        }
        outlineWidth = double(.outlineWidth, defaults.outlineWidth)
        outlineColor = color(.outlineColor, defaults.outlineColor)
        isShadowEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isShadowEnabled)) ?? defaults.isShadowEnabled
        shadowRadius = double(.shadowRadius, defaults.shadowRadius)
        shadowOffsetX = double(.shadowOffsetX, defaults.shadowOffsetX)
        shadowOffsetY = double(.shadowOffsetY, defaults.shadowOffsetY)
        shadowColor = color(.shadowColor, defaults.shadowColor)
        panelColor = (try? c.decodeIfPresent(ThumbnailDocumentColor.self, forKey: .panelColor)) ?? nil
        panelCornerRadius = double(.panelCornerRadius, defaults.panelCornerRadius)
        horizontalPadding = double(.horizontalPadding, defaults.horizontalPadding)
        verticalPadding = double(.verticalPadding, defaults.verticalPadding)
        lineSpacing = double(.lineSpacing, defaults.lineSpacing)
        letterSpacing = double(.letterSpacing, defaults.letterSpacing)
        alignmentRawValue = (try? c.decodeIfPresent(String.self, forKey: .alignmentRawValue)) ?? defaults.alignmentRawValue
        maxWidthFraction = double(.maxWidthFraction, defaults.maxWidthFraction)
        lineLimit = (try? c.decodeIfPresent(Int.self, forKey: .lineLimit)) ?? nil
        minimumScaleFactor = double(.minimumScaleFactor, defaults.minimumScaleFactor)
        presetID = (try? c.decodeIfPresent(String.self, forKey: .presetID)) ?? nil
        self = normalized()
    }

    func encode(to encoder: Encoder) throws {
        let value = normalized()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(value.outlineWidth, forKey: .outlineWidth)
        try c.encode(value.outlineColor, forKey: .outlineColor)
        try c.encode(value.isShadowEnabled, forKey: .isShadowEnabled)
        try c.encode(value.shadowRadius, forKey: .shadowRadius)
        try c.encode(value.shadowOffsetX, forKey: .shadowOffsetX)
        try c.encode(value.shadowOffsetY, forKey: .shadowOffsetY)
        try c.encode(value.shadowColor, forKey: .shadowColor)
        try c.encodeIfPresent(value.panelColor, forKey: .panelColor)
        try c.encode(value.panelCornerRadius, forKey: .panelCornerRadius)
        try c.encode(value.horizontalPadding, forKey: .horizontalPadding)
        try c.encode(value.verticalPadding, forKey: .verticalPadding)
        try c.encode(value.lineSpacing, forKey: .lineSpacing)
        try c.encode(value.letterSpacing, forKey: .letterSpacing)
        try c.encode(value.alignmentRawValue, forKey: .alignmentRawValue)
        try c.encode(value.maxWidthFraction, forKey: .maxWidthFraction)
        try c.encodeIfPresent(value.lineLimit, forKey: .lineLimit)
        try c.encode(value.minimumScaleFactor, forKey: .minimumScaleFactor)
        try c.encodeIfPresent(value.presetID, forKey: .presetID)
    }

    // MARK: Legacy approximation

    /// The style a nil (legacy) style is materialised into the first time the user
    /// touches a control. Chosen so the primary EXPORT is unchanged:
    ///
    /// At a 1280x720 export with textSize 0.15 the font size is 720 * 0.15 = 108pt.
    /// - legacy shadow radius 3pt  -> 3 / 108   ≈ 0.0278
    /// - legacy shadow offset 1pt  -> 1 / 108   ≈ 0.0093
    /// - overlay h-padding canvasW * 0.03 = 38.4pt -> 38.4 / 108 ≈ 0.356
    /// - overlay v-padding canvasH * 0.03 = 21.6pt -> 21.6 / 108 = 0.20
    /// Overlay: shadow alpha 1.0, maxWidth 0.9, no line limit, min scale 1.
    /// Content layer: shadow alpha 0.82, padding 0, line limit 3, min scale 0.6.
    static func legacyApproximation(for role: ThumbnailTextRole) -> ThumbnailTextStyle {
        switch role {
        case .overlay:
            return ThumbnailTextStyle(
                isShadowEnabled: true,
                shadowRadius: 3.0 / 108.0,
                shadowOffsetX: 1.0 / 108.0,
                shadowOffsetY: 1.0 / 108.0,
                shadowColor: black,
                horizontalPadding: 38.4 / 108.0,
                verticalPadding: 21.6 / 108.0,
                maxWidthFraction: 0.9,
                lineLimit: nil,
                minimumScaleFactor: 1
            )
        case .contentLayer:
            return ThumbnailTextStyle(
                isShadowEnabled: true,
                shadowRadius: 3.0 / 108.0,
                shadowOffsetX: 1.0 / 108.0,
                shadowOffsetY: 1.0 / 108.0,
                shadowColor: ThumbnailDocumentColor(red: 0, green: 0, blue: 0, alpha: 0.82),
                maxWidthFraction: 0.9,
                lineLimit: 3,
                minimumScaleFactor: 0.6
            )
        }
    }
}

// MARK: - Presets

struct ThumbnailTextStylePreset: Identifiable, Equatable {
    let id: String
    let displayName: String
    /// nil == the legacy look (the reset target).
    let style: ThumbnailTextStyle?

    static let defaultID = "default"

    /// Presets are role-specific only in their base layout (line limit / min scale),
    /// so a preset never makes a content layer overflow its box.
    static func all(for role: ThumbnailTextRole) -> [ThumbnailTextStylePreset] {
        let base: ThumbnailTextStyle = {
            switch role {
            case .overlay:
                return ThumbnailTextStyle(maxWidthFraction: 0.9, lineLimit: nil, minimumScaleFactor: 1)
            case .contentLayer:
                return ThumbnailTextStyle(maxWidthFraction: 0.9, lineLimit: 3, minimumScaleFactor: 0.6)
            }
        }()
        func make(_ id: String, _ mutate: (inout ThumbnailTextStyle) -> Void) -> ThumbnailTextStyle {
            var style = base
            mutate(&style)
            style.presetID = id
            return style.normalized()
        }
        let black = ThumbnailTextStyle.black
        return [
            ThumbnailTextStylePreset(id: defaultID, displayName: "Default", style: nil),
            ThumbnailTextStylePreset(id: "plain", displayName: "Plain", style: make("plain") { _ in }),
            ThumbnailTextStylePreset(id: "softShadow", displayName: "Soft Shadow", style: make("softShadow") {
                $0.isShadowEnabled = true
                $0.shadowColor = ThumbnailDocumentColor(red: 0, green: 0, blue: 0, alpha: 0.82)
                $0.shadowRadius = 0.028
                $0.shadowOffsetX = 0.009
                $0.shadowOffsetY = 0.009
            }),
            ThumbnailTextStylePreset(id: "boldOutline", displayName: "Bold Outline", style: make("boldOutline") {
                $0.outlineWidth = 0.06
                $0.outlineColor = black
            }),
            ThumbnailTextStylePreset(id: "outlineAndShadow", displayName: "Outline + Shadow", style: make("outlineAndShadow") {
                $0.outlineWidth = 0.06
                $0.outlineColor = black
                $0.isShadowEnabled = true
                $0.shadowColor = ThumbnailDocumentColor(red: 0, green: 0, blue: 0, alpha: 0.82)
                $0.shadowRadius = 0.05
                $0.shadowOffsetX = 0.03
                $0.shadowOffsetY = 0.03
            }),
            ThumbnailTextStylePreset(id: "panelPill", displayName: "Panel", style: make("panelPill") {
                $0.panelColor = ThumbnailDocumentColor(red: 0, green: 0, blue: 0, alpha: 0.55)
                $0.panelCornerRadius = 0.35
                $0.horizontalPadding = 0.36
                $0.verticalPadding = 0.20
            }),
            ThumbnailTextStylePreset(id: "glow", displayName: "Glow", style: make("glow") {
                $0.isShadowEnabled = true
                $0.shadowColor = ThumbnailDocumentColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
                $0.shadowRadius = 0.22
            })
        ]
    }
}
