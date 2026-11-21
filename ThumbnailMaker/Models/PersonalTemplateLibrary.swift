//
//  PersonalTemplateLibrary.swift
//  ThumbnailMaker
//
//  FEATURE-05: the creator's own saved templates. Pure value type (no I/O) so
//  every rule - cap, unique names, favourites, recoverable delete - is unit
//  testable. PersonalTemplateStore persists it.
//

import Foundation

struct PersonalTemplateLibrary: Codable, Equatable {
    static let currentVersion = 1
    static let maximumActiveTemplates = 60
    static let trashRetention: TimeInterval = 30 * 24 * 3600

    var version: Int = currentVersion
    var templates: [ThumbnailTemplate] = []
    var updatedAt = Date(timeIntervalSince1970: 0)

    enum LibraryError: LocalizedError, Equatable {
        case libraryFull(limit: Int)
        case notFound(String)
        case builtInNotEditable(String)
        case notInTrash(String)
        case emptyName
        case payloadTooLarge(bytes: Int, limit: Int)

        var errorDescription: String? {
            switch self {
            case .libraryFull(let limit):
                "You can keep up to \(limit) templates. Delete one you no longer use and try again."
            case .notFound:
                "That template no longer exists."
            case .builtInNotEditable:
                "Built-in templates can't be changed. Save a copy as your own template instead."
            case .notInTrash:
                "Only templates in Recently Deleted can be removed permanently."
            case .emptyName:
                "Give the template a name."
            case .payloadTooLarge(let bytes, let limit):
                "This template's kept images are too large (\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)); the limit is \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file))). Keep fewer images in the template."
            }
        }
    }

    init(templates: [ThumbnailTemplate] = [], updatedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.templates = templates
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case version, templates, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = max(try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion, Self.currentVersion)
        templates = try container.decodeIfPresent([ThumbnailTemplate].self, forKey: .templates) ?? []
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
    }

    // MARK: - Read

    /// Active templates: favourites first, then most recently updated, then name.
    var active: [ThumbnailTemplate] {
        templates
            .filter { $0.deletedAt == nil }
            .sorted { lhs, rhs in
                if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    var favorites: [ThumbnailTemplate] {
        active.filter(\.isFavorite)
    }

    var trashed: [ThumbnailTemplate] {
        templates
            .filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    func active(in category: ThumbnailTemplateCategory) -> [ThumbnailTemplate] {
        active.filter { $0.category == category }
    }

    func template(id: String) -> ThumbnailTemplate? {
        templates.first { $0.id == id }
    }

    // MARK: - Mutations

    @discardableResult
    mutating func insert(_ template: ThumbnailTemplate, now: Date = Date()) throws -> ThumbnailTemplate {
        guard template.origin == .personal else {
            throw LibraryError.builtInNotEditable(template.id)
        }
        guard active.count < Self.maximumActiveTemplates else {
            throw LibraryError.libraryFull(limit: Self.maximumActiveTemplates)
        }
        var template = template
        if templates.contains(where: { $0.id == template.id }) {
            template.id = UUID().uuidString
        }
        template.name = try uniqueName(for: template.name, excluding: nil)
        template.deletedAt = nil
        templates.append(template)
        updatedAt = now
        return template
    }

    mutating func update(
        id: String,
        now: Date = Date(),
        _ mutate: (inout ThumbnailTemplate) throws -> Void
    ) throws {
        let index = try editableIndex(id: id)
        var template = templates[index]
        try mutate(&template)
        template.id = id
        template.origin = .personal
        template.updatedAt = now
        templates[index] = template
        updatedAt = now
    }

    mutating func rename(id: String, to name: String, now: Date = Date()) throws {
        let uniqueName = try uniqueName(for: name, excluding: id)
        try update(id: id, now: now) { $0.name = uniqueName }
    }

    mutating func setFavorite(_ isFavorite: Bool, id: String, now: Date = Date()) throws {
        try update(id: id, now: now) { $0.isFavorite = isFavorite }
    }

    mutating func setCategory(_ category: ThumbnailTemplateCategory, id: String, now: Date = Date()) throws {
        try update(id: id, now: now) { $0.category = category }
    }

    @discardableResult
    mutating func duplicate(
        id: String,
        newID: String = UUID().uuidString,
        now: Date = Date()
    ) throws -> ThumbnailTemplate {
        let source = templates[try editableIndex(id: id)]
        var copy = source
        copy.id = newID
        copy.name = "\(source.name) Copy"
        copy.isFavorite = false
        copy.sourceTemplateID = source.id
        copy.createdAt = now
        copy.updatedAt = now
        copy.deletedAt = nil
        return try insert(copy, now: now)
    }

    mutating func softDelete(id: String, now: Date = Date()) throws {
        let index = try editableIndex(id: id)
        templates[index].deletedAt = now
        updatedAt = now
    }

    mutating func restore(id: String, now: Date = Date()) throws {
        let index = try editableIndex(id: id)
        guard templates[index].deletedAt != nil else { return }
        guard active.count < Self.maximumActiveTemplates else {
            throw LibraryError.libraryFull(limit: Self.maximumActiveTemplates)
        }
        templates[index].name = try uniqueName(for: templates[index].name, excluding: id)
        templates[index].deletedAt = nil
        updatedAt = now
    }

    mutating func purge(id: String, now: Date = Date()) throws {
        let index = try editableIndex(id: id)
        guard templates[index].deletedAt != nil else {
            throw LibraryError.notInTrash(id)
        }
        templates.remove(at: index)
        updatedAt = now
    }

    @discardableResult
    mutating func purgeExpired(now: Date = Date()) -> [String] {
        let expiredIDs = templates.compactMap { template -> String? in
            guard let deletedAt = template.deletedAt,
                  now.timeIntervalSince(deletedAt) >= Self.trashRetention else { return nil }
            return template.id
        }
        guard !expiredIDs.isEmpty else { return [] }
        templates.removeAll { expiredIDs.contains($0.id) }
        updatedAt = now
        return expiredIDs
    }

    // MARK: - Helpers

    private func editableIndex(id: String) throws -> Int {
        guard let index = templates.firstIndex(where: { $0.id == id }) else {
            throw LibraryError.notFound(id)
        }
        guard templates[index].origin == .personal else {
            throw LibraryError.builtInNotEditable(id)
        }
        return index
    }

    /// Collisions among active templates are resolved with " 2", " 3", ...
    func uniqueName(for proposedName: String, excluding excludedID: String?) throws -> String {
        let base = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { throw LibraryError.emptyName }

        let taken = Set(
            templates
                .filter { $0.deletedAt == nil && $0.id != excludedID }
                .map { Self.normalized($0.name) }
        )
        guard taken.contains(Self.normalized(base)) else { return base }

        var suffix = 2
        while taken.contains(Self.normalized("\(base) \(suffix)")) {
            suffix += 1
        }
        return "\(base) \(suffix)"
    }

    private static func normalized(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
