//
//  ThumbnailProjectStore.swift
//  ThumbnailMaker
//
//  FEATURE-01: pure file I/O for the project library.
//
//  <root>/index.json              ThumbnailProjectLibraryIndex (metadata only)
//  <root>/<uuid>/document.json    a plain ThumbnailDocument (same shape as a draft file)
//  <root>/<uuid>/project.json     metadata sidecar, used to rebuild a damaged index
//  <root>/<uuid>/preview.png      derived cache, always safe to regenerate
//  <root>/quarantine/             damaged index files are moved here, never deleted
//
//  Directories are named by UUID only, never by user text.
//

import Foundation

/// Anything an editor can save its document through.
protocol ThumbnailDocumentPersisting: AnyObject {
    func save(_ document: ThumbnailDocument) throws
    func loadDocument() throws -> ThumbnailDocument?
}

extension ThumbnailDraftStore: ThumbnailDocumentPersisting {}

/// Immutable after init (only a root URL), so it is safe to hand to detached tasks.
final class ThumbnailProjectStore: @unchecked Sendable {
    static let indexFileName = "index.json"
    static let documentFileName = "document.json"
    static let sidecarFileName = "project.json"
    static let previewFileName = "preview.png"
    static let quarantineDirectoryName = "quarantine"

    let rootDirectory: URL
    private var fileManager: FileManager { FileManager.default }

    init(rootDirectory: URL = ThumbnailProjectStore.defaultRootDirectory) {
        self.rootDirectory = rootDirectory
    }

    static var defaultRootDirectory: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return applicationSupport
            .appendingPathComponent("ThumbnailMaker", isDirectory: true)
            .appendingPathComponent("Projects", isDirectory: true)
    }

    var indexURL: URL { rootDirectory.appendingPathComponent(Self.indexFileName) }
    var quarantineDirectory: URL {
        rootDirectory.appendingPathComponent(Self.quarantineDirectoryName, isDirectory: true)
    }

    func projectDirectory(id: UUID) -> URL {
        rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func documentURL(id: UUID) -> URL {
        projectDirectory(id: id).appendingPathComponent(Self.documentFileName)
    }

    func sidecarURL(id: UUID) -> URL {
        projectDirectory(id: id).appendingPathComponent(Self.sidecarFileName)
    }

    func previewURL(id: UUID) -> URL {
        projectDirectory(id: id).appendingPathComponent(Self.previewFileName)
    }

    // MARK: Index

    /// Missing index -> empty library. Damaged index -> quarantined (never
    /// deleted) and rebuilt from the per-project sidecars.
    func loadIndex() throws -> (index: ThumbnailProjectLibraryIndex, rebuilt: Bool) {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return (ThumbnailProjectLibraryIndex(), false)
        }

        let data = try Data(contentsOf: indexURL)
        if let index = try? Self.metadataDecoder.decode(ThumbnailProjectLibraryIndex.self, from: data) {
            return (index, false)
        }

        try quarantineIndex()
        let rebuilt = rebuildIndexFromSidecars()
        try saveIndex(rebuilt)
        return (rebuilt, true)
    }

    func saveIndex(_ index: ThumbnailProjectLibraryIndex) throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try Self.metadataEncoder.encode(index).write(to: indexURL, options: [.atomic])
    }

    private func quarantineIndex() throws {
        try fileManager.createDirectory(at: quarantineDirectory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        var destination = quarantineDirectory.appendingPathComponent("index-\(stamp).json")
        if fileManager.fileExists(atPath: destination.path) {
            destination = quarantineDirectory.appendingPathComponent("index-\(stamp)-\(UUID().uuidString).json")
        }
        try fileManager.moveItem(at: indexURL, to: destination)
    }

    func rebuildIndexFromSidecars() -> ThumbnailProjectLibraryIndex {
        var index = ThumbnailProjectLibraryIndex()
        let entries = (try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        )) ?? []

        for entry in entries {
            guard let id = UUID(uuidString: entry.lastPathComponent),
                  let data = try? Data(contentsOf: sidecarURL(id: id)),
                  let metadata = try? Self.metadataDecoder.decode(ThumbnailProjectMetadata.self, from: data),
                  metadata.id == id else {
                continue
            }
            index.upsert(metadata)
        }

        index.projects.sort { $0.updatedAt > $1.updatedAt }
        // Every kind that already produced a migrated project stays migrated.
        for metadata in index.projects {
            switch metadata.origin {
            case .migratedSimpleDraft where !index.migratedLegacyDraftKinds.contains("simple"):
                index.migratedLegacyDraftKinds.append("simple")
            case .migratedPremiumDraft where !index.migratedLegacyDraftKinds.contains("premium"):
                index.migratedLegacyDraftKinds.append("premium")
            default:
                break
            }
        }
        return index
    }

    // MARK: Documents

    func loadDocument(id: UUID) throws -> ThumbnailDocument {
        let data = try Data(contentsOf: documentURL(id: id))
        return try Self.documentDecoder.decode(ThumbnailDocument.self, from: data)
    }

    /// Atomic: a failed write leaves the previous bytes intact.
    func saveDocument(_ document: ThumbnailDocument, id: UUID) throws {
        let directory = projectDirectory(id: id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.documentEncoder.encode(document).write(to: documentURL(id: id), options: [.atomic])
    }

    func saveMetadataSidecar(_ metadata: ThumbnailProjectMetadata) throws {
        let directory = projectDirectory(id: metadata.id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.metadataEncoder.encode(metadata).write(to: sidecarURL(id: metadata.id), options: [.atomic])
    }

    func loadPreviewData(id: UUID) -> Data? {
        try? Data(contentsOf: previewURL(id: id))
    }

    func savePreviewData(_ data: Data, id: UUID) throws {
        let directory = projectDirectory(id: id)
        guard fileManager.fileExists(atPath: directory.path) else {
            throw ThumbnailProjectLibraryError.projectNotFound(id)
        }
        try data.write(to: previewURL(id: id), options: [.atomic])
    }

    /// Duplicate = verbatim byte copy of document.json (and preview if present).
    func copyProjectFiles(from sourceID: UUID, to destinationID: UUID) throws {
        let destination = projectDirectory(id: destinationID)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let bytes = try Data(contentsOf: documentURL(id: sourceID))
        try bytes.write(to: documentURL(id: destinationID), options: [.atomic])
        if let preview = loadPreviewData(id: sourceID) {
            try? preview.write(to: previewURL(id: destinationID), options: [.atomic])
        }
    }

    /// The ONLY destructive call; used by an explicit purge.
    func purgeDirectory(id: UUID) throws {
        let directory = projectDirectory(id: id)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    // MARK: Coders

    /// Same shape as ThumbnailDraftStore's (file-private there) so a
    /// document.json is byte-compatible with a draft file.
    static var documentEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var documentDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Metadata keeps fractional seconds so ordering is stable within a second.
    static var metadataEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractionalFormatter().string(from: date))
        }
        return encoder
    }

    static var metadataDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = fractionalFormatter().date(from: string)
                ?? ISO8601DateFormatter().date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date \(string)"
            )
        }
        return decoder
    }

    private static func fractionalFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
