//
//  ThumbnailVariantSetTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-02: pure model tests for A/B/C variant sets and comparison.
//

import Foundation
import Testing
@testable import ThumbnailMaker

@MainActor
struct ThumbnailVariantSetTests {
    private func document(_ text: String, ratio: AspectRatio = .ratio16_9) -> ThumbnailDocument {
        var configuration = SimpleMakerConfigurationModel()
        configuration.overlayText = text
        configuration.selectedRatio = ratio
        return ThumbnailDocument(configuration: configuration)
    }

    private func threeVariantSet() -> ThumbnailVariantSet {
        var set = ThumbnailVariantSet(seedDocument: document("Seed"), editorMode: .simple)
        set.duplicateVariant(from: .a)
        set.duplicateVariant(from: .b)
        return set
    }

    @Test func seedProducesSingleVariantInSlotA() {
        let set = ThumbnailVariantSet(seedDocument: document("Hello"), editorMode: .simple)
        #expect(set.slots == [.a])
        #expect(set.variants.first?.name == "Variant A")
        #expect(set.activeSlot == .a)
        #expect(set.preferredSlot == nil)
        #expect(set.activeDocument.text.value == "Hello")
    }

    @Test func duplicateFillsLowestFreeSlotAndActivatesIt() {
        var set = ThumbnailVariantSet(seedDocument: document("Seed"), editorMode: .simple)
        let result1 = set.duplicateVariant(from: .a)
        #expect(result1 == .b)
        #expect(set.activeSlot == .b)
        let result2 = set.duplicateVariant(from: .b)
        #expect(result2 == .c)
        #expect(set.activeSlot == .c)
        #expect(set.canAddVariant == false)
        let result3 = set.duplicateVariant(from: .a)
        #expect(result3 == nil)
        #expect(set.slots == [.a, .b, .c])
        #expect(set.variant(for: .c)?.name == "Variant C")
    }

    @Test func editingOneVariantLeavesTheOthersByteIdentical() throws {
        var set = threeVariantSet()
        let snapshotA = try #require(set.document(for: .a))
        let snapshotC = try #require(set.document(for: .c))

        var edited = try #require(set.document(for: .b))
        edited.text.value = "Only B"
        edited.canvas.backgroundColor = ThumbnailDocumentColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        edited.export.presetID = "custom-b"
        _ = edited.layers.addShapeLayer(id: "b-shape")
        set.updateDocument(edited, for: .b)
        #expect(set.document(for: .a) == snapshotA)
        #expect(set.document(for: .c) == snapshotC)
        #expect(set.document(for: .b)?.text.value == "Only B")

        var withImage = try #require(set.document(for: .b))
        _ = withImage.layers.addImageLayer(imageData: Data([1, 2, 3]), id: "b-image")
        withImage.layers.deleteContentLayer(id: "b-shape")
        set.updateDocument(withImage, for: .b)
        #expect(set.document(for: .a) == snapshotA)
        #expect(set.document(for: .c) == snapshotC)
    }

    @Test func removeKeepsRemainingSlotLetters() {
        var set = threeVariantSet()
        set.setPreferred(.b)
        set.activate(.b)
        let result4 = set.removeVariant(.b)
        #expect(result4)
        #expect(set.slots == [.a, .c])
        #expect(set.variants.map(\.name) == ["Variant A", "Variant C"])
        #expect(set.activeSlot == .a)
        #expect(set.preferredSlot == nil)
        #expect(set.nextFreeSlot == .b)

        let result5 = set.removeVariant(.a)
        #expect(result5)
        #expect(set.slots == [.c])
        let result6 = set.removeVariant(.c)
        #expect(result6 == false)
        #expect(set.slots == [.c])
    }

    @Test func preferredIsOnlyEverAnExplicitChoice() {
        var set = ThumbnailVariantSet(seedDocument: document("Seed"), editorMode: .simple)
        #expect(set.preferredSlot == nil)
        set.duplicateVariant(from: .a)
        #expect(set.preferredSlot == nil)
        set.setPreferred(.c)
        #expect(set.preferredSlot == nil)
        set.setPreferred(.b)
        #expect(set.preferredSlot == .b)
        set.clearPreferred()
        #expect(set.preferredSlot == nil)
    }

    @Test func renameTrimsClampsAndFallsBack() {
        var set = ThumbnailVariantSet(seedDocument: document("Seed"), editorMode: .simple)
        set.rename(slot: .a, to: "   Bold face  ")
        #expect(set.variant(for: .a)?.name == "Bold face")
        set.rename(slot: .a, to: "    ")
        #expect(set.variant(for: .a)?.name == "Variant A")
        set.rename(slot: .a, to: String(repeating: "x", count: 80))
        #expect(set.variant(for: .a)?.name.count == ThumbnailVariantSet.maxNameLength)
    }

    @Test func normalizedRepairsCorruptSets() {
        let now = Date()
        func variant(_ slot: ThumbnailVariantSlot, _ text: String) -> ThumbnailVariant {
            ThumbnailVariant(slot: slot, name: "", createdAt: now, updatedAt: now, document: document(text))
        }

        let duplicated = ThumbnailVariantSet(
            updatedAt: now, editorMode: .simple, projectName: "", activeSlot: .c, preferredSlot: .c,
            variants: [variant(.b, "first b"), variant(.a, "a"), variant(.b, "second b")]
        ).normalized()
        #expect(duplicated.slots == [.a, .b])
        #expect(duplicated.document(for: .b)?.text.value == "first b")
        #expect(duplicated.activeSlot == .a)
        #expect(duplicated.preferredSlot == nil)
        #expect(duplicated.variants.map(\.name) == ["Variant A", "Variant B"])

        let empty = ThumbnailVariantSet(
            updatedAt: now, editorMode: .premium, projectName: "", activeSlot: .b, preferredSlot: nil, variants: []
        ).normalized()
        #expect(empty.slots == [.a])
        #expect(empty.activeSlot == .a)
    }

    @Test func codableRoundTripAndForwardCompat() throws {
        var set = threeVariantSet()
        set.setPreferred(.a)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ThumbnailVariantSet.self, from: encoder.encode(set))
        #expect(decoded == set)

        // A minimal object with only `variants` still decodes with defaults.
        let variantsJSON = try encoder.encode(Array(set.variants.suffix(2)))
        let variantsArray = try #require(String(data: variantsJSON, encoding: .utf8))
        let minimal = try #require("{\"variants\": \(variantsArray)}".data(using: .utf8))
        let restored = try decoder.decode(ThumbnailVariantSet.self, from: minimal)
        #expect(restored.slots == [.b, .c])
        #expect(restored.activeSlot == .b)
        #expect(restored.preferredSlot == nil)
        #expect(restored.projectName == "")
        #expect(restored.editorMode == .simple)
        #expect(restored.version == ThumbnailVariantSet.currentVersion)
    }

    @Test func duplicatePreservesLayerIdentifiers() throws {
        var seed = document("Seed")
        _ = seed.layers.addShapeLayer(id: "shape-1")
        var set = ThumbnailVariantSet(seedDocument: seed, editorMode: .simple)
        set.duplicateVariant(from: .a)
        let source = try #require(set.document(for: .a))
        let copy = try #require(set.document(for: .b))
        #expect(source.layers.map(\.id) == copy.layers.map(\.id))
        #expect(copy.layers.contains { $0.id == "shape-1" })
    }

    @Test func updateDocumentIgnoresTimestampOnlyChanges() throws {
        var set = ThumbnailVariantSet(seedDocument: document("Seed"), editorMode: .simple, now: Date(timeIntervalSince1970: 10))
        var sameContent = set.activeDocument
        sameContent.updatedAt = Date(timeIntervalSince1970: 999)
        set.updateDocument(sameContent, for: .a, now: Date(timeIntervalSince1970: 50))
        #expect(set.updatedAt == Date(timeIntervalSince1970: 10))
    }

    // MARK: Comparison

    @Test(arguments: [ThumbnailSmallPreviewSize.search, ThumbnailSmallPreviewSize.mobile], [2, 3])
    func everyPaneRendersAtTheSameSize(previewSize: ThumbnailSmallPreviewSize, count: Int) throws {
        var set = ThumbnailVariantSet(seedDocument: document("Seed"), editorMode: .simple)
        for _ in 1..<count {
            set.duplicateVariant(from: .a)
        }
        let comparison = try #require(ThumbnailVariantComparison.make(set: set, previewSize: previewSize))
        #expect(comparison.panes.count == count)
        #expect(comparison.renderSize == previewSize.size(for: comparison.aspectRatio))
        #expect(comparison.panes.map(\.slot) == Array(ThumbnailVariantSlot.allCases.prefix(count)))
    }

    @Test func mismatchedAspectRatiosAreReportedNotSilentlyDistorted() throws {
        var set = ThumbnailVariantSet(seedDocument: document("A", ratio: .ratio16_9), editorMode: .simple)
        set.duplicateVariant(from: .a)
        set.updateDocument(document("B", ratio: .ratio9_16), for: .b)
        set.activate(.a)
        let comparison = try #require(ThumbnailVariantComparison.make(set: set, previewSize: .search))
        #expect(comparison.aspectRatio == .ratio16_9)
        #expect(comparison.mismatchedSlots == [.b])
        #expect(comparison.renderSize == ThumbnailSmallPreviewSize.search.size(for: .ratio16_9))
        let paneB = try #require(comparison.panes.first { $0.slot == .b })
        #expect(paneB.aspectRatioNote == "B is set to 9:16")
    }

    @Test func makeReturnsNilForASingleVariant() {
        let set = ThumbnailVariantSet(seedDocument: document("Seed"), editorMode: .simple)
        #expect(ThumbnailVariantComparison.make(set: set, previewSize: .search) == nil)
    }
}
