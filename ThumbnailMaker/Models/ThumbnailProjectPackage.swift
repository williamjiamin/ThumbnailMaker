//
//  ThumbnailProjectPackage.swift
//  ThumbnailMaker
//
//  FEATURE-06: portable, editable project packages (.thumbproj).
//
//  A .thumbproj is a file package (a directory that Files shows as one item):
//
//    MyProject.thumbproj/
//      manifest.json        schema, identity, asset table, per-document asset refs
//      document.json        the active ThumbnailDocument, pixel blobs stripped
//      variants/<a|b|c>.json  optional FEATURE-02 variant documents, blobs stripped
//      assets/<sha256>.<ext>  original image bytes, content-addressed, deduped
//      preview.png          optional flattened preview, informational only
//
//  Pixel blobs are externalized with the same dehydrate/hydrate code the
//  variant store uses (ThumbnailVariantAssetLibrary), so ThumbnailDocument's
//  Codable shape is untouched and every field later features add to it is
//  carried through for free. Every path the reader opens is derived from a
//  fixed name or a validated `<sha256>.<ext>`; nothing in the manifest can
//  point outside the package or at a source-device path.
//

import Foundation

enum ThumbnailProjectPackageLayout {
    static let fileExtension = "thumbproj"
    static let formatIdentifier = "com.williamjiamin.ThumbnailMaker.project"
    /// The newest package schema this build writes and fully understands.
    static let supportedSchemaVersion = 1
    static let manifestFileName = "manifest.json"
    static let documentFileName = "document.json"
    static let assetsDirectoryName = "assets"
    static let variantsDirectoryName = "variants"
    static let previewFileName = "preview.png"
    static let fallbackImportName = "Imported Project"

    /// Extensions an asset file may carry. Anything else is rejected.
    static let allowedAssetExtensions: Set<String> = ["png", "jpg", "gif", "heic", "webp", "tiff", "img"]

    static func variantFileName(for slot: ThumbnailVariantSlot) -> String {
        "\(slot.rawValue).json"
    }
}

/// Ceilings enforced by both the writer and the reader, so the app can never
/// emit a package it would refuse to open. Injectable for tests.
struct ThumbnailProjectPackageLimits: Equatable {
    var maximumManifestByteCount = 1 * 1024 * 1024
    var maximumDocumentByteCount = 8 * 1024 * 1024
    var maximumAssetCount = 64
    var maximumAssetByteCount = 32 * 1024 * 1024
    var maximumTotalByteCount = 192 * 1024 * 1024
    var maximumPreviewByteCount = 8 * 1024 * 1024

    static let standard = ThumbnailProjectPackageLimits()
}

struct ThumbnailProjectAssetRecord: Codable, Equatable {
    /// Lowercase SHA-256 hex of the bytes (64 characters).
    var id: String
    /// Always `assets/<id>.<ext>`; validated on read, never resolved as a URL.
    var path: String
    var byteCount: Int
    var sha256: String
    var uniformTypeIdentifier: String

    private enum CodingKeys: String, CodingKey {
        case id, path, byteCount, sha256, uniformTypeIdentifier
    }

    init(id: String, path: String, byteCount: Int, sha256: String, uniformTypeIdentifier: String) {
        self.id = id
        self.path = path
        self.byteCount = byteCount
        self.sha256 = sha256
        self.uniformTypeIdentifier = uniformTypeIdentifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        byteCount = try container.decode(Int.self, forKey: .byteCount)
        sha256 = try container.decodeIfPresent(String.self, forKey: .sha256) ?? id
        uniformTypeIdentifier = try container.decodeIfPresent(String.self, forKey: .uniformTypeIdentifier)
            ?? "public.image"
    }
}

struct ThumbnailProjectPackageVariantEntry: Codable, Equatable {
    var slotRawValue: String
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var assets: ThumbnailVariantAssetRefs

    private enum CodingKeys: String, CodingKey {
        case slotRawValue = "slot"
        case name, createdAt, updatedAt, assets
    }

    init(
        slotRawValue: String,
        name: String,
        createdAt: Date,
        updatedAt: Date,
        assets: ThumbnailVariantAssetRefs
    ) {
        self.slotRawValue = slotRawValue
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.assets = assets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slotRawValue = try container.decode(String.self, forKey: .slotRawValue)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        let now = Date()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? now
        assets = try container.decodeIfPresent(ThumbnailVariantAssetRefs.self, forKey: .assets)
            ?? ThumbnailVariantAssetRefs()
    }
}

struct ThumbnailProjectPackageManifest: Codable, Equatable {
    var formatIdentifier: String
    var schemaVersion: Int
    /// A future writer that stays readable by this build keeps this at 1.
    var minimumReaderVersion: Int
    var projectID: String
    var name: String
    var createdAt: Date
    var updatedAt: Date
    /// Mirror of ThumbnailDocument.version at write time.
    var documentVersion: Int
    var editorModeRawValue: String
    var assets: [ThumbnailProjectAssetRecord]
    /// Asset refs for document.json.
    var documentAssets: ThumbnailVariantAssetRefs
    var variants: [ThumbnailProjectPackageVariantEntry]
    var activeVariantSlotRawValue: String?
    var preferredVariantSlotRawValue: String?
    var variantExportName: String
    var previewPath: String?
    var generatorVersion: String?

    init(
        formatIdentifier: String = ThumbnailProjectPackageLayout.formatIdentifier,
        schemaVersion: Int = ThumbnailProjectPackageLayout.supportedSchemaVersion,
        minimumReaderVersion: Int = 1,
        projectID: String,
        name: String,
        createdAt: Date,
        updatedAt: Date,
        documentVersion: Int,
        editorModeRawValue: String,
        assets: [ThumbnailProjectAssetRecord],
        documentAssets: ThumbnailVariantAssetRefs,
        variants: [ThumbnailProjectPackageVariantEntry] = [],
        activeVariantSlotRawValue: String? = nil,
        preferredVariantSlotRawValue: String? = nil,
        variantExportName: String = "",
        previewPath: String? = nil,
        generatorVersion: String? = nil
    ) {
        self.formatIdentifier = formatIdentifier
        self.schemaVersion = schemaVersion
        self.minimumReaderVersion = minimumReaderVersion
        self.projectID = projectID
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.documentVersion = documentVersion
        self.editorModeRawValue = editorModeRawValue
        self.assets = assets
        self.documentAssets = documentAssets
        self.variants = variants
        self.activeVariantSlotRawValue = activeVariantSlotRawValue
        self.preferredVariantSlotRawValue = preferredVariantSlotRawValue
        self.variantExportName = variantExportName
        self.previewPath = previewPath
        self.generatorVersion = generatorVersion
    }

    private enum CodingKeys: String, CodingKey {
        case formatIdentifier, schemaVersion, minimumReaderVersion, projectID, name
        case createdAt, updatedAt, documentVersion, editorModeRawValue = "editorMode"
        case assets, documentAssets, variants, activeVariantSlotRawValue = "activeVariantSlot"
        case preferredVariantSlotRawValue = "preferredVariantSlot", variantExportName
        case previewPath, generatorVersion
    }

    /// Only the three gate fields are required. Everything else decodes with a
    /// default, and unknown keys are ignored, so a newer writer that only adds
    /// fields still produces packages this build opens.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatIdentifier = try container.decode(String.self, forKey: .formatIdentifier)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        minimumReaderVersion = try container.decode(Int.self, forKey: .minimumReaderVersion)
        projectID = try container.decodeIfPresent(String.self, forKey: .projectID) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        let now = Date()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? now
        documentVersion = try container.decodeIfPresent(Int.self, forKey: .documentVersion)
            ?? ThumbnailDocument.currentVersion
        editorModeRawValue = try container.decodeIfPresent(String.self, forKey: .editorModeRawValue)
            ?? ThumbnailDocumentEditorMode.simple.rawValue
        assets = try container.decodeIfPresent([ThumbnailProjectAssetRecord].self, forKey: .assets) ?? []
        documentAssets = try container.decodeIfPresent(ThumbnailVariantAssetRefs.self, forKey: .documentAssets)
            ?? ThumbnailVariantAssetRefs()
        variants = try container.decodeIfPresent([ThumbnailProjectPackageVariantEntry].self, forKey: .variants) ?? []
        activeVariantSlotRawValue = try container.decodeIfPresent(String.self, forKey: .activeVariantSlotRawValue)
        preferredVariantSlotRawValue = try container.decodeIfPresent(
            String.self,
            forKey: .preferredVariantSlotRawValue
        )
        variantExportName = try container.decodeIfPresent(String.self, forKey: .variantExportName) ?? ""
        previewPath = try container.decodeIfPresent(String.self, forKey: .previewPath)
        generatorVersion = try container.decodeIfPresent(String.self, forKey: .generatorVersion)
    }

    var editorMode: ThumbnailDocumentEditorMode {
        ThumbnailDocumentEditorMode(rawValue: editorModeRawValue) ?? .simple
    }
}

/// The editable content of a package, fully hydrated (image bytes in place).
struct ThumbnailProjectPackageContents: Equatable {
    var projectID: String
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var editorMode: ThumbnailDocumentEditorMode
    /// The project's current document (the active variant's latest state).
    var document: ThumbnailDocument
    /// FEATURE-02 variants, when the project has any saved.
    var variantSet: ThumbnailVariantSet?
    var previewPNGData: Data?
}

/// A package as it lies on disk: the manifest plus every file by its
/// package-relative path. Produced by the writer, consumed by FileDocument.
struct ThumbnailProjectEncodedPackage: Equatable {
    var manifest: ThumbnailProjectPackageManifest
    var files: [String: Data]

    static let empty = ThumbnailProjectEncodedPackage(
        manifest: ThumbnailProjectPackageManifest(
            projectID: "",
            name: "",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            documentVersion: ThumbnailDocument.currentVersion,
            editorModeRawValue: ThumbnailDocumentEditorMode.simple.rawValue,
            assets: [],
            documentAssets: ThumbnailVariantAssetRefs()
        ),
        files: [:]
    )

    var totalByteCount: Int {
        files.values.reduce(0) { $0 + $1.count }
    }
}

/// A validated package read from disk.
struct ThumbnailProjectPackage: Equatable {
    var manifest: ThumbnailProjectPackageManifest
    var contents: ThumbnailProjectPackageContents
}

enum ThumbnailProjectPackageCoding {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
