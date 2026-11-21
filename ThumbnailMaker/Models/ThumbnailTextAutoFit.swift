//
//  ThumbnailTextAutoFit.swift
//  ThumbnailMaker
//
//  DONOR (Simple Meme Maker Editor/TextRenderer.swift): auto-fit and the
//  "text too long for its box" check, adapted to ThumbnailMaker text layers.
//
//  Differences from the donor, on purpose:
//  - The meme maker draws with Core Text at one fixed document size, so it
//    floors to whole points with an absolute 8pt minimum. ThumbnailMaker
//    renders the SAME SwiftUI view at editor size and at export size, so every
//    limit here is RELATIVE to the requested font size. That keeps the fitted
//    size a (near) linear function of the canvas, which is the canvas/export
//    parity guarantee FEATURE-04 already relies on.
//  - Layout metrics (padding, outline/shadow ink, line/letter spacing, line
//    limit) come from ThumbnailTextStyleResolver, so the fit is measured
//    against exactly the box StyledThumbnailTextView draws into.
//

import Foundation
import SwiftUI
import UIKit

enum ThumbnailTextAutoFit {
    /// Auto-fit never shrinks below this fraction of the requested size: a
    /// caption smaller than that is unreadable anyway, and shrinking forever
    /// to squeeze an essay into a one-line box is not a kindness.
    static let minimumScale: CGFloat = 0.3
    /// Binary-search precision, as a fraction of the requested size.
    static let precision: CGFloat = 0.01
    /// Fallback line cap when neither the style nor the legacy look sets one.
    static let defaultLineCap = 3

    struct Measurement: Equatable {
        var height: CGFloat
        var lineCount: Int
    }

    // MARK: Measurement

    /// Height and line count of `text` at `fontSize`, wrapped to `width`.
    /// Uses TextKit, which wraps the same way SwiftUI `Text` does closely
    /// enough for fitting (by word, breaking a single long word when needed).
    static func measure(
        text: String,
        font: CustomFont,
        fontSize: CGFloat,
        width: CGFloat,
        lineSpacing: CGFloat = 0,
        letterSpacing: CGFloat = 0
    ) -> Measurement {
        guard !text.isEmpty, fontSize > 0, fontSize.isFinite, width > 0, width.isFinite else {
            return Measurement(height: 0, lineCount: 0)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = max(0, lineSpacing)
        paragraph.lineBreakMode = .byWordWrapping
        var attributes: [NSAttributedString.Key: Any] = [
            .font: uiFont(for: text, font: font, size: fontSize),
            .paragraphStyle: paragraph,
        ]
        if letterSpacing != 0 {
            attributes[.kern] = letterSpacing
        }
        let storage = NSTextStorage(string: text, attributes: attributes)
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)

        var lines = 0
        let glyphRange = layoutManager.glyphRange(for: container)
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, _, _ in
            lines += 1
        }
        let used = layoutManager.usedRect(for: container)
        return Measurement(height: ceil(used.height), lineCount: lines)
    }

    /// The UIFont SwiftUI will draw with. Text that needs a script fallback is
    /// measured in GoNoto, the fallback FontManager substitutes.
    static func uiFont(for text: String, font: CustomFont, size: CGFloat) -> UIFont {
        let resolvedFont = FontManager.shared.needsFallback(for: text, selectedFont: font) ? CustomFont.goNoto : font
        return UIFont(name: resolvedFont.postScriptName, size: size)
            ?? UIFont.systemFont(ofSize: size, weight: .bold)
    }

    // MARK: Fit tests

    /// Whether the text fits the content-layer box at `fontSize`, measured
    /// against the inner text frame the renderer actually uses.
    static func fits(
        text: String,
        font: CustomFont,
        fontSize: CGFloat,
        style: ThumbnailTextStyle?,
        canvasSize: CGSize,
        boxSize: CGSize
    ) -> Bool {
        guard !text.isEmpty else { return true }
        let resolved = ThumbnailTextStyleResolver.resolve(
            style: style,
            role: .contentLayer,
            fontSize: fontSize,
            canvasSize: canvasSize,
            contentBoxSize: boxSize
        )
        let height = resolved.fixedHeight ?? boxSize.height
        let measured = measure(
            text: text,
            font: font,
            fontSize: fontSize,
            width: resolved.maxWidth,
            lineSpacing: resolved.lineSpacing,
            letterSpacing: resolved.letterSpacing
        )
        if let lineLimit = resolved.lineLimit, measured.lineCount > lineLimit {
            return false
        }
        // Half a point of slack for rounding, as in the donor.
        return measured.height <= height + 0.5
    }

    /// The size the text should draw at. With auto-fit, `requested` is a
    /// MAXIMUM and the result is the largest size (to `precision`) that still
    /// fits, found by binary search rather than stepping down, so a long line
    /// does not cost dozens of layout passes per keystroke.
    static func fittedFontSize(
        text: String,
        font: CustomFont,
        requested: CGFloat,
        style: ThumbnailTextStyle?,
        canvasSize: CGSize,
        boxSize: CGSize
    ) -> CGFloat {
        guard requested.isFinite, requested > 0 else { return max(1, requested.isFinite ? requested : 1) }
        guard !text.isEmpty, boxSize.width > 0, boxSize.height > 0 else { return requested }
        func fitsAt(_ size: CGFloat) -> Bool {
            fits(text: text, font: font, fontSize: size, style: style, canvasSize: canvasSize, boxSize: boxSize)
        }
        if fitsAt(requested) { return requested }

        let floor = requested * minimumScale
        var low = floor
        var high = requested
        let step = requested * precision
        while high - low > step {
            let mid = (low + high) / 2
            if fitsAt(mid) {
                low = mid
            } else {
                high = mid
            }
        }
        return low
    }

    /// The smallest size the renderer is willing to draw this layer at:
    /// the auto-fit floor, or SwiftUI's own minimumScaleFactor otherwise.
    static func smallestRenderableSize(
        requested: CGFloat,
        style: ThumbnailTextStyle?,
        autoFit: Bool
    ) -> CGFloat {
        let scaleFactor: CGFloat = if let style {
            CGFloat(style.normalized().minimumScaleFactor)
        } else {
            // The legacy content-layer look shrinks to 0.6 (see resolver).
            0.6
        }
        let floorScale = autoFit ? min(minimumScale, scaleFactor) : scaleFactor
        return requested * floorScale
    }

    /// Whether the text is too long for its box at every size the renderer
    /// will use. Companion to the clip: without it a truncated caption would
    /// quietly export incomplete.
    static func overflowsBox(
        text: String,
        font: CustomFont,
        requested: CGFloat,
        style: ThumbnailTextStyle?,
        autoFit: Bool,
        canvasSize: CGSize,
        boxSize: CGSize
    ) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, boxSize.width > 0, boxSize.height > 0, requested > 0 else { return false }
        let smallest = smallestRenderableSize(requested: requested, style: style, autoFit: autoFit)
        return !fits(text: text, font: font, fontSize: smallest, style: style, canvasSize: canvasSize, boxSize: boxSize)
    }

    // MARK: Main title (GAPS)

    /// Font size the MAIN overlay title draws at. Without auto-fit this is
    /// the requested size (the legacy behaviour, unchanged). With auto-fit the
    /// requested size is a maximum and the title shrinks into the same fixed
    /// box added text layers use, so it wraps before it shrinks and never
    /// runs off the canvas.
    static func overlayFontSize(
        text: String,
        font: CustomFont,
        requested: CGFloat,
        style: ThumbnailTextStyle?,
        autoFit: Bool,
        canvasSize: CGSize
    ) -> CGFloat {
        let requested = max(1, requested.isFinite ? requested : 1)
        guard autoFit, !text.isEmpty else { return requested }
        let box = autoFitBoxSize(text: text, style: style, fontSize: requested, canvasSize: canvasSize)
        return fittedFontSize(
            text: text,
            font: font,
            requested: requested,
            style: style,
            canvasSize: canvasSize,
            boxSize: box
        )
    }

    // MARK: Box

    /// The fixed box an auto-fit layer shrinks into. Sized from the REQUESTED
    /// (maximum) font size, so the box does not chase the fitted size. Unlike
    /// the legacy estimate it budgets for wrapped lines up to the line cap,
    /// so a long title wraps before it shrinks.
    static func autoFitBoxSize(
        text: String,
        style: ThumbnailTextStyle?,
        fontSize: CGFloat,
        canvasSize: CGSize
    ) -> CGSize {
        let f = max(1, fontSize.isFinite ? fontSize : 1)
        let normalized = style?.normalized()
        let maxWidthFraction = CGFloat(normalized?.maxWidthFraction ?? 0.9)
        let lineCap = normalized?.lineLimit ?? defaultLineCap
        let resolved = ThumbnailTextStyleResolver.resolve(
            style: normalized,
            role: .overlay,
            fontSize: f,
            canvasSize: canvasSize
        )
        let outerH = normalized == nil ? 0 : resolved.outerHorizontalInset
        let outerV = normalized == nil ? 0 : resolved.outerVerticalInset
        let letter = normalized == nil ? 0 : resolved.letterSpacing
        let lineSpacing = normalized == nil ? 0 : resolved.lineSpacing

        let characterWidth = max(1, f * 0.56 + letter)
        let estimatedWidth = CGFloat(max(text.count, 4)) * characterWidth
        let textWidth = min(canvasSize.width * maxWidthFraction, max(canvasSize.width * 0.18, estimatedWidth))
        let explicitLines = max(1, text.components(separatedBy: .newlines).count)
        let wrappedLines = Int((estimatedWidth / max(1, textWidth)).rounded(.up))
        let lines = min(lineCap, max(explicitLines, wrappedLines))
        let textHeight = min(
            canvasSize.height * 0.48,
            max(f * 1.45, f * CGFloat(lines) * 1.25 + lineSpacing * CGFloat(max(0, lines - 1)))
        )
        return CGSize(
            width: max(1, min(canvasSize.width, textWidth + 2 * outerH)),
            height: max(1, min(canvasSize.height, textHeight + 2 * outerV))
        )
    }
}

// MARK: - Content layer convenience

extension ThumbnailTextLayerContent {
    /// Font size (points) this layer draws at on a canvas of `canvasSize`,
    /// given its (possibly resize-adjusted) normalized size and box.
    func renderedFontSize(normalizedSize: CGFloat, canvasSize: CGSize, boxSize: CGSize) -> CGFloat {
        let requested = max(1, canvasSize.height * normalizedSize)
        guard isAutoFitEnabled else { return requested }
        return ThumbnailTextAutoFit.fittedFontSize(
            text: value.isEmpty ? "Text" : value,
            font: selectedFont,
            requested: requested,
            style: style,
            canvasSize: canvasSize,
            boxSize: boxSize
        )
    }

    /// True when this layer's text cannot fit its box at any size the
    /// renderer will use (see ThumbnailTextAutoFit.overflowsBox).
    func overflowsBox(canvasSize: CGSize) -> Bool {
        let box = ContentLayerCanvasGeometry.textFrameSize(
            for: self,
            resizeTranslation: .zero,
            canvasSize: canvasSize
        )
        return ThumbnailTextAutoFit.overflowsBox(
            text: value,
            font: selectedFont,
            requested: max(1, canvasSize.height * CGFloat(size)),
            style: style,
            autoFit: isAutoFitEnabled,
            canvasSize: canvasSize,
            boxSize: box
        )
    }
}

extension Array where Element == ThumbnailDocumentLayer {
    /// Names of visible text layers whose text is too long for their box.
    func overflowingTextLayerNames(canvasSize: CGSize) -> [String] {
        compactMap { layer in
            guard layer.isVisible, case .text(let content) = layer.content,
                  content.overflowsBox(canvasSize: canvasSize) else { return nil }
            return layer.name.isEmpty ? "Text layer" : layer.name
        }
    }
}
