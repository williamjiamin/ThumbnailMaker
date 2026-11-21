//
//  ThumbnailFormatViewModelIntentTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-09: size intents on both editors are single undo steps, autosave,
//  stay per variant / per project, export through the existing exporter and
//  never change the original design.
//

import Foundation
import SwiftUI
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ThumbnailFormatViewModelIntentTests {
    // MARK: Helpers

    private func makeSimple(text: String = "Launch day") -> (SimpleMakerViewModel, ThumbnailDraftStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json"))
        let viewModel = SimpleMakerViewModel(
            draftStore: store,
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        viewModel.simpleMakerConfiguration.selectedImage = ProjectTestSupport.makeImage(size: CGSize(width: 64, height: 36))
        viewModel.simpleMakerConfiguration.overlayText = text
        viewModel.commitEditorStateNow()
        return (viewModel, store, directory)
    }

    private func makePremium() -> (PremiumMakerViewModel, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let viewModel = PremiumMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        viewModel.premiumMakerConfiguration.selectedImage = ProjectTestSupport.makeImage(size: CGSize(width: 64, height: 36))
        viewModel.premiumMakerConfiguration.overlayText = "Premium title"
        viewModel.premiumMakerConfiguration.circularProfile = CircularProfileConfig(
            image: ProjectTestSupport.makeImage(size: CGSize(width: 20, height: 20), color: .systemPink),
            size: 0.2
        )
        viewModel.commitEditorStateNow()
        return (viewModel, directory)
    }

    /// The original design as rendered, ignoring sizes and timestamps.
    private func originalSnapshot<Editor: ThumbnailFormatEditing>(_ editor: Editor) -> ThumbnailDocument {
        ThumbnailDocumentHistory.snapshot(editor.formatEditorConfiguration.imagelessDocument.removingFormats())
    }

    private func undoDepth(_ viewModel: SimpleMakerViewModel) -> Int {
        var depth = 0
        while viewModel.canUndo {
            viewModel.undo()
            depth += 1
        }
        for _ in 0..<depth { viewModel.redo() }
        return depth
    }

    // MARK: Simple editor

    @Test func createIsOneUndoStepAndAutosaves() throws {
        let (viewModel, store, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }
        let before = undoDepth(viewModel)
        let original = originalSnapshot(viewModel)

        let id = try #require(viewModel.createAlternateFormat(.square))
        #expect(id == "square")
        #expect(viewModel.alternateFormats.map(\.kind) == [.square])
        #expect(undoDepth(viewModel) == before + 1)
        #expect(originalSnapshot(viewModel) == original)
        #expect(viewModel.simpleMakerConfiguration.selectedRatio == .ratio16_9)
        if case .saved = viewModel.draftSaveState {} else {
            Issue.record("Creating a size must autosave, got \(viewModel.draftSaveState)")
        }
        #expect(try #require(try store.load()).formatSet?.format(id: "square") != nil)

        viewModel.undo()
        #expect(viewModel.alternateFormats.isEmpty)
        #expect(viewModel.simpleMakerConfiguration.overlayText == "Launch day", "Undo removes only the size.")
        viewModel.redo()
        #expect(viewModel.alternateFormats.map(\.kind) == [.square])
    }

    @Test func createRejectsDuplicatesTheOwnRatioAndEmptyDesigns() {
        let (viewModel, _, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(viewModel.availableFormatKinds == [.square, .vertical])
        #expect(viewModel.createAlternateFormat(.landscape) == nil)
        #expect(viewModel.createAlternateFormat(.vertical) == "vertical")
        #expect(viewModel.createAlternateFormat(.vertical) == nil)

        let emptyDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: emptyDirectory) }
        let empty = SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: emptyDirectory.appendingPathComponent("simple.json")),
            brandKitStore: BrandKitStore(fileURL: emptyDirectory.appendingPathComponent("brand-kit.json"))
        )
        #expect(!empty.canCreateAlternateFormat)
        #expect(empty.createAlternateFormat(.square) == nil)
        #expect(!empty.canUndo)
    }

    @Test func committingAnEditIsOneUndoStepAndLeavesTheOriginalAlone() throws {
        let (viewModel, _, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = originalSnapshot(viewModel)
        viewModel.createAlternateFormat(.vertical)
        let depth = undoDepth(viewModel)

        var working = try #require(viewModel.resolvedFormatConfiguration("vertical"))
        #expect(working.selectedRatio == .ratio9_16)
        #expect(working.selectedImage === viewModel.simpleMakerConfiguration.selectedImage, "Resolving reuses the decoded image.")
        working.textTransform = ThumbnailOverlayTransform(x: 0.3, y: 0.25)
        working.imageRecipe = ThumbnailImageFrameRecipe(fit: .fill, focusX: 0.2, focusY: 0.5, zoom: 1.4)
        working.overlayText = "Typed while linked"
        #expect(viewModel.commitAlternateFormatEdit("vertical", edited: working))

        #expect(undoDepth(viewModel) == depth + 1)
        #expect(originalSnapshot(viewModel) == original)
        let resolved = try #require(viewModel.resolvedFormatConfiguration("vertical"))
        #expect(resolved.textTransform == ThumbnailOverlayTransform(x: 0.3, y: 0.25))
        #expect(resolved.imageRecipe == working.imageRecipe)
        #expect(resolved.overlayText == "Launch day", "Linked text always follows the original.")
        #expect(viewModel.simpleMakerConfiguration.textTransform == .centered)
        #expect(viewModel.simpleMakerConfiguration.imageRecipe == .identity)

        #expect(!viewModel.commitAlternateFormatEdit("vertical", edited: working), "An unchanged edit is not a step.")

        viewModel.undo()
        #expect(viewModel.alternateFormats.map(\.kind) == [.vertical], "Undo reverts only the edit.")
        #expect(viewModel.resolvedFormatConfiguration("vertical")?.textTransform != ThumbnailOverlayTransform(x: 0.3, y: 0.25))
    }

    @Test func unlinkAndRelinkAreReversibleSteps() throws {
        let (viewModel, _, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }
        viewModel.createAlternateFormat(.square)
        let original = originalSnapshot(viewModel)

        #expect(viewModel.unlinkFormatText("square", layerID: ThumbnailDocumentLayer.textID))
        #expect(viewModel.alternateFormats.first?.detachedText[ThumbnailDocumentLayer.textID] == "Launch day")

        viewModel.simpleMakerConfiguration.overlayText = "Original moved on"
        viewModel.commitEditorStateNow()
        #expect(viewModel.resolvedFormatConfiguration("square")?.overlayText == "Launch day")

        #expect(viewModel.relinkFormatText("square", layerID: ThumbnailDocumentLayer.textID))
        #expect(viewModel.resolvedFormatConfiguration("square")?.overlayText == "Original moved on")

        viewModel.undo()
        #expect(viewModel.resolvedFormatConfiguration("square")?.overlayText == "Launch day")
        viewModel.undo()
        viewModel.undo()
        #expect(viewModel.alternateFormats.first?.detachedText.isEmpty == true)
        #expect(originalSnapshot(viewModel) == original)
        #expect(!viewModel.unlinkFormatText("square", layerID: "not-a-layer"))
    }

    @Test func reproposeResetHideAndRemoveKeepTheOriginal() throws {
        let (viewModel, _, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }
        let shapeID = viewModel.simpleMakerConfiguration.layers.addShapeLayer()
        viewModel.commitEditorStateNow()
        viewModel.createAlternateFormat(.vertical)
        let original = originalSnapshot(viewModel)
        let proposed = try #require(viewModel.alternateFormats.first?.layout[shapeID])

        var working = try #require(viewModel.resolvedFormatConfiguration("vertical"))
        working.layers.updateShapeContent(id: shapeID) { $0.transform = ThumbnailOverlayTransform(x: 0.2, y: 0.2) }
        viewModel.commitAlternateFormatEdit("vertical", edited: working)
        #expect(viewModel.alternateFormats.first?.layout[shapeID] != proposed)

        #expect(viewModel.resetFormatLayer("vertical", layerID: shapeID))
        #expect(viewModel.alternateFormats.first?.layout[shapeID] == proposed)

        #expect(viewModel.setFormatLayerHidden("vertical", layerID: shapeID, hidden: true))
        #expect(viewModel.resolvedFormatConfiguration("vertical")?.layers.record(id: shapeID)?.isVisible == false)
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: shapeID)?.isVisible == true)

        viewModel.unlinkFormatText("vertical", layerID: ThumbnailDocumentLayer.textID)
        #expect(!viewModel.reproposeAlternateFormat("vertical"), "Re-proposing an untouched layout is not a step.")
        var moved = try #require(viewModel.resolvedFormatConfiguration("vertical"))
        moved.textTransform = ThumbnailOverlayTransform(x: 0.2, y: 0.8)
        viewModel.commitAlternateFormatEdit("vertical", edited: moved, detachedTextLayerIDs: [ThumbnailDocumentLayer.textID])
        #expect(viewModel.reproposeAlternateFormat("vertical"))
        let reproposed = try #require(viewModel.alternateFormats.first)
        #expect(reproposed.layout[ThumbnailDocumentLayer.textID]?.transform != ThumbnailOverlayTransform(x: 0.2, y: 0.8))
        #expect(reproposed.hiddenLayerIDs == [shapeID], "Re-proposing keeps per-size choices.")
        #expect(reproposed.detachedText[ThumbnailDocumentLayer.textID] == "Launch day")

        #expect(originalSnapshot(viewModel) == original)
        #expect(viewModel.removeAlternateFormat("vertical"))
        #expect(viewModel.alternateFormats.isEmpty)
        #expect(viewModel.simpleMakerConfiguration.formatSet == nil)
        #expect(!viewModel.removeAlternateFormat("vertical"))
        #expect(originalSnapshot(viewModel) == original)
        viewModel.undo()
        #expect(viewModel.alternateFormats.map(\.kind) == [.vertical])
    }

    @Test func sizesStayWithTheirVariant() throws {
        let (viewModel, _, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }
        viewModel.createAlternateFormat(.square)
        let slotB = try #require(viewModel.duplicateActiveVariant())
        #expect(viewModel.alternateFormats.map(\.kind) == [.square], "A duplicated variant starts with the same sizes.")
        viewModel.createAlternateFormat(.vertical)
        #expect(viewModel.alternateFormats.map(\.kind) == [.square, .vertical])

        viewModel.selectVariant(.a)
        #expect(viewModel.alternateFormats.map(\.kind) == [.square])
        viewModel.selectVariant(slotB)
        #expect(viewModel.alternateFormats.map(\.kind) == [.square, .vertical])
    }

    @Test func sizesArePerProjectAndSavedInTheProjectDocument() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)
        let viewModel = SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: root.appendingPathComponent("Drafts/simple.json")),
            brandKitStore: BrandKitStore(fileURL: root.appendingPathComponent("brand.json")),
            projectLibrary: library
        )
        let first = try #require(viewModel.activeProjectID)
        viewModel.simpleMakerConfiguration.overlayText = "Project one"
        viewModel.commitEditorStateNow()
        #expect(viewModel.createAlternateFormat(.vertical) != nil)
        #expect(try library.document(for: first).formats?.format(id: "vertical") != nil)

        let other = try library.createProject(
            name: "Other",
            editorMode: .simple,
            document: ProjectTestSupport.simpleDocument(text: "Project two")
        )
        #expect(viewModel.switchToProject(other.id))
        #expect(viewModel.alternateFormats.isEmpty)
        #expect(viewModel.switchToProject(first))
        #expect(viewModel.alternateFormats.map(\.kind) == [.vertical])
    }

    @Test func exportRendersTheSizeThroughTheExistingExporter() throws {
        let (viewModel, _, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }
        viewModel.createAlternateFormat(.square)
        #expect(viewModel.formatExportBaseName("square") == "\(viewModel.variantExportBaseName)-square")

        let original = originalSnapshot(viewModel)
        #expect(viewModel.prepareAlternateFormatExport("square") { configuration, size in
            SimpleMakerConfigurationModel.formatCanvas(
                .constant(configuration),
                size: size,
                isInteractive: false,
                safeZone: nil,
                selection: .constant(.textOverlay)
            )
        })
        let export = try #require(viewModel.fileExport)
        #expect(viewModel.isFileExporterPresented)
        #expect(export.fileName.contains("-square"))
        #expect(export.options.outputSize == ThumbnailExportPreset.instagramSquare.size)
        let image = try #require(UIImage(data: export.data))
        #expect(image.size.width == image.size.height)
        #expect(originalSnapshot(viewModel) == original)
        #expect(viewModel.simpleMakerConfiguration.exportOptions.preset == .youTubeThumbnail)

        viewModel.isFileExporterPresented = false
        #expect(!viewModel.prepareAlternateFormatExport("vertical") { _, _ in Color.clear })
        #expect(viewModel.showingSaveAlert)
        #expect(viewModel.saveError != nil)
    }

    @Test func chipPreviewsCarryClipFlags() throws {
        let (viewModel, _, directory) = makeSimple(text: "A deliberately long title for every single size")
        defer { try? FileManager.default.removeItem(at: directory) }
        viewModel.createAlternateFormat(.vertical)
        let previews = viewModel.alternateFormatPreviews()
        let preview = try #require(previews.first)
        #expect(preview.configuration.selectedRatio == .ratio9_16)
        #expect(!preview.flags.isEmpty)
        #expect(preview.flags == viewModel.formatClipFlags("vertical"))
    }

    // MARK: Premium editor

    @Test func premiumCreateUndoAndEditMirrorSimple() throws {
        let (viewModel, directory) = makePremium()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = originalSnapshot(viewModel)

        #expect(viewModel.createAlternateFormat(.vertical) == "vertical")
        let proposedProfile = try #require(viewModel.alternateFormats.first?.layout[ThumbnailDocumentLayer.profileID]?.size)
        #expect(proposedProfile > 0.2, "The width-relative profile grows on the narrow canvas.")

        var working = try #require(viewModel.resolvedFormatConfiguration("vertical"))
        #expect(working.circularProfile?.image != nil)
        working.profileTransform = ThumbnailOverlayTransform(x: 0.7, y: 0.2)
        #expect(viewModel.commitAlternateFormatEdit("vertical", edited: working))
        #expect(viewModel.resolvedFormatConfiguration("vertical")?.profileTransform == ThumbnailOverlayTransform(x: 0.7, y: 0.2))
        #expect(viewModel.premiumMakerConfiguration.profileTransform == .profileDefault)
        #expect(originalSnapshot(viewModel) == original)

        viewModel.undo()
        #expect(viewModel.alternateFormats.count == 1)
        viewModel.undo()
        #expect(viewModel.alternateFormats.isEmpty)
        #expect(viewModel.premiumMakerConfiguration.overlayText == "Premium title")
    }
}
