//
//  ThumbnailProjectImporter.swift
//  ThumbnailMaker
//
//  FEATURE-06: turns a validated package into an import plan (pure), and
//  moves projects between the FEATURE-01 library and .thumbproj packages.
//
//  Import always creates a NEW library project (new UUID, collision-free
//  name). It never overwrites or merges into an existing project, and the
//  open project is untouched until the package has been fully validated.
//

import Foundation

struct ThumbnailProjectImportPlan: Equatable {
    var name: String
    var sourceName: String
    var editorMode: ThumbnailDocumentEditorMode
    var document: ThumbnailDocument
    var variantSet: ThumbnailVariantSet?
    var previewPNGData: Data?
    var didRenameForCollision: Bool
    var isCrossEditorImport: Bool
    var sourceEditorMode: ThumbnailDocumentEditorMode

    /// One-time, user-facing notes about the import (never errors).
    var notices: [String] {
        var notices: [String] = []
        if didRenameForCollision {
            notices.append("A project named \"\(sourceName)\" already exists, so the copy was named \"\(name)\".")
        }
        if isCrossEditorImport {
            switch (sourceEditorMode, editorMode) {
            case (.premium, .simple):
                notices.append("This project was made in Premium Maker. Simple Maker doesn't show the profile image, so it isn't included here.")
            default:
                notices.append("This project was made in \(sourceEditorMode == .simple ? "Simple" : "Premium") Maker and was opened here as a copy.")
            }
        }
        return notices
    }
}

enum ThumbnailProjectImporter {
    static func importPlan(
        for package: ThumbnailProjectPackage,
        into editorMode: ThumbnailDocumentEditorMode,
        existingNames: [String] = [],
        now: Date = Date()
    ) -> ThumbnailProjectImportPlan {
        let contents = package.contents
        let trimmed = contents.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceName = trimmed.isEmpty
            ? ThumbnailProjectPackageLayout.fallbackImportName
            : ThumbnailProjectMetadata.sanitizedName(trimmed)
        let name = uniqueName(sourceName, among: existingNames)

        let document = healed(contents.document, editorMode: editorMode, now: now)
        var variantSet = contents.variantSet.map { set -> ThumbnailVariantSet in
            var set = set
            set.editorMode = editorMode
            set.updatedAt = now
            for index in set.variants.indices {
                set.variants[index].document = healed(set.variants[index].document, editorMode: editorMode, now: now)
            }
            return set.normalized()
        }
        // The project document is the active variant's latest state.
        if var set = variantSet {
            if let index = set.variants.firstIndex(where: { $0.slot == set.activeSlot }) {
                set.variants[index].document = document
            }
            variantSet = set
        }

        return ThumbnailProjectImportPlan(
            name: name,
            sourceName: sourceName,
            editorMode: editorMode,
            document: document,
            variantSet: variantSet,
            previewPNGData: contents.previewPNGData,
            didRenameForCollision: name != sourceName,
            isCrossEditorImport: contents.editorMode != editorMode,
            sourceEditorMode: contents.editorMode
        )
    }

    /// "Launch Art" among ["Launch Art", "Launch Art 2"] -> "Launch Art 3".
    static func uniqueName(_ candidate: String, among existing: [String]) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        guard taken.contains(candidate.lowercased()) else { return candidate }
        var counter = 2
        while true {
            let suffix = " \(counter)"
            let base = String(candidate.prefix(ThumbnailProjectMetadata.maximumNameLength - suffix.count))
            let name = base + suffix
            if !taken.contains(name.lowercased()) {
                return name
            }
            counter += 1
        }
    }

    /// Repairs a hand-edited layer list without changing anything a valid
    /// document relies on: duplicate ids keep their first record, content
    /// layers with no content are dropped, and z-order is sorted (stable).
    /// Layer ids are kept verbatim: they are only unique within a document,
    /// and FEATURE-02 variants deliberately share them.
    static func healed(
        _ document: ThumbnailDocument,
        editorMode: ThumbnailDocumentEditorMode,
        now: Date
    ) -> ThumbnailDocument {
        var document = document
        let singletonIDs: Set<String> = [
            ThumbnailDocumentLayer.backgroundID,
            ThumbnailDocumentLayer.profileID,
            ThumbnailDocumentLayer.textID
        ]
        var seen = Set<String>()
        let kept = document.layers.filter { layer in
            guard seen.insert(layer.id).inserted else { return false }
            return singletonIDs.contains(layer.id) || layer.content != nil
        }
        document.layers = kept.enumerated()
            .sorted { lhs, rhs in
                lhs.element.zIndex != rhs.element.zIndex
                    ? lhs.element.zIndex < rhs.element.zIndex
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
        document.editorMode = editorMode
        document.updatedAt = now
        return document
    }
}

// MARK: - Library bridge

struct ThumbnailProjectImportOutcome {
    var openResult: ThumbnailProjectOpenResult
    var plan: ThumbnailProjectImportPlan
    /// Non-fatal problems while writing optional parts (variants, preview).
    var warnings: [String]

    var message: String {
        (["Imported \"\(plan.name)\"."] + plan.notices + warnings).joined(separator: " ")
    }
}

@MainActor
enum ThumbnailProjectTransfer {
    static let variantsNotImportedWarning = "Its A/B/C variants couldn't be saved, so only the current design was imported."

    /// Reads a library project (document, saved variants, cached preview)
    /// into package contents. Read-only.
    static func exportContents(
        projectID: UUID,
        library: ThumbnailProjectLibrary
    ) throws -> ThumbnailProjectPackageContents {
        guard let metadata = library.metadata(id: projectID) else {
            throw ThumbnailProjectPackageError.projectUnavailable
        }
        let document: ThumbnailDocument
        do {
            document = try library.document(for: projectID)
        } catch {
            throw ThumbnailProjectPackageError.writeFailed(error.localizedDescription)
        }

        var variantSet: ThumbnailVariantSet?
        let variantStore = ThumbnailVariantStore(
            fileURL: variantFileURL(projectID: projectID, editorMode: metadata.editorMode, library: library)
        )
        // Variants are optional: an unreadable or partially missing set is
        // left out rather than exported damaged.
        if let loaded = try? variantStore.load(), loaded.missingAssetDigests.isEmpty {
            var set = loaded.set
            set.updateDocument(document, for: set.activeSlot, now: set.updatedAt)
            variantSet = set
        }

        return ThumbnailProjectPackageContents(
            projectID: metadata.id.uuidString,
            name: metadata.name,
            createdAt: metadata.createdAt,
            updatedAt: metadata.updatedAt,
            editorMode: metadata.editorMode,
            document: document,
            variantSet: variantSet,
            previewPNGData: library.store.loadPreviewData(id: projectID)
        )
    }

    static func makeExportDocument(
        projectID: UUID,
        library: ThumbnailProjectLibrary,
        limits: ThumbnailProjectPackageLimits = .standard
    ) throws -> ThumbnailProjectFileDocument {
        let contents = try exportContents(projectID: projectID, library: library)
        let encoded = try ThumbnailProjectPackageWriter.encode(contents, limits: limits)
        return ThumbnailProjectFileDocument(package: encoded)
    }

    /// Validates the package completely, then adds it to the library as a new
    /// project. Does not open it; the caller adopts `openResult`.
    static func importPackage(
        _ package: ThumbnailProjectPackage,
        into library: ThumbnailProjectLibrary,
        editorMode: ThumbnailDocumentEditorMode,
        now: Date = Date()
    ) throws -> ThumbnailProjectImportOutcome {
        let existingNames = (library.projects + library.trashedProjects).map(\.name)
        let plan = ThumbnailProjectImporter.importPlan(
            for: package,
            into: editorMode,
            existingNames: existingNames,
            now: now
        )

        let metadata: ThumbnailProjectMetadata
        do {
            metadata = try library.createProject(
                name: plan.name,
                editorMode: editorMode,
                document: plan.document,
                origin: .imported,
                timestamp: now
            )
        } catch {
            throw ThumbnailProjectPackageError.writeFailed(error.localizedDescription)
        }

        var warnings: [String] = []
        if let variantSet = plan.variantSet {
            let store = ThumbnailVariantStore(
                fileURL: variantFileURL(projectID: metadata.id, editorMode: editorMode, library: library)
            )
            do {
                try store.save(variantSet)
            } catch {
                warnings.append(variantsNotImportedWarning)
            }
        }
        if let preview = plan.previewPNGData {
            try? library.store.savePreviewData(preview, id: metadata.id)
        }

        return ThumbnailProjectImportOutcome(
            openResult: ThumbnailProjectOpenResult(metadata: metadata, document: plan.document, warning: nil),
            plan: plan,
            warnings: warnings
        )
    }

    static func variantFileURL(
        projectID: UUID,
        editorMode: ThumbnailDocumentEditorMode,
        library: ThumbnailProjectLibrary
    ) -> URL {
        let kind: ThumbnailDraftStore.DraftKind = editorMode == .simple ? .simple : .premium
        return library.store.projectDirectory(id: projectID)
            .appendingPathComponent(ThumbnailVariantStore.fileName(for: kind))
    }
}

// MARK: - Editor hooks (both view models get these via ThumbnailProjectEditing)

extension ThumbnailProjectEditing {
    /// Commits pending edits when exporting the open project, then builds the
    /// package. Never changes the project.
    func exportProjectPackage(_ id: UUID) -> Result<ThumbnailProjectFileDocument, ThumbnailProjectPackageError> {
        guard let projectLibrary else { return .failure(.projectUnavailable) }
        if id == activeProjectID, !commitBeforeLeavingProject() {
            return .failure(.writeFailed("the current project couldn't be saved first"))
        }
        do {
            return .success(try ThumbnailProjectTransfer.makeExportDocument(projectID: id, library: projectLibrary))
        } catch let error as ThumbnailProjectPackageError {
            return .failure(error)
        } catch {
            return .failure(.writeFailed(error.localizedDescription))
        }
    }

    /// Reads and validates first; only a fully valid package reaches the
    /// library, and only a successfully created project replaces what the
    /// editor shows. Undo history starts fresh for the imported project; the
    /// previous project is saved and stays in the library unchanged.
    func importProjectPackage(from url: URL) -> Result<ThumbnailProjectImportOutcome, ThumbnailProjectPackageError> {
        let package: ThumbnailProjectPackage
        do {
            package = try ThumbnailProjectPackageReader.readPackage(at: url)
        } catch let error as ThumbnailProjectPackageError {
            return .failure(error)
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
        return importProjectPackage(package)
    }

    func importProjectPackage(_ package: ThumbnailProjectPackage) -> Result<ThumbnailProjectImportOutcome, ThumbnailProjectPackageError> {
        guard let projectLibrary else { return .failure(.projectUnavailable) }
        guard commitBeforeLeavingProject() else {
            return .failure(.writeFailed("the current project couldn't be saved first"))
        }
        do {
            let outcome = try ThumbnailProjectTransfer.importPackage(
                package,
                into: projectLibrary,
                editorMode: Self.projectEditorMode
            )
            adoptProject(outcome.openResult)
            return .success(outcome)
        } catch let error as ThumbnailProjectPackageError {
            return .failure(error)
        } catch {
            return .failure(.writeFailed(error.localizedDescription))
        }
    }
}
