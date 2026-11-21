//
//  ThumbnailVariantSet.swift
//  ThumbnailMaker
//
//  FEATURE-02: a set of up to three full `ThumbnailDocument`s (A/B/C).
//
//  Anti-requirement: nothing here computes, stores or displays a predicted or
//  measured winner, click-through rate, score or ranking. `preferredSlot` is
//  only ever set by an explicit user gesture.
//

import Foundation

struct ThumbnailVariant: Codable, Equatable, Identifiable {
    var slot: ThumbnailVariantSlot
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var document: ThumbnailDocument

    var id: ThumbnailVariantSlot { slot }
}

struct ThumbnailVariantSet: Codable, Equatable {
    static let currentVersion = 1
    static let maxVariantCount = ThumbnailVariantSlot.allCases.count
    static let maxNameLength = 40

    var version = currentVersion
    var updatedAt: Date
    var editorMode: ThumbnailDocumentEditorMode
    /// Optional export base name. Empty means "use the export preset name".
    var projectName: String
    var activeSlot: ThumbnailVariantSlot
    var preferredSlot: ThumbnailVariantSlot?
    var variants: [ThumbnailVariant]

    init(
        seedDocument: ThumbnailDocument,
        editorMode: ThumbnailDocumentEditorMode,
        projectName: String = "",
        now: Date = Date()
    ) {
        updatedAt = now
        self.editorMode = editorMode
        self.projectName = projectName
        activeSlot = .a
        preferredSlot = nil
        variants = [
            ThumbnailVariant(
                slot: .a,
                name: ThumbnailVariantSlot.a.defaultName,
                createdAt: now,
                updatedAt: now,
                document: seedDocument
            )
        ]
    }

    init(
        version: Int = currentVersion,
        updatedAt: Date,
        editorMode: ThumbnailDocumentEditorMode,
        projectName: String,
        activeSlot: ThumbnailVariantSlot,
        preferredSlot: ThumbnailVariantSlot?,
        variants: [ThumbnailVariant]
    ) {
        self.version = version
        self.updatedAt = updatedAt
        self.editorMode = editorMode
        self.projectName = projectName
        self.activeSlot = activeSlot
        self.preferredSlot = preferredSlot
        self.variants = variants
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case updatedAt
        case editorMode
        case projectName
        case activeSlot
        case preferredSlot
        case variants
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVariants = try container.decode([ThumbnailVariant].self, forKey: .variants)
        let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        self.init(
            version: max(decodedVersion, Self.currentVersion),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(),
            editorMode: try container.decodeIfPresent(ThumbnailDocumentEditorMode.self, forKey: .editorMode) ?? .simple,
            projectName: try container.decodeIfPresent(String.self, forKey: .projectName) ?? "",
            activeSlot: try container.decodeIfPresent(ThumbnailVariantSlot.self, forKey: .activeSlot)
                ?? decodedVariants.map(\.slot).min() ?? .a,
            preferredSlot: try container.decodeIfPresent(ThumbnailVariantSlot.self, forKey: .preferredSlot),
            variants: decodedVariants
        )
        self = normalized()
    }

    // MARK: Queries

    var slots: [ThumbnailVariantSlot] { variants.map(\.slot) }

    var activeVariant: ThumbnailVariant {
        variant(for: activeSlot) ?? variants.first ?? Self.fallbackVariant(editorMode: editorMode)
    }

    var activeDocument: ThumbnailDocument { activeVariant.document }

    func variant(for slot: ThumbnailVariantSlot) -> ThumbnailVariant? {
        variants.first { $0.slot == slot }
    }

    func document(for slot: ThumbnailVariantSlot) -> ThumbnailDocument? {
        variant(for: slot)?.document
    }

    func contains(_ slot: ThumbnailVariantSlot) -> Bool {
        variants.contains { $0.slot == slot }
    }

    var canAddVariant: Bool { variants.count < Self.maxVariantCount }
    var canCompare: Bool { variants.count >= 2 }
    var hasMultipleVariants: Bool { variants.count > 1 }

    var nextFreeSlot: ThumbnailVariantSlot? {
        ThumbnailVariantSlot.allCases.first { !contains($0) }
    }

    // MARK: Mutations

    /// Copies the source variant's document into the lowest free slot and makes
    /// it active. Layer IDs are preserved verbatim: documents are independent
    /// values, so reuse across variants is harmless and keeps selection stable.
    @discardableResult
    mutating func duplicateVariant(
        from source: ThumbnailVariantSlot,
        now: Date = Date()
    ) -> ThumbnailVariantSlot? {
        guard let sourceVariant = variant(for: source), let destination = nextFreeSlot else {
            return nil
        }

        variants.append(
            ThumbnailVariant(
                slot: destination,
                name: destination.defaultName,
                createdAt: now,
                updatedAt: now,
                document: sourceVariant.document
            )
        )
        variants.sort { $0.slot < $1.slot }
        activeSlot = destination
        updatedAt = now
        return destination
    }

    /// Removes a variant. Refuses to remove the last one. Remaining variants keep
    /// their letters.
    @discardableResult
    mutating func removeVariant(_ slot: ThumbnailVariantSlot, now: Date = Date()) -> Bool {
        guard variants.count > 1, contains(slot) else { return false }

        variants.removeAll { $0.slot == slot }
        if activeSlot == slot {
            activeSlot = variants.map(\.slot).min() ?? .a
        }
        if preferredSlot == slot {
            preferredSlot = nil
        }
        updatedAt = now
        return true
    }

    /// Records the user's own pick. Ignored for a slot that does not exist.
    mutating func setPreferred(_ slot: ThumbnailVariantSlot, now: Date = Date()) {
        guard contains(slot), preferredSlot != slot else { return }
        preferredSlot = slot
        updatedAt = now
    }

    mutating func clearPreferred(now: Date = Date()) {
        guard preferredSlot != nil else { return }
        preferredSlot = nil
        updatedAt = now
    }

    mutating func rename(slot: ThumbnailVariantSlot, to name: String, now: Date = Date()) {
        guard let index = variants.firstIndex(where: { $0.slot == slot }) else { return }
        let cleaned = Self.cleanedName(name, fallback: slot.defaultName)
        guard variants[index].name != cleaned else { return }
        variants[index].name = cleaned
        variants[index].updatedAt = now
        updatedAt = now
    }

    mutating func activate(_ slot: ThumbnailVariantSlot) {
        guard contains(slot) else { return }
        activeSlot = slot
    }

    /// Replaces a variant's document. A no-op when only `updatedAt` differs, so
    /// autosave does not churn timestamps.
    mutating func updateDocument(
        _ document: ThumbnailDocument,
        for slot: ThumbnailVariantSlot,
        now: Date = Date()
    ) {
        guard let index = variants.firstIndex(where: { $0.slot == slot }) else { return }
        guard ThumbnailDocumentHistory.snapshot(variants[index].document)
                != ThumbnailDocumentHistory.snapshot(document) else { return }
        variants[index].document = document
        variants[index].updatedAt = now
        updatedAt = now
    }

    /// Repairs any structurally invalid set (e.g. a hand-edited or damaged file).
    func normalized() -> ThumbnailVariantSet {
        var copy = self
        var seen = Set<ThumbnailVariantSlot>()
        copy.variants = variants.filter { seen.insert($0.slot).inserted }
        copy.variants.sort { $0.slot < $1.slot }
        if copy.variants.count > Self.maxVariantCount {
            copy.variants = Array(copy.variants.prefix(Self.maxVariantCount))
        }
        if copy.variants.isEmpty {
            copy.variants = [Self.fallbackVariant(editorMode: editorMode)]
        }
        for index in copy.variants.indices {
            copy.variants[index].name = Self.cleanedName(
                copy.variants[index].name,
                fallback: copy.variants[index].slot.defaultName
            )
        }
        if !copy.contains(copy.activeSlot) {
            copy.activeSlot = copy.variants[0].slot
        }
        if let preferred = copy.preferredSlot, !copy.contains(preferred) {
            copy.preferredSlot = nil
        }
        return copy
    }

    static func cleanedName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.prefix(maxNameLength))
    }

    private static func fallbackVariant(editorMode: ThumbnailDocumentEditorMode) -> ThumbnailVariant {
        let now = Date()
        return ThumbnailVariant(
            slot: .a,
            name: ThumbnailVariantSlot.a.defaultName,
            createdAt: now,
            updatedAt: now,
            document: ThumbnailDocument(updatedAt: now, editorMode: editorMode)
        )
    }
}
