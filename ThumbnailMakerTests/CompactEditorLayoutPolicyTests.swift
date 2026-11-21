//
//  CompactEditorLayoutPolicyTests.swift
//  ThumbnailMakerTests
//
//  APP-07 / APP-08: pure sizing, density and spoken-text rules.
//

import CoreGraphics
import Foundation
import Testing
@testable import ThumbnailMaker

struct CompactEditorLayoutPolicyTests {
    private let wide = 16.0 / 9.0

    @Test func canvasFillsPhoneWidthForWideRatio() {
        // iPhone 16 Pro Max portrait content area.
        let size = CompactEditorLayoutPolicy.canvasSize(
            viewport: CGSize(width: 440, height: 720),
            aspectRatio: wide
        )
        #expect(abs(size.width - 400) < 0.5)
        #expect(abs(size.height - 225) < 0.5)
        // At least 1.4x the old 0.6 x 0.35 heuristic.
        #expect(size.height >= 720 * 0.6 * 0.35 * 1.4)
    }

    @Test func canvasIsCappedByHeightForTallRatios() {
        let viewport = CGSize(width: 393, height: 660)
        let size = CompactEditorLayoutPolicy.canvasSize(viewport: viewport, aspectRatio: 9.0 / 16.0)
        #expect(abs(size.height - viewport.height * 0.36) < 0.5)
        #expect(size.width <= viewport.width - 40)
        #expect(abs(size.width / size.height - 9.0 / 16.0) < 0.001)
    }

    @Test func canvasNeverDropsBelowMinimumHeightInShortLandscape() {
        let size = CompactEditorLayoutPolicy.canvasSize(
            viewport: CGSize(width: 667, height: 250),
            aspectRatio: wide
        )
        #expect(size.height >= CompactEditorLayoutPolicy.minimumCanvasHeight - 0.5)
        #expect(size.width <= 667 - 40)
    }

    @Test func canvasNeverExceedsAvailableWidth() {
        let size = CompactEditorLayoutPolicy.canvasSize(
            viewport: CGSize(width: 200, height: 900),
            aspectRatio: 3
        )
        #expect(size.width <= 160 + 0.001)
        #expect(abs(size.width / size.height - 3) < 0.001)
    }

    @Test func canvasToleratesDegenerateInput() {
        for ratio: Double in [0.0, -1.0, Double.nan, Double.infinity] {
            let size = CompactEditorLayoutPolicy.canvasSize(
                viewport: CGSize(width: CGFloat.nan, height: 0),
                aspectRatio: ratio
            )
            #expect(size.width.isFinite && size.width >= 1)
            #expect(size.height.isFinite && size.height >= 1)
        }
    }

    @Test func variantsSectionExpandsOnlyWhenItHoldsWork() {
        #expect(!CompactEditorLayoutPolicy.expandsVariantsSectionByDefault(variantCount: 1, alternateSizeCount: 0))
        #expect(CompactEditorLayoutPolicy.expandsVariantsSectionByDefault(variantCount: 2, alternateSizeCount: 0))
        #expect(CompactEditorLayoutPolicy.expandsVariantsSectionByDefault(variantCount: 1, alternateSizeCount: 1))
        #expect(!CompactEditorLayoutPolicy.expandsArrangePanelByDefault)
    }
}

struct ThumbnailAccessibilityTextTests {
    @Test func exportPresetReadsSelectedOnlyForActivePreset() {
        let options = ThumbnailExportOptions()
        #expect(ThumbnailAccessibilityText.isExportPresetSelected(.youTubeThumbnail, options: options))
        #expect(ThumbnailAccessibilityText.exportPresetValue(preset: .youTubeThumbnail, options: options)
            .hasPrefix("Selected, "))
        for preset in ThumbnailExportPreset.all where preset != .youTubeThumbnail {
            #expect(!ThumbnailAccessibilityText.isExportPresetSelected(preset, options: options))
            #expect(ThumbnailAccessibilityText.exportPresetValue(preset: preset, options: options)
                .hasPrefix("Not selected, "))
        }
    }

    @Test func customSizeDeselectsEveryPreset() {
        var options = ThumbnailExportOptions()
        options.usesCustomSize = true
        for preset in ThumbnailExportPreset.all {
            #expect(!ThumbnailAccessibilityText.isExportPresetSelected(preset, options: options))
        }
    }

    @Test func exportPresetValueIncludesSizeSummary() {
        var options = ThumbnailExportOptions()
        options.applyPreset(.instagramSquare)
        let value = ThumbnailAccessibilityText.exportPresetValue(preset: .instagramSquare, options: options)
        #expect(value == "Selected, \(ThumbnailExportPreset.instagramSquare.summary)")
    }

    @Test func variantsSummaryDescribesCountsAndActiveVariant() {
        #expect(ThumbnailAccessibilityText.variantsSectionSummary(
            variantCount: 1, activeVariantName: "Variant A", alternateSizeCount: 0
        ) == "1 variant")
        #expect(ThumbnailAccessibilityText.variantsSectionSummary(
            variantCount: 3, activeVariantName: "Bold", alternateSizeCount: 2
        ) == "3 variants, editing Bold, 2 extra sizes")
        #expect(ThumbnailAccessibilityText.variantsSectionSummary(
            variantCount: 0, activeVariantName: " ", alternateSizeCount: 1
        ) == "1 variant, 1 extra size")
    }

    @Test func disclosureValueSpeaksState() {
        #expect(ThumbnailAccessibilityText.disclosureValue(isExpanded: true, summary: nil) == "Expanded")
        #expect(ThumbnailAccessibilityText.disclosureValue(isExpanded: false, summary: "1 variant")
            == "Collapsed, 1 variant")
    }
}

@MainActor
struct VariantChipAccessibilityLabelTests {
    private func variant(_ slot: ThumbnailVariantSlot, name: String) -> ThumbnailVariant {
        let now = Date(timeIntervalSince1970: 0)
        return ThumbnailVariant(
            slot: slot,
            name: name,
            createdAt: now,
            updatedAt: now,
            document: SimpleMakerConfigurationModel().document
        )
    }

    @Test func unrenamedVariantIsNotSpokenTwice() {
        #expect(ThumbnailVariantBarView.chipAccessibilityLabel(for: variant(.b, name: "Variant B")) == "Variant B")
    }

    @Test func renamedVariantKeepsItsLetter() {
        #expect(ThumbnailVariantBarView.chipAccessibilityLabel(for: variant(.c, name: "Bold red"))
            == "Bold red, variant C")
    }
}
