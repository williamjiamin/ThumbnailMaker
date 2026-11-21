//
//  ThumbnailShapeRenderView.swift
//  ThumbnailMaker
//
//  FEATURE-12: draws arrows, badges and callouts from their recipe, plus the
//  optional label of any shape. Used by the shared ContentShapeLayerCanvasItem,
//  so the Simple editor, the Premium editor and export all render the same
//  way. Layout is frame + offset only (no scaleEffect) so ImageRenderer
//  output matches the canvas.
//

import SwiftUI

struct ThumbnailRecipeShape: Shape {
    let content: ThumbnailShapeLayerContent

    func path(in rect: CGRect) -> Path {
        ThumbnailShapePathBuilder.paths(for: content, in: rect).body
    }
}

struct ThumbnailShapeRenderView: View {
    let content: ThumbnailShapeLayerContent
    /// Canvas size; stroke widths are a fraction of its short side, exactly
    /// like the legacy rectangle/ellipse renderer.
    let canvasSize: CGSize
    let size: CGSize

    static func lineWidth(for content: ThumbnailShapeLayerContent, canvasSize: CGSize) -> CGFloat {
        max(1, min(canvasSize.width, canvasSize.height) * CGFloat(content.strokeWidth))
    }

    var body: some View {
        let rect = CGRect(origin: .zero, size: size)
        let lineWidth = Self.lineWidth(for: content, canvasSize: canvasSize)
        let paths = ThumbnailShapePathBuilder.paths(for: content, in: rect, lineWidth: lineWidth)

        ZStack(alignment: .topLeading) {
            if content.shapeKind.usesFill {
                paths.body.fill(content.fillColor.color)
                if let strokeColor = content.strokeColor {
                    paths.body.stroke(
                        strokeColor.color,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                    )
                }
            } else {
                let color = content.lineColor.color
                paths.body.stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                paths.filledHeads.fill(color)
                paths.strokedHeads.stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            ThumbnailShapeLabelView(content: content, size: size)
        }
    }
}

/// Draws `content.label` inside the shape's label rect. Renders nothing when
/// the shape has no (non-empty) label, so legacy shapes are pixel-identical.
struct ThumbnailShapeLabelView: View {
    let content: ThumbnailShapeLayerContent
    let size: CGSize

    var body: some View {
        if let label = content.label, !label.displayText.isEmpty, content.shapeKind.supportsLabel {
            let labelRect = ThumbnailShapePathBuilder.labelRect(
                for: content,
                in: CGRect(origin: .zero, size: size)
            )
            let fontSize = max(4, labelRect.height * CGFloat(label.effectiveSizeFraction) * 1.6)
            Text(label.displayText)
                .font(.custom(label.font.postScriptName, size: fontSize))
                .fontWeight(label.isBold ? .heavy : .regular)
                .foregroundStyle(label.color.color)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.3)
                .frame(width: max(labelRect.width, 1), height: max(labelRect.height, 1))
                .offset(x: labelRect.minX, y: labelRect.minY)
                .allowsHitTesting(false)
        }
    }
}

enum ThumbnailShapeAccessibility {
    /// Canvas accessibility label: the layer name plus any label text, so
    /// VoiceOver (and UI tests) can read a callout's words.
    static func label(name: String, content: ThumbnailShapeLayerContent) -> String {
        let base = name.isEmpty ? "Shape layer" : name
        guard let text = content.label?.displayText, !text.isEmpty, content.shapeKind.supportsLabel else {
            return base
        }
        return "\(base): \(text)"
    }
}
