//
//  ThumbnailExportRecipeStore.swift
//  ThumbnailMaker
//
//  FEATURE-10: persists the user's export recipes (built-ins are code, never
//  stored) at Application Support/ThumbnailMaker/ExportRecipes/recipes.json,
//  written atomically. An unreadable file is moved to quarantine, never
//  overwritten or deleted.
//

import Foundation

struct ThumbnailExportRecipeLibrary: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var recipes: [ThumbnailExportRecipe]
    /// Project UUID string -> the recipe last run for that project.
    var lastRecipeIDByProject: [String: UUID]

    init(
        version: Int = ThumbnailExportRecipeLibrary.currentVersion,
        recipes: [ThumbnailExportRecipe] = [],
        lastRecipeIDByProject: [String: UUID] = [:]
    ) {
        self.version = version
        self.recipes = recipes
        self.lastRecipeIDByProject = lastRecipeIDByProject
    }

    private enum CodingKeys: String, CodingKey { case version, recipes, lastRecipeIDByProject }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        recipes = try container.decodeIfPresent([ThumbnailExportRecipe].self, forKey: .recipes) ?? []
        lastRecipeIDByProject = try container.decodeIfPresent([String: UUID].self, forKey: .lastRecipeIDByProject) ?? [:]
    }

    static let empty = ThumbnailExportRecipeLibrary()
}

final class ThumbnailExportRecipeStore {
    static let fileName = "recipes.json"
    static let quarantineDirectoryName = "quarantine"

    let directory: URL
    var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    init(directory: URL = ThumbnailExportRecipeStore.defaultDirectory) {
        self.directory = directory
    }

    static var defaultDirectory: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return applicationSupport
            .appendingPathComponent("ThumbnailMaker", isDirectory: true)
            .appendingPathComponent("ExportRecipes", isDirectory: true)
    }

    /// Missing file -> empty. Unreadable file -> quarantined, then empty.
    func load() -> ThumbnailExportRecipeLibrary {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }
        do {
            let data = try Data(contentsOf: fileURL)
            return try Self.decoder.decode(ThumbnailExportRecipeLibrary.self, from: data)
        } catch {
            quarantineFile()
            return .empty
        }
    }

    func saveLibrary(_ library: ThumbnailExportRecipeLibrary) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(library).write(to: fileURL, options: .atomic)
    }

    /// Inserts or updates (by id). Built-in recipes are never stored.
    @discardableResult
    func save(_ recipe: ThumbnailExportRecipe, now: Date = Date()) throws -> ThumbnailExportRecipe {
        guard !recipe.isBuiltIn else { return recipe }
        var library = load()
        var stored = recipe
        stored.name = ThumbnailExportRecipe.cleanedName(recipe.name)
        stored.updatedAt = now
        if let index = library.recipes.firstIndex(where: { $0.id == recipe.id }) {
            library.recipes[index] = stored
        } else {
            library.recipes.append(stored)
        }
        try saveLibrary(library)
        return stored
    }

    /// Returns the removed recipe so the caller can offer Undo via `restore`.
    @discardableResult
    func delete(id: UUID) throws -> ThumbnailExportRecipe? {
        var library = load()
        guard let index = library.recipes.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = library.recipes.remove(at: index)
        try saveLibrary(library)
        return removed
    }

    func restore(_ recipe: ThumbnailExportRecipe) throws {
        var library = load()
        guard !library.recipes.contains(where: { $0.id == recipe.id }) else { return }
        library.recipes.append(recipe)
        try saveLibrary(library)
    }

    func setLastRecipeID(_ recipeID: UUID, forProject projectID: UUID) throws {
        var library = load()
        guard library.lastRecipeIDByProject[projectID.uuidString] != recipeID else { return }
        library.lastRecipeIDByProject[projectID.uuidString] = recipeID
        try saveLibrary(library)
    }

    func lastRecipeID(forProject projectID: UUID) -> UUID? {
        load().lastRecipeIDByProject[projectID.uuidString]
    }

    private func quarantineFile() {
        let quarantine = directory.appendingPathComponent(Self.quarantineDirectoryName, isDirectory: true)
        let stamp = Int(Date().timeIntervalSince1970)
        let destination = quarantine.appendingPathComponent("recipes-\(stamp)-\(UUID().uuidString.prefix(8)).json")
        try? FileManager.default.createDirectory(at: quarantine, withIntermediateDirectories: true)
        try? FileManager.default.moveItem(at: fileURL, to: destination)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
