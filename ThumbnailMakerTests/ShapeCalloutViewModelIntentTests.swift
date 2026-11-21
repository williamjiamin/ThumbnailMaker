//
//  ShapeCalloutViewModelIntentTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-12: callout intents are single undo steps on both editors, persist
//  to the draft, and pick up the active brand kit accent.
//

import Foundation
import SwiftUI
import Testing
@testable import ThumbnailMaker

@MainActor
struct ShapeCalloutViewModelIntentTests {
    private let accent = ThumbnailDocumentColor(red: 0.2, green: 0.3, blue: 0.9, alpha: 1)

    private func makeSimple() -> (SimpleMakerViewModel, ThumbnailDraftStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json"))
        let viewModel = SimpleMakerViewModel(
            draftStore: store,
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        return (viewModel, store, directory)
    }

    private func makePremium() -> (PremiumMakerViewModel, ThumbnailDraftStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium.json"))
        let viewModel = PremiumMakerViewModel(
            draftStore: store,
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        return (viewModel, store, directory)
    }

    private func shapeContent(_ layers: [ThumbnailDocumentLayer], _ id: String) -> ThumbnailShapeLayerContent? {
        guard case .shape(let content) = layers.record(id: id)?.content else { return nil }
        return content
    }

    private func undoDepth(_ editor: SimpleMakerViewModel) -> Int {
        var depth = 0
        while editor.canUndo {
            editor.undo()
            depth += 1
        }
        for _ in 0..<depth { editor.redo() }
        return depth
    }

    // MARK: Simple

    @Test func simpleAddCalloutIsOneUndoStepAndPersists() throws {
        let (viewModel, store, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }

        let depthBefore = undoDepth(viewModel)
        let selection = viewModel.addCalloutLayer(.speechCallout)
        guard case .content(let id) = selection else {
            Issue.record("expected a content selection")
            return
        }
        let layer = try #require(viewModel.simpleMakerConfiguration.layers.record(id: id))
        #expect(layer.kind == .shape)
        #expect(layer.name.hasPrefix("Callout"))
        let added = try #require(shapeContent(viewModel.simpleMakerConfiguration.layers, id))
        #expect(added.shapeKind == .callout)
        #expect(viewModel.canUndo)
        #expect(undoDepth(viewModel) == depthBefore + 1)

        let saved = try #require(try store.load())
        #expect(shapeContent(saved.layers, id) == added, "The draft keeps the recipe and label")

        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: id) == nil)
        viewModel.redo()
        #expect(shapeContent(viewModel.simpleMakerConfiguration.layers, id) == added)
    }

    @Test func simpleAddCalloutUsesBrandAccent() throws {
        let (viewModel, _, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }

        viewModel.saveBrandKit(BrandKit(
            id: "kit", name: "Kit",
            palette: [BrandColor(id: "c1", name: "Blue", color: accent)]
        ))
        #expect(viewModel.calloutBrandAccent == accent)
        guard case .content(let id) = viewModel.addCalloutLayer(.arrowRight) else {
            Issue.record("expected a content selection")
            return
        }
        #expect(shapeContent(viewModel.simpleMakerConfiguration.layers, id)?.fillColor == accent)

        guard case .content(let plainID) = viewModel.addCalloutLayer(.arrowRight, useBrandAccent: false) else {
            Issue.record("expected a content selection")
            return
        }
        #expect(shapeContent(viewModel.simpleMakerConfiguration.layers, plainID)?.fillColor == ThumbnailCalloutPreset.red)
    }

    @Test func simpleUpdateShapeLayerIsOneStepAndNoOpRecordsNothing() throws {
        let (viewModel, _, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }

        guard case .content(let id) = viewModel.addCalloutLayer(.pointerLine) else {
            Issue.record("expected a content selection")
            return
        }
        let depth = undoDepth(viewModel)
        #expect(viewModel.updateShapeLayer(id) { $0.editGeometry { $0.endHead = .open } })
        #expect(shapeContent(viewModel.simpleMakerConfiguration.layers, id)?.resolvedGeometry.endHead == .open)
        #expect(undoDepth(viewModel) == depth + 1)

        let changed = viewModel.updateShapeLayer(id) { $0.editGeometry { $0.endHead = .open } }
        #expect(!changed, "Unchanged content is not an edit")
        #expect(undoDepth(viewModel) == depth + 1)
        #expect(!viewModel.updateShapeLayer("missing") { $0.width = 0.5 })

        viewModel.undo()
        #expect(shapeContent(viewModel.simpleMakerConfiguration.layers, id)?.resolvedGeometry.endHead == .triangle)
    }

    @Test func simpleBindingLabelEditIsCommittedAsOneStep() throws {
        let (viewModel, _, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }

        guard case .content(let id) = viewModel.addCalloutLayer(.newBadge) else {
            Issue.record("expected a content selection")
            return
        }
        let depth = undoDepth(viewModel)
        let layersBinding = Binding(
            get: { viewModel.simpleMakerConfiguration.layers },
            set: { viewModel.simpleMakerConfiguration.layers = $0 }
        )
        let binding = try #require(ShapeLayerControlView.binding(layers: layersBinding, selection: .content(id)))
        binding.wrappedValue.label?.text = "L"
        binding.wrappedValue.label?.text = "LO"
        binding.wrappedValue.label?.text = "LOOK"
        viewModel.commitEditorStateNow()
        #expect(shapeContent(viewModel.simpleMakerConfiguration.layers, id)?.label?.text == "LOOK")
        #expect(undoDepth(viewModel) == depth + 1)

        viewModel.undo()
        #expect(shapeContent(viewModel.simpleMakerConfiguration.layers, id)?.label?.text == "NEW")
        #expect(ShapeLayerControlView.binding(layers: layersBinding, selection: .textOverlay) == nil)
    }

    @Test func simpleApplyPresetAndBrandColor() throws {
        let (viewModel, _, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }

        guard case .content(let id) = viewModel.addCalloutLayer(.speechCallout) else {
            Issue.record("expected a content selection")
            return
        }
        #expect(viewModel.applyCalloutPreset(.rectCallout, to: id))
        #expect(shapeContent(viewModel.simpleMakerConfiguration.layers, id)?.resolvedGeometry.tailDirection == .bottom)
        #expect(viewModel.applyBrandColor(accent, to: id))
        let content = try #require(shapeContent(viewModel.simpleMakerConfiguration.layers, id))
        #expect(content.fillColor == accent)
        #expect(content.label?.color == ThumbnailCalloutPreset.white)

        guard case .content(let circleID) = viewModel.addCalloutLayer(.highlightCircle) else {
            Issue.record("expected a content selection")
            return
        }
        #expect(viewModel.applyBrandColor(accent, to: circleID))
        #expect(shapeContent(viewModel.simpleMakerConfiguration.layers, circleID)?.strokeColor == accent)
    }

    @Test func simpleDuplicateKeepsRecipe() throws {
        let (viewModel, _, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }

        let selection = viewModel.addCalloutLayer(.burstBadge)
        let duplicateSelection = viewModel.duplicateLayer(selection)
        let copy = try #require(duplicateSelection)
        guard case .content(let id) = selection, case .content(let copyID) = copy else {
            Issue.record("expected content selections")
            return
        }
        let original = try #require(shapeContent(viewModel.simpleMakerConfiguration.layers, id))
        let duplicated = try #require(shapeContent(viewModel.simpleMakerConfiguration.layers, copyID))
        #expect(duplicated.geometry == original.geometry)
        #expect(duplicated.label == original.label)
    }

    @Test func simpleLegacyAddShapeStillHasNoRecipe() throws {
        let (viewModel, _, directory) = makeSimple()
        defer { try? FileManager.default.removeItem(at: directory) }

        guard case .content(let id) = viewModel.addShapeLayer(.rectangle) else {
            Issue.record("expected a content selection")
            return
        }
        let content = try #require(shapeContent(viewModel.simpleMakerConfiguration.layers, id))
        #expect(content.geometry == nil)
        #expect(content.label == nil)
    }

    // MARK: Premium

    @Test func premiumAddCalloutIsOneUndoStep() throws {
        let (viewModel, store, directory) = makePremium()
        defer { try? FileManager.default.removeItem(at: directory) }

        guard case .content(let id) = viewModel.addCalloutLayer(.doubleArrow) else {
            Issue.record("expected a content selection")
            return
        }
        let added = try #require(shapeContent(viewModel.premiumMakerConfiguration.layers, id))
        #expect(added.shapeKind == .arrow)
        #expect(viewModel.premiumMakerConfiguration.layers.record(id: id)?.name.hasPrefix("Arrow") == true)
        let saved = try #require(try store.loadPremium())
        #expect(shapeContent(saved.layers, id) == added)

        #expect(viewModel.updateShapeLayer(id) { $0.editGeometry { $0.shaftThickness = 0.6 } })
        viewModel.undo()
        #expect(shapeContent(viewModel.premiumMakerConfiguration.layers, id) == added)
        viewModel.undo()
        #expect(viewModel.premiumMakerConfiguration.layers.record(id: id) == nil)
        viewModel.redo()
        #expect(shapeContent(viewModel.premiumMakerConfiguration.layers, id) == added)
    }

    @Test func premiumAddCalloutUsesBrandAccent() throws {
        let (viewModel, _, directory) = makePremium()
        defer { try? FileManager.default.removeItem(at: directory) }

        viewModel.saveBrandKit(BrandKit(
            id: "kit", name: "Kit",
            palette: [BrandColor(id: "c1", name: "Blue", color: accent)]
        ))
        guard case .content(let id) = viewModel.addCalloutLayer(.highlightCircle) else {
            Issue.record("expected a content selection")
            return
        }
        #expect(shapeContent(viewModel.premiumMakerConfiguration.layers, id)?.strokeColor == accent)
    }
}
