//
//  ThumbnailCutoutMaskRenderer.swift
//  ThumbnailMaker
//
//  FEATURE-11: turns a `ThumbnailCutoutMask` recipe into pixels.
//
//  - `rasterizedAlpha` builds an 8-bit gray mask (white = keep): the automatic
//    base (or solid white), then every stroke stamped as radial-gradient dabs,
//    then ONE feather blur over the whole mask (clamped before the blur and
//    cropped after, so the border never erodes).
//  - `composited` clips the source through that mask. CoreGraphics clip-to-
//    mask MULTIPLIES into the source alpha, so pre-existing partial alpha
//    survives (the mask never replaces it).
//  - `ThumbnailCutoutImageCache` is the canvas resolver. It is SYNCHRONOUS by
//    design: ThumbnailExporter renders the same SwiftUI tree with
//    ImageRenderer in one pass, so an async resolver would export the
//    unmasked image.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum ThumbnailCutoutRenderError: LocalizedError, Equatable {
    case missingCGImage
    case maskDecodeFailed
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .missingCGImage:
            return "The image could not be read for the cutout."
        case .maskDecodeFailed:
            return "The saved cutout mask could not be read."
        case .renderFailed:
            return "Could not render the cutout."
        }
    }
}

enum ThumbnailCutoutMaskRenderer {
    static let previewMaxDimension: CGFloat = 1024
    /// Dab spacing as a fraction of the brush radius.
    static let dabSpacing: CGFloat = 0.35

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    // MARK: Geometry

    /// Pixel size of `image` as displayed (orientation applied).
    static func displayPixelSize(of image: UIImage) -> (width: Int, height: Int) {
        (
            Int((image.size.width * image.scale).rounded()),
            Int((image.size.height * image.scale).rounded())
        )
    }

    static func outputPixelSize(sourceWidth: Int, sourceHeight: Int, maxDimension: CGFloat?) -> (width: Int, height: Int) {
        guard let maxDimension, maxDimension > 0 else { return (sourceWidth, sourceHeight) }
        let longSide = CGFloat(max(sourceWidth, sourceHeight))
        guard longSide > maxDimension else { return (sourceWidth, sourceHeight) }
        let factor = maxDimension / longSide
        return (
            max(1, Int((CGFloat(sourceWidth) * factor).rounded(.down))),
            max(1, Int((CGFloat(sourceHeight) * factor).rounded(.down)))
        )
    }

    /// Whether the recipe would change pixels for this image at all.
    static func shouldRender(_ mask: ThumbnailCutoutMask?, for image: UIImage) -> Bool {
        guard let mask, mask.isActive else { return false }
        let size = displayPixelSize(of: image)
        return mask.isCompatible(withSourcePixelWidth: size.width, height: size.height)
    }

    // MARK: Mask raster

    static func rasterizedAlpha(_ mask: ThumbnailCutoutMask, pixelWidth: Int, pixelHeight: Int) throws -> CGImage {
        guard pixelWidth > 0, pixelHeight > 0,
              let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else {
            throw ThumbnailCutoutRenderError.renderFailed
        }

        let fullRect = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        context.interpolationQuality = .high
        if let base = mask.automaticBase {
            guard let baseImage = decodeMaskPNG(base.maskPNGData) else {
                throw ThumbnailCutoutRenderError.maskDecodeFailed
            }
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(fullRect)
            context.draw(baseImage, in: fullRect)
        } else {
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(fullRect)
        }

        // Strokes are in top-left normalized space.
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: 1, y: -1)
        let longSide = CGFloat(max(pixelWidth, pixelHeight))
        for stroke in mask.strokes {
            stamp(stroke, in: context, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight), longSide: longSide)
        }

        guard let raster = context.makeImage() else {
            throw ThumbnailCutoutRenderError.renderFailed
        }
        guard mask.feather > 0 else { return raster }
        return try feathered(raster, sigma: CGFloat(mask.feather) * longSide)
    }

    private static func stamp(
        _ stroke: ThumbnailCutoutStroke,
        in context: CGContext,
        width: CGFloat,
        height: CGFloat,
        longSide: CGFloat
    ) {
        let radius = max(0.5, CGFloat(stroke.radius) * longSide)
        let value: CGFloat = stroke.mode == .erase ? 0 : 1
        let opacity = CGFloat(stroke.opacity)
        guard opacity > 0 else { return }
        let softness = CGFloat(stroke.softness)
        let core = max(0, min(1, 1 - softness))

        let gradient: CGGradient? = softness > 0
            ? CGGradient(
                colorSpace: CGColorSpaceCreateDeviceGray(),
                colorComponents: [value, opacity, value, opacity, value, 0],
                locations: [0, core, 1],
                count: 3
            )
            : nil

        func dab(at point: CGPoint) {
            if let gradient {
                context.drawRadialGradient(
                    gradient,
                    startCenter: point,
                    startRadius: 0,
                    endCenter: point,
                    endRadius: radius,
                    options: []
                )
            } else {
                context.setFillColor(gray: value, alpha: opacity)
                context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            }
        }

        let points = stroke.points.map { CGPoint(x: CGFloat($0.x) * width, y: CGFloat($0.y) * height) }
        guard let first = points.first else { return }
        dab(at: first)
        let spacing = max(0.5, radius * dabSpacing)
        var previous = first
        var carried: CGFloat = 0
        for point in points.dropFirst() {
            let dx = point.x - previous.x
            let dy = point.y - previous.y
            let distance = hypot(dx, dy)
            guard distance > 0 else { continue }
            var travelled = spacing - carried
            while travelled <= distance {
                let t = travelled / distance
                dab(at: CGPoint(x: previous.x + dx * t, y: previous.y + dy * t))
                travelled += spacing
            }
            carried = distance - (travelled - spacing)
            previous = point
        }
        if points.count > 1, let last = points.last, carried > 0.01 {
            dab(at: last)
        }
    }

    private static func feathered(_ raster: CGImage, sigma: CGFloat) throws -> CGImage {
        let input = CIImage(cgImage: raster)
        let extent = input.extent
        // Clamp BEFORE the blur and crop AFTER it; otherwise the transparent
        // outside bleeds in and the whole border darkens into a halo.
        let blurred = input
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(max(0, sigma)))
            .cropped(to: extent)
        guard let output = ciContext.createCGImage(
            blurred,
            from: extent,
            format: .L8,
            colorSpace: CGColorSpaceCreateDeviceGray()
        ) else {
            throw ThumbnailCutoutRenderError.renderFailed
        }
        return output
    }

    // MARK: Composite

    /// Returns `image` itself (no re-encode) when there is nothing to do.
    /// `requireCompatibleSource: false` is only for the refinement sheet,
    /// which works on a downscaled copy of the (already matched) photo.
    static func composited(
        _ image: UIImage,
        mask: ThumbnailCutoutMask?,
        maxDimension: CGFloat? = nil,
        requireCompatibleSource: Bool = true
    ) throws -> UIImage {
        let applies: Bool = {
            guard let mask, mask.isActive else { return false }
            return requireCompatibleSource ? shouldRender(mask, for: image) : true
        }()
        let needsResize: Bool = {
            guard let maxDimension else { return false }
            let size = displayPixelSize(of: image)
            return CGFloat(max(size.width, size.height)) > maxDimension
        }()
        guard applies || needsResize else { return image }

        guard let source = uprightCGImage(of: image) else {
            throw ThumbnailCutoutRenderError.missingCGImage
        }
        let output = outputPixelSize(sourceWidth: source.width, sourceHeight: source.height, maxDimension: maxDimension)
        let colorSpace = (source.colorSpace?.model == .rgb ? source.colorSpace : nil)
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: output.width,
            height: output.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) ?? CGContext(
            data: nil,
            width: output.width,
            height: output.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ThumbnailCutoutRenderError.renderFailed
        }

        let rect = CGRect(x: 0, y: 0, width: output.width, height: output.height)
        context.interpolationQuality = .high
        if applies, let mask {
            let alpha = try rasterizedAlpha(mask, pixelWidth: output.width, pixelHeight: output.height)
            context.clip(to: rect, mask: alpha)
        }
        context.draw(source, in: rect)

        guard let result = context.makeImage() else {
            throw ThumbnailCutoutRenderError.renderFailed
        }
        let scale = output.width == source.width ? image.scale : 1
        return UIImage(cgImage: result, scale: scale, orientation: .up)
    }

    /// The source pixels in display orientation.
    static func uprightCGImage(of image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cgImage = image.cgImage {
            return cgImage
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }.cgImage
    }

    // MARK: Automatic base helpers

    static func decodeMaskPNG(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func encodeGrayPNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Redraws any mask-like image (gray, or an RGBA image's alpha) into an
    /// 8-bit gray raster bounded by `maxAutomaticMaskDimension`.
    static func makeAutomaticBase(
        fromGrayMask mask: CGImage,
        sourcePixelWidth: Int,
        sourcePixelHeight: Int
    ) throws -> ThumbnailCutoutAutomaticBase {
        let bounded = outputPixelSize(
            sourceWidth: max(1, sourcePixelWidth),
            sourceHeight: max(1, sourcePixelHeight),
            maxDimension: CGFloat(ThumbnailCutoutMask.maxAutomaticMaskDimension)
        )
        guard let context = CGContext(
            data: nil,
            width: bounded.width,
            height: bounded.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw ThumbnailCutoutRenderError.renderFailed
        }
        context.interpolationQuality = .high
        context.draw(mask, in: CGRect(x: 0, y: 0, width: bounded.width, height: bounded.height))
        guard let gray = context.makeImage(), let png = encodeGrayPNG(gray) else {
            throw ThumbnailCutoutRenderError.renderFailed
        }
        return ThumbnailCutoutAutomaticBase(
            maskPNGData: png,
            pixelWidth: bounded.width,
            pixelHeight: bounded.height,
            sourcePixelWidth: sourcePixelWidth,
            sourcePixelHeight: sourcePixelHeight
        )
    }

    /// Lifts the alpha channel of an already cut-out image into a gray mask
    /// sized for `sourcePixelWidth x sourcePixelHeight`.
    static func automaticBase(
        fromCutoutImage cutout: UIImage,
        sourcePixelWidth: Int,
        sourcePixelHeight: Int
    ) throws -> ThumbnailCutoutAutomaticBase {
        guard let cutoutCG = uprightCGImage(of: cutout) else {
            throw ThumbnailCutoutRenderError.missingCGImage
        }
        let width = cutoutCG.width
        let height = cutoutCG.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drewAlpha: Bool = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cutoutCG, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drewAlpha else { throw ThumbnailCutoutRenderError.renderFailed }
        var alpha = [UInt8](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            alpha[index] = rgba[index * 4 + 3]
        }
        guard let provider = CGDataProvider(data: Data(alpha) as CFData),
              let gray = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw ThumbnailCutoutRenderError.renderFailed
        }
        return try makeAutomaticBase(
            fromGrayMask: gray,
            sourcePixelWidth: sourcePixelWidth,
            sourcePixelHeight: sourcePixelHeight
        )
    }
}

// MARK: - Canvas resolver

@MainActor
final class ThumbnailCutoutImageCache {
    struct Metrics: Equatable {
        var resolveCount = 0
        var cacheHits = 0
        var failures = 0
        var lastResolveSeconds: Double = 0
        var lastPixelCount = 0
    }

    static let shared = ThumbnailCutoutImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private(set) var metrics = Metrics()
    private var memoryWarningObserver: NSObjectProtocol?

    init(totalCostLimit: Int = 96 * 1024 * 1024) {
        cache.totalCostLimit = totalCostLimit
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.removeAll()
            }
        }
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    func resetMetrics() {
        metrics = Metrics()
    }

    /// Content layers: the image bytes are the immutable original.
    /// Returns the decoded original when the recipe is inert, nil only when
    /// the bytes cannot be decoded at all.
    func resolvedImage(
        imageData: Data,
        identity: String,
        mask: ThumbnailCutoutMask?,
        maxDimension: CGFloat? = nil
    ) -> UIImage? {
        guard let mask, mask.isActive else { return UIImage(data: imageData) }
        let key = cacheKey(identity: identity, source: Self.dataToken(imageData), mask: mask, maxDimension: maxDimension)
        if let hit = cache.object(forKey: key) {
            metrics.cacheHits += 1
            return hit
        }
        guard let image = UIImage(data: imageData) else { return nil }
        return render(image, mask: mask, maxDimension: maxDimension, key: key)
    }

    /// Base photo: an in-memory UIImage, identified per instance.
    func resolvedImage(
        image: UIImage,
        identity: String,
        mask: ThumbnailCutoutMask?,
        maxDimension: CGFloat? = nil
    ) -> UIImage {
        guard let mask, mask.isActive else { return image }
        let key = cacheKey(identity: identity, source: image.thumbnailCutoutInstanceToken, mask: mask, maxDimension: maxDimension)
        if let hit = cache.object(forKey: key) {
            metrics.cacheHits += 1
            return hit
        }
        return render(image, mask: mask, maxDimension: maxDimension, key: key) ?? image
    }

    func prewarm(image: UIImage, identity: String, mask: ThumbnailCutoutMask?) {
        _ = resolvedImage(image: image, identity: identity, mask: mask)
    }

    func prewarm(imageData: Data, identity: String, mask: ThumbnailCutoutMask?) {
        _ = resolvedImage(imageData: imageData, identity: identity, mask: mask)
    }

    private func render(_ image: UIImage, mask: ThumbnailCutoutMask, maxDimension: CGFloat?, key: NSString) -> UIImage? {
        let start = CFAbsoluteTimeGetCurrent()
        metrics.resolveCount += 1
        do {
            let result = try ThumbnailCutoutMaskRenderer.composited(image, mask: mask, maxDimension: maxDimension)
            let pixels = Int(result.size.width * result.scale) * Int(result.size.height * result.scale)
            metrics.lastPixelCount = pixels
            metrics.lastResolveSeconds = CFAbsoluteTimeGetCurrent() - start
            cache.setObject(result, forKey: key, cost: pixels * 4)
            return result
        } catch {
            // Never lose the photo: fall back to the untouched original.
            metrics.failures += 1
            return image
        }
    }

    private func cacheKey(identity: String, source: String, mask: ThumbnailCutoutMask, maxDimension: CGFloat?) -> NSString {
        "\(identity)|\(source)|\(mask.fingerprint)|\(Int(maxDimension ?? 0))" as NSString
    }

    /// O(1) identity for image bytes: length plus 64 sampled bytes. Never
    /// hashes the whole payload (this runs on every canvas render pass).
    static func dataToken(_ data: Data) -> String {
        let count = data.count
        guard count > 0 else { return "0" }
        var hasher = Hasher()
        hasher.combine(count)
        let samples = Swift.min(64, count)
        data.withUnsafeBytes { raw in
            for index in 0..<samples {
                let offset = samples == 1 ? 0 : (count - 1) * index / (samples - 1)
                hasher.combine(raw[offset])
            }
        }
        return "\(count)-\(hasher.finalize())"
    }
}

private var thumbnailCutoutInstanceTokenKey: UInt8 = 0

extension UIImage {
    /// A stable per-instance token, so a cached composite can never be served
    /// for a different photo that happens to reuse the same address.
    var thumbnailCutoutInstanceToken: String {
        if let token = objc_getAssociatedObject(self, &thumbnailCutoutInstanceTokenKey) as? String {
            return token
        }
        let token = UUID().uuidString
        objc_setAssociatedObject(self, &thumbnailCutoutInstanceTokenKey, token, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return token
    }
}
