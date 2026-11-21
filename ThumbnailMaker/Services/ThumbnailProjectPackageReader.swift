//
//  ThumbnailProjectPackageReader.swift
//  ThumbnailMaker
//
//  FEATURE-06: reads and fully validates a .thumbproj package. Read-only: it
//  never writes to the source, so a rejected package (including one from a
//  newer app version) is left byte-for-byte as it was. Every check runs
//  before anything is returned, so a failure cannot reach the open project.
//

import Foundation
import UIKit

enum ThumbnailProjectPackageReader {
    /// Reads a package from a URL (for example a `fileImporter` result). The
    /// security scope is opened and closed here, and every byte is read
    /// inside it.
    static func readPackage(
        at url: URL,
        limits: ThumbnailProjectPackageLimits = .standard
    ) throws -> ThumbnailProjectPackage {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ThumbnailProjectPackageError.unreadable("the file could not be found")
        }
        guard isDirectory.boolValue else {
            throw ThumbnailProjectPackageError.notAPackage
        }

        let wrapper: FileWrapper
        do {
            wrapper = try FileWrapper(url: url, options: [])
        } catch {
            throw ThumbnailProjectPackageError.unreadable(error.localizedDescription)
        }
        return try package(from: wrapper, limits: limits)
    }

    static func package(
        from wrapper: FileWrapper,
        limits: ThumbnailProjectPackageLimits = .standard
    ) throws -> ThumbnailProjectPackage {
        guard wrapper.isDirectory, let children = wrapper.fileWrappers else {
            throw ThumbnailProjectPackageError.notAPackage
        }
        let decoder = ThumbnailProjectPackageCoding.decoder

        // 1. Manifest.
        guard let manifestWrapper = children[ThumbnailProjectPackageLayout.manifestFileName],
              manifestWrapper.isRegularFile else {
            throw ThumbnailProjectPackageError.manifestMissing
        }
        let declaredManifestSize = byteCount(of: manifestWrapper)
        if let declaredManifestSize, declaredManifestSize > limits.maximumManifestByteCount {
            throw ThumbnailProjectPackageError.manifestTooLarge(
                byteCount: declaredManifestSize,
                limit: limits.maximumManifestByteCount
            )
        }
        let manifestData = try contents(of: manifestWrapper)
        guard manifestData.count <= limits.maximumManifestByteCount else {
            throw ThumbnailProjectPackageError.manifestTooLarge(
                byteCount: manifestData.count,
                limit: limits.maximumManifestByteCount
            )
        }
        let manifest: ThumbnailProjectPackageManifest
        do {
            manifest = try decoder.decode(ThumbnailProjectPackageManifest.self, from: manifestData)
        } catch {
            throw ThumbnailProjectPackageError.manifestUnreadable(error.localizedDescription)
        }

        // 2. Identity and version gates.
        guard manifest.formatIdentifier == ThumbnailProjectPackageLayout.formatIdentifier else {
            throw ThumbnailProjectPackageError.unsupportedFormatIdentifier(manifest.formatIdentifier)
        }
        guard manifest.minimumReaderVersion <= ThumbnailProjectPackageLayout.supportedSchemaVersion else {
            throw ThumbnailProjectPackageError.unsupportedFutureVersion(
                found: manifest.minimumReaderVersion,
                supported: ThumbnailProjectPackageLayout.supportedSchemaVersion
            )
        }
        guard manifest.schemaVersion >= 1, manifest.minimumReaderVersion >= 1 else {
            throw ThumbnailProjectPackageError.unsupportedLegacyVersion(
                found: min(manifest.schemaVersion, manifest.minimumReaderVersion)
            )
        }
        guard manifest.documentVersion <= ThumbnailDocument.currentVersion else {
            throw ThumbnailProjectPackageError.unsupportedFutureVersion(
                found: manifest.documentVersion,
                supported: ThumbnailDocument.currentVersion
            )
        }

        // 3. Asset table: count, paths, declared sizes - before reading bytes.
        guard manifest.assets.count <= limits.maximumAssetCount else {
            throw ThumbnailProjectPackageError.assetCountExceeded(
                found: manifest.assets.count,
                limit: limits.maximumAssetCount
            )
        }
        let assetDirectory = children[ThumbnailProjectPackageLayout.assetsDirectoryName]
        var assetWrappers: [(record: ThumbnailProjectAssetRecord, wrapper: FileWrapper)] = []
        var seenIDs = Set<String>()
        var runningTotal = manifestData.count
        for record in manifest.assets {
            let fileName = try validatedAssetFileName(for: record)
            guard seenIDs.insert(record.id).inserted else {
                throw ThumbnailProjectPackageError.assetPathRejected(record.path)
            }
            guard let assetDirectory,
                  assetDirectory.isDirectory,
                  let assetWrapper = assetDirectory.fileWrappers?[fileName],
                  assetWrapper.isRegularFile else {
                throw ThumbnailProjectPackageError.assetMissing(id: record.id)
            }
            guard record.byteCount >= 0, record.byteCount <= limits.maximumAssetByteCount else {
                throw ThumbnailProjectPackageError.assetTooLarge(
                    id: record.id,
                    byteCount: record.byteCount,
                    limit: limits.maximumAssetByteCount
                )
            }
            if let actual = byteCount(of: assetWrapper), actual != record.byteCount {
                throw ThumbnailProjectPackageError.assetSizeMismatch(id: record.id)
            }
            runningTotal += record.byteCount
            guard runningTotal <= limits.maximumTotalByteCount else {
                throw ThumbnailProjectPackageError.packageTooLarge(
                    byteCount: runningTotal,
                    limit: limits.maximumTotalByteCount
                )
            }
            assetWrappers.append((record, assetWrapper))
        }

        // 4. Documents (sizes first, then decode).
        guard let documentWrapper = children[ThumbnailProjectPackageLayout.documentFileName],
              documentWrapper.isRegularFile else {
            throw ThumbnailProjectPackageError.documentMissing
        }
        let documentData = try boundedDocumentData(documentWrapper, limits: limits)
        runningTotal += documentData.count

        var variantData: [(entry: ThumbnailProjectPackageVariantEntry, slot: ThumbnailVariantSlot, data: Data)] = []
        if !manifest.variants.isEmpty {
            guard manifest.variants.count <= ThumbnailVariantSet.maxVariantCount else {
                throw ThumbnailProjectPackageError.variantInvalid("too many variants")
            }
            let variantDirectory = children[ThumbnailProjectPackageLayout.variantsDirectoryName]
            var seenSlots = Set<ThumbnailVariantSlot>()
            for entry in manifest.variants {
                guard let slot = ThumbnailVariantSlot(rawValue: entry.slotRawValue),
                      seenSlots.insert(slot).inserted else {
                    throw ThumbnailProjectPackageError.variantInvalid("unknown or repeated slot \(entry.slotRawValue)")
                }
                guard let variantDirectory,
                      variantDirectory.isDirectory,
                      let variantWrapper = variantDirectory.fileWrappers?[
                        ThumbnailProjectPackageLayout.variantFileName(for: slot)
                      ],
                      variantWrapper.isRegularFile else {
                    throw ThumbnailProjectPackageError.variantInvalid("variant \(slot.displayLetter) is missing")
                }
                let data = try boundedDocumentData(variantWrapper, limits: limits)
                runningTotal += data.count
                variantData.append((entry, slot, data))
            }
        }
        guard runningTotal <= limits.maximumTotalByteCount else {
            throw ThumbnailProjectPackageError.packageTooLarge(
                byteCount: runningTotal,
                limit: limits.maximumTotalByteCount
            )
        }

        // 5. Asset bytes: size, checksum, decodability.
        var assets: [String: Data] = [:]
        for (record, assetWrapper) in assetWrappers {
            let data = try contents(of: assetWrapper)
            guard data.count == record.byteCount else {
                throw ThumbnailProjectPackageError.assetSizeMismatch(id: record.id)
            }
            let digest = ThumbnailVariantAssetLibrary.digest(data)
            guard digest == record.id, digest == record.sha256.lowercased() else {
                throw ThumbnailProjectPackageError.assetChecksumMismatch(id: record.id)
            }
            guard UIImage(data: data) != nil else {
                throw ThumbnailProjectPackageError.assetUndecodable(id: record.id)
            }
            assets[record.id] = data
        }

        // 6. Decode and re-bind every document.
        let document = try hydratedDocument(
            from: documentData,
            refs: manifest.documentAssets,
            assets: assets,
            scope: nil,
            decoder: decoder
        )

        var variantSet: ThumbnailVariantSet?
        if !variantData.isEmpty {
            let variants = try variantData.map { entry, slot, data in
                ThumbnailVariant(
                    slot: slot,
                    name: entry.name,
                    createdAt: entry.createdAt,
                    updatedAt: entry.updatedAt,
                    document: try hydratedDocument(
                        from: data,
                        refs: entry.assets,
                        assets: assets,
                        scope: "variant \(slot.displayLetter)",
                        decoder: decoder
                    )
                )
            }
            let activeSlot = manifest.activeVariantSlotRawValue.flatMap(ThumbnailVariantSlot.init(rawValue:))
            variantSet = ThumbnailVariantSet(
                updatedAt: manifest.updatedAt,
                editorMode: manifest.editorMode,
                projectName: manifest.variantExportName,
                activeSlot: activeSlot ?? variants.map(\.slot).min() ?? .a,
                preferredSlot: manifest.preferredVariantSlotRawValue.flatMap(ThumbnailVariantSlot.init(rawValue:)),
                variants: variants
            ).normalized()
        }

        // 7. Preview: optional and non-fatal; it carries no editable state.
        var preview: Data?
        if manifest.previewPath == ThumbnailProjectPackageLayout.previewFileName,
           let previewWrapper = children[ThumbnailProjectPackageLayout.previewFileName],
           previewWrapper.isRegularFile,
           (byteCount(of: previewWrapper) ?? 0) <= limits.maximumPreviewByteCount,
           let data = try? contents(of: previewWrapper),
           data.count <= limits.maximumPreviewByteCount,
           runningTotal + data.count <= limits.maximumTotalByteCount,
           UIImage(data: data) != nil {
            preview = data
        }

        return ThumbnailProjectPackage(
            manifest: manifest,
            contents: ThumbnailProjectPackageContents(
                projectID: manifest.projectID,
                name: manifest.name,
                createdAt: manifest.createdAt,
                updatedAt: manifest.updatedAt,
                editorMode: manifest.editorMode,
                document: document,
                variantSet: variantSet,
                previewPNGData: preview
            )
        )
    }

    // MARK: - Validation helpers

    /// Accepts only `assets/<64 lowercase hex>.<allowed ext>` whose name is
    /// the record's id. Returns the bare file name used for the lookup inside
    /// the `assets` wrapper; the manifest string is never turned into a URL.
    static func validatedAssetFileName(for record: ThumbnailProjectAssetRecord) throws -> String {
        let path = record.path
        let rejected = ThumbnailProjectPackageError.assetPathRejected(path)
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains(".."),
              !path.contains("\\"),
              !path.contains(":"),
              !path.contains("\u{0}"),
              isSHA256Hex(record.id) else {
            throw rejected
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count == 2,
              components[0] == ThumbnailProjectPackageLayout.assetsDirectoryName else {
            throw rejected
        }
        let fileName = components[1]
        let parts = fileName.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2,
              parts[0] == record.id,
              ThumbnailProjectPackageLayout.allowedAssetExtensions.contains(parts[1]) else {
            throw rejected
        }
        return fileName
    }

    static func isSHA256Hex(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    private static func boundedDocumentData(
        _ wrapper: FileWrapper,
        limits: ThumbnailProjectPackageLimits
    ) throws -> Data {
        if let declared = byteCount(of: wrapper), declared > limits.maximumDocumentByteCount {
            throw ThumbnailProjectPackageError.documentTooLarge(
                byteCount: declared,
                limit: limits.maximumDocumentByteCount
            )
        }
        let data = try contents(of: wrapper)
        guard data.count <= limits.maximumDocumentByteCount else {
            throw ThumbnailProjectPackageError.documentTooLarge(
                byteCount: data.count,
                limit: limits.maximumDocumentByteCount
            )
        }
        return data
    }

    private struct DocumentVersionProbe: Decodable {
        var version: Int?
    }

    private static func hydratedDocument(
        from data: Data,
        refs: ThumbnailVariantAssetRefs,
        assets: [String: Data],
        scope: String?,
        decoder: JSONDecoder
    ) throws -> ThumbnailDocument {
        // ThumbnailDocument clamps its version upward on decode, so a document
        // from a newer app would otherwise decode silently and lose fields.
        if let probe = try? decoder.decode(DocumentVersionProbe.self, from: data),
           let version = probe.version,
           version > ThumbnailDocument.currentVersion {
            throw ThumbnailProjectPackageError.unsupportedFutureVersion(
                found: version,
                supported: ThumbnailDocument.currentVersion
            )
        }

        let document: ThumbnailDocument
        do {
            document = try decoder.decode(ThumbnailDocument.self, from: data)
        } catch {
            if let scope {
                throw ThumbnailProjectPackageError.variantInvalid("\(scope) could not be decoded")
            }
            throw ThumbnailProjectPackageError.documentUnreadable(error.localizedDescription)
        }

        func slotLabel(_ slot: String) -> String {
            scope.map { "\($0) \(slot)" } ?? slot
        }

        // Every ref must resolve, and every layer ref must name an image layer.
        if let key = refs.backgroundImage, assets[key] == nil {
            throw ThumbnailProjectPackageError.bindingUnresolved(slot: slotLabel("background"))
        }
        if let key = refs.profileImage, assets[key] == nil || document.profile == nil {
            throw ThumbnailProjectPackageError.bindingUnresolved(slot: slotLabel("profile"))
        }
        let imageLayerIDs = Set(document.layers.compactMap { layer -> String? in
            if case .image = layer.content { return layer.id }
            return nil
        })
        for (layerID, key) in refs.contentLayers.sorted(by: { $0.key < $1.key }) {
            guard assets[key] != nil, imageLayerIDs.contains(layerID) else {
                throw ThumbnailProjectPackageError.bindingUnresolved(slot: slotLabel("layer:\(layerID)"))
            }
        }

        let hydrated = ThumbnailVariantAssetLibrary.hydrate(document, refs: refs, assets: assets)
        guard hydrated.missingDigests.isEmpty else {
            throw ThumbnailProjectPackageError.bindingUnresolved(slot: slotLabel("asset"))
        }

        // Never hand back a silently blank image layer.
        for layer in hydrated.document.layers {
            if case .image(let content) = layer.content, content.imageData.isEmpty {
                throw ThumbnailProjectPackageError.bindingUnresolved(slot: slotLabel("layer:\(layer.id)"))
            }
        }
        return hydrated.document
    }

    private static func byteCount(of wrapper: FileWrapper) -> Int? {
        (wrapper.fileAttributes[FileAttributeKey.size.rawValue] as? NSNumber)?.intValue
    }

    private static func contents(of wrapper: FileWrapper) throws -> Data {
        guard let data = wrapper.regularFileContents else {
            throw ThumbnailProjectPackageError.unreadable("a file inside the package could not be read")
        }
        return data
    }
}
