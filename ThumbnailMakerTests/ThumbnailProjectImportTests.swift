//
//  ThumbnailProjectImportTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-06: importing a package always creates a new, independent library
//  project; a failed import leaves the open project exactly as it was.
//

import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ThumbnailProjectImportTests {
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

    private func package(named name: String = "Launch Art") throws -> ThumbnailProjectPackage {
        let contents = PackageFixtures.contents(document: try PackageFixtures.premiumDocument(), name: name)
        let encoded = try ThumbnailProjectPackageWriter.encode(contents)
        return try ThumbnailProjectPackageReader.package(from: ThumbnailProjectPackageWriter.fileWrapper(for: encoded))
    }

    // MARK: Pure planning

    @Test func importResolvesNameCollisions() throws {
        let colliding = ThumbnailProjectImporter.importPlan(
            for: try package(named: "Launch Art"),
            into: .premium,
            existingNames: ["Launch Art", "Launch Art 2"]
        )
        #expect(colliding.name == "Launch Art 3")
        #expect(colliding.didRenameForCollision)
        #expect(colliding.notices.count == 1)

        let fresh = ThumbnailProjectImporter.importPlan(for: try package(named: "Other"), into: .premium, existingNames: ["Launch Art"])
        #expect(fresh.name == "Other")
        #expect(fresh.didRenameForCollision == false)
        #expect(fresh.notices.isEmpty)

        let blank = ThumbnailProjectImporter.importPlan(for: try package(named: "   "), into: .premium)
        #expect(blank.name == "Imported Project")
    }

    @Test func crossEditorImportIsFlaggedAndDowngradesSafely() throws {
        let plan = ThumbnailProjectImporter.importPlan(for: try package(), into: .simple, now: PackageFixtures.date)

        #expect(plan.isCrossEditorImport)
        #expect(plan.document.editorMode == .simple)
        #expect(plan.notices.contains { $0.contains("Premium Maker") })
        let original = try PackageFixtures.premiumDocument()
        #expect(plan.document.layers.filter { $0.content != nil } == original.layers.filter { $0.content != nil })
        #expect(plan.document.export == original.export)

        let configuration = plan.document.makeSimpleConfiguration()
        #expect(configuration.selectedImage != nil)
        #expect(configuration.overlayText == "Launch Day")
    }

    @Test func importHealsHandEditedLayerLists() throws {
        var document = try PackageFixtures.premiumDocument()
        document.layers.append(ThumbnailDocumentLayer(id: ThumbnailDocumentLayer.textID, kind: .text, name: "Dup", zIndex: 5))
        document.layers.append(ThumbnailDocumentLayer(id: "empty", kind: .shape, name: "Empty", zIndex: 35))
        document.layers.swapAt(1, 5)

        let contents = PackageFixtures.contents(document: document)
        let wrapper = ThumbnailProjectPackageWriter.fileWrapper(for: try ThumbnailProjectPackageWriter.encode(contents))
        let plan = ThumbnailProjectImporter.importPlan(
            for: try ThumbnailProjectPackageReader.package(from: wrapper),
            into: .premium
        )

        let ids = plan.document.layers.map(\.id)
        #expect(ids.filter { $0 == ThumbnailDocumentLayer.textID }.count == 1)
        #expect(plan.document.layers.first { $0.id == ThumbnailDocumentLayer.textID }?.name == "Headline")
        #expect(!ids.contains("empty"))
        let zIndices = plan.document.layers.map(\.zIndex)
        #expect(zIndices == zIndices.sorted())
    }

    // MARK: Library + view model

    @Test func importCreatesANewProjectAndNeverTouchesTheOriginal() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)
        let viewModel = makePremiumViewModel(root: root, library: library)
        let originalID = try #require(viewModel.activeProjectID)
        viewModel.premiumMakerConfiguration = PremiumMakerConfigurationModel(document: try PackageFixtures.premiumDocument())
        viewModel.commitEditorStateNow()
        viewModel.renameProject(originalID, to: "Launch Art")

        // Export the open project, then import it back into the same library.
        let exported = try viewModel.exportProjectPackage(originalID).get()
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Launch Art.thumbproj")
        try ThumbnailProjectPackageWriter.write(exported.package, to: url)

        let outcome = try viewModel.importProjectPackage(from: url).get()
        let importedID = outcome.openResult.metadata.id
        #expect(importedID != originalID)
        #expect(importedID.uuidString != exported.package.manifest.projectID)
        #expect(outcome.plan.name == "Launch Art 2")
        #expect(outcome.openResult.metadata.origin == .imported)
        #expect(viewModel.activeProjectID == importedID)
        #expect(viewModel.activeProjectName == "Launch Art 2")
        #expect(viewModel.canUndo == false)
        #expect(viewModel.premiumMakerConfiguration.overlayText == "Launch Day")
        let originalDocument = try library.document(for: originalID)
        #expect(ThumbnailDocumentHistory.snapshot(try library.document(for: importedID))
            == ThumbnailDocumentHistory.snapshot(originalDocument))

        // Independent copies: editing the import never touches the original.
        viewModel.premiumMakerConfiguration.overlayText = "Only in the copy"
        viewModel.commitEditorStateNow()
        #expect(try library.document(for: originalID) == originalDocument)
        #expect(try library.document(for: importedID).text.value == "Only in the copy")
        #expect(library.projects.count == 2)
    }

    @Test func failedImportLeavesTheOpenProjectUnchanged() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)
        let viewModel = makeSimpleViewModel(root: root, library: library)
        let activeID = try #require(viewModel.activeProjectID)
        viewModel.simpleMakerConfiguration.overlayText = "Keep me"
        viewModel.commitEditorStateNow()
        viewModel.simpleMakerConfiguration.overlayText = "Keep me, edited"
        viewModel.commitEditorStateNow()
        #expect(viewModel.canUndo)

        let snapshot = ThumbnailDocumentHistory.snapshot(viewModel.simpleMakerConfiguration.document)
        let diskBytes = try Data(contentsOf: library.store.documentURL(id: activeID))
        let projectCount = library.projects.count

        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let good = PackageFixtures.contents(document: try PackageFixtures.premiumDocument())

        let malformed = try PackageFixtures.writePackage(good, in: directory, fileName: "Malformed")
        try Data("{".utf8).write(to: malformed.appendingPathComponent("manifest.json"))

        let missingAsset = try PackageFixtures.writePackage(good, in: directory, fileName: "MissingAsset")
        let assetsURL = missingAsset.appendingPathComponent("assets")
        let firstAsset = try #require(try FileManager.default.contentsOfDirectory(atPath: assetsURL.path).first)
        try FileManager.default.removeItem(at: assetsURL.appendingPathComponent(firstAsset))

        let future = try PackageFixtures.writePackage(good, in: directory, fileName: "Future")
        var futureManifest = try PackageFixtures.readManifestJSON(future)
        futureManifest["minimumReaderVersion"] = 9
        try PackageFixtures.writeManifestJSON(futureManifest, to: future)

        let traversal = try PackageFixtures.writePackage(good, in: directory, fileName: "Traversal")
        var traversalManifest = try PackageFixtures.readManifestJSON(traversal)
        var assets = try #require(traversalManifest["assets"] as? [[String: Any]])
        assets[0]["path"] = "../../escape.png"
        traversalManifest["assets"] = assets
        try PackageFixtures.writeManifestJSON(traversalManifest, to: traversal)

        for url in [malformed, missingAsset, future, traversal] {
            let result = viewModel.importProjectPackage(from: url)
            guard case .failure = result else {
                Issue.record("\(url.lastPathComponent) was imported")
                continue
            }
            #expect(ThumbnailDocumentHistory.snapshot(viewModel.simpleMakerConfiguration.document) == snapshot)
            #expect(viewModel.activeProjectID == activeID)
            #expect(viewModel.canUndo)
            #expect(library.projects.count == projectCount)
            #expect(try Data(contentsOf: library.store.documentURL(id: activeID)) == diskBytes)
        }

        // A good package does open, as a fresh project with its own undo timeline.
        let goodURL = try PackageFixtures.writePackage(good, in: directory, fileName: "Good")
        let outcome = try viewModel.importProjectPackage(from: goodURL).get()
        #expect(viewModel.activeProjectID == outcome.openResult.metadata.id)
        #expect(viewModel.canUndo == false)
        #expect(outcome.plan.isCrossEditorImport)
        #expect(library.projects.count == projectCount + 1)
        // The previous project is intact in the library.
        #expect(try library.document(for: activeID).text.value == "Keep me, edited")
    }

    @Test func importedProjectSurvivesRelaunch() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)
        let viewModel = makePremiumViewModel(root: root, library: library)
        let original = try PackageFixtures.premiumDocument()

        let outcome = try viewModel.importProjectPackage(try package()).get()
        let importedID = outcome.openResult.metadata.id

        let relaunchedLibrary = ProjectTestSupport.makeLibrary(root: root)
        let relaunched = makePremiumViewModel(root: root, library: relaunchedLibrary)
        #expect(relaunched.activeProjectID == importedID)
        #expect(relaunched.activeProjectName == "Launch Art")
        #expect(relaunched.premiumMakerConfiguration.overlayText == "Launch Day")
        #expect(relaunched.premiumMakerConfiguration.circularProfile?.image != nil)
        let document = try relaunchedLibrary.document(for: importedID)
        #expect(document.imageData == original.imageData)
        #expect(document.profile?.imageData == original.profile?.imageData)
        #expect(document.text.style == original.text.style)
        #expect(document.export == original.export)
        #expect(document.layers == original.layers)
    }

    @Test func variantsTravelWithTheProject() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)
        let viewModel = makeSimpleViewModel(root: root, library: library)
        let sourceID = try #require(viewModel.activeProjectID)
        viewModel.simpleMakerConfiguration.overlayText = "Variant A title"
        viewModel.commitEditorStateNow()
        _ = viewModel.duplicateActiveVariant()
        viewModel.simpleMakerConfiguration.overlayText = "Variant B title"
        viewModel.commitEditorStateNow()
        viewModel.renameVariant(.b, to: "Punchy")

        let exported = try viewModel.exportProjectPackage(sourceID).get()
        #expect(exported.package.manifest.variants.map(\.slotRawValue) == ["a", "b"])
        let wrapper = ThumbnailProjectPackageWriter.fileWrapper(for: exported.package)
        let package = try ThumbnailProjectPackageReader.package(from: wrapper)

        let outcome = try viewModel.importProjectPackage(package).get()
        #expect(outcome.warnings.isEmpty)
        #expect(viewModel.activeProjectID == outcome.openResult.metadata.id)
        #expect(viewModel.variantSet.slots == [.a, .b])
        #expect(viewModel.variantSet.activeSlot == .b)
        #expect(viewModel.variantSet.variant(for: .b)?.name == "Punchy")
        #expect(viewModel.variantSet.document(for: .a)?.text.value == "Variant A title")
        #expect(viewModel.simpleMakerConfiguration.overlayText == "Variant B title")
    }

    @Test func exportIsRefusedWithoutALibrary() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let viewModel = SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: root.appendingPathComponent("simple.json")),
            brandKitStore: BrandKitStore(fileURL: root.appendingPathComponent("brand.json"))
        )
        guard case .failure(let error) = viewModel.exportProjectPackage(UUID()) else {
            Issue.record("export without a library succeeded")
            return
        }
        #expect(error == .projectUnavailable)
    }
}
