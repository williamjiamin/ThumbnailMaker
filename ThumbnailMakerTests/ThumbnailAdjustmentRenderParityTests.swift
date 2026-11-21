//
//  ThumbnailAdjustmentRenderParityTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-14: renders through SwiftUI ImageRenderer (the export path) to
//  pin identity, compare, cutout alpha and preview/export parity.
//

import SwiftUI
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ThumbnailAdjustmentRenderParityTests {
    private let recipe = ThumbnailImageAdjustments(brightness: 0.15, contrast: 1.3, saturation: 1.4, blur: 0.03, vignette: 0.5)

    struct Bitmap: Equatable {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            let i = (y * width + x) * 4
            return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]), Int(bytes[i + 3]))
        }

        func meanAbsoluteDifference(to other: Bitmap) -> Double {
            precondition(width == other.width && height == other.height)
            var total = 0
            for index in bytes.indices {
                total += abs(Int(bytes[index]) - Int(other.bytes[index]))
            }
            return Double(total) / Double(bytes.count)
        }
    }

    @Test func neutralAdjustmentsRenderIdenticallyToNoAdjustments() throws {
        let plain = try render(configuration(adjustments: nil), size: CGSize(width: 160, height: 90))
        let neutral = try render(configuration(adjustments: .neutral), size: CGSize(width: 160, height: 90))
        #expect(plain == neutral)

        let adjusted = try render(configuration(adjustments: recipe), size: CGSize(width: 160, height: 90))
        #expect(adjusted.meanAbsoluteDifference(to: plain) > 4, "A non-trivial recipe must visibly change the render.")
    }

    @Test func compareShowsTheOriginalAndExportDefaultsToAdjusted() throws {
        let size = CGSize(width: 160, height: 90)
        let plain = try render(configuration(adjustments: nil), size: size)
        let adjusted = try render(configuration(adjustments: recipe), size: size)
        let comparing = try render(configuration(adjustments: recipe), size: size, showsOriginal: true)
        #expect(comparing == plain)
        #expect(adjusted != plain)
        #expect(EnvironmentValues().thumbnailShowsOriginalAdjustments == false, "Export views must never show the before state.")
    }

    @Test func adjustmentIntensityMatchesBetweenPreviewAndExportSize() throws {
        let small = CGSize(width: 160, height: 90)
        let large = CGSize(width: 640, height: 360)

        let neutralSmall = try render(configuration(adjustments: nil), size: small)
        let neutralLarge = try downscale(render(configuration(adjustments: nil), size: large), to: small)
        let adjustedSmall = try render(configuration(adjustments: recipe), size: small)
        let adjustedLarge = try downscale(render(configuration(adjustments: recipe), size: large), to: small)

        let baselineGap = neutralSmall.meanAbsoluteDifference(to: neutralLarge)
        let adjustedGap = adjustedSmall.meanAbsoluteDifference(to: adjustedLarge)
        let effect = adjustedSmall.meanAbsoluteDifference(to: neutralSmall)
        #expect(effect > 4)
        #expect(adjustedGap <= baselineGap + 6, "Scaling the canvas changed the look: gap \(adjustedGap) vs baseline \(baselineGap), effect \(effect)")
    }

    @Test func adjustmentsPreserveTransparentPixelsOfACutout() throws {
        let cutout = makeCutout()
        let heavy = ThumbnailImageAdjustments(brightness: 0.35, contrast: 1.6, saturation: 2, blur: 0.02, vignette: 1)
        let size = CGSize(width: 64, height: 64)
        let view = Image(uiImage: cutout)
            .resizable()
            .frame(width: size.width, height: size.height)
            .thumbnailAdjustments(heavy, renderedSize: size)
            .frame(width: size.width, height: size.height)
        let bitmap = try render(view)
        #expect(bitmap.width == 64)

        for y in 0..<64 {
            for x in 0..<32 {
                #expect(bitmap.pixel(x, y).a == 0, "Transparent pixel (\(x), \(y)) was painted")
            }
        }
        let inside = bitmap.pixel(48, 32)
        #expect(inside.a == 255)
        #expect(inside.r > 150, "The opaque half still renders")
    }

    @Test func premiumProfileAndContentLayersRenderTheirRecipes() throws {
        let size = CGSize(width: 160, height: 90)
        var configuration = PremiumMakerConfigurationModel()
        configuration.backgroundColor = .white
        configuration.circularProfile = CircularProfileConfig(image: makeGradient(), size: 0.4)
        configuration.layers = configuration.layers.reconciledForCurrentOverlays(hasText: false, hasProfile: true)
        let layerID = configuration.layers.addImageLayer(imageData: try #require(makeGradient().pngData()), size: 0.5)
        let plain = try render(PremiumPreviewComponentView(
            premiumMakerConfiguration: .constant(configuration), width: size.width, height: size.height
        ), proposed: size)

        var profileAdjusted = configuration
        profileAdjusted.layers.setAdjustments(ThumbnailImageAdjustments(saturation: 0), forLayerID: ThumbnailDocumentLayer.profileID)
        let profileRender = try render(PremiumPreviewComponentView(
            premiumMakerConfiguration: .constant(profileAdjusted), width: size.width, height: size.height
        ), proposed: size)
        #expect(profileRender != plain)

        var layerAdjusted = configuration
        layerAdjusted.layers.setAdjustments(ThumbnailImageAdjustments(saturation: 0), forLayerID: layerID)
        let layerRender = try render(PremiumPreviewComponentView(
            premiumMakerConfiguration: .constant(layerAdjusted), width: size.width, height: size.height
        ), proposed: size)
        #expect(layerRender != plain)
        #expect(layerRender != profileRender)
    }

    // MARK: Helpers

    private func configuration(adjustments: ThumbnailImageAdjustments?) -> SimpleMakerConfigurationModel {
        var configuration = SimpleMakerConfigurationModel()
        configuration.backgroundColor = .white
        configuration.selectedImage = makeGradient()
        configuration.imageRecipe = ThumbnailImageFrameRecipe(fit: .fill)
        if let adjustments {
            // Write directly (bypassing normalisation) so a stored neutral value is exercised too.
            if let index = configuration.layers.firstIndex(where: { $0.id == ThumbnailDocumentLayer.backgroundID }) {
                configuration.layers[index].adjustments = adjustments
            }
        }
        return configuration
    }

    private func render(
        _ configuration: SimpleMakerConfigurationModel,
        size: CGSize,
        showsOriginal: Bool = false
    ) throws -> Bitmap {
        try render(
            PreviewComponentView(
                simpleMakerConfiguration: .constant(configuration),
                width: size.width,
                height: size.height
            )
            .environment(\.thumbnailShowsOriginalAdjustments, showsOriginal),
            proposed: size
        )
    }

    private func render<V: View>(_ view: V, proposed: CGSize? = nil) throws -> Bitmap {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        if let proposed {
            renderer.proposedSize = ProposedViewSize(proposed)
        }
        renderer.scale = 1
        renderer.colorMode = .nonLinear
        return try bitmap(#require(renderer.cgImage))
    }

    private func downscale(_ bitmap: Bitmap, to size: CGSize) throws -> Bitmap {
        let provider = try #require(CGDataProvider(data: Data(bitmap.bytes) as CFData))
        let image = try #require(CGImage(
            width: bitmap.width, height: bitmap.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        ))
        let width = Int(size.width)
        let height = Int(size.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return Bitmap(width: width, height: height, bytes: bytes)
    }

    private func bitmap(_ cgImage: CGImage) throws -> Bitmap {
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        #expect(drawn)
        return Bitmap(width: width, height: height, bytes: bytes)
    }

    /// Smooth colour gradient: downscaling it is well behaved, so any
    /// preview/export gap comes from the recipe, not from aliasing.
    private func makeGradient() -> UIImage {
        let size = CGSize(width: 320, height: 180)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let colors = [UIColor.systemTeal.cgColor, UIColor.systemOrange.cgColor, UIColor.systemPurple.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }
    }

    /// Left half fully transparent, right half opaque red.
    private func makeCutout() -> UIImage {
        let size = CGSize(width: 64, height: 64)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 32, y: 0, width: 32, height: 64))
        }
    }
}
