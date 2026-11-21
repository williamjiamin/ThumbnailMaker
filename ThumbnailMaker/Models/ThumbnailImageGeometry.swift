//
//  ThumbnailImageGeometry.swift
//  ThumbnailMaker
//
//  The single geometry function that preview, export and the framing editor
//  all call to place an image inside a frame according to a
//  `ThumbnailImageFrameRecipe`. It is pure and scale-invariant: the
//  normalized `sourceRect` it reports depends only on the frame's aspect
//  ratio, so a ~350pt preview and a 1920x1080 export show the same pixels.
//

import CoreGraphics
import SwiftUI

enum ThumbnailImageGeometry {
    struct Solution: Equatable {
        /// Clipping frame.
        var frameSize: CGSize
        /// Size handed to the resizable image.
        var renderSize: CGSize
        /// Offset of the image's top-left corner from the frame's top-left.
        var offset: CGSize
        /// Normalized rect of the source that ends up visible.
        var sourceRect: CGRect
    }

    static let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    static func solve(
        sourceSize: CGSize,
        frameSize: CGSize,
        recipe: ThumbnailImageFrameRecipe
    ) -> Solution {
        guard isUsable(sourceSize), isUsable(frameSize) else {
            let safeFrame = isFinite(frameSize) ? frameSize : .zero
            return Solution(frameSize: safeFrame, renderSize: safeFrame, offset: .zero, sourceRect: unitRect)
        }

        if recipe.fit == .stretch {
            return Solution(frameSize: frameSize, renderSize: frameSize, offset: .zero, sourceRect: unitRect)
        }

        let widthScale = frameSize.width / sourceSize.width
        let heightScale = frameSize.height / sourceSize.height
        let baseScale = recipe.fit == .fill ? max(widthScale, heightScale) : min(widthScale, heightScale)
        let scale = baseScale * CGFloat(ThumbnailImageFrameRecipe.clampedZoom(recipe.zoom))
        let renderSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)

        let offset = CGSize(
            width: axisOffset(frame: frameSize.width, render: renderSize.width, focus: recipe.focusX),
            height: axisOffset(frame: frameSize.height, render: renderSize.height, focus: recipe.focusY)
        )
        let sourceRect = CGRect(
            x: max(0, -offset.width / renderSize.width),
            y: max(0, -offset.height / renderSize.height),
            width: min(1, frameSize.width / renderSize.width),
            height: min(1, frameSize.height / renderSize.height)
        )
        return Solution(frameSize: frameSize, renderSize: renderSize, offset: offset, sourceRect: sourceRect)
    }

    private static func axisOffset(frame: CGFloat, render: CGFloat, focus: Double) -> CGFloat {
        guard render > frame else {
            return (frame - render) / 2
        }
        let focus = CGFloat(ThumbnailImageFrameRecipe.clampedFocus(focus))
        let desired = frame / 2 - focus * render
        // Clamp so no gutter is ever exposed once the image overflows the frame.
        return min(0, max(frame - render, desired))
    }

    private static func isFinite(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite
    }

    private static func isUsable(_ size: CGSize) -> Bool {
        isFinite(size) && size.width > 0 && size.height > 0
    }
}

extension Image {
    /// Renders a resizable image placed by a solved frame recipe. Uses a real
    /// frame + offset (never `scaleEffect`) so `ImageRenderer` exports stay
    /// sharp, and a top-leading alignment so the offset matches the solver.
    func framed(_ solution: ThumbnailImageGeometry.Solution) -> some View {
        self.resizable()
            .frame(width: solution.renderSize.width, height: solution.renderSize.height)
            .offset(solution.offset)
            .frame(width: solution.frameSize.width, height: solution.frameSize.height, alignment: .topLeading)
            .clipped()
    }
}
