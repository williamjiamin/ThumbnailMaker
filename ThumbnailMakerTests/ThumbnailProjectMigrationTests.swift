//
//  ThumbnailProjectMigrationTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-01: one-time migration of the legacy single-slot drafts.
//

import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ThumbnailProjectMigrationTests {
    private struct LegacyFixture {
        let simpleStore: ThumbnailDraftStore
        let premiumStore: ThumbnailDraftStore
        let simpleDocument: ThumbnailDocument
        let premiumDocument: ThumbnailDocument
    }

    private func seedLegacyDrafts(in root: URL) throws -> LegacyFixture {
        let simpleStore = ThumbnailDraftStore(fileURL: root.appendingPathComponent("Drafts/simple-maker-draft.json"))
        let premiumStore = ThumbnailDraftStore(fileURL: root.appendingPathComponent("Drafts/premium-maker-draft.json"))

        var simple = SimpleMakerConfigurationModel()
        simple.overlayText = "Legacy simple"
        simple.selectedImage = ProjectTestSupport.makeImage(size: CGSize(width: 48, height: 27))
        simple.layers.addTextLayer(value: "Layer text", id: "legacy-text-layer")
        simple.exportOptions.applyPreset(.instagramSquare)
        simple.exportOptions.format = .jpeg
        simple.exportOptions.compressionQuality = 0.55
        try simpleStore.save(simple)

        var premium = PremiumMakerConfigurationModel()
        premium.overlayText = "Legacy premium"
        premium.selectedImage = ProjectTestSupport.makeImage(size: CGSize(width: 30, height: 30), color: .systemPink)
        try premiumStore.save(premium)

        return LegacyFixture(
            simpleStore: simpleStore,
            premiumStore: premiumStore,
            simpleDocument: try #require(try simpleStore.loadDocument()),
            premiumDocument: try #require(try premiumStore.loadDocument())
        )
    }

    @Test func legacySimpleAndPremiumDraftsMigrateOnceEach() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let fixture = try seedLegacyDrafts(in: root)
        let library = ProjectTestSupport.makeLibrary(root: root)

        library.migrateLegacyDraftsIfNeeded(simpleStore: fixture.simpleStore, premiumStore: fixture.premiumStore)

        #expect(library.projects.count == 2)
        let simpleMeta = try #require(library.projects.first { $0.metadata.editorMode == .simple }?.metadata)
        let premiumMeta = try #require(library.projects.first { $0.metadata.editorMode == .premium }?.metadata)
        #expect(simpleMeta.name == "Simple Draft")
        #expect(premiumMeta.name == "Premium Draft")
        #expect(simpleMeta.origin == .migratedSimpleDraft)
        #expect(premiumMeta.origin == .migratedPremiumDraft)
        #expect(simpleMeta.createdAt == fixture.simpleDocument.updatedAt)
        #expect(simpleMeta.updatedAt == fixture.simpleDocument.updatedAt)
        #expect(premiumMeta.createdAt == fixture.premiumDocument.updatedAt)

        let simpleConfiguration = try library.document(for: simpleMeta.id).makeSimpleConfiguration()
        #expect(simpleConfiguration.overlayText == "Legacy simple")
        #expect(simpleConfiguration.selectedImage?.size == CGSize(width: 48, height: 27))
        #expect(simpleConfiguration.layers.count == fixture.simpleDocument.layers.count)
        #expect(simpleConfiguration.layers.map(\.id) == fixture.simpleDocument.layers.map(\.id))
        #expect(simpleConfiguration.layers.contains { $0.id == "legacy-text-layer" })
        #expect(simpleConfiguration.exportOptions.preset == .instagramSquare)
        #expect(simpleConfiguration.exportOptions.format == .jpeg)
        #expect(simpleConfiguration.exportOptions.compressionQuality == 0.55)

        let premiumConfiguration = try library.document(for: premiumMeta.id).makePremiumConfiguration()
        #expect(premiumConfiguration.overlayText == "Legacy premium")
        #expect(premiumConfiguration.selectedImage?.size == CGSize(width: 30, height: 30))

        // A second launch (fresh library over the same root) migrates nothing.
        let relaunched = ProjectTestSupport.makeLibrary(root: root)
        relaunched.migrateLegacyDraftsIfNeeded(simpleStore: fixture.simpleStore, premiumStore: fixture.premiumStore)
        #expect(relaunched.projects.count == 2)
    }

    @Test func migrationNeverDeletesLegacyDraftFiles() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let fixture = try seedLegacyDrafts(in: root)
        let simpleBytes = try Data(contentsOf: fixture.simpleStore.fileURL)
        let premiumBytes = try Data(contentsOf: fixture.premiumStore.fileURL)
        let library = ProjectTestSupport.makeLibrary(root: root)

        library.migrateLegacyDraftsIfNeeded(simpleStore: fixture.simpleStore, premiumStore: fixture.premiumStore)

        // Further edits go to the project, never back into the legacy file.
        let viewModel = SimpleMakerViewModel(
            draftStore: fixture.simpleStore,
            brandKitStore: BrandKitStore(fileURL: root.appendingPathComponent("brand.json")),
            projectLibrary: library
        )
        viewModel.simpleMakerConfiguration.overlayText = "edited after migration"
        viewModel.commitEditorStateNow()

        #expect(try Data(contentsOf: fixture.simpleStore.fileURL) == simpleBytes)
        #expect(try Data(contentsOf: fixture.premiumStore.fileURL) == premiumBytes)
        let activeID = try #require(viewModel.activeProjectID)
        #expect(try library.document(for: activeID).text.value == "edited after migration")
    }

    @Test func migrationIsIdempotentWhenTheLedgerWriteWasLost() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let fixture = try seedLegacyDrafts(in: root)
        let library = ProjectTestSupport.makeLibrary(root: root)
        library.migrateLegacyDraftsIfNeeded(simpleStore: fixture.simpleStore, premiumStore: fixture.premiumStore)
        #expect(library.projects.count == 2)

        // Simulate the ledger being lost.
        var (index, _) = try library.store.loadIndex()
        index.migratedLegacyDraftKinds = []
        try library.store.saveIndex(index)

        let relaunched = ProjectTestSupport.makeLibrary(root: root)
        #expect(relaunched.migratedLegacyDraftKinds.isEmpty)
        relaunched.migrateLegacyDraftsIfNeeded(simpleStore: fixture.simpleStore, premiumStore: fixture.premiumStore)

        #expect(relaunched.projects.count == 2)
        #expect(Set(relaunched.migratedLegacyDraftKinds) == Set(["simple", "premium"]))
    }

    @Test func corruptLegacyDraftIsRecordedAsAWarningAndTheFileIsKept() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let simpleStore = ThumbnailDraftStore(fileURL: root.appendingPathComponent("Drafts/simple-maker-draft.json"))
        let premiumStore = ThumbnailDraftStore(fileURL: root.appendingPathComponent("Drafts/premium-maker-draft.json"))
        try FileManager.default.createDirectory(
            at: simpleStore.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let garbage = Data("definitely not a draft".utf8)
        try garbage.write(to: simpleStore.fileURL)

        let library = ProjectTestSupport.makeLibrary(root: root)
        library.migrateLegacyDraftsIfNeeded(simpleStore: simpleStore, premiumStore: premiumStore)

        #expect(library.projects.isEmpty)
        #expect(library.migrationWarnings["simple"] != nil)
        #expect(library.migrationWarnings["premium"] == nil)
        #expect(library.libraryError != nil)
        #expect(Set(library.migratedLegacyDraftKinds) == Set(["simple", "premium"]))
        #expect(try Data(contentsOf: simpleStore.fileURL) == garbage)
    }

    @Test func migrationSetsTheActiveProjectPerEditor() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let fixture = try seedLegacyDrafts(in: root)
        let library = ProjectTestSupport.makeLibrary(root: root)

        library.migrateLegacyDraftsIfNeeded(simpleStore: fixture.simpleStore, premiumStore: fixture.premiumStore)

        let simpleID = try #require(library.activeProjectID(for: .simple))
        let premiumID = try #require(library.activeProjectID(for: .premium))
        #expect(simpleID != premiumID)
        #expect(library.metadata(id: simpleID)?.origin == .migratedSimpleDraft)
        #expect(library.metadata(id: premiumID)?.origin == .migratedPremiumDraft)

        let relaunched = ProjectTestSupport.makeLibrary(root: root)
        #expect(relaunched.activeProjectID(for: .simple) == simpleID)
        #expect(relaunched.activeProjectID(for: .premium) == premiumID)
    }
}
