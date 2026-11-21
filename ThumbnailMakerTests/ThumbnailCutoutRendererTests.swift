//
//  ThumbnailCutoutRendererTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-11: pixel correctness of the cutout renderer and the canvas cache.
//

import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ThumbnailCutoutRendererTests {
    private static func gradientFixture(width: Int = 8, height: Int = 8) -> UIImage {
        CutoutFixtures.image(width: width, height: height) { x, y in
            (UInt8((20 + x * 25) % 256), UInt8((30 + y * 25) % 256), 180, 255)
        }
    }

    @Test func identityMaskReturnsTheSourceImageUnchanged() throws {
        let image = Self.gradientFixture()
        #expect(try ThumbnailCutoutMaskRenderer.composited(image, mask: nil) === image)
        #expect(try ThumbnailCutoutMaskRenderer.composited(image, mask: .empty) === image)

        var disabled = ThumbnailCutoutMask()
        disabled.appendStroke(ThumbnailCutoutStroke(mode: .erase, points: [ThumbnailCutoutPoint(x: 0.5, y: 0.5)], radius: 0.3))
        disabled.isEnabled = false
        #expect(try ThumbnailCutoutMaskRenderer.composited(image, mask: disabled) === image)
    }

    @Test func erasedRegionBecomesTransparentAndUntouchedRegionKeepsOriginalPixels() throws {
        let image = Self.gradientFixture()
        let original = CutoutFixtures.rgba(image)
        var mask = ThumbnailCutoutMask(sourcePixelWidth: 8, sourcePixelHeight: 8)
        // A hard vertical stroke down the left edge, TOP HALF ONLY (asymmetric
        // on purpose: it pins the top-left origin convention).
        mask.appendStroke(ThumbnailCutoutStroke(
            mode: .erase,
            points: [ThumbnailCutoutPoint(x: 0.125, y: 0), ThumbnailCutoutPoint(x: 0.125, y: 0.25)],
            radius: 0.25,
            softness: 0
        ))
        let result = CutoutFixtures.rgba(try ThumbnailCutoutMaskRenderer.composited(image, mask: mask))

        for y in 0...2 {
            for x in 0...1 {
                #expect(CutoutFixtures.alpha(result, x: x, y: y) == 0, "(\(x),\(y)) should be erased")
            }
        }
        // Bottom-left is untouched: the stroke is not flipped vertically.
        for y in 6...7 {
            for x in 0...1 {
                #expect(CutoutFixtures.pixel(result, x: x, y: y) == CutoutFixtures.pixel(original, x: x, y: y))
            }
        }
        // The right half is byte-identical to the source.
        for y in 0..<8 {
            for x in 4..<8 {
                #expect(CutoutFixtures.pixel(result, x: x, y: y) == CutoutFixtures.pixel(original, x: x, y: y))
            }
        }
    }

    @Test func restoreStrokeRecoversOriginalPixelsAfterErase() throws {
        let image = Self.gradientFixture(width: 32, height: 32)
        let original = CutoutFixtures.rgba(image)
        var mask = ThumbnailCutoutMask(sourcePixelWidth: 32, sourcePixelHeight: 32)
        mask.appendStroke(ThumbnailCutoutStroke(mode: .erase, points: [ThumbnailCutoutPoint(x: 0.5, y: 0.5)], radius: 0.2, softness: 0.3))
        let erased = CutoutFixtures.rgba(try ThumbnailCutoutMaskRenderer.composited(image, mask: mask))
        #expect(CutoutFixtures.alpha(erased, x: 16, y: 16) == 0)

        // Restore over (and beyond) the erased area brings back the original bytes.
        mask.appendStroke(ThumbnailCutoutStroke(mode: .restore, points: [ThumbnailCutoutPoint(x: 0.5, y: 0.5)], radius: 0.3, softness: 0))
        let restored = CutoutFixtures.rgba(try ThumbnailCutoutMaskRenderer.composited(image, mask: mask))
        var maxDelta = 0
        for index in restored.bytes.indices {
            maxDelta = max(maxDelta, abs(Int(restored.bytes[index]) - Int(original.bytes[index])))
        }
        #expect(maxDelta <= 1, "max channel delta \(maxDelta)")
    }

    @Test func partialSourceAlphaSurvivesMasking() throws {
        let alphas: [UInt8] = [0, 64, 128, 255]
        let image = CutoutFixtures.image(width: 4, height: 1) { x, _ in (255, 255, 255, alphas[x]) }

        // Full-white base: alphas unchanged (multiply, not replace).
        var white = ThumbnailCutoutMask()
        white.automaticBase = try CutoutFixtures.uniformBase(value: 255, sourceWidth: 4, sourceHeight: 1)
        let kept = CutoutFixtures.rgba(try ThumbnailCutoutMaskRenderer.composited(image, mask: white))
        for x in 0..<4 {
            #expect(abs(CutoutFixtures.alpha(kept, x: x, y: 0) - Int(alphas[x])) <= 1)
        }

        // Uniform 50% gray base: every alpha halves.
        var half = ThumbnailCutoutMask()
        half.automaticBase = try CutoutFixtures.uniformBase(value: 128, sourceWidth: 4, sourceHeight: 1)
        let halved = CutoutFixtures.rgba(try ThumbnailCutoutMaskRenderer.composited(image, mask: half))
        for x in 0..<4 {
            let expected = Int(alphas[x]) * 128 / 255
            #expect(abs(CutoutFixtures.alpha(halved, x: x, y: 0) - expected) <= 2, "x=\(x)")
        }
    }

    @Test func softStrokeProducesIntermediateAlphaAtItsEdge() throws {
        let image = CutoutFixtures.solidImage(width: 64, height: 64)
        func alphaAtNinetyPercentRadius(softness: Double) throws -> Int {
            var mask = ThumbnailCutoutMask()
            mask.appendStroke(ThumbnailCutoutStroke(
                mode: .erase,
                points: [ThumbnailCutoutPoint(x: 0.5, y: 0.5)],
                radius: 0.3,
                softness: softness
            ))
            let pixels = CutoutFixtures.rgba(try ThumbnailCutoutMaskRenderer.composited(image, mask: mask))
            // Centre (32, 32); radius 0.3 * 64 = 19.2px; 0.9r ≈ 17px.
            return CutoutFixtures.alpha(pixels, x: 32 + 17, y: 32)
        }
        let soft = try alphaAtNinetyPercentRadius(softness: 0.6)
        #expect(soft > 0 && soft < 255, "soft edge alpha \(soft)")
        let hard = try alphaAtNinetyPercentRadius(softness: 0)
        #expect(hard == 0, "hard edge alpha \(hard)")
    }

    @Test func featherDoesNotDarkenTheImageBorder() throws {
        var mask = ThumbnailCutoutMask()
        mask.feather = 0.05
        let raster = try ThumbnailCutoutMaskRenderer.rasterizedAlpha(mask, pixelWidth: 64, pixelHeight: 48)
        let gray = CutoutFixtures.gray(raster)
        for (x, y) in [(0, 0), (63, 0), (0, 47), (63, 47)] {
            #expect(gray[y * 64 + x] >= 254, "corner (\(x),\(y)) = \(gray[y * 64 + x])")
        }

        // And the feather really softens an erase edge.
        mask.appendStroke(ThumbnailCutoutStroke(mode: .erase, points: [ThumbnailCutoutPoint(x: 0, y: 0.5), ThumbnailCutoutPoint(x: 0.5, y: 0.5)], radius: 0.5, softness: 0))
        let hardEdge = CutoutFixtures.gray(try ThumbnailCutoutMaskRenderer.rasterizedAlpha(
            ThumbnailCutoutMask(strokes: mask.strokes), pixelWidth: 64, pixelHeight: 48
        ))
        let softEdge = CutoutFixtures.gray(try ThumbnailCutoutMaskRenderer.rasterizedAlpha(mask, pixelWidth: 64, pixelHeight: 48))
        let hardIntermediates = hardEdge.filter { $0 > 10 && $0 < 245 }.count
        let softIntermediates = softEdge.filter { $0 > 10 && $0 < 245 }.count
        #expect(softIntermediates > hardIntermediates)
    }

    @Test func previewAndFullResolutionAgreeOnCoverage() throws {
        var mask = ThumbnailCutoutMask()
        mask.appendStroke(ThumbnailCutoutStroke(
            mode: .erase,
            points: [ThumbnailCutoutPoint(x: 0.1, y: 0.2), ThumbnailCutoutPoint(x: 0.6, y: 0.7), ThumbnailCutoutPoint(x: 0.9, y: 0.3)],
            radius: 0.08,
            softness: 0.2
        ))
        mask.appendStroke(ThumbnailCutoutStroke(mode: .restore, points: [ThumbnailCutoutPoint(x: 0.6, y: 0.7)], radius: 0.05))
        mask.feather = 0.01

        func keptFraction(_ size: Int) throws -> Double {
            let gray = CutoutFixtures.gray(try ThumbnailCutoutMaskRenderer.rasterizedAlpha(mask, pixelWidth: size, pixelHeight: size * 3 / 4))
            return Double(gray.filter { $0 > 127 }.count) / Double(gray.count)
        }
        let preview = try keptFraction(128)
        let full = try keptFraction(1024)
        #expect(abs(preview - full) < 0.02, "preview \(preview) vs full \(full)")
    }

    @Test func resolveIsBoundedByMaxDimension() throws {
        let image = CutoutFixtures.solidImage(width: 2000, height: 1500)
        var mask = ThumbnailCutoutMask(sourcePixelWidth: 2000, sourcePixelHeight: 1500)
        mask.appendStroke(ThumbnailCutoutStroke(mode: .erase, points: [ThumbnailCutoutPoint(x: 0.5, y: 0.5)], radius: 0.1))

        let bounded = try ThumbnailCutoutMaskRenderer.composited(image, mask: mask, maxDimension: 512)
        #expect(max(bounded.size.width * bounded.scale, bounded.size.height * bounded.scale) <= 512)
        let native = try ThumbnailCutoutMaskRenderer.composited(image, mask: mask)
        #expect(native.size.width * native.scale == 2000)
        #expect(native.size.height * native.scale == 1500)
    }

    @Test func incompatibleRecipeRendersTheOriginal() throws {
        let image = Self.gradientFixture()
        var mask = ThumbnailCutoutMask(sourcePixelWidth: 100, sourcePixelHeight: 50)
        mask.appendStroke(ThumbnailCutoutStroke(mode: .erase, points: [ThumbnailCutoutPoint(x: 0.5, y: 0.5)], radius: 0.4))
        #expect(!ThumbnailCutoutMaskRenderer.shouldRender(mask, for: image))
        #expect(try ThumbnailCutoutMaskRenderer.composited(image, mask: mask) === image)

        var staleBase = ThumbnailCutoutMask()
        staleBase.automaticBase = try CutoutFixtures.uniformBase(value: 0, sourceWidth: 9, sourceHeight: 9)
        #expect(try ThumbnailCutoutMaskRenderer.composited(image, mask: staleBase) === image)
    }

    @Test func automaticBaseIsLiftedFromACutoutImagesAlpha() throws {
        // Left half opaque, right half transparent, at a different size than the source.
        let cutout = CutoutFixtures.image(width: 10, height: 10) { x, _ in (255, 0, 0, x < 5 ? 255 : 0) }
        let base = try ThumbnailCutoutMaskRenderer.automaticBase(fromCutoutImage: cutout, sourcePixelWidth: 40, sourcePixelHeight: 40)
        #expect(base.sourcePixelWidth == 40 && base.sourcePixelHeight == 40)
        #expect(base.pixelWidth == 40 && base.pixelHeight == 40)
        let raster = try #require(ThumbnailCutoutMaskRenderer.decodeMaskPNG(base.maskPNGData))
        let gray = CutoutFixtures.gray(raster)
        #expect(gray[20 * 40 + 2] > 240)
        #expect(gray[20 * 40 + 37] < 15)
    }

    @Test func automaticBaseIsBoundedForLargeSources() throws {
        let base = try CutoutFixtures.uniformBase(value: 255, sourceWidth: 6000, sourceHeight: 3000)
        #expect(max(base.pixelWidth, base.pixelHeight) <= Int(ThumbnailCutoutMask.maxAutomaticMaskDimension))
        #expect(base.sourcePixelWidth == 6000)
    }

    @Test func undecodableBaseSurfacesAnErrorAndTheCacheFallsBackToTheOriginal() throws {
        let image = Self.gradientFixture()
        var mask = ThumbnailCutoutMask()
        mask.automaticBase = ThumbnailCutoutAutomaticBase(
            maskPNGData: Data([1, 2, 3]),
            pixelWidth: 8,
            pixelHeight: 8,
            sourcePixelWidth: 8,
            sourcePixelHeight: 8
        )
        #expect(throws: ThumbnailCutoutRenderError.maskDecodeFailed) {
            _ = try ThumbnailCutoutMaskRenderer.composited(image, mask: mask)
        }
        let cache = ThumbnailCutoutImageCache()
        let resolved = cache.resolvedImage(image: image, identity: "base", mask: mask)
        #expect(resolved === image)
        #expect(cache.metrics.failures == 1)
    }

    @Test func cacheHitsOnAnUnchangedRecipeAndMissesAfterAStroke() throws {
        let cache = ThumbnailCutoutImageCache()
        let data = try #require(CutoutFixtures.solidPNG(width: 16, height: 16))
        var mask = ThumbnailCutoutMask(sourcePixelWidth: 16, sourcePixelHeight: 16)
        mask.appendStroke(ThumbnailCutoutStroke(mode: .erase, points: [ThumbnailCutoutPoint(x: 0.5, y: 0.5)], radius: 0.2))

        _ = cache.resolvedImage(imageData: data, identity: "layer-a", mask: mask)
        #expect(cache.metrics.resolveCount == 1)
        #expect(cache.metrics.cacheHits == 0)
        _ = cache.resolvedImage(imageData: data, identity: "layer-a", mask: mask)
        #expect(cache.metrics.resolveCount == 1)
        #expect(cache.metrics.cacheHits == 1)

        mask.appendStroke(ThumbnailCutoutStroke(mode: .erase, points: [ThumbnailCutoutPoint(x: 0.1, y: 0.1)], radius: 0.1))
        _ = cache.resolvedImage(imageData: data, identity: "layer-a", mask: mask)
        #expect(cache.metrics.resolveCount == 2)

        // A duplicated layer with an identical recipe has its own entry.
        _ = cache.resolvedImage(imageData: data, identity: "layer-b", mask: mask)
        #expect(cache.metrics.resolveCount == 3)

        // No recipe: no work, no cache entry — just the decoded original.
        let plain = cache.resolvedImage(imageData: data, identity: "layer-c", mask: nil)
        #expect(plain != nil)
        #expect(cache.metrics.resolveCount == 3)

        // Different photo bytes under the same layer id never hit a stale entry.
        let other = try #require(CutoutFixtures.solidPNG(width: 16, height: 16, color: .blue))
        _ = cache.resolvedImage(imageData: other, identity: "layer-a", mask: mask)
        #expect(cache.metrics.resolveCount == 4)
    }

    @Test func baseImageCacheIsKeyedPerImageInstance() throws {
        let cache = ThumbnailCutoutImageCache()
        let first = CutoutFixtures.solidImage(width: 8, height: 8, color: .red)
        let second = CutoutFixtures.solidImage(width: 8, height: 8, color: .green)
        var mask = ThumbnailCutoutMask()
        mask.appendStroke(ThumbnailCutoutStroke(mode: .erase, points: [ThumbnailCutoutPoint(x: 0.5, y: 0.5)], radius: 0.2))

        _ = cache.resolvedImage(image: first, identity: "background", mask: mask)
        _ = cache.resolvedImage(image: first, identity: "background", mask: mask)
        #expect(cache.metrics.cacheHits == 1)
        let resolvedSecond = cache.resolvedImage(image: second, identity: "background", mask: mask)
        #expect(cache.metrics.resolveCount == 2)
        let pixels = CutoutFixtures.rgba(resolvedSecond)
        #expect(pixels.bytes[1] > 100, "The second photo's own pixels are rendered (green channel).")
    }
}
