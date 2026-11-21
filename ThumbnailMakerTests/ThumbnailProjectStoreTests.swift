//
//  ThumbnailProjectStoreTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-01: file layer of the project library.
//

import Foundation
import Testing
@testable import ThumbnailMaker

@MainActor
struct ThumbnailProjectStoreTests {
    @Test func indexRoundTripsThroughCodable() throws {
        let directory = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(directory) }
        let store = ThumbnailProjectStore(rootDirectory: directory)

        var index = ThumbnailProjectLibraryIndex()
        let first = ThumbnailProjectMetadata(
            name: "First",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000.25),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100.5),
            editorMode: .simple
        )
        var second = ThumbnailProjectMetadata(
            name: "Second",
            createdAt: Date(timeIntervalSince1970: 1_700_000_200),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_300),
            editorMode: .premium,
            origin: .duplicated
        )
        second.deletedAt = Date(timeIntervalSince1970: 1_700_000_400.75)
        index.upsert(first)
        index.upsert(second)
        index.activeSimpleProjectID = first.id
        index.activePremiumProjectID = second.id
        index.migratedLegacyDraftKinds = ["simple", "premium"]
        index.migrationWarnings = ["premium": "damaged"]

        try store.saveIndex(index)
        let loaded = try store.loadIndex()

        #expect(loaded.rebuilt == false)
        #expect(loaded.index == index)
    }

    @Test func indexDecodesLegacyPayloadWithoutOptionalFields() throws {
        let directory = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(directory) }
        let store = ThumbnailProjectStore(rootDirectory: directory)
        let id = UUID()
        let json = """
        {"version":1,"projects":[{"id":"\(id.uuidString)","name":"Old","createdAt":"2025-01-01T00:00:00Z","updatedAt":"2025-01-02T00:00:00Z","editorMode":"simple"}]}
        """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: store.indexURL)

        let loaded = try store.loadIndex()
        let metadata = try #require(loaded.index.projects.first)

        #expect(loaded.rebuilt == false)
        #expect(metadata.id == id)
        #expect(metadata.name == "Old")
        #expect(metadata.deletedAt == nil)
        #expect(metadata.schemaVersion == 1)
        #expect(metadata.previewFileName == "preview.png")
        #expect(metadata.documentFileName == "document.json")
        #expect(metadata.origin == .created)
        #expect(loaded.index.migratedLegacyDraftKinds.isEmpty)
        #expect(loaded.index.migrationWarnings.isEmpty)
        #expect(loaded.index.activeSimpleProjectID == nil)
    }

    @Test func corruptIndexIsQuarantinedAndRebuiltFromSidecars() throws {
        let directory = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(directory) }
        let store = ThumbnailProjectStore(rootDirectory: directory)

        var ids: [UUID] = []
        var index = ThumbnailProjectLibraryIndex()
        for number in 0..<3 {
            let metadata = ThumbnailProjectMetadata(
                name: "Project \(number)",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(number)),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(number)),
                editorMode: .simple
            )
            try store.saveDocument(ProjectTestSupport.simpleDocument(text: "doc \(number)"), id: metadata.id)
            try store.saveMetadataSidecar(metadata)
            index.upsert(metadata)
            ids.append(metadata.id)
        }
        try store.saveIndex(index)

        let badBytes = Data("{not json".utf8)
        try badBytes.write(to: store.indexURL)

        let loaded = try store.loadIndex()

        #expect(loaded.rebuilt == true)
        #expect(Set(loaded.index.projects.map(\.id)) == Set(ids))
        // Newest first.
        #expect(loaded.index.projects.first?.name == "Project 2")

        let quarantined = try FileManager.default.contentsOfDirectory(
            at: store.quarantineDirectory,
            includingPropertiesForKeys: nil
        )
        #expect(quarantined.count == 1)
        let quarantinedFile = try #require(quarantined.first)
        #expect(try Data(contentsOf: quarantinedFile) == badBytes)

        // The rebuilt index was written back and now loads cleanly.
        let reloaded = try store.loadIndex()
        #expect(reloaded.rebuilt == false)
        #expect(reloaded.index.projects.count == 3)
    }

    @Test func documentSaveIsAtomicAndPreservesLastGoodBytesOnFailure() throws {
        let directory = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(directory) }
        let store = ThumbnailProjectStore(rootDirectory: directory)
        let id = UUID()

        try store.saveDocument(ProjectTestSupport.simpleDocument(text: "good"), id: id)
        let baseline = try Data(contentsOf: store.documentURL(id: id))

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: store.projectDirectory(id: id).path
        )
        #expect(throws: (any Error).self) {
            try store.saveDocument(ProjectTestSupport.simpleDocument(text: "doomed"), id: id)
        }
        #expect(try Data(contentsOf: store.documentURL(id: id)) == baseline)
        #expect(try store.loadDocument(id: id).text.value == "good")

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: store.projectDirectory(id: id).path
        )
        try store.saveDocument(ProjectTestSupport.simpleDocument(text: "recovered"), id: id)
        #expect(try store.loadDocument(id: id).text.value == "recovered")
    }

    @Test func documentFileIsByteCompatibleWithTheDraftStore() throws {
        let directory = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(directory) }
        let store = ThumbnailProjectStore(rootDirectory: directory.appendingPathComponent("Projects"))
        let id = UUID()
        try store.saveDocument(ProjectTestSupport.simpleDocument(text: "portable"), id: id)

        // A project's document.json opens with the existing draft reader.
        let draftReader = ThumbnailDraftStore(fileURL: store.documentURL(id: id))
        let configuration = try #require(try draftReader.load())
        #expect(configuration.overlayText == "portable")
    }

    @Test func purgeRemovesOnlyTheTargetDirectory() throws {
        let directory = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(directory) }
        let store = ThumbnailProjectStore(rootDirectory: directory)
        let keep = UUID()
        let remove = UUID()
        try store.saveDocument(ProjectTestSupport.simpleDocument(text: "keep"), id: keep)
        try store.saveDocument(ProjectTestSupport.simpleDocument(text: "remove"), id: remove)
        try store.saveIndex(ThumbnailProjectLibraryIndex())

        try store.purgeDirectory(id: remove)

        #expect(!FileManager.default.fileExists(atPath: store.projectDirectory(id: remove).path))
        #expect(FileManager.default.fileExists(atPath: store.documentURL(id: keep).path))
        #expect(FileManager.default.fileExists(atPath: store.indexURL.path))
    }

    @Test func metadataSanitizesNamesAndMatchesQueries() {
        #expect(ThumbnailProjectMetadata.sanitizedName("   \n ") == "Untitled Project")
        #expect(ThumbnailProjectMetadata.sanitizedName("  Hello  ") == "Hello")
        #expect(ThumbnailProjectMetadata.sanitizedName(String(repeating: "a", count: 300)).count == 120)

        let metadata = ThumbnailProjectMetadata(
            name: "Café Gaming",
            createdAt: Date(),
            updatedAt: Date(),
            editorMode: .simple
        )
        #expect(metadata.matches(query: ""))
        #expect(metadata.matches(query: "cafe"))
        #expect(metadata.matches(query: "GAM"))
        #expect(!metadata.matches(query: "zzz"))
    }
}
