//
//  ThumbnailVariantStore.swift
//  ThumbnailMaker
//
//  FEATURE-02: persists a `ThumbnailVariantSet` beside the legacy single draft.
//  The legacy draft is still written first on every save, so the active design
//  is always recoverable even if this file cannot be written.
//

import Foundation

struct ThumbnailVariantLoadResult: Equatable {
    var set: ThumbnailVariantSet
    var missingAssetDigests: Set<String>
}

enum ThumbnailVariantStoreError: LocalizedError, Equatable {
    case setTooLarge(byteCount: Int)

    var errorDescription: String? {
        switch self {
        case .setTooLarge(let byteCount):
            let megabytes = ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
            let limit = ByteCountFormatter.string(
                fromByteCount: Int64(ThumbnailVariantStore.maximumByteCount),
                countStyle: .file
            )
            return "The variants are too large to save (\(megabytes), limit \(limit)). The active variant is still saved. Remove a variant or use smaller images."
        }
    }
}

final class ThumbnailVariantStore {
    static let maximumByteCount = 120 * 1024 * 1024

    let fileURL: URL
    private let maximumByteCount: Int
    private var lastSavedSet: ThumbnailVariantSet?

    init(fileURL: URL, maximumByteCount: Int = ThumbnailVariantStore.maximumByteCount) {
        self.fileURL = fileURL
        self.maximumByteCount = maximumByteCount
    }

    convenience init(kind: ThumbnailDraftStore.DraftKind) {
        self.init(fileURL: Self.defaultFileURL(for: kind))
    }

    /// Lives in the same directory as the draft so injected test stores and the
    /// real container both keep drafts and variants together.
    convenience init(siblingOf draftURL: URL, kind: ThumbnailDraftStore.DraftKind) {
        self.init(fileURL: Self.siblingURL(of: draftURL, kind: kind))
    }

    static func fileName(for kind: ThumbnailDraftStore.DraftKind) -> String {
        switch kind {
        case .simple:
            return "simple-maker-variants.json"
        case .premium:
            return "premium-maker-variants.json"
        }
    }

    static func defaultFileURL(for kind: ThumbnailDraftStore.DraftKind) -> URL {
        siblingURL(of: ThumbnailDraftStore.defaultFileURL(for: kind), kind: kind)
    }

    static func siblingURL(of draftURL: URL, kind: ThumbnailDraftStore.DraftKind) -> URL {
        draftURL.deletingLastPathComponent().appendingPathComponent(fileName(for: kind))
    }

    func save(_ set: ThumbnailVariantSet) throws {
        let set = set.normalized()
        // Autosave fires on every editing pause; skip identical rewrites.
        if let lastSavedSet, lastSavedSet == set,
           FileManager.default.fileExists(atPath: fileURL.path) {
            return
        }

        var assets: [String: Data] = [:]
        let variants = set.variants.map { variant -> StoredVariant in
            let dehydrated = ThumbnailVariantAssetLibrary.dehydrate(variant.document, into: &assets)
            return StoredVariant(
                slot: variant.slot,
                name: variant.name,
                createdAt: variant.createdAt,
                updatedAt: variant.updatedAt,
                document: dehydrated.document,
                assets: dehydrated.refs
            )
        }

        let rawAssetBytes = assets.values.reduce(0) { $0 + $1.count }
        // Base64 inflates payloads by 4/3; fail fast before encoding a huge file.
        if rawAssetBytes * 4 / 3 > maximumByteCount {
            throw ThumbnailVariantStoreError.setTooLarge(byteCount: rawAssetBytes * 4 / 3)
        }

        let stored = StoredFile(
            version: set.version,
            updatedAt: set.updatedAt,
            editorMode: set.editorMode,
            projectName: set.projectName,
            activeSlot: set.activeSlot,
            preferredSlot: set.preferredSlot,
            assets: assets,
            variants: variants
        )
        let data = try Self.encoder.encode(stored)
        guard data.count <= maximumByteCount else {
            throw ThumbnailVariantStoreError.setTooLarge(byteCount: data.count)
        }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic])
        lastSavedSet = set
    }

    func load() throws -> ThumbnailVariantLoadResult? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let data = try Data(contentsOf: fileURL)
        let stored = try Self.decoder.decode(StoredFile.self, from: data)
        var missing = Set<String>()
        let variants = stored.variants.map { storedVariant -> ThumbnailVariant in
            let hydrated = ThumbnailVariantAssetLibrary.hydrate(
                storedVariant.document,
                refs: storedVariant.assets,
                assets: stored.assets
            )
            missing.formUnion(hydrated.missingDigests)
            return ThumbnailVariant(
                slot: storedVariant.slot,
                name: storedVariant.name,
                createdAt: storedVariant.createdAt,
                updatedAt: storedVariant.updatedAt,
                document: hydrated.document
            )
        }

        let set = ThumbnailVariantSet(
            version: max(stored.version, ThumbnailVariantSet.currentVersion),
            updatedAt: stored.updatedAt,
            editorMode: stored.editorMode,
            projectName: stored.projectName,
            activeSlot: stored.activeSlot,
            preferredSlot: stored.preferredSlot,
            variants: variants
        ).normalized()
        lastSavedSet = missing.isEmpty ? set : nil
        return ThumbnailVariantLoadResult(set: set, missingAssetDigests: missing)
    }

    func delete() throws {
        lastSavedSet = nil
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    // MARK: Persisted envelope

    struct StoredVariant: Codable, Equatable {
        var slot: ThumbnailVariantSlot
        var name: String
        var createdAt: Date
        var updatedAt: Date
        var document: ThumbnailDocument
        var assets: ThumbnailVariantAssetRefs

        private enum CodingKeys: String, CodingKey {
            case slot, name, createdAt, updatedAt, document, assets
        }

        init(
            slot: ThumbnailVariantSlot,
            name: String,
            createdAt: Date,
            updatedAt: Date,
            document: ThumbnailDocument,
            assets: ThumbnailVariantAssetRefs
        ) {
            self.slot = slot
            self.name = name
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.document = document
            self.assets = assets
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            slot = try container.decode(ThumbnailVariantSlot.self, forKey: .slot)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? slot.defaultName
            document = try container.decode(ThumbnailDocument.self, forKey: .document)
            createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? document.updatedAt
            updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? document.updatedAt
            assets = try container.decodeIfPresent(ThumbnailVariantAssetRefs.self, forKey: .assets)
                ?? ThumbnailVariantAssetRefs()
        }
    }

    struct StoredFile: Codable, Equatable {
        var version: Int
        var updatedAt: Date
        var editorMode: ThumbnailDocumentEditorMode
        var projectName: String
        var activeSlot: ThumbnailVariantSlot
        var preferredSlot: ThumbnailVariantSlot?
        var assets: [String: Data]
        var variants: [StoredVariant]

        private enum CodingKeys: String, CodingKey {
            case version, updatedAt, editorMode, projectName, activeSlot, preferredSlot, assets, variants
        }

        init(
            version: Int,
            updatedAt: Date,
            editorMode: ThumbnailDocumentEditorMode,
            projectName: String,
            activeSlot: ThumbnailVariantSlot,
            preferredSlot: ThumbnailVariantSlot?,
            assets: [String: Data],
            variants: [StoredVariant]
        ) {
            self.version = version
            self.updatedAt = updatedAt
            self.editorMode = editorMode
            self.projectName = projectName
            self.activeSlot = activeSlot
            self.preferredSlot = preferredSlot
            self.assets = assets
            self.variants = variants
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            variants = try container.decode([StoredVariant].self, forKey: .variants)
            version = try container.decodeIfPresent(Int.self, forKey: .version) ?? ThumbnailVariantSet.currentVersion
            updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
            editorMode = try container.decodeIfPresent(ThumbnailDocumentEditorMode.self, forKey: .editorMode) ?? .simple
            projectName = try container.decodeIfPresent(String.self, forKey: .projectName) ?? ""
            activeSlot = try container.decodeIfPresent(ThumbnailVariantSlot.self, forKey: .activeSlot)
                ?? variants.map(\.slot).min() ?? .a
            preferredSlot = try container.decodeIfPresent(ThumbnailVariantSlot.self, forKey: .preferredSlot)
            assets = try container.decodeIfPresent([String: Data].self, forKey: .assets) ?? [:]
        }
    }

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

// MARK: - Restore / migration

struct ThumbnailVariantRestoreResult: Equatable {
    var set: ThumbnailVariantSet
    var warning: String?
    var migratedFromLegacyDraft: Bool
}

extension ThumbnailVariantStore {
    static let missingImagesWarning = "Some variant images could not be restored. The other parts of your variants opened normally."
    static let unreadableVariantsWarning = "Your variants could not be opened, so only the last saved design was restored."

    /// Opens the variant set, migrating a pre-variant single draft when no set
    /// exists yet. The legacy draft is written first on every save, so when it
    /// disagrees with the set's active variant (e.g. the variant write failed)
    /// the draft wins for that slot. Never throws: damaged variant files fall
    /// back to the legacy draft.
    func restoreSet(
        legacyDraft: ThumbnailDocument?,
        editorMode: ThumbnailDocumentEditorMode
    ) -> ThumbnailVariantRestoreResult? {
        let loaded: ThumbnailVariantLoadResult?
        var warning: String?
        do {
            loaded = try load()
        } catch {
            print("Failed to restore variants: \(error.localizedDescription)")
            loaded = nil
            warning = Self.unreadableVariantsWarning
        }

        guard let loaded else {
            guard let legacyDraft else { return nil }
            return ThumbnailVariantRestoreResult(
                set: ThumbnailVariantSet(seedDocument: legacyDraft, editorMode: editorMode),
                warning: warning,
                migratedFromLegacyDraft: true
            )
        }

        var set = loaded.set
        if let legacyDraft {
            set.updateDocument(legacyDraft, for: set.activeSlot, now: set.updatedAt)
        }
        if !loaded.missingAssetDigests.isEmpty {
            warning = Self.missingImagesWarning
        }
        return ThumbnailVariantRestoreResult(set: set, warning: warning, migratedFromLegacyDraft: false)
    }
}
