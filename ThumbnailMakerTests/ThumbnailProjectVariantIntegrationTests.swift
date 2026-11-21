//
//  ThumbnailProjectVariantIntegrationTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-01 x FEATURE-02: every project owns its own variant set.
//

import Foundation
import Testing
@testable import ThumbnailMaker

@MainActor
struct ThumbnailProjectVariantIntegrationTests {
    @Test func variantsStayWithTheirProjectAcrossSwitches() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)
        let viewModel = SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: root.appendingPathComponent("Drafts/simple.json")),
            brandKitStore: BrandKitStore(fileURL: root.appendingPathComponent("brand.json")),
            projectLibrary: library
        )
        let firstID = try #require(viewModel.activeProjectID)

        viewModel.simpleMakerConfiguration.overlayText = "variant A"
        let duplicated = viewModel.duplicateActiveVariant()
        #expect(duplicated != nil)
        viewModel.simpleMakerConfiguration.overlayText = "variant B"
        viewModel.saveDraftNow()
        #expect(viewModel.variantSet.variants.count == 2)

        let created = viewModel.createNewProject(named: "Second")
        #expect(created)
        #expect(viewModel.activeProjectID != firstID)
        #expect(viewModel.variantSet.variants.count == 1)

        let switched = viewModel.switchToProject(firstID)
        #expect(switched)
        #expect(viewModel.variantSet.variants.count == 2)
        #expect(viewModel.simpleMakerConfiguration.overlayText == "variant B")
    }

    @Test func premiumProjectsKeepSeparateVariantSets() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)
        let viewModel = PremiumMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: root.appendingPathComponent("Drafts/premium.json")),
            brandKitStore: BrandKitStore(fileURL: root.appendingPathComponent("brand.json")),
            projectLibrary: library
        )
        let firstID = try #require(viewModel.activeProjectID)

        _ = viewModel.duplicateActiveVariant()
        viewModel.saveDraftNow()
        #expect(viewModel.variantSet.variants.count == 2)

        #expect(viewModel.createNewProject(named: "Other"))
        #expect(viewModel.variantSet.variants.count == 1)

        #expect(viewModel.switchToProject(firstID))
        #expect(viewModel.variantSet.variants.count == 2)
    }
}
