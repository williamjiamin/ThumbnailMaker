//
//  BackgroundRemovalService.swift
//  ThumbnailMaker
//

import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UIKit
import Vision

enum BackgroundRemovalError: LocalizedError, Equatable {
    case missingCGImage
    case foregroundMaskUnavailable
    case foregroundMaskFailed
    case faceNotDetected
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .missingCGImage:
            return "The selected image could not be processed."
        case .foregroundMaskUnavailable:
            return "Background removal is not available on this device."
        case .foregroundMaskFailed:
            return "Could not separate the subject from the background."
        case .faceNotDetected:
            return "Could not find a face in the selected image."
        case .renderFailed:
            return "Could not render the cutout image."
        }
    }
}

struct ThumbnailDetectedFace: Equatable {
    let normalizedBounds: CGRect
    let confidence: Float
}

protocol ThumbnailSubjectProcessing {
    func removeBackground(from image: UIImage) async throws -> UIImage
    func suggestedFaceCrop(in image: UIImage, padding: CGFloat) async throws -> CGRect?
    /// FEATURE-11: the subject mask ONLY (never baked into pixels), in the
    /// image's display orientation, bounded by `maxAutomaticMaskDimension`.
    func foregroundAlphaMask(from image: UIImage) async throws -> ThumbnailCutoutAutomaticBase
}

extension ThumbnailSubjectProcessing {
    /// Default: lift the alpha channel of `removeBackground`'s result. Keeps
    /// every existing conformer (including test stubs) compiling unchanged.
    func foregroundAlphaMask(from image: UIImage) async throws -> ThumbnailCutoutAutomaticBase {
        let cutout = try await removeBackground(from: image)
        let size = ThumbnailCutoutMaskRenderer.displayPixelSize(of: image)
        return try ThumbnailCutoutMaskRenderer.automaticBase(
            fromCutoutImage: cutout,
            sourcePixelWidth: size.width,
            sourcePixelHeight: size.height
        )
    }
}

struct BackgroundRemovalService {
    private let context: CIContext

    init(context: CIContext = CIContext()) {
        self.context = context
    }

    static var supportsForegroundMask: Bool {
        if #available(iOS 17.0, macCatalyst 17.0, *) {
            return true
        }
        return false
    }

    func removeBackground(from image: UIImage) async throws -> UIImage {
        guard Self.supportsForegroundMask else {
            throw BackgroundRemovalError.foregroundMaskUnavailable
        }

        if #available(iOS 17.0, macCatalyst 17.0, *) {
            return try await removeBackgroundWithForegroundMask(from: image)
        }

        throw BackgroundRemovalError.foregroundMaskUnavailable
    }

    func detectFaces(in image: UIImage) async throws -> [ThumbnailDetectedFace] {
        guard let cgImage = image.cgImage else {
            throw BackgroundRemovalError.missingCGImage
        }

        return try await Task.detached(priority: .userInitiated) {
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: CGImagePropertyOrientation(image.imageOrientation),
                options: [:]
            )

            try handler.perform([request])

            return (request.results ?? []).map {
                ThumbnailDetectedFace(
                    normalizedBounds: $0.boundingBox,
                    confidence: $0.confidence
                )
            }
        }.value
    }

    func suggestedFaceCrop(in image: UIImage, padding: CGFloat = 0.18) async throws -> CGRect? {
        let faces = try await detectFaces(in: image)
        return Self.suggestedFaceCrop(for: faces.map(\.normalizedBounds), padding: padding)
    }

    static func suggestedFaceCrop(for faceBounds: [CGRect], padding: CGFloat = 0.18) -> CGRect? {
        guard let firstFace = faceBounds.first else { return nil }

        let union = faceBounds.dropFirst().reduce(firstFace) { partialResult, face in
            partialResult.union(face)
        }

        let expansionX = union.width * padding
        let expansionY = union.height * padding
        let padded = union.insetBy(dx: -expansionX, dy: -expansionY)

        let minX = max(0, padded.minX)
        let minY = max(0, padded.minY)
        let maxX = min(1, padded.maxX)
        let maxY = min(1, padded.maxY)

        guard maxX > minX, maxY > minY else { return nil }

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    static func croppedImage(_ image: UIImage, toNormalizedVisionRect normalizedRect: CGRect) -> UIImage? {
        let sourceImage = image.normalizedForThumbnailProcessing()
        guard let cgImage = sourceImage.cgImage else {
            return nil
        }

        let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        let clampedRect = normalizedRect.standardized.intersection(unitRect)
        guard clampedRect.width > 0, clampedRect.height > 0 else {
            return nil
        }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let pixelRect = CGRect(
            x: clampedRect.minX * imageWidth,
            y: (1 - clampedRect.maxY) * imageHeight,
            width: clampedRect.width * imageWidth,
            height: clampedRect.height * imageHeight
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

        guard pixelRect.width > 0, pixelRect.height > 0,
              let croppedCGImage = cgImage.cropping(to: pixelRect) else {
            return nil
        }

        return UIImage(cgImage: croppedCGImage, scale: sourceImage.scale, orientation: .up)
    }

    @available(iOS 17.0, macCatalyst 17.0, *)
    private func removeBackgroundWithForegroundMask(from image: UIImage) async throws -> UIImage {
        guard let cgImage = image.cgImage else {
            throw BackgroundRemovalError.missingCGImage
        }

        let context = context
        return try await Task.detached(priority: .userInitiated) {
            let inputImage = CIImage(cgImage: cgImage)
            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: CGImagePropertyOrientation(image.imageOrientation),
                options: [:]
            )
            let request = VNGenerateForegroundInstanceMaskRequest()

            do {
                try handler.perform([request])
                guard let observation = request.results?.first else {
                    throw BackgroundRemovalError.foregroundMaskFailed
                }

                let maskBuffer = try observation.generateScaledMaskForImage(
                    forInstances: observation.allInstances,
                    from: handler
                )
                let maskImage = CIImage(cvPixelBuffer: maskBuffer)
                let transparentBackground = CIImage(color: .clear).cropped(to: inputImage.extent)
                let blendFilter = CIFilter.blendWithMask()
                blendFilter.inputImage = inputImage
                blendFilter.backgroundImage = transparentBackground
                blendFilter.maskImage = maskImage

                guard
                    let outputImage = blendFilter.outputImage,
                    let outputCGImage = context.createCGImage(outputImage, from: inputImage.extent)
                else {
                    throw BackgroundRemovalError.renderFailed
                }

                return UIImage(
                    cgImage: outputCGImage,
                    scale: image.scale,
                    orientation: image.imageOrientation
                )
            } catch let error as BackgroundRemovalError {
                throw error
            } catch {
                throw BackgroundRemovalError.foregroundMaskFailed
            }
        }.value
    }
}

extension BackgroundRemovalService: ThumbnailSubjectProcessing {
    /// FEATURE-11: Vision's mask straight to a bounded gray PNG. The photo is
    /// normalized to `.up` first so the mask is in display space.
    func foregroundAlphaMask(from image: UIImage) async throws -> ThumbnailCutoutAutomaticBase {
        guard Self.supportsForegroundMask else {
            throw BackgroundRemovalError.foregroundMaskUnavailable
        }
        guard let cgImage = ThumbnailCutoutMaskRenderer.uprightCGImage(of: image) else {
            throw BackgroundRemovalError.missingCGImage
        }
        let size = ThumbnailCutoutMaskRenderer.displayPixelSize(of: image)
        let context = context

        return try await Task.detached(priority: .userInitiated) {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            let request = VNGenerateForegroundInstanceMaskRequest()
            do {
                try handler.perform([request])
                guard let observation = request.results?.first else {
                    throw BackgroundRemovalError.foregroundMaskFailed
                }
                let maskBuffer = try observation.generateScaledMaskForImage(
                    forInstances: observation.allInstances,
                    from: handler
                )
                let maskImage = CIImage(cvPixelBuffer: maskBuffer)
                guard let grayMask = context.createCGImage(
                    maskImage,
                    from: maskImage.extent,
                    format: .L8,
                    colorSpace: CGColorSpaceCreateDeviceGray()
                ) else {
                    throw BackgroundRemovalError.renderFailed
                }
                return try ThumbnailCutoutMaskRenderer.makeAutomaticBase(
                    fromGrayMask: grayMask,
                    sourcePixelWidth: size.width,
                    sourcePixelHeight: size.height
                )
            } catch let error as BackgroundRemovalError {
                throw error
            } catch is ThumbnailCutoutRenderError {
                throw BackgroundRemovalError.renderFailed
            } catch {
                throw BackgroundRemovalError.foregroundMaskFailed
            }
        }.value
    }
}

private extension UIImage {
    func normalizedForThumbnailProcessing() -> UIImage {
        guard imageOrientation != .up else {
            return self
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ imageOrientation: UIImage.Orientation) {
        switch imageOrientation {
        case .up:
            self = .up
        case .upMirrored:
            self = .upMirrored
        case .down:
            self = .down
        case .downMirrored:
            self = .downMirrored
        case .left:
            self = .left
        case .leftMirrored:
            self = .leftMirrored
        case .right:
            self = .right
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}
