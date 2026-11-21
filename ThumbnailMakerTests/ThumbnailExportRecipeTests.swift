//
//  ThumbnailExportRecipeTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-10: recipe model, back-compat decoding and built-ins.
//

import Foundation
import Testing
@testable import ThumbnailMaker

@MainActor
struct ThumbnailExportRecipeTests {
    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @Test func roundTripsEveryField() throws {
        let recipe = ThumbnailExportRecipe(
            name: "Mine",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            variantSelection: .only([.c, .a]),
            sizes: [ThumbnailExportRecipeSize(presetID: "x", width: 1280, height: 720)],
            format: .webP,
            compressionQuality: 0.77,
            fileSizeBudget: ThumbnailExportFileSizeBudget(maxBytes: 123_456, qualityFloor: 0.5),
            overwritePolicy: .skip,
            namingIncludesSizeToken: false
        )
        let data = try encoder().encode(recipe)
        let decoded = try decoder().decode(ThumbnailExportRecipe.self, from: data)
        #expect(decoded == recipe)
        #expect(decoded.variantSelection.slots == [.a, .c])
    }

    @Test func minimalJSONDecodesWithDefaults() throws {
        let id = UUID()
        let json = #"{"id":"\#(id.uuidString)","name":"Bare"}"#
        let recipe = try decoder().decode(ThumbnailExportRecipe.self, from: Data(json.utf8))
        #expect(recipe.id == id)
        #expect(recipe.name == "Bare")
        #expect(recipe.version == ThumbnailExportRecipe.currentVersion)
        #expect(recipe.variantSelection == .all)
        #expect(recipe.sizes == [ThumbnailExportRecipeSize(preset: .youTubeThumbnail)])
        #expect(recipe.format == .jpeg)
        #expect(recipe.fileSizeBudget == nil)
        #expect(recipe.overwritePolicy == .keepBoth)
        #expect(recipe.namingIncludesSizeToken)
        #expect(!recipe.isReadOnly)
    }

    @Test func futureVersionAndUnknownKeysLoadReadOnly() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","name":"Future","version":9,"somethingNew":{"a":1},
         "overwritePolicy":"askEveryTime","formatRawValue":"avif",
         "variantSelection":{"mode":"random"}}
        """
        let recipe = try decoder().decode(ThumbnailExportRecipe.self, from: Data(json.utf8))
        #expect(recipe.isFromNewerVersion)
        #expect(recipe.isReadOnly)
        #expect(recipe.overwritePolicy == .keepBoth)
        #expect(recipe.variantSelection.mode == .all)
        // Unknown format is kept verbatim and reported, never swapped silently.
        #expect(recipe.format == nil)
        #expect(recipe.formatRawValue == "avif")
    }

    @Test func youTubeABCBuiltIn() {
        let recipe = ThumbnailExportRecipe.youTubeABC
        #expect(recipe.sizes.count == 3)
        for size in recipe.sizes {
            #expect(ThumbnailExportQueuePlan.aspectMatches(canvas: .ratio16_9, size: size))
        }
        #expect(recipe.format == .jpeg)
        #expect(recipe.fileSizeBudget?.maxBytes == 2_000_000)
        #expect(recipe.fileSizeBudget?.qualityFloor == 0.6)
        #expect(recipe.isBuiltIn)
        #expect(recipe.isReadOnly)
        // Same number the single-export validator warns about.
        #expect(ThumbnailExportPreset.youTubeThumbnail.uploadLimits.map(\.byteLimit).contains(2_000_000))
    }

    @Test func qualityFloorNeverExceedsRequestedQuality() {
        let budget = ThumbnailExportFileSizeBudget(maxBytes: 1_000, qualityFloor: 0.9)
        #expect(budget.effectiveFloor(requestedQuality: 0.7) == 0.7)
        let low = ThumbnailExportFileSizeBudget(maxBytes: 1_000, qualityFloor: 0.1)
        #expect(low.effectiveFloor(requestedQuality: 0.9) == ThumbnailExportFileSizeBudget.minimumQualityFloor)
    }

    @Test func qualityIsClamped() {
        let high = ThumbnailExportRecipe(name: "x", sizes: [], compressionQuality: 3)
        let low = ThumbnailExportRecipe(name: "x", sizes: [], compressionQuality: 0.01)
        #expect(high.compressionQuality == 1.0)
        #expect(low.compressionQuality == 0.4)
    }

    @Test func currentOptionsBecomeAOneSizeRecipe() {
        var options = ThumbnailExportOptions()
        options.applyPreset(.instagramSquare)
        options.format = .png
        let recipe = ThumbnailExportRecipe.fromCurrentOptions(options)
        #expect(recipe.sizes == [ThumbnailExportRecipeSize(preset: .instagramSquare)])
        #expect(recipe.format == .png)
        #expect(recipe.isBuiltIn)
    }

    @Test func preferredOnlyWithoutPreferredSelectsNothing() {
        var set = ExportQueueTestSupport.threeVariantSet()
        set.clearPreferred()
        #expect(ThumbnailExportVariantSelection.preferredOnly.selectedSlots(in: set).isEmpty)
        #expect(ThumbnailExportVariantSelection.only([.c, .b]).selectedSlots(in: set) == [.b, .c])
    }
}
