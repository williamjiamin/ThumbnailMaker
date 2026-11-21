//
//  ThumbnailProject.swift
//  ThumbnailMaker
//
//  FEATURE-01: named, listable, recoverable project library.
//  Project identity lives in metadata (not in ThumbnailDocument) so the
//  document payload stays byte-compatible with the legacy draft files.
//

import Foundation

enum ThumbnailProjectOrigin: String, Codable, Equatable {
    case created
    case duplicated
    case migratedSimpleDraft
    case migratedPremiumDraft
    /// FEATURE-06: created from a .thumbproj package. Older builds decode an
    /// unknown origin as `.created`, so this stays back-compatible.
    case imported

    static func migrated(for mode: ThumbnailDocumentEditorMode) -> ThumbnailProjectOrigin {
        switch mode {
        case .simple: return .migratedSimpleDraft
        case .premium: return .migratedPremiumDraft
        }
    }
}

struct ThumbnailProjectMetadata: Codable, Equatable, Identifiable {
    static let currentSchemaVersion = 1
    static let defaultName = "Untitled Project"
    static let maximumNameLength = 120

    var id: UUID
    var schemaVersion: Int = ThumbnailProjectMetadata.currentSchemaVersion
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var editorMode: ThumbnailDocumentEditorMode
    /// nil == live; non-nil == in trash. Nothing is removed from disk until an explicit purge.
    var deletedAt: Date? = nil
    var originRawValue: String = ThumbnailProjectOrigin.created.rawValue
    var previewFileName: String? = "preview.png"
    var documentFileName: String = "document.json"

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date,
        updatedAt: Date,
        editorMode: ThumbnailDocumentEditorMode,
        origin: ThumbnailProjectOrigin = .created,
        deletedAt: Date? = nil,
        schemaVersion: Int = ThumbnailProjectMetadata.currentSchemaVersion
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.name = Self.sanitizedName(name)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.editorMode = editorMode
        self.deletedAt = deletedAt
        self.originRawValue = origin.rawValue
    }

    private enum CodingKeys: String, CodingKey {
        case id, schemaVersion, name, createdAt, updatedAt, editorMode
        case deletedAt, originRawValue, previewFileName, documentFileName
    }

    /// Back-compat contract: only identity fields are required; every later
    /// addition decodes with `decodeIfPresent ?? default`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        editorMode = try container.decode(ThumbnailDocumentEditorMode.self, forKey: .editorMode)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? Self.currentSchemaVersion
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        originRawValue = try container.decodeIfPresent(String.self, forKey: .originRawValue)
            ?? ThumbnailProjectOrigin.created.rawValue
        previewFileName = try container.decodeIfPresent(String.self, forKey: .previewFileName)
            ?? "preview.png"
        documentFileName = try container.decodeIfPresent(String.self, forKey: .documentFileName)
            ?? "document.json"
    }

    var isTrashed: Bool { deletedAt != nil }

    var origin: ThumbnailProjectOrigin {
        ThumbnailProjectOrigin(rawValue: originRawValue) ?? .created
    }

    /// A project written by a newer app is refused rather than opened and
    /// re-saved with unknown fields dropped.
    var isSupported: Bool { schemaVersion <= Self.currentSchemaVersion }

    static func sanitizedName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultName }
        return String(trimmed.prefix(maximumNameLength))
    }

    func matches(query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

struct ThumbnailProjectLibraryIndex: Codable, Equatable {
    static let currentVersion = 1

    var version: Int = ThumbnailProjectLibraryIndex.currentVersion
    var projects: [ThumbnailProjectMetadata] = []
    var activeSimpleProjectID: UUID? = nil
    var activePremiumProjectID: UUID? = nil
    /// One-time migration ledger: ["simple", "premium"].
    var migratedLegacyDraftKinds: [String] = []
    /// kind -> message, surfaced once.
    var migrationWarnings: [String: String] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case version, projects, activeSimpleProjectID, activePremiumProjectID
        case migratedLegacyDraftKinds, migrationWarnings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        projects = try container.decodeIfPresent([ThumbnailProjectMetadata].self, forKey: .projects) ?? []
        activeSimpleProjectID = try container.decodeIfPresent(UUID.self, forKey: .activeSimpleProjectID)
        activePremiumProjectID = try container.decodeIfPresent(UUID.self, forKey: .activePremiumProjectID)
        migratedLegacyDraftKinds = try container.decodeIfPresent(
            [String].self,
            forKey: .migratedLegacyDraftKinds
        ) ?? []
        migrationWarnings = try container.decodeIfPresent(
            [String: String].self,
            forKey: .migrationWarnings
        ) ?? [:]
    }

    func activeProjectID(for mode: ThumbnailDocumentEditorMode) -> UUID? {
        switch mode {
        case .simple: return activeSimpleProjectID
        case .premium: return activePremiumProjectID
        }
    }

    mutating func setActiveProjectID(_ id: UUID?, for mode: ThumbnailDocumentEditorMode) {
        switch mode {
        case .simple: activeSimpleProjectID = id
        case .premium: activePremiumProjectID = id
        }
    }

    func metadata(id: UUID) -> ThumbnailProjectMetadata? {
        projects.first { $0.id == id }
    }

    mutating func upsert(_ metadata: ThumbnailProjectMetadata) {
        if let position = projects.firstIndex(where: { $0.id == metadata.id }) {
            projects[position] = metadata
        } else {
            projects.append(metadata)
        }
    }

    mutating func remove(id: UUID) {
        projects.removeAll { $0.id == id }
        if activeSimpleProjectID == id { activeSimpleProjectID = nil }
        if activePremiumProjectID == id { activePremiumProjectID = nil }
    }
}

/// View-facing, not persisted.
struct ThumbnailProjectSummary: Identifiable, Equatable {
    let metadata: ThumbnailProjectMetadata
    var loadFailureMessage: String?

    var id: UUID { metadata.id }
    var name: String { metadata.name }
    var isReadable: Bool { loadFailureMessage == nil && metadata.isSupported }
}

enum ThumbnailProjectLibraryError: LocalizedError, Equatable {
    case projectNotFound(UUID)
    case documentUnreadable(UUID, String)
    case unsupportedSchema(UUID, Int)
    case writeFailed(String)
    case indexRebuilt(String)

    var errorDescription: String? {
        switch self {
        case .projectNotFound:
            return "That project could not be found in the library."
        case .documentUnreadable(_, let reason):
            return "This project couldn't be opened (\(reason)). Its file was left untouched on disk, so your work is still there."
        case .unsupportedSchema(_, let version):
            return "This project was saved by a newer version of ThumbnailMaker (format \(version)). Update the app to open it. Your work is still on disk."
        case .writeFailed(let reason):
            return "The project library could not be saved (\(reason)). Your work is still on disk."
        case .indexRebuilt(let reason):
            return "The project list was damaged (\(reason)) and has been rebuilt from your project files. The damaged list was kept in quarantine."
        }
    }
}

/// Result of opening a project for an editor.
struct ThumbnailProjectOpenResult {
    let metadata: ThumbnailProjectMetadata
    let document: ThumbnailDocument
    /// A user-facing warning to surface once (fallback, migration problem).
    var warning: String?
}
