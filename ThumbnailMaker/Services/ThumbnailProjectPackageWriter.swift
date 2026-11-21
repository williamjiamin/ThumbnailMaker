//
//  ThumbnailProjectPackageWriter.swift
//  ThumbnailMaker
//
//  FEATURE-06: turns a project into .thumbproj package files. Pure: never
//  touches the project library or the open editor.
//

import Foundation
import UIKit

enum ThumbnailProjectPackageWriter {
    static var currentGeneratorVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// Builds every package file in memory. Enforces the same ceilings the
    /// reader enforces, so an exported package always re-imports.
    static func encode(
        _ contents: ThumbnailProjectPackageContents,
        limits: ThumbnailProjectPackageLimits = .standard,
        generatorVersion: String? = ThumbnailProjectPackageWriter.currentGeneratorVersion
    ) throws -> ThumbnailProjectEncodedPackage {
        let encoder = ThumbnailProjectPackageCoding.encoder
        var assets: [String: Data] = [:]
        var files: [String: Data] = [:]

        let document = Self.normalizedForExport(contents.document)
        let dehydrated = ThumbnailVariantAssetLibrary.dehydrate(document, into: &assets)
        let documentData = try encodeJSON(dehydrated.document, with: encoder)
        guard documentData.count <= limits.maximumDocumentByteCount else {
            throw ThumbnailProjectPackageError.documentTooLarge(
                byteCount: documentData.count,
                limit: limits.maximumDocumentByteCount
            )
        }
        files[ThumbnailProjectPackageLayout.documentFileName] = documentData

        var variantEntries: [ThumbnailProjectPackageVariantEntry] = []
        var activeSlot: String?
        var preferredSlot: String?
        var variantExportName = ""
        if let variantSet = contents.variantSet?.normalized() {
            for variant in variantSet.variants {
                let variantDocument = Self.normalizedForExport(variant.document)
                let dehydratedVariant = ThumbnailVariantAssetLibrary.dehydrate(variantDocument, into: &assets)
                let data = try encodeJSON(dehydratedVariant.document, with: encoder)
                guard data.count <= limits.maximumDocumentByteCount else {
                    throw ThumbnailProjectPackageError.documentTooLarge(
                        byteCount: data.count,
                        limit: limits.maximumDocumentByteCount
                    )
                }
                let path = ThumbnailProjectPackageLayout.variantsDirectoryName + "/"
                    + ThumbnailProjectPackageLayout.variantFileName(for: variant.slot)
                files[path] = data
                variantEntries.append(
                    ThumbnailProjectPackageVariantEntry(
                        slotRawValue: variant.slot.rawValue,
                        name: variant.name,
                        createdAt: variant.createdAt,
                        updatedAt: variant.updatedAt,
                        assets: dehydratedVariant.refs
                    )
                )
            }
            activeSlot = variantSet.activeSlot.rawValue
            preferredSlot = variantSet.preferredSlot?.rawValue
            variantExportName = variantSet.projectName
        }

        guard assets.count <= limits.maximumAssetCount else {
            throw ThumbnailProjectPackageError.assetCountExceeded(
                found: assets.count,
                limit: limits.maximumAssetCount
            )
        }

        var records: [ThumbnailProjectAssetRecord] = []
        for (id, data) in assets.sorted(by: { $0.key < $1.key }) {
            guard data.count <= limits.maximumAssetByteCount else {
                throw ThumbnailProjectPackageError.assetTooLarge(
                    id: id,
                    byteCount: data.count,
                    limit: limits.maximumAssetByteCount
                )
            }
            guard UIImage(data: data) != nil else {
                throw ThumbnailProjectPackageError.assetUndecodable(id: id)
            }
            let format = ThumbnailProjectAssetFormat.sniff(data)
            let path = ThumbnailProjectPackageLayout.assetsDirectoryName + "/\(id).\(format.fileExtension)"
            files[path] = data
            records.append(
                ThumbnailProjectAssetRecord(
                    id: id,
                    path: path,
                    byteCount: data.count,
                    sha256: id,
                    uniformTypeIdentifier: format.uniformTypeIdentifier
                )
            )
        }

        var previewPath: String?
        if let preview = contents.previewPNGData,
           !preview.isEmpty,
           preview.count <= limits.maximumPreviewByteCount,
           UIImage(data: preview) != nil {
            files[ThumbnailProjectPackageLayout.previewFileName] = preview
            previewPath = ThumbnailProjectPackageLayout.previewFileName
        }

        let manifest = ThumbnailProjectPackageManifest(
            projectID: contents.projectID,
            // Blank stays blank so the importer can choose its own fallback name.
            name: String(
                contents.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(ThumbnailProjectMetadata.maximumNameLength)
            ),
            createdAt: contents.createdAt,
            updatedAt: contents.updatedAt,
            documentVersion: max(document.version, ThumbnailDocument.currentVersion),
            editorModeRawValue: contents.editorMode.rawValue,
            assets: records,
            documentAssets: dehydrated.refs,
            variants: variantEntries,
            activeVariantSlotRawValue: activeSlot,
            preferredVariantSlotRawValue: preferredSlot,
            variantExportName: variantExportName,
            previewPath: previewPath,
            generatorVersion: generatorVersion
        )
        let manifestData = try encodeJSON(manifest, with: encoder)
        guard manifestData.count <= limits.maximumManifestByteCount else {
            throw ThumbnailProjectPackageError.manifestTooLarge(
                byteCount: manifestData.count,
                limit: limits.maximumManifestByteCount
            )
        }
        files[ThumbnailProjectPackageLayout.manifestFileName] = manifestData

        let package = ThumbnailProjectEncodedPackage(manifest: manifest, files: files)
        guard package.totalByteCount <= limits.maximumTotalByteCount else {
            throw ThumbnailProjectPackageError.packageTooLarge(
                byteCount: package.totalByteCount,
                limit: limits.maximumTotalByteCount
            )
        }
        return package
    }

    /// A directory wrapper: top-level files plus one level of sub-directories.
    static func fileWrapper(for package: ThumbnailProjectEncodedPackage) -> FileWrapper {
        var topLevel: [String: FileWrapper] = [:]
        var directories: [String: [String: FileWrapper]] = [:]

        for (path, data) in package.files {
            let components = path.split(separator: "/").map(String.init)
            if components.count == 2 {
                let child = FileWrapper(regularFileWithContents: data)
                child.preferredFilename = components[1]
                directories[components[0], default: [:]][components[1]] = child
            } else {
                let child = FileWrapper(regularFileWithContents: data)
                child.preferredFilename = path
                topLevel[path] = child
            }
        }

        for (name, children) in directories {
            let directory = FileWrapper(directoryWithFileWrappers: children)
            directory.preferredFilename = name
            topLevel[name] = directory
        }

        return FileWrapper(directoryWithFileWrappers: topLevel)
    }

    /// Test/CLI seam. Atomic: a failed write leaves no half package behind.
    static func write(_ package: ThumbnailProjectEncodedPackage, to url: URL) throws {
        do {
            try fileWrapper(for: package).write(to: url, options: [.atomic], originalContentsURL: nil)
        } catch {
            throw ThumbnailProjectPackageError.writeFailed(error.localizedDescription)
        }
    }

    /// "My / Project: 2" -> "My - Project - 2"; never empty.
    static func suggestedFileName(for name: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters)
        let cleaned = name
            .components(separatedBy: unsafe)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? "Thumbnail Project" : String(cleaned.prefix(100))
    }

    /// Empty blobs carry no pixels and would not decode; drop them.
    private static func normalizedForExport(_ document: ThumbnailDocument) -> ThumbnailDocument {
        var document = document
        if document.imageData?.isEmpty == true {
            document.imageData = nil
        }
        if document.profile?.imageData?.isEmpty == true {
            document.profile?.imageData = nil
        }
        return document
    }

    private static func encodeJSON<T: Encodable>(_ value: T, with encoder: JSONEncoder) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw ThumbnailProjectPackageError.writeFailed(error.localizedDescription)
        }
    }
}

/// Picks an asset file extension from magic bytes. Bytes are never re-encoded.
struct ThumbnailProjectAssetFormat: Equatable {
    var fileExtension: String
    var uniformTypeIdentifier: String

    static func sniff(_ data: Data) -> ThumbnailProjectAssetFormat {
        let bytes = [UInt8](data.prefix(12))
        func starts(_ prefix: [UInt8], at offset: Int = 0) -> Bool {
            bytes.count >= offset + prefix.count && Array(bytes[offset..<(offset + prefix.count)]) == prefix
        }

        if starts([0x89, 0x50, 0x4E, 0x47]) {
            return ThumbnailProjectAssetFormat(fileExtension: "png", uniformTypeIdentifier: "public.png")
        }
        if starts([0xFF, 0xD8, 0xFF]) {
            return ThumbnailProjectAssetFormat(fileExtension: "jpg", uniformTypeIdentifier: "public.jpeg")
        }
        if starts(Array("GIF8".utf8)) {
            return ThumbnailProjectAssetFormat(fileExtension: "gif", uniformTypeIdentifier: "com.compuserve.gif")
        }
        if starts(Array("RIFF".utf8)), starts(Array("WEBP".utf8), at: 8) {
            return ThumbnailProjectAssetFormat(fileExtension: "webp", uniformTypeIdentifier: "org.webmproject.webp")
        }
        if starts(Array("ftyp".utf8), at: 4) {
            return ThumbnailProjectAssetFormat(fileExtension: "heic", uniformTypeIdentifier: "public.heic")
        }
        if starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A]) {
            return ThumbnailProjectAssetFormat(fileExtension: "tiff", uniformTypeIdentifier: "public.tiff")
        }
        return ThumbnailProjectAssetFormat(fileExtension: "img", uniformTypeIdentifier: "public.image")
    }
}
