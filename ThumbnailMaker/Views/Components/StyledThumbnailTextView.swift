//
//  StyledThumbnailTextView.swift
//  ThumbnailMaker
//
//  FEATURE-04: the one text renderer shared by the legacy overlay text (both
//  editors) and added text layers. Export renders the same preview views, so
//  whatever this draws in the editor is what ImageRenderer writes to disk.
//
//  Composition order is deliberate: with `style == nil` it reproduces the
//  pre-FEATURE-04 modifier chain (Text -> truncation -> alignment -> shadow ->
//  frame -> padding) with no extra ZStack, compositing group or background.
//
//  Emoji note: SwiftUI cannot recolour bitmap emoji glyphs, so outline ring
//  copies behind emoji render as offset emoji. That is a documented visual
//  limitation; `inkInset` still guarantees nothing clips.
//

import SwiftUI

struct StyledThumbnailTextView: View {
    let text: String
    let font: CustomFont
    let color: Color
    let fontSize: CGFloat
    let resolved: ThumbnailResolvedTextStyle

    static func overlay(
        text: String,
        font: CustomFont,
        color: Color,
        fontSize: CGFloat,
        style: ThumbnailTextStyle?,
        canvasSize: CGSize
    ) -> StyledThumbnailTextView {
        StyledThumbnailTextView(
            text: text,
            font: font,
            color: color,
            fontSize: fontSize,
            resolved: ThumbnailTextStyleResolver.resolve(
                style: style,
                role: .overlay,
                fontSize: fontSize,
                canvasSize: canvasSize
            )
        )
    }

    static func contentLayer(
        text: String,
        font: CustomFont,
        color: Color,
        fontSize: CGFloat,
        style: ThumbnailTextStyle?,
        canvasSize: CGSize,
        boxSize: CGSize
    ) -> StyledThumbnailTextView {
        StyledThumbnailTextView(
            text: text,
            font: font,
            color: color,
            fontSize: fontSize,
            resolved: ThumbnailTextStyleResolver.resolve(
                style: style,
                role: .contentLayer,
                fontSize: fontSize,
                canvasSize: canvasSize,
                contentBoxSize: boxSize
            )
        )
    }

    var body: some View {
        if let panel = resolved.panelColor {
            let panelled = padded
                .background(
                    RoundedRectangle(cornerRadius: resolved.panelCornerRadius, style: .continuous)
                        .fill(panel)
                )
            if let shadow = resolved.shadow {
                // The panel casts the shadow, not the glyphs.
                panelled
                    .compositingGroup()
                    .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
            } else {
                panelled
            }
        } else {
            padded
        }
    }

    @ViewBuilder
    private var padded: some View {
        let horizontal = resolved.outerHorizontalInset
        let vertical = resolved.outerVerticalInset
        if horizontal == 0 && vertical == 0 {
            framed
        } else {
            framed
                .padding(.horizontal, horizontal)
                .padding(.vertical, vertical)
        }
    }

    @ViewBuilder
    private var framed: some View {
        if let fixedHeight = resolved.fixedHeight {
            shadowedInk
                .frame(width: resolved.maxWidth, height: fixedHeight, alignment: resolved.frameAlignment)
        } else {
            shadowedInk
                .frame(width: resolved.maxWidth, alignment: resolved.frameAlignment)
        }
    }

    @ViewBuilder
    private var shadowedInk: some View {
        if resolved.panelColor == nil, let shadow = resolved.shadow {
            ink.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
        } else {
            ink
        }
    }

    @ViewBuilder
    private var ink: some View {
        let fill = FontManager.shared.getAttributedText(text, selectedFont: font, size: fontSize, color: color)
        if resolved.outlineOffsets.isEmpty {
            styledText(fill)
        } else {
            let outline = FontManager.shared.getAttributedText(
                text,
                selectedFont: font,
                size: fontSize,
                color: resolved.outlineColor
            )
            let stack = ZStack {
                ForEach(Array(resolved.outlineOffsets.enumerated()), id: \.offset) { _, offset in
                    styledText(outline)
                        .offset(x: offset.width, y: offset.height)
                        .accessibilityHidden(true)
                }
                styledText(fill)
            }
            if resolved.usesCompositingGroup {
                stack.compositingGroup()
            } else {
                stack
            }
        }
    }

    /// Every ring copy and the fill go through this so the outline aligns with the glyphs.
    private func styledText(_ attributed: AttributedString) -> some View {
        let base = resolved.letterSpacing != 0
            ? Text(attributed).tracking(resolved.letterSpacing)
            : Text(attributed)
        return base
            .truncationMode(.tail)
            .modifier(OptionalTextLayoutModifier(
                lineLimit: resolved.lineLimit,
                minimumScaleFactor: resolved.minimumScaleFactor,
                lineSpacing: resolved.lineSpacing
            ))
            .multilineTextAlignment(resolved.alignment)
    }
}

/// Applies only the layout modifiers that differ from SwiftUI's defaults, so the
/// legacy overlay path does not override any inherited environment.
private struct OptionalTextLayoutModifier: ViewModifier {
    let lineLimit: Int?
    let minimumScaleFactor: CGFloat
    let lineSpacing: CGFloat

    func body(content: Content) -> some View {
        content
            .modifier(LineLimitModifier(lineLimit: lineLimit))
            .modifier(MinimumScaleModifier(minimumScaleFactor: minimumScaleFactor))
            .modifier(LineSpacingModifier(lineSpacing: lineSpacing))
    }

    private struct LineLimitModifier: ViewModifier {
        let lineLimit: Int?
        @ViewBuilder func body(content: Content) -> some View {
            if let lineLimit { content.lineLimit(lineLimit) } else { content }
        }
    }

    private struct MinimumScaleModifier: ViewModifier {
        let minimumScaleFactor: CGFloat
        @ViewBuilder func body(content: Content) -> some View {
            if minimumScaleFactor < 1 { content.minimumScaleFactor(minimumScaleFactor) } else { content }
        }
    }

    private struct LineSpacingModifier: ViewModifier {
        let lineSpacing: CGFloat
        @ViewBuilder func body(content: Content) -> some View {
            if lineSpacing != 0 { content.lineSpacing(lineSpacing) } else { content }
        }
    }
}
