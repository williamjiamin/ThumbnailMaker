//
//  ThumbnailImageGeometryTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-03: the pure framing solver shared by preview, export and the
//  framing editor.
//

import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ThumbnailImageGeometryTests {
    private static let sources: [CGSize] = [
        CGSize(width: 600, height: 900),
        CGSize(width: 1600, height: 400),
        CGSize(width: 512, height: 512),
        CGSize(width: 1, height: 5000),
        CGSize(width: 5000, height: 1),
    ]

    private static let recipes: [ThumbnailImageFrameRecipe] = [
        .identity,
        .fillCentered,
        ThumbnailImageFrameRecipe(fit: .fill, focusX: 0.1, focusY: 0.9, zoom: 2.5),
        ThumbnailImageFrameRecipe(fit: .fit, focusX: 0.8, focusY: 0.2, zoom: 3),
        ThumbnailImageFrameRecipe(fit: .fill, focusX: 1, focusY: 0, zoom: 8),
        ThumbnailImageFrameRecipe(fit: .stretch),
    ]

    private static let frames: [CGSize] = AspectRatio.allCases.map {
        CGSize(width: $0.dimensions.width, height: $0.dimensions.height)
    }

    private func approx(_ lhs: CGFloat, _ rhs: CGFloat, tolerance: CGFloat = 1e-9) -> Bool {
        abs(lhs - rhs) <= tolerance * max(1, abs(lhs), abs(rhs))
    }

    private func approx(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        approx(lhs.minX, rhs.minX) && approx(lhs.minY, rhs.minY)
            && approx(lhs.width, rhs.width) && approx(lhs.height, rhs.height)
    }

    private func isFinite(_ solution: ThumbnailImageGeometry.Solution) -> Bool {
        [solution.frameSize.width, solution.frameSize.height,
         solution.renderSize.width, solution.renderSize.height,
         solution.offset.width, solution.offset.height,
         solution.sourceRect.minX, solution.sourceRect.minY,
         solution.sourceRect.width, solution.sourceRect.height].allSatisfy(\.isFinite)
    }

    // 1. Preview/export parity: the visible source region is scale-invariant.
    @Test func previewAndExportFrameTheSamePixels() {
        let preview = CGSize(width: 350, height: 196.875)
        for source in Self.sources {
            for recipe in Self.recipes {
                let reference = ThumbnailImageGeometry.solve(sourceSize: source, frameSize: preview, recipe: recipe)
                for scale: CGFloat in [0.1, 1, 1920.0 / 350.0, 100] {
                    let scaled = CGSize(width: preview.width * scale, height: preview.height * scale)
                    let solution = ThumbnailImageGeometry.solve(sourceSize: source, frameSize: scaled, recipe: recipe)
                    #expect(approx(solution.sourceRect, reference.sourceRect), "source \(source.width)x\(source.height) scale \(scale)")
                }
            }
        }
    }

    // 2. `.identity` is exactly today's scaledToFit letterbox.
    @Test func identityMatchesLegacyScaledToFit() {
        let frame = CGSize(width: 1920, height: 1080)
        let same = ThumbnailImageGeometry.solve(
            sourceSize: CGSize(width: 1600, height: 900), frameSize: frame, recipe: .identity
        )
        #expect(approx(same.renderSize.width, frame.width))
        #expect(approx(same.renderSize.height, frame.height))
        #expect(same.offset == .zero)
        #expect(approx(same.sourceRect, ThumbnailImageGeometry.unitRect))

        let portrait = ThumbnailImageGeometry.solve(
            sourceSize: CGSize(width: 300, height: 400), frameSize: frame, recipe: .identity
        )
        #expect(approx(portrait.renderSize.height, frame.height))
        #expect(approx(portrait.renderSize.width, 810))
        #expect(approx(portrait.offset.width, (1920 - 810) / 2))
        #expect(portrait.offset.height == 0)
        #expect(approx(portrait.sourceRect, ThumbnailImageGeometry.unitRect))
    }

    // 3 + 4 + 5. Fill never leaks a gutter; fit/fill never distort; any focal
    // point keeps the visible window inside the source.
    @Test func fillCoversFrameWithoutDistortionForEveryFocalPoint() {
        for source in Self.sources {
            for frame in Self.frames {
                for focus in [0.0, 0.5, 1.0] {
                    for zoom in [1.0, 2.0, 8.0] {
                        let recipe = ThumbnailImageFrameRecipe(fit: .fill, focusX: focus, focusY: 1 - focus, zoom: zoom)
                        let solution = ThumbnailImageGeometry.solve(sourceSize: source, frameSize: frame, recipe: recipe)
                        #expect(solution.renderSize.width >= frame.width - 1e-6)
                        #expect(solution.renderSize.height >= frame.height - 1e-6)
                        #expect(solution.offset.width <= 1e-9)
                        #expect(solution.offset.height <= 1e-9)
                        #expect(solution.offset.width >= frame.width - solution.renderSize.width - 1e-6)
                        #expect(solution.offset.height >= frame.height - solution.renderSize.height - 1e-6)
                        #expect(approx(
                            solution.renderSize.width / solution.renderSize.height,
                            source.width / source.height,
                            tolerance: 1e-6
                        ))
                        #expect(solution.sourceRect.minX >= -1e-9 && solution.sourceRect.maxX <= 1 + 1e-9)
                        #expect(solution.sourceRect.minY >= -1e-9 && solution.sourceRect.maxY <= 1 + 1e-9)
                    }
                }
            }
        }
    }

    @Test func fitKeepsAspectAndStretchIsOnlyExplicit() {
        let source = CGSize(width: 600, height: 900)
        let frame = CGSize(width: 1024, height: 576)
        let fit = ThumbnailImageGeometry.solve(sourceSize: source, frameSize: frame, recipe: .identity)
        #expect(approx(fit.renderSize.width / fit.renderSize.height, source.width / source.height))

        let stretch = ThumbnailImageGeometry.solve(
            sourceSize: source, frameSize: frame, recipe: ThumbnailImageFrameRecipe(fit: .stretch, zoom: 4)
        )
        #expect(stretch.renderSize == frame)
        #expect(stretch.offset == .zero)
        #expect(ThumbnailImageFrameRecipe.identity.fit != .stretch)
        #expect(ThumbnailImageFrameRecipe.fillCentered.fit != .stretch)
        #expect(ThumbnailDocument().imageRecipe.fit == .fit)
        #expect(SimpleMakerConfigurationModel().imageRecipe == .identity)
        #expect(PremiumMakerConfigurationModel().imageRecipe == .identity)
    }

    @Test func centredFillCropsSymmetrically() {
        let solution = ThumbnailImageGeometry.solve(
            sourceSize: CGSize(width: 1000, height: 1000),
            frameSize: CGSize(width: 1600, height: 900),
            recipe: .fillCentered
        )
        #expect(approx(solution.sourceRect.minX, 0))
        #expect(approx(solution.sourceRect.width, 1))
        #expect(approx(solution.sourceRect.minY, (1 - 900.0 / 1600.0) / 2))
        #expect(approx(solution.sourceRect.height, 900.0 / 1600.0))
    }

    // 6. Zoom halves the visible window and is clamped / sanitized.
    @Test func zoomScalesVisibleWindowAndIsClamped() {
        let source = CGSize(width: 1600, height: 900)
        let frame = CGSize(width: 1600, height: 900)
        let one = ThumbnailImageGeometry.solve(sourceSize: source, frameSize: frame, recipe: .fillCentered)
        let two = ThumbnailImageGeometry.solve(
            sourceSize: source, frameSize: frame, recipe: ThumbnailImageFrameRecipe(fit: .fill, zoom: 2)
        )
        #expect(approx(two.sourceRect.width, one.sourceRect.width / 2))
        #expect(approx(two.sourceRect.height, one.sourceRect.height / 2))
        #expect(approx(two.sourceRect.midX, 0.5))

        for (input, expected) in [(0.1, 1.0), (-3, 1.0), (99, 8.0), (.nan, 1.0), (.infinity, 1.0)] as [(Double, Double)] {
            let recipe = ThumbnailImageFrameRecipe(fit: .fill, focusX: input, focusY: input, zoom: input)
            #expect(recipe.zoom == expected)
            #expect(recipe.focusX.isFinite && (0...1).contains(recipe.focusX))
            #expect(isFinite(ThumbnailImageGeometry.solve(sourceSize: source, frameSize: frame, recipe: recipe)))
        }
    }

    // 7. Degenerate inputs never divide by zero or emit NaN.
    @Test func degenerateInputsReturnFiniteUnitSolutions() {
        let bad: [CGSize] = [
            .zero,
            CGSize(width: -10, height: 20),
            CGSize(width: CGFloat.nan, height: 10),
            CGSize(width: CGFloat.infinity, height: 10),
            CGSize(width: 10, height: 0),
        ]
        let good = CGSize(width: 100, height: 50)
        for size in bad {
            for recipe in Self.recipes {
                let asSource = ThumbnailImageGeometry.solve(sourceSize: size, frameSize: good, recipe: recipe)
                let asFrame = ThumbnailImageGeometry.solve(sourceSize: good, frameSize: size, recipe: recipe)
                #expect(isFinite(asSource))
                #expect(isFinite(asFrame))
                #expect(asSource.sourceRect == ThumbnailImageGeometry.unitRect)
                #expect(asFrame.sourceRect == ThumbnailImageGeometry.unitRect)
            }
        }
    }

    // 8. EXIF-rotated images frame from their display-oriented size.
    @Test(arguments: [UIImage.Orientation.right, .down, .leftMirrored, .upMirrored])
    func orientedImagesSolveFromDisplaySize(orientation: UIImage.Orientation) throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let base = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 10), format: format).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 10))
        }
        let cgImage = try #require(base.cgImage)
        let oriented = UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
        let recipe = ThumbnailImageFrameRecipe(fit: .fill, focusX: 0.3, focusY: 0.7, zoom: 1.5)
        let frame = CGSize(width: 1024, height: 576)
        let normalizedTwin = UIGraphicsImageRenderer(size: oriented.size, format: format).image { _ in
            oriented.draw(in: CGRect(origin: .zero, size: oriented.size))
        }
        #expect(
            ThumbnailImageGeometry.solve(sourceSize: oriented.size, frameSize: frame, recipe: recipe)
                == ThumbnailImageGeometry.solve(sourceSize: normalizedTwin.size, frameSize: frame, recipe: recipe)
        )
    }

    // 9. Gesture math.
    @Test func panAndPinchProduceClampedRecipes() {
        let source = CGSize(width: 1000, height: 1000)
        let frame = CGSize(width: 400, height: 225)
        let base = ThumbnailImageFrameRecipe(fit: .fill, zoom: 1)

        let unchanged = ThumbnailImageFrameRecipe.applying(
            panTranslation: .zero, magnification: 1, to: base, sourceSize: source, frameSize: frame
        )
        #expect(unchanged == base)

        // Render is 400x400; a +40pt drag moves the focal back by 40/400 = 0.1.
        // Horizontally the image exactly fits the frame, so the visible
        // window cannot move even though the focal point is recorded.
        let panned = ThumbnailImageFrameRecipe.applying(
            panTranslation: CGSize(width: 40, height: 0), magnification: 1, to: base, sourceSize: source, frameSize: frame
        )
        #expect(approx(CGFloat(panned.focusX), 0.4))
        #expect(approx(
            ThumbnailImageGeometry.solve(sourceSize: source, frameSize: frame, recipe: panned).sourceRect,
            ThumbnailImageGeometry.solve(sourceSize: source, frameSize: frame, recipe: base).sourceRect
        ))
        let pannedVertically = ThumbnailImageFrameRecipe.applying(
            panTranslation: CGSize(width: 0, height: 40), magnification: 1, to: base, sourceSize: source, frameSize: frame
        )
        #expect(approx(CGFloat(pannedVertically.focusY), 0.4))

        let zoomed = ThumbnailImageFrameRecipe.applying(
            panTranslation: .zero, magnification: 2, to: base, sourceSize: source, frameSize: frame
        )
        #expect(zoomed.zoom == 2)
        let zoomedPan = ThumbnailImageFrameRecipe.applying(
            panTranslation: CGSize(width: 40, height: 0), magnification: 1, to: zoomed, sourceSize: source, frameSize: frame
        )
        #expect(approx(CGFloat(zoomedPan.focusX), 0.45))

        // Huge drags clamp to the edge where the window meets the image edge.
        let farDrag = ThumbnailImageFrameRecipe.applying(
            panTranslation: CGSize(width: 0, height: 100_000), magnification: 100, to: base, sourceSize: source, frameSize: frame
        )
        #expect(farDrag.zoom == 8)
        let edge = ThumbnailImageGeometry.solve(sourceSize: source, frameSize: frame, recipe: farDrag)
        #expect(approx(edge.sourceRect.minY, 0))
        #expect(approx(CGFloat(farDrag.focusY), edge.sourceRect.height / 2))

        let garbage = ThumbnailImageFrameRecipe.applying(
            panTranslation: CGSize(width: CGFloat.nan, height: .infinity), magnification: .nan,
            to: base, sourceSize: source, frameSize: frame
        )
        #expect(garbage.focusX.isFinite && garbage.focusY.isFinite && garbage.zoom == 1)
    }
}
