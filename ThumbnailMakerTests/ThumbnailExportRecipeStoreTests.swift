//
//  ThumbnailExportRecipeStoreTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-10: recipe persistence, undo of delete, quarantine.
//

import Foundation
import Testing
@testable import ThumbnailMaker

@MainActor
struct ThumbnailExportRecipeStoreTests {
    private func makeStore() -> (ThumbnailExportRecipeStore, URL) {
        let directory = ExportQueueTestSupport.makeTemporaryDirectory()
        return (ThumbnailExportRecipeStore(directory: directory), directory)
    }

    @Test func missingFileIsEmpty() {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(store.load() == .empty)
    }

    @Test func saveLoadUpdateDeleteRestore() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var recipe = ExportQueueTestSupport.smallRecipe()
        recipe.name = "  Weekly  "
        let stored = try store.save(recipe)
        #expect(stored.name == "Weekly")
        #expect(store.load().recipes.map(\.id) == [recipe.id])

        var updated = stored
        updated.sizes.removeLast()
        try store.save(updated)
        let reloaded = try #require(store.load().recipes.first)
        #expect(reloaded.sizes.count == 2)
        #expect(store.load().recipes.count == 1)

        let removed = try store.delete(id: recipe.id)
        #expect(removed?.id == recipe.id)
        #expect(store.load().recipes.isEmpty)

        let toRestore = try #require(removed)
        try store.restore(toRestore)
        #expect(store.load().recipes.first?.sizes.count == 2)
    }

    @Test func builtInsAreNeverStored() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.save(.youTubeABC)
        #expect(store.load().recipes.isEmpty)
    }

    @Test func lastRecipePerProjectPersists() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let projectID = UUID()
        try store.setLastRecipeID(ThumbnailExportRecipe.youTubeABCID, forProject: projectID)
        let reopened = ThumbnailExportRecipeStore(directory: directory)
        #expect(reopened.lastRecipeID(forProject: projectID) == ThumbnailExportRecipe.youTubeABCID)
        #expect(reopened.lastRecipeID(forProject: UUID()) == nil)
    }

    @Test func corruptFileIsQuarantinedNotOverwritten() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let garbage = Data("{ not json".utf8)
        try garbage.write(to: store.fileURL)

        #expect(store.load() == .empty)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        let quarantine = directory.appendingPathComponent(ThumbnailExportRecipeStore.quarantineDirectoryName)
        let moved = try FileManager.default.contentsOfDirectory(atPath: quarantine.path)
        #expect(moved.count == 1)
        let movedData = try Data(contentsOf: quarantine.appendingPathComponent(moved[0]))
        #expect(movedData == garbage)
    }

    @Test func libraryDecodesWithMissingFields() throws {
        let data = Data(#"{"recipes":[{"id":"\#(UUID().uuidString)","name":"Old"}]}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let library = try decoder.decode(ThumbnailExportRecipeLibrary.self, from: data)
        #expect(library.recipes.count == 1)
        #expect(library.lastRecipeIDByProject.isEmpty)
        #expect(library.version == ThumbnailExportRecipeLibrary.currentVersion)
    }
}
