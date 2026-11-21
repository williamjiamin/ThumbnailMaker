//
//  ThumbnailProjectSwitchingTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-01: view-model level project switching, save safety and undo
//  isolation.
//

import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ThumbnailProjectSwitchingTests {
    private func makeSimpleViewModel(root: URL, library: ThumbnailProjectLibrary) -> SimpleMakerViewModel {
        SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: root.appendingPathComponent("Drafts/simple.json")),
            brandKitStore: BrandKitStore(fileURL: root.appendingPathComponent("brand.json")),
            projectLibrary: library
        )
    }

    private func makePremiumViewModel(root: URL, library: ThumbnailProjectLibrary) -> PremiumMakerViewModel {
        PremiumMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: root.appendingPathComponent("Drafts/premium.json")),
            brandKitStore: BrandKitStore(fileURL: root.appendingPathComponent("brand.json")),
            projectLibrary: library
        )
    }

    @Test func firstLaunchWithoutDraftsCreatesAnUntitledProject() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)

        let viewModel = makeSimpleViewModel(root: root, library: library)

        let activeID = try #require(viewModel.activeProjectID)
        #expect(viewModel.isProjectLibraryAvailable)
        #expect(viewModel.activeProjectName == "Untitled Project")
        #expect(library.projects.map(\.id) == [activeID])
        #expect(viewModel.canUndo == false)
        #expect(viewModel.restoredDraft == false)
        #expect(viewModel.draftSaveState.lastSavedDate != nil)
    }

    @Test func viewModelsWithoutALibraryKeepTheLegacyDraftPath() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let store = ThumbnailDraftStore(fileURL: root.appendingPathComponent("simple.json"))
        let viewModel = SimpleMakerViewModel(
            draftStore: store,
            brandKitStore: BrandKitStore(fileURL: root.appendingPathComponent("brand.json"))
        )
        viewModel.simpleMakerConfiguration.overlayText = "legacy path"
        viewModel.saveDraftNow()

        #expect(viewModel.activeProjectID == nil)
        #expect(viewModel.isProjectLibraryAvailable == false)
        #expect(viewModel.switchToProject(UUID()) == false)
        #expect(try store.load()?.overlayText == "legacy path")
    }

    @Test func editsAutosaveIntoTheActiveProjectAndSurviveARelaunch() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)
        let viewModel = makeSimpleViewModel(root: root, library: library)
        let activeID = try #require(viewModel.activeProjectID)

        viewModel.simpleMakerConfiguration.overlayText = "persist me"
        viewModel.commitEditorStateNow()

        let relaunchedLibrary = ProjectTestSupport.makeLibrary(root: root)
        let relaunched = makeSimpleViewModel(root: root, library: relaunchedLibrary)
        #expect(relaunched.activeProjectID == activeID)
        #expect(relaunched.simpleMakerConfiguration.overlayText == "persist me")
        #expect(relaunched.canUndo == false)
    }

    @Test func switchingCommitsThePendingSaveBeforeLoading() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)
        let viewModel = makeSimpleViewModel(root: root, library: library)
        let first = try #require(viewModel.activeProjectID)
        let other = try library.createProject(
            name: "Other",
            editorMode: .simple,
            document: ProjectTestSupport.simpleDocument(text: "other content")
        )

        // Do NOT wait for the 0.6s debounce.
        viewModel.simpleMakerConfiguration.overlayText = "pending text"
        #expect(viewModel.switchToProject(other.id))

        #expect(viewModel.activeProjectID == other.id)
        #expect(viewModel.activeProjectName == "Other")
        #expect(viewModel.simpleMakerConfiguration.overlayText == "other content")
        #expect(try library.document(for: first).text.value == "pending text")
        #expect(library.activeProjectID(for: .simple) == other.id)
    }

    @Test func switchingIsBlockedAndVisiblyFailsWhenTheSaveFails() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)
        let viewModel = makeSimpleViewModel(root: root, library: library)
        let first = try #require(viewModel.activeProjectID)
        let other = try library.createProject(
            name: "Other",
            editorMode: .simple,
            document: ProjectTestSupport.simpleDocument(text: "other content")
        )

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: library.store.projectDirectory(id: first).path
        )
        viewModel.simpleMakerConfiguration.overlayText = "unsaved work"
        let switched = viewModel.switchToProject(other.id)

        #expect(switched == false)
        #expect(viewModel.draftSaveState.failureMessage != nil)
        #expect(viewModel.saveError != nil)
        #expect(viewModel.showingSaveAlert)
        #expect(viewModel.activeProjectID == first)
        #expect(viewModel.simpleMakerConfiguration.overlayText == "unsaved work")

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: library.store.projectDirectory(id: first).path
        )
        viewModel.showingSaveAlert = false
        #expect(viewModel.switchToProject(other.id))
        #expect(viewModel.activeProjectID == other.id)
        #expect(try library.document(for: first).text.value == "unsaved work")
    }

    @Test func switchingResetsUndoHistoryAcrossTheBoundary() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)
        let viewModel = makeSimpleViewModel(root: root, library: library)
        let first = try #require(viewModel.activeProjectID)
        let other = try library.createProject(
            name: "B",
            editorMode: .simple,
            document: ProjectTestSupport.simpleDocument(text: "B content")
        )

        viewModel.simpleMakerConfiguration.overlayText = "A edit"
        viewModel.commitEditorStateNow()
        #expect(viewModel.canUndo)

        #expect(viewModel.switchToProject(other.id))
        #expect(viewModel.canUndo == false)
        #expect(viewModel.canRedo == false)

        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.overlayText == "B content")
        #expect(try library.document(for: other.id).text.value == "B content")
        #expect(try library.document(for: first).text.value == "A edit")
    }

    @Test func adoptingAProjectDoesNotScheduleAStaleAutosaveIntoIt() async throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)
        let viewModel = makeSimpleViewModel(root: root, library: library)
        let other = try library.createProject(
            name: "B",
            editorMode: .simple,
            document: ProjectTestSupport.simpleDocument(text: "B content")
        )
        let bytesBefore = try Data(contentsOf: library.store.documentURL(id: other.id))

        #expect(viewModel.switchToProject(other.id))
        // Wait past the autosave debounce.
        try await Task.sleep(nanoseconds: 900_000_000)

        #expect(try Data(contentsOf: library.store.documentURL(id: other.id)) == bytesBefore)
        #expect(viewModel.canUndo == false)
    }

    @Test func switchingToAnUnreadableProjectFailsVisiblyAndKeepsTheCurrentOne() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)
        let viewModel = makeSimpleViewModel(root: root, library: library)
        let first = try #require(viewModel.activeProjectID)
        viewModel.simpleMakerConfiguration.overlayText = "current"
        viewModel.commitEditorStateNow()

        let broken = try library.createProject(
            name: "Broken",
            editorMode: .simple,
            document: ProjectTestSupport.simpleDocument(text: "x")
        )
        try Data("{".utf8).write(to: library.store.documentURL(id: broken.id))

        #expect(viewModel.switchToProject(broken.id) == false)
        #expect(viewModel.activeProjectID == first)
        #expect(viewModel.simpleMakerConfiguration.overlayText == "current")
        #expect(viewModel.showingSaveAlert)
        #expect(viewModel.saveError != nil)
        #expect(library.projects.first { $0.id == broken.id }?.isReadable == false)
    }

    @Test func openingWhenTheActiveProjectIsCorruptFallsBackToTheNewestReadableProject() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)
        let readable = try library.createProject(
            name: "Readable",
            editorMode: .simple,
            document: ProjectTestSupport.simpleDocument(text: "fallback content")
        )
        let corrupt = try library.createProject(
            name: "Corrupt",
            editorMode: .simple,
            document: ProjectTestSupport.simpleDocument(text: "lost?")
        )
        library.setActiveProjectID(corrupt.id, for: .simple)
        let corruptBytes = Data("{ broken".utf8)
        try corruptBytes.write(to: library.store.documentURL(id: corrupt.id))

        let relaunchedLibrary = ProjectTestSupport.makeLibrary(root: root)
        let viewModel = makeSimpleViewModel(root: root, library: relaunchedLibrary)

        #expect(viewModel.activeProjectID == readable.id)
        #expect(viewModel.simpleMakerConfiguration.overlayText == "fallback content")
        #expect(relaunchedLibrary.libraryError != nil)
        #expect(try Data(contentsOf: relaunchedLibrary.store.documentURL(id: corrupt.id)) == corruptBytes)
        #expect(relaunchedLibrary.projects.count == 2)
    }

    @Test func bothViewModelsAdoptTheMigratedProjectOnFirstLaunch() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let simpleStore = ThumbnailDraftStore(fileURL: root.appendingPathComponent("Drafts/simple.json"))
        let premiumStore = ThumbnailDraftStore(fileURL: root.appendingPathComponent("Drafts/premium.json"))
        var simple = SimpleMakerConfigurationModel()
        simple.overlayText = "simple legacy"
        try simpleStore.save(simple)
        var premium = PremiumMakerConfigurationModel()
        premium.overlayText = "premium legacy"
        try premiumStore.save(premium)

        let library = ProjectTestSupport.makeLibrary(root: root)
        let simpleViewModel = makeSimpleViewModel(root: root, library: library)
        let premiumViewModel = makePremiumViewModel(root: root, library: library)

        #expect(simpleViewModel.simpleMakerConfiguration.overlayText == "simple legacy")
        #expect(premiumViewModel.premiumMakerConfiguration.overlayText == "premium legacy")
        #expect(simpleViewModel.restoredDraft)
        #expect(premiumViewModel.restoredDraft)
        let simpleID = try #require(simpleViewModel.activeProjectID)
        let premiumID = try #require(premiumViewModel.activeProjectID)
        #expect(simpleID != premiumID)
        #expect(simpleViewModel.activeProjectName == "Simple Draft")
        #expect(premiumViewModel.activeProjectName == "Premium Draft")

        simpleViewModel.simpleMakerConfiguration.overlayText = "simple edited"
        simpleViewModel.commitEditorStateNow()
        premiumViewModel.premiumMakerConfiguration.overlayText = "premium edited"
        premiumViewModel.commitEditorStateNow()

        #expect(try library.document(for: simpleID).text.value == "simple edited")
        #expect(try library.document(for: premiumID).text.value == "premium edited")
        #expect(library.projects.count == 2)
    }

    @Test func createDuplicateTrashAndRestoreThroughTheViewModel() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)
        let viewModel = makePremiumViewModel(root: root, library: library)
        let first = try #require(viewModel.activeProjectID)
        viewModel.premiumMakerConfiguration.overlayText = "first project"

        #expect(viewModel.renameProject(first, to: "Launch Video"))
        #expect(viewModel.activeProjectName == "Launch Video")

        #expect(viewModel.createNewProject(named: "Second"))
        let second = try #require(viewModel.activeProjectID)
        #expect(second != first)
        #expect(viewModel.premiumMakerConfiguration.overlayText.isEmpty)
        #expect(try library.document(for: first).text.value == "first project")
        #expect(library.metadata(id: second)?.editorMode == .premium)

        let copy = try #require(viewModel.duplicateProject(first))
        #expect(copy.name == "Launch Video copy")
        #expect(viewModel.activeProjectID == second)

        // Trashing the open project moves the editor to the newest other one.
        #expect(viewModel.trashProject(second))
        #expect(viewModel.activeProjectID != second)
        #expect(viewModel.activeProjectID != nil)
        #expect(library.trashedProjects.map(\.id) == [second])
        #expect(FileManager.default.fileExists(atPath: library.store.documentURL(id: second).path))

        // The open project can never be purged.
        let current = try #require(viewModel.activeProjectID)
        #expect(viewModel.purgeProject(current) == false)

        #expect(viewModel.restoreProject(second))
        #expect(library.trashedProjects.isEmpty)
        #expect(viewModel.switchToProject(second))
        #expect(viewModel.activeProjectName == "Second")
    }
}
