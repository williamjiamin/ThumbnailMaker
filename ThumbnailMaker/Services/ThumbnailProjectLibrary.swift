//
//  ThumbnailProjectLibrary.swift
//  ThumbnailMaker
//
//  FEATURE-01: the observable project library. Layered on top of
//  ThumbnailProjectStore; never decodes a document just to list projects.
//
//  Safety rules:
//  - Nothing is removed from disk except by an explicit `purge`.
//  - Legacy draft files are read for migration and never deleted.
//  - A corrupt project is isolated: it is listed as "couldn't open",
//    its bytes are left untouched, and every other project still opens.
//  - A project written by a newer schema is refused, never re-saved.
//

import Foundation
import SwiftUI

@MainActor
final class ThumbnailProjectLibrary: ObservableObject {
    static let shared: ThumbnailProjectLibrary = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestSeedProjectLibrary") {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("UITestProjectLibrary", isDirectory: true)
            return ThumbnailProjectLibrary(store: ThumbnailProjectStore(rootDirectory: root))
        }
        #endif
        return ThumbnailProjectLibrary()
    }()

    let store: ThumbnailProjectStore
    private let previewRenderer: ThumbnailProjectPreviewRendering
    private let previewDelay: TimeInterval

    @Published private(set) var projects: [ThumbnailProjectSummary] = []
    @Published private(set) var trashedProjects: [ThumbnailProjectSummary] = []
    @Published var libraryError: String?
    @Published private(set) var didRebuildIndex = false
    /// Bumped whenever a project's preview.png is rewritten, so cards reload.
    @Published private(set) var previewRevisions: [UUID: Int] = [:]

    private var index = ThumbnailProjectLibraryIndex()
    private var unreadableProjects: [UUID: String] = [:]
    private var previewTasks: [UUID: Task<Void, Never>] = [:]
    /// False when the index exists but could not be read for an I/O reason;
    /// writing would clobber it, so mutations are refused instead.
    private(set) var isIndexWritable = true

    init(
        store: ThumbnailProjectStore = ThumbnailProjectStore(),
        previewRenderer: ThumbnailProjectPreviewRendering = ThumbnailProjectPreviewRenderer(),
        previewDelay: TimeInterval = 1.0
    ) {
        self.store = store
        self.previewRenderer = previewRenderer
        self.previewDelay = previewDelay
        refresh()
    }

    // MARK: - Read

    /// Reads index.json only. Never decodes a document.
    func refresh() {
        do {
            let result = try store.loadIndex()
            index = result.index
            isIndexWritable = true
            if result.rebuilt {
                didRebuildIndex = true
                libraryError = ThumbnailProjectLibraryError
                    .indexRebuilt("it could not be decoded")
                    .errorDescription
            }
        } catch {
            isIndexWritable = false
            libraryError = ThumbnailProjectLibraryError
                .writeFailed(error.localizedDescription)
                .errorDescription
        }
        publish()
    }

    func projects(
        matching query: String,
        editorMode: ThumbnailDocumentEditorMode? = nil
    ) -> [ThumbnailProjectSummary] {
        projects.filter { summary in
            (editorMode == nil || summary.metadata.editorMode == editorMode)
                && summary.metadata.matches(query: query)
        }
    }

    func trashedProjects(editorMode: ThumbnailDocumentEditorMode? = nil) -> [ThumbnailProjectSummary] {
        trashedProjects.filter { editorMode == nil || $0.metadata.editorMode == editorMode }
    }

    func metadata(id: UUID) -> ThumbnailProjectMetadata? {
        index.metadata(id: id)
    }

    var migratedLegacyDraftKinds: [String] { index.migratedLegacyDraftKinds }
    var migrationWarnings: [String: String] { index.migrationWarnings }

    func document(for id: UUID) throws -> ThumbnailDocument {
        guard let metadata = index.metadata(id: id) else {
            throw ThumbnailProjectLibraryError.projectNotFound(id)
        }
        guard metadata.isSupported else {
            throw ThumbnailProjectLibraryError.unsupportedSchema(id, metadata.schemaVersion)
        }

        do {
            let document = try store.loadDocument(id: id)
            if unreadableProjects.removeValue(forKey: id) != nil {
                publish()
            }
            return document
        } catch {
            let reason = Self.shortReason(for: error)
            unreadableProjects[id] = reason
            publish()
            throw ThumbnailProjectLibraryError.documentUnreadable(id, reason)
        }
    }

    func previewData(for id: UUID) async -> Data? {
        let store = store
        return await Task.detached(priority: .utility) {
            store.loadPreviewData(id: id)
        }.value
    }

    // MARK: - Mutate

    @discardableResult
    func createProject(
        name: String,
        editorMode: ThumbnailDocumentEditorMode,
        document: ThumbnailDocument,
        origin: ThumbnailProjectOrigin = .created,
        timestamp: Date = Date()
    ) throws -> ThumbnailProjectMetadata {
        try insertProject(
            name: name,
            editorMode: editorMode,
            document: document,
            origin: origin,
            timestamp: timestamp,
            indexMutation: { _, _ in }
        )
    }

    /// Writes document.json FIRST, then touches the index. If the index write
    /// fails the document is already safe and only `updatedAt` is stale.
    func saveDocument(_ document: ThumbnailDocument, for id: UUID) throws {
        guard var metadata = index.metadata(id: id) else {
            throw ThumbnailProjectLibraryError.projectNotFound(id)
        }
        guard metadata.isSupported else {
            throw ThumbnailProjectLibraryError.unsupportedSchema(id, metadata.schemaVersion)
        }

        try store.saveDocument(document, id: id)

        metadata.updatedAt = document.updatedAt
        unreadableProjects.removeValue(forKey: id)
        try? commitIndex { $0.upsert(metadata) }
        try? store.saveMetadataSidecar(metadata)
        publish()
    }

    func rename(id: UUID, to name: String) throws {
        guard var metadata = index.metadata(id: id) else {
            throw ThumbnailProjectLibraryError.projectNotFound(id)
        }
        metadata.name = ThumbnailProjectMetadata.sanitizedName(name)
        try commitIndex { $0.upsert(metadata) }
        try? store.saveMetadataSidecar(metadata)
        publish()
    }

    /// New UUID + verbatim byte copy, so editing one can never touch the other.
    @discardableResult
    func duplicate(id: UUID) throws -> ThumbnailProjectMetadata {
        guard let source = index.metadata(id: id) else {
            throw ThumbnailProjectLibraryError.projectNotFound(id)
        }

        let now = Date()
        var copy = ThumbnailProjectMetadata(
            name: uniqueCopyName(of: source.name),
            createdAt: now,
            updatedAt: now,
            editorMode: source.editorMode,
            origin: .duplicated
        )
        copy.schemaVersion = source.schemaVersion

        do {
            try store.copyProjectFiles(from: id, to: copy.id)
            try store.saveMetadataSidecar(copy)
        } catch {
            throw ThumbnailProjectLibraryError.writeFailed(Self.shortReason(for: error))
        }
        try commitIndex { $0.upsert(copy) }
        publish()
        return copy
    }

    /// Sets `deletedAt`; nothing is removed from disk.
    func moveToTrash(id: UUID) throws {
        guard var metadata = index.metadata(id: id) else {
            throw ThumbnailProjectLibraryError.projectNotFound(id)
        }
        metadata.deletedAt = Date()
        try commitIndex { index in
            index.upsert(metadata)
            if index.activeSimpleProjectID == id { index.activeSimpleProjectID = nil }
            if index.activePremiumProjectID == id { index.activePremiumProjectID = nil }
        }
        try? store.saveMetadataSidecar(metadata)
        publish()
    }

    func restoreFromTrash(id: UUID) throws {
        guard var metadata = index.metadata(id: id) else {
            throw ThumbnailProjectLibraryError.projectNotFound(id)
        }
        metadata.deletedAt = nil
        try commitIndex { $0.upsert(metadata) }
        try? store.saveMetadataSidecar(metadata)
        publish()
    }

    /// The ONLY destructive path. Explicit user action only.
    func purge(id: UUID) throws {
        guard index.metadata(id: id) != nil else {
            throw ThumbnailProjectLibraryError.projectNotFound(id)
        }
        previewTasks[id]?.cancel()
        previewTasks[id] = nil
        try commitIndex { $0.remove(id: id) }
        do {
            try store.purgeDirectory(id: id)
        } catch {
            // Index no longer references it; the directory is an orphan the
            // user can never see. Report but do not resurrect.
            libraryError = ThumbnailProjectLibraryError
                .writeFailed(Self.shortReason(for: error))
                .errorDescription
        }
        unreadableProjects.removeValue(forKey: id)
        previewRevisions.removeValue(forKey: id)
        publish()
    }

    /// Implemented and tested, but intentionally NOT called automatically.
    @discardableResult
    func purgeExpiredTrash(olderThan interval: TimeInterval, now: Date = Date()) -> [UUID] {
        let cutoff = now.addingTimeInterval(-interval)
        let expired = index.projects
            .filter { ($0.deletedAt.map { $0 < cutoff }) ?? false }
            .map(\.id)
        var purged: [UUID] = []
        for id in expired where (try? purge(id: id)) != nil {
            purged.append(id)
        }
        return purged
    }

    func activeProjectID(for mode: ThumbnailDocumentEditorMode) -> UUID? {
        index.activeProjectID(for: mode)
    }

    func setActiveProjectID(_ id: UUID?, for mode: ThumbnailDocumentEditorMode) {
        guard index.activeProjectID(for: mode) != id else { return }
        try? commitIndex { $0.setActiveProjectID(id, for: mode) }
    }

    // MARK: - Opening for an editor

    /// Migrates this editor's legacy draft once, then opens the active
    /// project, falling back to the newest readable one, then to a new one.
    /// Returns nil only when the library cannot be written at all.
    func openInitialProject(
        for mode: ThumbnailDocumentEditorMode,
        legacyStore: ThumbnailDocumentPersisting?,
        defaultDocument: () -> ThumbnailDocument
    ) -> ThumbnailProjectOpenResult? {
        if let legacyStore {
            migrateLegacyDraftIfNeeded(for: mode, from: legacyStore)
        }

        var warning: String?
        let activeID = index.activeProjectID(for: mode)
        if let activeID,
           let metadata = index.metadata(id: activeID),
           !metadata.isTrashed,
           metadata.editorMode == mode {
            do {
                let document = try document(for: activeID)
                return ThumbnailProjectOpenResult(metadata: metadata, document: document, warning: nil)
            } catch {
                warning = "\"\(metadata.name)\": " + (error.localizedDescription)
            }
        }

        guard var result = openFallbackProject(
            for: mode,
            excluding: activeID,
            defaultDocument: defaultDocument
        ) else {
            return nil
        }
        if let warning {
            result.warning = warning
            libraryError = warning
        }
        return result
    }

    /// Newest readable live project of this editor mode, else a new one.
    func openFallbackProject(
        for mode: ThumbnailDocumentEditorMode,
        excluding excludedID: UUID?,
        defaultDocument: () -> ThumbnailDocument
    ) -> ThumbnailProjectOpenResult? {
        let candidates = index.projects
            .filter { !$0.isTrashed && $0.editorMode == mode && $0.id != excludedID && $0.isSupported }
            .sorted(by: Self.liveOrder)

        for metadata in candidates {
            if let document = try? document(for: metadata.id) {
                setActiveProjectID(metadata.id, for: mode)
                return ThumbnailProjectOpenResult(metadata: metadata, document: document, warning: nil)
            }
        }

        var document = defaultDocument()
        document.editorMode = mode
        do {
            let metadata = try insertProject(
                name: ThumbnailProjectMetadata.defaultName,
                editorMode: mode,
                document: document,
                origin: .created,
                timestamp: Date(),
                indexMutation: { draftIndex, created in draftIndex.setActiveProjectID(created.id, for: mode) }
            )
            return ThumbnailProjectOpenResult(metadata: metadata, document: document, warning: nil)
        } catch {
            libraryError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Migration

    func migrateLegacyDraftsIfNeeded(
        simpleStore: ThumbnailDocumentPersisting,
        premiumStore: ThumbnailDocumentPersisting
    ) {
        migrateLegacyDraftIfNeeded(for: .simple, from: simpleStore)
        migrateLegacyDraftIfNeeded(for: .premium, from: premiumStore)
    }

    /// Idempotent by two independent mechanisms: the ledger, and an
    /// origin-based content check (covers a lost ledger write). The legacy
    /// file is never deleted.
    func migrateLegacyDraftIfNeeded(
        for mode: ThumbnailDocumentEditorMode,
        from legacyStore: ThumbnailDocumentPersisting
    ) {
        let kind = mode.rawValue
        guard isIndexWritable, !index.migratedLegacyDraftKinds.contains(kind) else { return }

        let origin = ThumbnailProjectOrigin.migrated(for: mode)
        if index.projects.contains(where: { $0.origin == origin }) {
            try? commitIndex { $0.migratedLegacyDraftKinds.append(kind) }
            return
        }

        let legacyDocument: ThumbnailDocument?
        do {
            legacyDocument = try legacyStore.loadDocument()
        } catch {
            let message = "Your previous \(mode == .simple ? "Simple" : "Premium") draft couldn't be read (\(Self.shortReason(for: error))). The file was kept on disk and was not changed."
            try? commitIndex { index in
                index.migratedLegacyDraftKinds.append(kind)
                index.migrationWarnings[kind] = message
            }
            libraryError = message
            return
        }

        guard var document = legacyDocument else {
            try? commitIndex { $0.migratedLegacyDraftKinds.append(kind) }
            return
        }

        document.editorMode = mode
        do {
            try insertProject(
                name: mode == .simple ? "Simple Draft" : "Premium Draft",
                editorMode: mode,
                document: document,
                origin: origin,
                timestamp: document.updatedAt,
                indexMutation: { draftIndex, created in
                    draftIndex.migratedLegacyDraftKinds.append(kind)
                    draftIndex.setActiveProjectID(created.id, for: mode)
                }
            )
        } catch {
            // Not recorded as migrated: the next launch retries.
            libraryError = error.localizedDescription
        }
    }

    // MARK: - Previews

    /// Coalesced per project; failures are swallowed and never surface as a
    /// save error. Always runs after the save has returned.
    func schedulePreviewRefresh(for id: UUID, document: ThumbnailDocument) {
        previewTasks[id]?.cancel()
        let delay = previewDelay
        let renderer = previewRenderer
        let store = store
        previewTasks[id] = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            guard let data = await renderer.previewPNGData(for: document, maxPixelWidth: 640),
                  !Task.isCancelled else { return }
            let didWrite = await Task.detached(priority: .utility) {
                (try? store.savePreviewData(data, id: id)) != nil
            }.value
            guard let self, didWrite else { return }
            self.previewRevisions[id, default: 0] += 1
        }
    }

    /// Test/diagnostic hook: waits for every in-flight preview render.
    func waitForPendingPreviews() async {
        let tasks = Array(previewTasks.values)
        for task in tasks {
            await task.value
        }
    }

    // MARK: - Private

    @discardableResult
    private func insertProject(
        name: String,
        editorMode: ThumbnailDocumentEditorMode,
        document: ThumbnailDocument,
        origin: ThumbnailProjectOrigin,
        timestamp: Date,
        indexMutation: (inout ThumbnailProjectLibraryIndex, ThumbnailProjectMetadata) -> Void
    ) throws -> ThumbnailProjectMetadata {
        guard isIndexWritable else {
            throw ThumbnailProjectLibraryError.writeFailed("the project list could not be read")
        }

        let metadata = ThumbnailProjectMetadata(
            name: name,
            createdAt: timestamp,
            updatedAt: timestamp,
            editorMode: editorMode,
            origin: origin
        )

        do {
            try store.saveDocument(document, id: metadata.id)
            try store.saveMetadataSidecar(metadata)
        } catch {
            throw ThumbnailProjectLibraryError.writeFailed(Self.shortReason(for: error))
        }

        try commitIndex { index in
            index.upsert(metadata)
            indexMutation(&index, metadata)
        }
        publish()
        return metadata
    }

    /// Mutates a copy, persists it, and only then adopts it in memory.
    private func commitIndex(_ mutate: (inout ThumbnailProjectLibraryIndex) -> Void) throws {
        guard isIndexWritable else {
            throw ThumbnailProjectLibraryError.writeFailed("the project list could not be read")
        }
        var next = index
        mutate(&next)
        do {
            try store.saveIndex(next)
        } catch {
            throw ThumbnailProjectLibraryError.writeFailed(Self.shortReason(for: error))
        }
        index = next
    }

    private func uniqueCopyName(of name: String) -> String {
        let existing = Set(index.projects.map(\.name))
        let base = ThumbnailProjectMetadata.sanitizedName("\(name) copy")
        guard existing.contains(base) else { return base }
        var counter = 2
        while existing.contains("\(base) \(counter)") {
            counter += 1
        }
        return "\(base) \(counter)"
    }

    private func publish() {
        let summaries = index.projects.map { metadata in
            ThumbnailProjectSummary(
                metadata: metadata,
                loadFailureMessage: unreadableProjects[metadata.id]
                    ?? (metadata.isSupported ? nil : "Made with a newer app version")
            )
        }
        let live = summaries.filter { !$0.metadata.isTrashed }
            .sorted { Self.liveOrder($0.metadata, $1.metadata) }
        let trashed = summaries.filter { $0.metadata.isTrashed }
            .sorted { ($0.metadata.deletedAt ?? .distantPast) > ($1.metadata.deletedAt ?? .distantPast) }
        if live != projects { projects = live }
        if trashed != trashedProjects { trashedProjects = trashed }
    }

    private static func liveOrder(_ lhs: ThumbnailProjectMetadata, _ rhs: ThumbnailProjectMetadata) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func shortReason(for error: Error) -> String {
        if let libraryError = error as? ThumbnailProjectLibraryError {
            switch libraryError {
            case .writeFailed(let reason), .documentUnreadable(_, let reason), .indexRebuilt(let reason):
                return reason
            default:
                return libraryError.localizedDescription
            }
        }
        if error is DecodingError {
            return "the file is damaged"
        }
        return error.localizedDescription
    }
}
