//
//  ThumbnailTextStyleResolver.swift
//  ThumbnailMaker
//
//  FEATURE-04: turns a (possibly nil) ThumbnailTextStyle into absolute point
//  metrics for one render. This is the single place the legacy branch lives.
//

import Foundation
import SwiftUI

struct ThumbnailResolvedTextShadow: Equatable {
    var color: Color
    var radius: CGFloat
    var x: CGFloat
    var y: CGFloat
}

struct ThumbnailResolvedTextStyle: Equatable {
    var alignment: TextAlignment
    var frameAlignment: Alignment
    var maxWidth: CGFloat
    /// Content layers only.
    var fixedHeight: CGFloat?
    var horizontalPadding: CGFloat
    var verticalPadding: CGFloat
    /// Outline + shadow spill allowance, so nothing clips.
    var inkInset: CGFloat
    var lineSpacing: CGFloat
    var letterSpacing: CGFloat
    var outlineWidth: CGFloat
    var outlineColor: Color
    /// Empty when outlineWidth == 0.
    var outlineOffsets: [CGSize]
    var shadow: ThumbnailResolvedTextShadow?
    var panelColor: Color?
    var panelCornerRadius: CGFloat
    var lineLimit: Int?
    var minimumScaleFactor: CGFloat
    /// false whenever there is no outline, so the single-Text legacy case is unchanged.
    var usesCompositingGroup: Bool

    /// Total outer size added around the text frame on each axis.
    var outerHorizontalInset: CGFloat { horizontalPadding + inkInset }
    var outerVerticalInset: CGFloat { verticalPadding + inkInset }
}

enum ThumbnailTextStyleResolver {
    static let maximumOutlineSamples = 24
    static let minimumOutlineSamples = 8

    static func resolve(
        style: ThumbnailTextStyle?,
        role: ThumbnailTextRole,
        fontSize: CGFloat,
        canvasSize: CGSize,
        contentBoxSize: CGSize? = nil
    ) -> ThumbnailResolvedTextStyle {
        guard let rawStyle = style else {
            return legacy(role: role, canvasSize: canvasSize, contentBoxSize: contentBoxSize)
        }

        let style = rawStyle.normalized()
        let f = max(1, fontSize.isFinite ? fontSize : 1)
        let outlineWidth = CGFloat(style.outlineWidth) * f
        let shadow: ThumbnailResolvedTextShadow? = style.isShadowEnabled
            ? ThumbnailResolvedTextShadow(
                color: style.shadowColor.color,
                radius: CGFloat(style.shadowRadius) * f,
                x: CGFloat(style.shadowOffsetX) * f,
                y: CGFloat(style.shadowOffsetY) * f
            )
            : nil
        let inkInset = outlineWidth + (shadow.map { $0.radius + max(abs($0.x), abs($0.y)) } ?? 0)
        let hPad = CGFloat(style.horizontalPadding) * f
        let vPad = CGFloat(style.verticalPadding) * f

        let maxWidth: CGFloat
        let fixedHeight: CGFloat?
        switch role {
        case .overlay:
            maxWidth = max(1, canvasSize.width * CGFloat(style.maxWidthFraction))
            fixedHeight = nil
        case .contentLayer:
            let box = contentBoxSize ?? CGSize(
                width: canvasSize.width * CGFloat(style.maxWidthFraction),
                height: canvasSize.height
            )
            maxWidth = max(1, box.width - 2 * (hPad + inkInset))
            fixedHeight = max(1, box.height - 2 * (vPad + inkInset))
        }

        let offsets = outlineOffsets(width: outlineWidth)
        let frameAlignment: Alignment = switch style.alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }

        return ThumbnailResolvedTextStyle(
            alignment: style.alignment.textAlignment,
            frameAlignment: frameAlignment,
            maxWidth: maxWidth,
            fixedHeight: fixedHeight,
            horizontalPadding: hPad,
            verticalPadding: vPad,
            inkInset: inkInset,
            lineSpacing: CGFloat(style.lineSpacing) * f,
            letterSpacing: CGFloat(style.letterSpacing) * f,
            outlineWidth: outlineWidth,
            outlineColor: style.outlineColor.color,
            outlineOffsets: offsets,
            shadow: shadow,
            panelColor: style.panelColor?.color,
            panelCornerRadius: CGFloat(style.panelCornerRadius) * f,
            lineLimit: style.lineLimit,
            minimumScaleFactor: CGFloat(style.minimumScaleFactor),
            usesCompositingGroup: !offsets.isEmpty
        )
    }

    /// The literal constants shipped before FEATURE-04. Old documents decode with
    /// `style == nil` and get exactly these (absolute-point shadow included).
    private static func legacy(
        role: ThumbnailTextRole,
        canvasSize: CGSize,
        contentBoxSize: CGSize?
    ) -> ThumbnailResolvedTextStyle {
        switch role {
        case .overlay:
            return ThumbnailResolvedTextStyle(
                alignment: .center,
                frameAlignment: .center,
                maxWidth: canvasSize.width * 0.9,
                fixedHeight: nil,
                horizontalPadding: canvasSize.width * 0.03,
                verticalPadding: canvasSize.height * 0.03,
                inkInset: 0,
                lineSpacing: 0,
                letterSpacing: 0,
                outlineWidth: 0,
                outlineColor: .black,
                outlineOffsets: [],
                shadow: ThumbnailResolvedTextShadow(color: .black, radius: 3, x: 1, y: 1),
                panelColor: nil,
                panelCornerRadius: 0,
                lineLimit: nil,
                minimumScaleFactor: 1,
                usesCompositingGroup: false
            )
        case .contentLayer:
            let box = contentBoxSize ?? CGSize(width: canvasSize.width * 0.9, height: canvasSize.height * 0.48)
            return ThumbnailResolvedTextStyle(
                alignment: .center,
                frameAlignment: .center,
                maxWidth: box.width,
                fixedHeight: box.height,
                horizontalPadding: 0,
                verticalPadding: 0,
                inkInset: 0,
                lineSpacing: 0,
                letterSpacing: 0,
                outlineWidth: 0,
                outlineColor: .black,
                outlineOffsets: [],
                shadow: ThumbnailResolvedTextShadow(color: .black.opacity(0.82), radius: 3, x: 1, y: 1),
                panelColor: nil,
                panelCornerRadius: 0,
                lineLimit: 3,
                minimumScaleFactor: 0.6,
                usesCompositingGroup: false
            )
        }
    }

    /// A deterministic ring of offsets approximating a stroke of `width` points.
    static func outlineOffsets(width: CGFloat) -> [CGSize] {
        guard width > 0, width.isFinite else { return [] }
        let count = min(
            maximumOutlineSamples,
            max(minimumOutlineSamples, Int((width * 4).rounded(.up)))
        )
        return (0..<count).map { index in
            let angle = 2 * CGFloat.pi * CGFloat(index) / CGFloat(count)
            return CGSize(width: width * cos(angle), height: width * sin(angle))
        }
    }

    /// Frame size for a styled content text layer (used by ContentLayerCanvasGeometry
    /// when `content.style != nil`). Includes padding and ink allowance and is clamped
    /// to the canvas so a hostile style cannot produce an unbounded frame.
    static func styledContentFrameSize(
        text: String,
        style rawStyle: ThumbnailTextStyle,
        fontSize: CGFloat,
        canvasSize: CGSize
    ) -> CGSize {
        let style = rawStyle.normalized()
        let resolved = resolve(
            style: style,
            role: .overlay,
            fontSize: fontSize,
            canvasSize: canvasSize
        )
        let lineCap = style.lineLimit ?? 3
        let lineCount = min(lineCap, max(1, text.components(separatedBy: .newlines).count))
        let estimatedCharacterWidth = max(1, fontSize * 0.56 + resolved.letterSpacing)
        let estimatedTextWidth = CGFloat(max(text.count, 4)) * estimatedCharacterWidth
        let textWidth = min(
            canvasSize.width * CGFloat(style.maxWidthFraction),
            max(canvasSize.width * 0.18, estimatedTextWidth)
        )
        let textHeight = min(
            canvasSize.height * 0.48,
            max(
                fontSize * 1.45,
                fontSize * CGFloat(lineCount) * 1.25
                    + resolved.lineSpacing * CGFloat(max(0, lineCount - 1))
            )
        )
        let width = textWidth + 2 * resolved.outerHorizontalInset
        let height = textHeight + 2 * resolved.outerVerticalInset
        return CGSize(
            width: max(1, min(canvasSize.width, width)),
            height: max(1, min(canvasSize.height, height))
        )
    }
}
