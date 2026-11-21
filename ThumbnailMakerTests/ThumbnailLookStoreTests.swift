//
//  ThumbnailLookStoreTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-14: saved looks - library rules, disk persistence and error paths.
//

import Foundation
import Testing
@testable import ThumbnailMaker

@MainActor
struct ThumbnailLookStoreTests {
    private let recipe = ThumbnailImageAdjustments(brightness: 0.1, contrast: 1.2, saturation: 1.3, blur: 0.01, vignette: 0.2)

    @Test func savedLooksReloadFromDisk() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailLookStore(fileURL: directory.appendingPathComponent("Looks/looks.json"))

        var library = ThumbnailLookLibrary()
        let start = Date(timeIntervalSince1970: 1_000)
        try library.upsert(name: "One", adjustments: recipe, now: start)
        try library.upsert(name: "Two", adjustments: ThumbnailImageAdjustments(saturation: 0), now: start.addingTimeInterval(1))
        try library.upsert(name: "Three", adjustments: ThumbnailImageAdjustments(vignette: 0.5), now: start.addingTimeInterval(2))
        try store.save(library)

        let loaded = try #require(try store.load())
        #expect(loaded.looks == library.looks)
        #expect(loaded.updatedAt > start.addingTimeInterval(2), "save() stamps updatedAt")
    }

    @Test func missingFileLoadsNilAndDeleteRemovesFile() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailLookStore(fileURL: directory.appendingPathComponent("looks.json"))
        #expect(try store.load() == nil)
        try store.delete()

        try store.save(ThumbnailLookLibrary())
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
        try store.delete()
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(try store.load() == nil)
    }

    @Test func builtInsAreNeverPersistedAndAreAlwaysAvailable() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailLookStore(fileURL: directory.appendingPathComponent("looks.json"))
        var library = ThumbnailLookLibrary()
        try library.upsert(name: "Mine", adjustments: recipe)
        try store.save(library)

        let json = try String(contentsOf: store.fileURL, encoding: .utf8)
        for builtIn in ThumbnailLookLibrary.builtIns {
            #expect(!json.contains(builtIn.id))
        }
        let loaded = try #require(try store.load())
        #expect(Array(loaded.allLooks.prefix(5)).map(\.id) == ThumbnailLookLibrary.builtIns.map(\.id))
        #expect(loaded.allLooks.last?.name == "Mine")

        // A hand-edited file that smuggles in a built-in is filtered on load.
        let smuggled = """
        {"version":1,"updatedAt":"2026-01-01T00:00:00Z","looks":[
          {"id":"look-punchy","name":"Punchy","isBuiltIn":false,"updatedAt":"2026-01-01T00:00:00Z","adjustments":{"brightness":0.3}},
          {"id":"x","name":"Fake","isBuiltIn":true,"updatedAt":"2026-01-01T00:00:00Z","adjustments":{}},
          {"id":"y","name":"Kept","updatedAt":"2026-01-01T00:00:00Z","adjustments":{"contrast":40}}
        ]}
        """
        try Data(smuggled.utf8).write(to: store.fileURL)
        let filtered = try #require(try store.load())
        #expect(filtered.looks.map(\.id) == ["y"])
        #expect(filtered.looks.first?.adjustments.contrast == ThumbnailImageAdjustments.contrastRange.upperBound)
    }

    @Test func upsertTrimsTruncatesDeduplicatesAndCaps() throws {
        var library = ThumbnailLookLibrary()
        let base = Date(timeIntervalSince1970: 10_000)

        let trimmed = try library.upsert(name: "  Warm Glow \n", adjustments: recipe, now: base)
        #expect(trimmed.name == "Warm Glow")

        let longName = String(repeating: "a", count: 60)
        let truncated = try library.upsert(name: longName, adjustments: recipe, now: base)
        #expect(truncated.name.count == ThumbnailLookLibrary.nameCharacterLimit)

        #expect(throws: ThumbnailLookError.invalidName) {
            try library.upsert(name: "   ", adjustments: recipe)
        }
        #expect(throws: ThumbnailLookError.reservedName("Punchy")) {
            try library.upsert(name: "punchy", adjustments: recipe)
        }

        let replaced = try library.upsert(name: "warm glow", adjustments: ThumbnailImageAdjustments(saturation: 0), now: base)
        #expect(replaced.id == trimmed.id)
        #expect(library.looks.count == 2)
        #expect(library.look(id: trimmed.id)?.adjustments.saturation == 0)

        library = ThumbnailLookLibrary()
        for index in 0..<ThumbnailLookLibrary.maxUserLooks {
            try library.upsert(name: "Look \(index)", adjustments: recipe, now: base.addingTimeInterval(Double(index)))
        }
        #expect(library.looks.count == ThumbnailLookLibrary.maxUserLooks)
        try library.upsert(name: "Newest", adjustments: recipe, now: base.addingTimeInterval(1_000))
        #expect(library.looks.count == ThumbnailLookLibrary.maxUserLooks)
        #expect(!library.looks.contains { $0.name == "Look 0" }, "The oldest look is evicted")
        #expect(library.looks.contains { $0.name == "Newest" })
    }

    @Test func removeAndRenameRefuseBuiltIns() throws {
        var library = ThumbnailLookLibrary()
        let mine = try library.upsert(name: "Mine", adjustments: recipe)
        let other = try library.upsert(name: "Other", adjustments: recipe)

        #expect(throws: ThumbnailLookError.builtInLook) { try library.remove(id: "look-mono") }
        #expect(throws: ThumbnailLookError.builtInLook) { try library.rename(id: "look-mono", to: "X") }
        #expect(throws: ThumbnailLookError.reservedName("Clean")) { try library.rename(id: mine.id, to: "CLEAN") }

        try library.rename(id: mine.id, to: "  Renamed  ")
        #expect(library.look(id: mine.id)?.name == "Renamed")

        try library.rename(id: mine.id, to: "other")
        #expect(library.look(id: other.id) == nil, "Renaming onto a user look's name replaces it")
        #expect(library.looks.count == 1)

        try library.remove(id: mine.id)
        #expect(library.looks.isEmpty)
        #expect(library.allLooks.count == ThumbnailLookLibrary.builtIns.count)
    }

    @Test func corruptLookFileThrowsAndDoesNotCrash() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("looks.json")
        try Data("{ not json".utf8).write(to: fileURL)
        let store = ThumbnailLookStore(fileURL: fileURL)
        #expect(throws: (any Error).self) { try store.load() }

        let controller = ThumbnailLookLibraryController(store: store)
        #expect(controller.errorMessage != nil)
        #expect(controller.allLooks.map(\.id) == ThumbnailLookLibrary.builtIns.map(\.id))
    }

    @Test func controllerPersistsAndRollsBackOnFailedSave() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailLookStore(fileURL: directory.appendingPathComponent("looks.json"))

        let controller = ThumbnailLookLibraryController(store: store)
        let saved = try #require(controller.saveLook(named: "Mine", adjustments: recipe))
        #expect(controller.errorMessage == nil)
        #expect(try store.load()?.looks.map(\.id) == [saved.id])

        let reopened = ThumbnailLookLibraryController(store: store)
        #expect(reopened.library.looks.map(\.name) == ["Mine"])
        #expect(reopened.renameLook(id: saved.id, to: "Ours"))
        #expect(try store.load()?.looks.first?.name == "Ours")
        #expect(!reopened.deleteLook(id: "look-soft"))
        #expect(reopened.errorMessage != nil)
        reopened.errorMessage = nil
        #expect(reopened.deleteLook(id: saved.id))
        #expect(try store.load()?.looks.isEmpty == true)

        // A store whose folder can't be created: the edit is rolled back.
        let blocker = directory.appendingPathComponent("blocker")
        try Data("file".utf8).write(to: blocker)
        let broken = ThumbnailLookLibraryController(store: ThumbnailLookStore(fileURL: blocker.appendingPathComponent("looks.json")))
        #expect(broken.saveLook(named: "Lost", adjustments: recipe) == nil)
        #expect(broken.errorMessage != nil)
        #expect(broken.library.looks.isEmpty)

        // In-memory controller (UI tests) never touches disk.
        let memory = ThumbnailLookLibraryController(store: nil)
        #expect(memory.saveLook(named: "Temp", adjustments: recipe) != nil)
        #expect(memory.library.looks.count == 1)
    }

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
}
