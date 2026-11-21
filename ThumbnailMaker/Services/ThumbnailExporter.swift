//
//  ThumbnailExporter.swift
//  ThumbnailMaker
//

import ImageIO
import Photos
import SwiftUI
import UIKit

enum ThumbnailExportError: LocalizedError, Equatable {
    case renderFailed
    case encodeFailed(ThumbnailExportFormat)
    case unsupportedFormat(ThumbnailExportFormat)
    case photoPermissionDenied
    case fileWriteFailed

    var errorDescription: String? {
        switch self {
        case .renderFailed:
            return "Failed to render the thumbnail."
        case .encodeFailed(let format):
            return "Failed to encode the thumbnail as \(format.displayName)."
        case .unsupportedFormat(let format):
            return "\(format.displayName) export is not supported on this device."
        case .photoPermissionDenied:
            return "This app needs permission to save photos. Please open Settings > Privacy & Security > Photos and allow access for this app."
        case .fileWriteFailed:
            return "Failed to prepare the exported file."
        }
    }
}

struct ThumbnailShareItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

struct ThumbnailExporter {
    @MainActor
    static func render<Content: View>(
        content: Content,
        options: ThumbnailExportOptions
    ) throws -> UIImage {
        let outputSize = options.outputSize.cgSize
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(outputSize)
        renderer.scale = 1
        renderer.colorMode = .nonLinear

        guard let renderedImage = renderer.uiImage else {
            throw ThumbnailExportError.renderFailed
        }

        return renderedImage
    }

    static func encodedData(
        for image: UIImage,
        options: ThumbnailExportOptions
    ) throws -> Data {
        switch options.format {
        case .png:
            guard let data = image.pngData() else {
                throw ThumbnailExportError.encodeFailed(options.format)
            }
            return data
        case .jpeg:
            guard let data = image.jpegData(compressionQuality: options.compressionQuality) else {
                throw ThumbnailExportError.encodeFailed(options.format)
            }
            return data
        case .webP:
            guard options.format.canEncodeOnCurrentPlatform else {
                throw ThumbnailExportError.unsupportedFormat(options.format)
            }
            guard let cgImage = image.cgImage else {
                throw ThumbnailExportError.encodeFailed(options.format)
            }

            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                data,
                options.format.uniformTypeIdentifier as CFString,
                1,
                nil
            ) else {
                throw ThumbnailExportError.unsupportedFormat(options.format)
            }

            let properties = [
                kCGImageDestinationLossyCompressionQuality as String: options.compressionQuality
            ] as CFDictionary
            CGImageDestinationAddImage(destination, cgImage, properties)

            guard CGImageDestinationFinalize(destination) else {
                throw ThumbnailExportError.encodeFailed(options.format)
            }

            return data as Data
        }
    }

    static func saveToPhotoLibrary(
        image: UIImage,
        options: ThumbnailExportOptions
    ) async throws {
        let data = try encodedData(for: image, options: options)
        try await saveEncodedDataToPhotoLibrary(data, options: options)
    }

    static func saveEncodedDataToPhotoLibrary(
        _ data: Data,
        options: ThumbnailExportOptions
    ) async throws {
        try await ensurePhotoAddAuthorization()

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let resourceOptions = PHAssetResourceCreationOptions()
            resourceOptions.uniformTypeIdentifier = options.format.uniformTypeIdentifier
            request.addResource(with: .photo, data: data, options: resourceOptions)
        }
    }

    @MainActor
    static func preparedFileExport<Content: View>(
        content: Content,
        options: ThumbnailExportOptions,
        baseFileName: String = "thumbnailmaker-export"
    ) throws -> ThumbnailPreparedFileExport {
        let renderedImage = try render(content: content, options: options)
        let data = try encodedData(for: renderedImage, options: options)
        let fileName = "\(sanitizedFileName(baseFileName)).\(options.format.fileExtension)"

        return ThumbnailPreparedFileExport(
            data: data,
            fileName: fileName,
            contentType: options.format.contentType,
            options: options
        )
    }

    static func writeTemporaryExport(
        data: Data,
        options: ThumbnailExportOptions,
        baseFileName: String = "thumbnailmaker-export"
    ) throws -> URL {
        let safeBaseName = sanitizedFileName(baseFileName)
        let fileName = "\(safeBaseName)-\(UUID().uuidString).\(options.format.fileExtension)"
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThumbnailMakerExports", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: exportDirectory,
                withIntermediateDirectories: true
            )
            let url = exportDirectory.appendingPathComponent(fileName)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw ThumbnailExportError.fileWriteFailed
        }
    }

    static func temporaryExportURL(
        for image: UIImage,
        options: ThumbnailExportOptions,
        baseFileName: String = "thumbnailmaker-export"
    ) throws -> URL {
        let data = try encodedData(for: image, options: options)
        return try writeTemporaryExport(
            data: data,
            options: options,
            baseFileName: baseFileName
        )
    }

    private static func ensurePhotoAddAuthorization() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        switch status {
        case .notDetermined:
            let requestedStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard requestedStatus == .authorized || requestedStatus == .limited else {
                throw ThumbnailExportError.photoPermissionDenied
            }
        case .authorized, .limited:
            break
        case .restricted, .denied:
            throw ThumbnailExportError.photoPermissionDenied
        @unknown default:
            break
        }
    }

    static func sanitizedFileName(_ value: String) -> String {
        let sanitized = value
            .replacingOccurrences(
                of: #"[^A-Za-z0-9_-]+"#,
                with: "-",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))

        return sanitized.isEmpty ? "thumbnailmaker-export" : sanitized
    }
}
