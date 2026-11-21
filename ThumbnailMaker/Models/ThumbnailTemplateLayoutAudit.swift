//
//  ThumbnailTemplateLayoutAudit.swift
//  ThumbnailMaker
//
//  TEMPLATES: measures where a template's text, badges and decorations
//  actually land on a canvas, with the same TextKit wrapping the auto-fit
//  code uses and the same style metrics StyledThumbnailTextView draws with,
//  and reports anything that would clip, leave the safe zone, overlap other
//  text or cover the focal subject. Pure and deterministic; used by the
//  curated-library tests and available to any future template tooling.
//

import CoreGraphics
import Foundation
import UIKit

struct ThumbnailTemplateLayoutElement: Equatable {
    enum Kind: String, Equatable {
        /// The document's headline (overlay text).
        case headline
        /// An added text layer.
        case text
        /// A shape that carries a label (badge, burst, callout).
        case labeledShape
        /// A shape without words (arrow, ring, bar).
        case decoration
    }

    let layerID: String
    let kind: Kind
    let zIndex: Int
    /// Canvas points: the rotated bounding box of what is drawn.
    let rect: CGRect
    /// Rendered text line count (0 for decorations).
    let lineCount: Int

    var carriesText: Bool { kind != .decoration }
}

enum ThumbnailTemplateLayoutIssue: Equatable, CustomStringConvertible {
    case outsideCanvas(layerID: String)
    case outsideSafeZone(layerID: String)
    /// Text that cannot draw at its designed size inside its own box.
    case textDoesNotFit(layerID: String)
    case textOverlapsText(first: String, second: String)
    case shapeCoversText(shapeID: String, textID: String)
    case textCoversFocalRegion(layerID: String)

    var description: String {
        switch self {
        case .outsideCanvas(let id): "\(id): outside canvas"
        case .outsideSafeZone(let id): "\(id): outside safe zone"
        case .textDoesNotFit(let id): "\(id): text does not fit"
        case .textOverlapsText(let first, let second): "\(first) overlaps \(second)"
        case .shapeCoversText(let shape, let text): "\(shape) covers \(text)"
        case .textCoversFocalRegion(let id): "\(id): covers focal region"
        }
    }
}

enum ThumbnailTemplateLayoutAudit {
    /// Rounding slack in points at the measured canvas size.
    static let tolerance: CGFloat = 1

    struct TextMeasurement: Equatable {
        var size: CGSize
        var lineCount: Int
    }

    // MARK: Audit

    static func issues(
        in document: ThumbnailDocument,
        canvasSize: CGSize,
        safeZone: ThumbnailSafeZone?,
        focalRegion: CGRect? = nil
    ) -> [ThumbnailTemplateLayoutIssue] {
        let measured = measuredElements(in: document, canvasSize: canvasSize)
        var issues: [ThumbnailTemplateLayoutIssue] = measured.unfitLayerIDs.map { .textDoesNotFit(layerID: $0) }
        let canvasRect = CGRect(origin: .zero, size: canvasSize).insetBy(dx: -tolerance, dy: -tolerance)
        let safeRect = safeZone.flatMap { zone -> CGRect? in
            guard zone.hasValidNormalizedInsets else { return nil }
            return zone.contentRect(in: canvasSize).insetBy(dx: -tolerance, dy: -tolerance)
        }
        let focalRect = focalRegion.map {
            CGRect(
                x: $0.minX * canvasSize.width,
                y: $0.minY * canvasSize.height,
                width: $0.width * canvasSize.width,
                height: $0.height * canvasSize.height
            ).insetBy(dx: tolerance, dy: tolerance)
        }

        let elements = measured.elements
        for element in elements {
            if !canvasRect.contains(element.rect) {
                issues.append(.outsideCanvas(layerID: element.layerID))
            } else if element.carriesText, let safeRect, !safeRect.contains(element.rect) {
                issues.append(.outsideSafeZone(layerID: element.layerID))
            }
            if element.carriesText, let focalRect, element.rect.intersects(focalRect) {
                issues.append(.textCoversFocalRegion(layerID: element.layerID))
            }
        }

        let texts = elements.filter(\.carriesText)
        for (index, first) in texts.enumerated() {
            for second in texts.dropFirst(index + 1) where overlaps(first.rect, second.rect) {
                issues.append(.textOverlapsText(first: first.layerID, second: second.layerID))
            }
        }
        for shape in elements where shape.kind == .decoration {
            for text in texts where shape.zIndex > text.zIndex && overlaps(shape.rect, text.rect) {
                issues.append(.shapeCoversText(shapeID: shape.layerID, textID: text.layerID))
            }
        }
        return issues
    }

    private static func overlaps(_ first: CGRect, _ second: CGRect) -> Bool {
        let overlap = first.intersection(second)
        return !overlap.isNull && overlap.width > tolerance && overlap.height > tolerance
    }

    // MARK: Elements

    static func elements(in document: ThumbnailDocument, canvasSize: CGSize) -> [ThumbnailTemplateLayoutElement] {
        measuredElements(in: document, canvasSize: canvasSize).elements
    }

    private static func measuredElements(
        in document: ThumbnailDocument,
        canvasSize: CGSize
    ) -> (elements: [ThumbnailTemplateLayoutElement], unfitLayerIDs: [String]) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return ([], []) }
        var elements: [ThumbnailTemplateLayoutElement] = []
        var unfit: [String] = []

        for layer in document.layers where layer.isVisible {
            switch layer.kind {
            case .background, .profile, .image:
                continue
            case .text where layer.id == ThumbnailDocumentLayer.textID:
                guard !document.text.value.isEmpty else { continue }
                elements.append(headlineElement(document.text, layer: layer, canvasSize: canvasSize))
            case .text, .shape:
                switch layer.content {
                case .text(let content):
                    let result = textLayerElement(content, layer: layer, canvasSize: canvasSize)
                    elements.append(result.element)
                    if !result.fits { unfit.append(layer.id) }
                case .shape(let content):
                    let result = shapeElement(content, layer: layer, canvasSize: canvasSize)
                    elements.append(result.element)
                    if !result.labelFits { unfit.append(layer.id) }
                case .image, nil:
                    continue
                }
            }
        }
        return (elements, unfit)
    }

    /// The overlay headline: a fixed-width frame (`maxWidth`) with the
    /// glyphs aligned inside it, padding and ink outside, panel behind.
    static func headlineElement(
        _ text: ThumbnailDocumentText,
        layer: ThumbnailDocumentLayer,
        canvasSize: CGSize
    ) -> ThumbnailTemplateLayoutElement {
        let fontSize = max(1, canvasSize.height * CGFloat(text.size))
        let resolved = ThumbnailTextStyleResolver.resolve(
            style: text.style,
            role: .overlay,
            fontSize: fontSize,
            canvasSize: canvasSize
        )
        let font = CustomFont(rawValue: text.selectedFontRawValue) ?? .goNoto
        let measurement = measure(
            text.value,
            font: font,
            fontSize: fontSize,
            width: resolved.maxWidth,
            lineSpacing: resolved.lineSpacing,
            letterSpacing: resolved.letterSpacing
        )
        let center = CGPoint(x: text.transform.x * canvasSize.width, y: text.transform.y * canvasSize.height)
        let local: CGRect
        if resolved.panelColor != nil {
            let width = resolved.maxWidth + 2 * resolved.outerHorizontalInset
            let height = measurement.size.height + 2 * resolved.outerVerticalInset
            local = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        } else {
            let glyphWidth = min(resolved.maxWidth, measurement.size.width)
            let glyphMinX: CGFloat = switch text.style?.alignment ?? .center {
            case .leading: -resolved.maxWidth / 2
            case .center: -glyphWidth / 2
            case .trailing: resolved.maxWidth / 2 - glyphWidth
            }
            local = CGRect(
                x: glyphMinX,
                y: -measurement.size.height / 2,
                width: glyphWidth,
                height: measurement.size.height
            ).insetBy(dx: -resolved.inkInset, dy: -resolved.inkInset)
        }
        return ThumbnailTemplateLayoutElement(
            layerID: layer.id,
            kind: .headline,
            zIndex: layer.zIndex,
            rect: placed(local, at: center, degrees: text.transform.rotationDegrees),
            lineCount: measurement.lineCount
        )
    }

    static func textLayerElement(
        _ content: ThumbnailTextLayerContent,
        layer: ThumbnailDocumentLayer,
        canvasSize: CGSize
    ) -> (element: ThumbnailTemplateLayoutElement, fits: Bool) {
        let box = ContentLayerCanvasGeometry.textFrameSize(for: content, resizeTranslation: .zero, canvasSize: canvasSize)
        let fontSize = max(1, canvasSize.height * CGFloat(content.size))
        let fits = ThumbnailTextAutoFit.fits(
            text: content.value,
            font: content.selectedFont,
            fontSize: fontSize,
            style: content.style,
            canvasSize: canvasSize,
            boxSize: box
        )
        let resolved = ThumbnailTextStyleResolver.resolve(
            style: content.style,
            role: .contentLayer,
            fontSize: fontSize,
            canvasSize: canvasSize,
            contentBoxSize: box
        )
        let measurement = measure(
            content.value,
            font: content.selectedFont,
            fontSize: fontSize,
            width: resolved.maxWidth,
            lineSpacing: resolved.lineSpacing,
            letterSpacing: resolved.letterSpacing
        )
        let center = CGPoint(x: content.transform.x * canvasSize.width, y: content.transform.y * canvasSize.height)
        let local = CGRect(x: -box.width / 2, y: -box.height / 2, width: box.width, height: box.height)
        return (
            ThumbnailTemplateLayoutElement(
                layerID: layer.id,
                kind: .text,
                zIndex: layer.zIndex,
                rect: placed(local, at: center, degrees: content.transform.rotationDegrees),
                lineCount: measurement.lineCount
            ),
            fits
        )
    }

    static func shapeElement(
        _ content: ThumbnailShapeLayerContent,
        layer: ThumbnailDocumentLayer,
        canvasSize: CGSize
    ) -> (element: ThumbnailTemplateLayoutElement, labelFits: Bool) {
        let size = CGSize(
            width: canvasSize.width * CGFloat(content.width),
            height: canvasSize.height * CGFloat(content.height)
        )
        let center = CGPoint(x: content.transform.x * canvasSize.width, y: content.transform.y * canvasSize.height)
        let local = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        let rect = placed(local, at: center, degrees: content.transform.rotationDegrees)

        guard let label = content.label, !label.displayText.isEmpty, content.shapeKind.supportsLabel else {
            return (
                ThumbnailTemplateLayoutElement(layerID: layer.id, kind: .decoration, zIndex: layer.zIndex, rect: rect, lineCount: 0),
                true
            )
        }
        // Mirrors ThumbnailShapeLabelView: font from the label rect, two lines.
        let labelRect = ThumbnailShapePathBuilder.labelRect(for: content, in: CGRect(origin: .zero, size: size))
        let fontSize = max(4, labelRect.height * CGFloat(label.effectiveSizeFraction) * 1.6)
        // The label draws heavy; leave room for the wider synthesized weight.
        let measurement = measure(
            label.displayText,
            font: label.font,
            fontSize: fontSize,
            width: labelRect.width * 0.88
        )
        let fits = measurement.lineCount <= 1 && measurement.size.height <= labelRect.height + tolerance
        return (
            ThumbnailTemplateLayoutElement(
                layerID: layer.id,
                kind: .labeledShape,
                zIndex: layer.zIndex,
                rect: rect,
                lineCount: measurement.lineCount
            ),
            fits
        )
    }

    /// Rotated bounding box of `local` (centred on the origin) moved to `center`.
    static func placed(_ local: CGRect, at center: CGPoint, degrees: Double) -> CGRect {
        let radians = CGFloat((degrees.isFinite ? degrees : 0) * .pi / 180)
        guard radians != 0 else { return local.offsetBy(dx: center.x, dy: center.y) }
        let corners = [
            CGPoint(x: local.minX, y: local.minY),
            CGPoint(x: local.maxX, y: local.minY),
            CGPoint(x: local.minX, y: local.maxY),
            CGPoint(x: local.maxX, y: local.maxY)
        ].map { point in
            CGPoint(
                x: point.x * cos(radians) - point.y * sin(radians) + center.x,
                y: point.x * sin(radians) + point.y * cos(radians) + center.y
            )
        }
        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        return CGRect(
            x: xs.min() ?? center.x,
            y: ys.min() ?? center.y,
            width: (xs.max() ?? center.x) - (xs.min() ?? center.x),
            height: (ys.max() ?? center.y) - (ys.min() ?? center.y)
        )
    }

    // MARK: Measurement

    /// Wrapped size of `text`, laid out the way ThumbnailTextAutoFit measures.
    static func measure(
        _ text: String,
        font: CustomFont,
        fontSize: CGFloat,
        width: CGFloat,
        lineSpacing: CGFloat = 0,
        letterSpacing: CGFloat = 0
    ) -> TextMeasurement {
        guard !text.isEmpty, fontSize > 0, fontSize.isFinite, width > 0, width.isFinite else {
            return TextMeasurement(size: .zero, lineCount: 0)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = max(0, lineSpacing)
        paragraph.lineBreakMode = .byWordWrapping
        var attributes: [NSAttributedString.Key: Any] = [
            .font: ThumbnailTextAutoFit.uiFont(for: text, font: font, size: fontSize),
            .paragraphStyle: paragraph
        ]
        if letterSpacing != 0 {
            attributes[.kern] = letterSpacing
        }
        let storage = NSTextStorage(string: text, attributes: attributes)
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)

        var lines = 0
        var usedWidth: CGFloat = 0
        let glyphRange = layoutManager.glyphRange(for: container)
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
            lines += 1
            usedWidth = max(usedWidth, usedRect.width)
        }
        let used = layoutManager.usedRect(for: container)
        return TextMeasurement(size: CGSize(width: ceil(usedWidth), height: ceil(used.height)), lineCount: lines)
    }
}

// MARK: - Colour families

enum ThumbnailTemplatePaletteAudit {
    /// Hue families (plus one "neutral" family for greys, near-black and
    /// near-white) used by the visible, mostly opaque colours of a design.
    /// Shades of one hue count once, so a two-stop gradient of one colour is
    /// a single family.
    static func colorFamilyCount(in document: ThumbnailDocument) -> Int {
        var colors: [ThumbnailDocumentColor] = []
        if let fill = document.canvas.backgroundFill, fill.drawsGradient {
            colors += fill.stops.map(\.color)
        } else {
            colors.append(document.canvas.backgroundColor)
        }
        if !document.text.value.isEmpty {
            colors.append(document.text.color)
            if let panel = document.text.style?.panelColor { colors.append(panel) }
            if let style = document.text.style, style.outlineWidth > 0 { colors.append(style.outlineColor) }
            if let style = document.text.style, style.isShadowEnabled, style.shadowRadius >= 0.1 {
                colors.append(style.shadowColor) // a glow reads as a colour
            }
        }
        for layer in document.layers where layer.isVisible {
            switch layer.content {
            case .shape(let shape):
                colors.append(shape.fillColor)
                if let stroke = shape.strokeColor, shape.strokeWidth > 0 { colors.append(stroke) }
                if let label = shape.label, !label.displayText.isEmpty { colors.append(label.color) }
            case .text(let text):
                colors.append(text.color)
            case .image, nil:
                continue
            }
        }
        return families(of: colors.filter { $0.alpha >= 0.5 })
    }

    static func families(of colors: [ThumbnailDocumentColor]) -> Int {
        var hasNeutral = false
        var hues: [Double] = []
        for color in colors {
            let hsb = hueSaturationBrightness(color)
            if hsb.saturation < 0.25 || hsb.brightness < 0.2 {
                hasNeutral = true
                continue
            }
            if !hues.contains(where: { hueDistance($0, hsb.hue) <= 0.08 }) {
                hues.append(hsb.hue)
            }
        }
        return hues.count + (hasNeutral ? 1 : 0)
    }

    private static func hueDistance(_ first: Double, _ second: Double) -> Double {
        let distance = abs(first - second)
        return min(distance, 1 - distance)
    }

    static func hueSaturationBrightness(_ color: ThumbnailDocumentColor) -> (hue: Double, saturation: Double, brightness: Double) {
        let red = color.red, green = color.green, blue = color.blue
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        let saturation = maximum == 0 ? 0 : delta / maximum
        guard delta > 0 else { return (0, saturation, maximum) }
        var hue: Double
        if maximum == red {
            hue = (green - blue) / delta
        } else if maximum == green {
            hue = (blue - red) / delta + 2
        } else {
            hue = (red - green) / delta + 4
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, saturation, maximum)
    }
}
