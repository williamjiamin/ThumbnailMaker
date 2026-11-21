//
//  ThumbnailProjectLibraryTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-01 acceptance criteria for the project library.
//

import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ThumbnailProjectLibraryTests {
    @Test func tenProjectsSurviveARestartIndependently() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)

        let ratios = AspectRatio.allCases
        var created: [UUID: (text: String, ratio: AspectRatio, hasImage: Bool)] = [:]
        for number in 0..<10 {
            let ratio = ratios[number % ratios.count]
            let image = number == 3 ? ProjectTestSupport.makeImage(size: CGSize(width: 40, height: 20)) : nil
            let text = "Episode \(number) title"
            let metadata = try library.createProject(
                name: "Project \(number)",
                editorMode: .simple,
                document: ProjectTestSupport.simpleDocument(text: text, ratio: ratio, image: image)
            )
            created[metadata.id] = (text, ratio, image != nil)
        }

        // Restart: a brand-new library instance over the same root.
        let restarted = ProjectTestSupport.makeLibrary(root: root)

        #expect(restarted.projects.count == 10)
        #expect(Set(restarted.projects.map(\.id)) == Set(created.keys))

        var seenBytes = Set<Data>()
        for (id, expected) in created {
            let document = try restarted.document(for: id)
            #expect(document.text.value == expected.text)
            #expect(document.canvas.aspectRatioRawValue == expected.ratio.rawValue)
            #expect((document.imageData != nil) == expected.hasImage)
            let bytes = try Data(contentsOf: restarted.store.documentURL(id: id))
            seenBytes.insert(bytes)
        }
        #expect(seenBytes.count == 10)
    }

    @Test func createRenameSearchDuplicateReopen() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)

        let first = try library.createProject(
            name: "Draft",
            editorMode: .simple,
            document: ProjectTestSupport.simpleDocument(text: "one")
        )
        _ = try library.createProject(
            name: "Cooking Show",
            editorMode: .simple,
            document: ProjectTestSupport.simpleDocument(text: "two")
        )
        try library.rename(id: first.id, to: "  Gaming Intro  ")

        #expect(library.metadata(id: first.id)?.name == "Gaming Intro")
        #expect(library.projects(matching: "gam").map(\.id) == [first.id])
        #expect(library.projects(matching: "GÁM").map(\.id) == [first.id])
        #expect(library.projects(matching: "zzz").isEmpty)

        let all = library.projects(matching: "")
        #expect(all.count == 2)
        for (earlier, later) in zip(all, all.dropFirst()) {
            #expect(earlier.metadata.updatedAt >= later.metadata.updatedAt)
        }

        // Rename survives a restart.
        let restarted = ProjectTestSupport.makeLibrary(root: root)
        #expect(restarted.metadata(id: first.id)?.name == "Gaming Intro")
        #expect(try restarted.document(for: first.id).text.value == "one")

        // Mode filtering.
        #expect(restarted.projects(matching: "", editorMode: .premium).isEmpty)
        #expect(restarted.projects(matching: "", editorMode: .simple).count == 2)
    }

    @Test func duplicateProducesAnIndependentCopy() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)

        let original = try library.createProject(
            name: "X",
            editorMode: .simple,
            document: ProjectTestSupport.simpleDocument(text: "original", image: ProjectTestSupport.makeImage())
        )
        let originalBytes = try Data(contentsOf: library.store.documentURL(id: original.id))

        let copy = try library.duplicate(id: original.id)
        #expect(copy.id != original.id)
        #expect(copy.name == "X copy")
        #expect(copy.origin == .duplicated)
        #expect(try library.document(for: copy.id) == library.document(for: original.id))

        var mutated = try library.document(for: copy.id)
        mutated.text.value = "changed in copy"
        mutated.imageData = nil
        try library.saveDocument(mutated, for: copy.id)

        #expect(try library.document(for: copy.id).text.value == "changed in copy")
        #expect(try library.document(for: original.id).text.value == "original")
        #expect(try Data(contentsOf: library.store.documentURL(id: original.id)) == originalBytes)

        let secondCopy = try library.duplicate(id: original.id)
        #expect(secondCopy.name == "X copy 2")
    }

    @Test func trashIsRecoverable() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)
        let metadata = try library.createProject(
            name: "Keep me",
            editorMode: .simple,
            document: ProjectTestSupport.simpleDocument(text: "precious")
        )

        try library.moveToTrash(id: metadata.id)

        #expect(library.projects.isEmpty)
        #expect(library.trashedProjects.map(\.id) == [metadata.id])
        #expect(FileManager.default.fileExists(atPath: library.store.documentURL(id: metadata.id).path))

        // Trash state survives a restart.
        let restarted = ProjectTestSupport.makeLibrary(root: root)
        #expect(restarted.trashedProjects.map(\.id) == [metadata.id])

        try restarted.restoreFromTrash(id: metadata.id)
        #expect(restarted.trashedProjects.isEmpty)
        #expect(restarted.projects.map(\.id) == [metadata.id])
        #expect(try restarted.document(for: metadata.id).text.value == "precious")

        try restarted.moveToTrash(id: metadata.id)
        try restarted.purge(id: metadata.id)
        #expect(restarted.trashedProjects.isEmpty)
        #expect(restarted.metadata(id: metadata.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: restarted.store.projectDirectory(id: metadata.id).path))
    }

    @Test func corruptProjectIsIsolatedNotFatal() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)
        var goodIDs: [UUID] = []
        for number in 0..<3 {
            goodIDs.append(try library.createProject(
                name: "Good \(number)",
                editorMode: .simple,
                document: ProjectTestSupport.simpleDocument(text: "good \(number)")
            ).id)
        }
        let bad = try library.createProject(
            name: "Bad",
            editorMode: .simple,
            document: ProjectTestSupport.simpleDocument(text: "bad")
        )
        let badBytes = Data("{".utf8)
        try badBytes.write(to: library.store.documentURL(id: bad.id))

        let restarted = ProjectTestSupport.makeLibrary(root: root)
        #expect(restarted.libraryError == nil)
        #expect(restarted.projects.count == 4)

        for (number, id) in goodIDs.enumerated() {
            #expect(try restarted.document(for: id).text.value == "good \(number)")
        }

        do {
            _ = try restarted.document(for: bad.id)
            Issue.record("Expected documentUnreadable")
        } catch let error as ThumbnailProjectLibraryError {
            if case .documentUnreadable(let id, _) = error {
                #expect(id == bad.id)
            } else {
                Issue.record("Unexpected error \(error)")
            }
        }

        #expect(try Data(contentsOf: restarted.store.documentURL(id: bad.id)) == badBytes)
        let badSummary = try #require(restarted.projects.first { $0.id == bad.id })
        #expect(badSummary.isReadable == false)
        #expect(restarted.projects.filter(\.isReadable).count == 3)
    }

    @Test func futureSchemaProjectIsRefusedNotSilentlyRewritten() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let store = ThumbnailProjectStore(rootDirectory: root.appendingPathComponent("Projects"))
        let future = ThumbnailProjectMetadata(
            name: "From the future",
            createdAt: Date(),
            updatedAt: Date(),
            editorMode: .simple,
            schemaVersion: 99
        )
        try store.saveDocument(ProjectTestSupport.simpleDocument(text: "future"), id: future.id)
        try store.saveMetadataSidecar(future)
        var index = ThumbnailProjectLibraryIndex()
        index.upsert(future)
        try store.saveIndex(index)
        let bytesBefore = try Data(contentsOf: store.documentURL(id: future.id))

        let library = ProjectTestSupport.makeLibrary(root: root)
        #expect(throws: ThumbnailProjectLibraryError.unsupportedSchema(future.id, 99)) {
            _ = try library.document(for: future.id)
        }
        #expect(throws: ThumbnailProjectLibraryError.unsupportedSchema(future.id, 99)) {
            try library.saveDocument(ProjectTestSupport.simpleDocument(text: "overwrite"), for: future.id)
        }
        #expect(try Data(contentsOf: store.documentURL(id: future.id)) == bytesBefore)
        #expect(library.projects.first?.isReadable == false)

        // The editor fallback never picks an unsupported project.
        let opened = try #require(library.openFallbackProject(
            for: .simple,
            excluding: nil,
            defaultDocument: { SimpleMakerConfigurationModel().document }
        ))
        #expect(opened.metadata.id != future.id)
    }

    @Test func previewIsRegeneratedAndFailureIsNonFatal() async throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let stub = StubProjectPreviewRenderer()
        let library = ProjectTestSupport.makeLibrary(root: root, renderer: stub)
        let metadata = try library.createProject(
            name: "Preview",
            editorMode: .simple,
            document: ProjectTestSupport.simpleDocument(text: "preview")
        )

        library.schedulePreviewRefresh(for: metadata.id, document: try library.document(for: metadata.id))
        await library.waitForPendingPreviews()

        #expect(library.store.loadPreviewData(id: metadata.id) == stub.bytes)
        #expect(await library.previewData(for: metadata.id) == stub.bytes)
        #expect(library.previewRevisions[metadata.id] == 1)

        let failingRoot = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(failingRoot) }
        let failing = ProjectTestSupport.makeLibrary(
            root: failingRoot,
            renderer: StubProjectPreviewRenderer(bytes: nil)
        )
        let other = try failing.createProject(
            name: "No preview",
            editorMode: .simple,
            document: ProjectTestSupport.simpleDocument(text: "x")
        )
        try failing.saveDocument(ProjectTestSupport.simpleDocument(text: "y"), for: other.id)
        failing.schedulePreviewRefresh(for: other.id, document: try failing.document(for: other.id))
        await failing.waitForPendingPreviews()

        #expect(failing.store.loadPreviewData(id: other.id) == nil)
        #expect(failing.libraryError == nil)
        #expect(try failing.document(for: other.id).text.value == "y")
    }

    @Test func previewRendererProducesPNGForBothEditorModes() async throws {
        let renderer = ThumbnailProjectPreviewRenderer()
        let simple = ProjectTestSupport.simpleDocument(text: "Simple", ratio: .ratio16_9)
        var premiumConfiguration = PremiumMakerConfigurationModel()
        premiumConfiguration.overlayText = "Premium"
        premiumConfiguration.selectedRatio = .ratio9_16
        let premium = premiumConfiguration.document

        let simpleData = try #require(await renderer.previewPNGData(for: simple, maxPixelWidth: 320))
        let premiumData = try #require(await renderer.previewPNGData(for: premium, maxPixelWidth: 320))
        let simpleImage = try #require(UIImage(data: simpleData))
        let premiumImage = try #require(UIImage(data: premiumData))

        #expect(abs(simpleImage.size.width - 320) <= 1)
        #expect(abs(simpleImage.size.height - 180) <= 1)
        #expect(abs(premiumImage.size.width - 180) <= 1)
        #expect(abs(premiumImage.size.height - 320) <= 1)
    }

    @Test func purgeExpiredTrashOnlyRemovesOldEntries() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)
        let old = try library.createProject(
            name: "Old",
            editorMode: .simple,
            document: ProjectTestSupport.simpleDocument(text: "old")
        )
        let recent = try library.createProject(
            name: "Recent",
            editorMode: .simple,
            document: ProjectTestSupport.simpleDocument(text: "recent")
        )
        let live = try library.createProject(
            name: "Live",
            editorMode: .simple,
            document: ProjectTestSupport.simpleDocument(text: "live")
        )
        try library.moveToTrash(id: old.id)
        try library.moveToTrash(id: recent.id)

        // refresh() never purges.
        library.refresh()
        #expect(library.trashedProjects.count == 2)

        let thirtyDays: TimeInterval = 30 * 24 * 60 * 60
        let purged = library.purgeExpiredTrash(
            olderThan: thirtyDays,
            now: Date().addingTimeInterval(thirtyDays + 60)
        )
        // Both are older than the cutoff at that simulated "now".
        #expect(Set(purged) == Set([old.id, recent.id]))
        #expect(library.projects.map(\.id) == [live.id])

        let untouched = library.purgeExpiredTrash(olderThan: thirtyDays)
        #expect(untouched.isEmpty)
        #expect(FileManager.default.fileExists(atPath: library.store.documentURL(id: live.id).path))
    }

    @Test func recentTrashIsNotPurgedEarly() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)
        let recent = try library.createProject(
            name: "Recent",
            editorMode: .simple,
            document: ProjectTestSupport.simpleDocument(text: "recent")
        )
        try library.moveToTrash(id: recent.id)

        let purged = library.purgeExpiredTrash(olderThan: 30 * 24 * 60 * 60)

        #expect(purged.isEmpty)
        #expect(library.trashedProjects.map(\.id) == [recent.id])
        #expect(FileManager.default.fileExists(atPath: library.store.documentURL(id: recent.id).path))
    }

    @Test func corruptIndexIsRebuiltAndReported() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)
        let metadata = try library.createProject(
            name: "Survivor",
            editorMode: .simple,
            document: ProjectTestSupport.simpleDocument(text: "alive")
        )
        try Data("garbage".utf8).write(to: library.store.indexURL)

        let restarted = ProjectTestSupport.makeLibrary(root: root)

        #expect(restarted.didRebuildIndex)
        #expect(restarted.libraryError != nil)
        #expect(restarted.projects.map(\.id) == [metadata.id])
        #expect(try restarted.document(for: metadata.id).text.value == "alive")
    }
}
