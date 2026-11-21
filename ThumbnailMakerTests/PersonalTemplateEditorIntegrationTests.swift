//
//  PersonalTemplateEditorIntegrationTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-05: personal templates through the real editors and the shared
//  library model.
//

import Foundation
import SwiftUI
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct PersonalTemplateEditorIntegrationTests {
    typealias F = PersonalTemplateFixtures

    private static func makeImage(color: UIColor, size: CGSize = CGSize(width: 32, height: 18)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private static func contentIDs(_ layers: [ThumbnailDocumentLayer]) -> [String] {
        layers.filter { $0.content != nil }.map(\.id)
    }

    @Test func applyingAPersonalTemplateIsExactlyOneUndoActionInSimpleEditor() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json"))
        )
        viewModel.simpleMakerConfiguration.selectedImage = Self.makeImage(color: .blue)
        viewModel.simpleMakerConfiguration.overlayText = "Before"
        let before = ThumbnailDocumentHistory.snapshot(viewModel.simpleMakerConfiguration.document)

        let template = F.personal(name: "Mine")
        let warnings = viewModel.applyTemplate(template)

        #expect(warnings.isEmpty)
        #expect(viewModel.canUndo)
        #expect(viewModel.simpleMakerConfiguration.overlayText == "Before")
        #expect(viewModel.simpleMakerConfiguration.selectedImage?.size == CGSize(width: 32, height: 18))
        let applied = ThumbnailDocumentHistory.snapshot(viewModel.simpleMakerConfiguration.document)
        #expect(applied != before)
        // The template's shape layer arrives with a fresh id.
        let ids = Self.contentIDs(viewModel.simpleMakerConfiguration.layers)
        #expect(ids.count == 1)
        #expect(!ids.contains("tpl-0"))

        viewModel.undo()
        #expect(ThumbnailDocumentHistory.snapshot(viewModel.simpleMakerConfiguration.document) == before)

        viewModel.redo()
        #expect(ThumbnailDocumentHistory.snapshot(viewModel.simpleMakerConfiguration.document) == applied)
    }

    @Test func applyingAPersonalTemplateTwiceGivesDistinctLayerIDsInPremiumEditor() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = PremiumMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium.json"))
        )
        viewModel.premiumMakerConfiguration.selectedImage = Self.makeImage(color: .red)
        viewModel.premiumMakerConfiguration.overlayText = "Premium"

        let template = F.personal(name: "Mine")
        viewModel.applyTemplate(template)
        let firstIDs = Self.contentIDs(viewModel.premiumMakerConfiguration.layers)
        viewModel.applyTemplate(template)
        let secondIDs = Self.contentIDs(viewModel.premiumMakerConfiguration.layers)

        #expect(firstIDs.count == 1)
        #expect(secondIDs.count == 1)
        #expect(Set(firstIDs).isDisjoint(with: secondIDs))
        #expect(viewModel.premiumMakerConfiguration.selectedImage != nil)

        viewModel.undo()
        #expect(Self.contentIDs(viewModel.premiumMakerConfiguration.layers) == firstIDs)
    }

    @Test func placeholderSlotsReportWarningsAndClearTheImage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json"))
        )
        viewModel.simpleMakerConfiguration.selectedImage = Self.makeImage(color: .green)

        var template = F.personal(name: "Empty BG")
        template.slots.backgroundImage = .placeholder
        let warnings = viewModel.applyTemplate(template)

        #expect(warnings.contains(.missingBackgroundImage))
        #expect(viewModel.simpleMakerConfiguration.selectedImage == nil)

        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.selectedImage != nil)
    }

    @Test func styleOnlyApplicationLeavesImagesAndLayersIntactInTheEditor() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json"))
        )
        viewModel.simpleMakerConfiguration.selectedImage = Self.makeImage(color: .orange)
        viewModel.simpleMakerConfiguration.overlayText = "Keep me"
        _ = viewModel.simpleMakerConfiguration.layers.addShapeLayer(id: "my-shape")
        let layersBefore = viewModel.simpleMakerConfiguration.layers.filter { $0.content != nil }
        let ratioBefore = viewModel.simpleMakerConfiguration.selectedRatio
        let template = try #require(ThumbnailTemplate.builtIns.first { $0.id == "short-form-hook" })

        viewModel.applyTemplate(template, mode: .styleOnly)

        #expect(viewModel.simpleMakerConfiguration.layers.filter { $0.content != nil } == layersBefore)
        #expect(layersBefore.map(\.id) == ["my-shape"])
        #expect(viewModel.simpleMakerConfiguration.overlayText == "Keep me")
        #expect(viewModel.simpleMakerConfiguration.selectedRatio == ratioBefore)
        #expect(viewModel.simpleMakerConfiguration.selectedImage != nil)
        #expect(viewModel.simpleMakerConfiguration.selectedFont.rawValue == template.document.text.selectedFontRawValue)
        #expect(viewModel.canUndo)
    }

    @Test func captureThenApplyRoundTripsThroughTheStoreAndSurvivesRelaunch() throws {
        let (directory, url) = F.temporaryURL()
        defer { try? FileManager.default.removeItem(at: directory) }

        let logoID = UUID().uuidString
        let source = F.projectDocument(title: "Episode 1", logoID: logoID)
        let model = PersonalTemplateLibraryModel(store: PersonalTemplateStore(fileURL: url))
        let saved = try #require(model.saveTemplate(
            from: source,
            name: "Channel Look",
            category: .podcast,
            isFavorite: true,
            retainedLayerIDs: [logoID]
        ))
        #expect(model.errorMessage == nil)
        #expect(model.favoriteTemplates.map(\.id) == [saved.id])

        // "Relaunch": a fresh model on the same file.
        let relaunched = PersonalTemplateLibraryModel(store: PersonalTemplateStore(fileURL: url))
        let reloaded = try #require(relaunched.activeTemplates.first)
        #expect(reloaded.id == saved.id)
        #expect(reloaded.name == "Channel Look")
        #expect(reloaded.slots.retainedLayerIDs == ["tpl-0"])

        let editorDirectory = directory.appendingPathComponent("editor")
        let viewModel = PremiumMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: editorDirectory.appendingPathComponent("premium.json"))
        )
        viewModel.premiumMakerConfiguration.overlayText = "Episode 2"
        viewModel.applyTemplate(reloaded)

        #expect(viewModel.premiumMakerConfiguration.overlayText == "Episode 2")
        let hasLogo = viewModel.premiumMakerConfiguration.layers.contains { layer in
            if case .image(let content) = layer.content { return content.imageData == F.logoData }
            return false
        }
        #expect(hasLogo)
    }

    @Test func libraryModelManagementIsTransactionalAndPersists() throws {
        let (directory, url) = F.temporaryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = PersonalTemplateLibraryModel(store: PersonalTemplateStore(fileURL: url))

        let saved = try #require(model.saveTemplate(from: F.projectDocument(), name: "Base", category: .vlog))
        #expect(model.rename(id: saved.id, to: "Renamed"))
        let copy = try #require(model.duplicate(id: saved.id))
        #expect(copy.name == "Renamed Copy")
        #expect(model.moveToTrash(id: saved.id))
        #expect(model.trashedTemplates.map(\.id) == [saved.id])

        // A failing mutation leaves the library untouched and explains why.
        let before = model.library
        #expect(!model.rename(id: "missing", to: "X"))
        #expect(model.errorMessage != nil)
        #expect(model.library == before)

        let reloaded = PersonalTemplateLibraryModel(store: PersonalTemplateStore(fileURL: url))
        #expect(reloaded.activeTemplates.map(\.name) == ["Renamed Copy"])
        #expect(reloaded.trashedTemplates.map(\.name) == ["Renamed"])

        #expect(reloaded.restore(id: saved.id))
        #expect(reloaded.activeTemplates.count == 2)
    }

    @Test func oversizedCaptureIsRejectedWithAnExplanation() throws {
        let (directory, url) = F.temporaryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = PersonalTemplateLibraryModel(store: PersonalTemplateStore(fileURL: url))
        var source = F.projectDocument()
        source.imageData = Data(repeating: 1, count: PersonalTemplateStore.maximumTemplateBytes)

        let result = model.saveTemplate(from: source, name: "Huge", category: .youtube, backgroundPolicy: .retained)

        #expect(result == nil)
        #expect(model.errorMessage?.contains("too large") == true)
        #expect(model.activeTemplates.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func corruptLibraryIsQuarantinedAndExplained() throws {
        let (directory, url) = F.temporaryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: url)

        let model = PersonalTemplateLibraryModel(store: PersonalTemplateStore(fileURL: url))

        #expect(model.activeTemplates.isEmpty)
        #expect(model.recoveryNotice != nil)
    }

    @Test func pendingWarningsArePresentedOnlyAfterDismiss() {
        let model = PersonalTemplateLibraryModel(store: nil)
        model.reportApplication([.missingBackgroundImage])
        #expect(model.applicationWarnings.isEmpty)
        model.presentPendingWarnings()
        #expect(model.applicationWarnings == [.missingBackgroundImage])
    }
}
