//
//  ThumbnailVariantExportNamingTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-02: export names sort A, B, C and never claim a winner.
//

import Foundation
import SwiftUI
import Testing
@testable import ThumbnailMaker

@MainActor
struct ThumbnailVariantExportNamingTests {
    private let fallback = ThumbnailExportPreset.youTubeThumbnail.id

    @Test(arguments: [nil, ThumbnailVariantSlot.a, .b, .c])
    func namesSortAsABCForEveryPreferredCombination(preferred: ThumbnailVariantSlot?) {
        let names = ThumbnailVariantSlot.allCases.map { slot in
            ThumbnailVariantExportNaming.baseName(
                projectName: "My Channel Ep 12",
                slot: slot,
                isPreferred: slot == preferred,
                includeSlotToken: true,
                fallback: fallback
            )
        }
        #expect(names == names.sorted())
        #expect(names[0].contains("variant-a"))
        #expect(names[1].contains("variant-b"))
        #expect(names[2].contains("variant-c"))
        #expect(Set(names).count == 3)
    }

    @Test func singleVariantKeepsLegacyName() {
        let name = ThumbnailVariantExportNaming.baseName(
            projectName: "Anything",
            slot: .a,
            isPreferred: true,
            includeSlotToken: false,
            fallback: fallback
        )
        #expect(name == ThumbnailExportPreset.youTubeThumbnail.id)
    }

    @Test func emptyProjectNameUsesThePresetName() {
        let name = ThumbnailVariantExportNaming.baseName(
            projectName: "  ",
            slot: .b,
            isPreferred: false,
            includeSlotToken: true,
            fallback: fallback
        )
        #expect(name == "\(ThumbnailVariantExportNaming.sanitized(fallback))-variant-b")
    }

    @Test func preferredSuffixIsPlainAndNeverClaimsAWinner() {
        let name = ThumbnailVariantExportNaming.baseName(
            projectName: "Launch",
            slot: .b,
            isPreferred: true,
            includeSlotToken: true,
            fallback: fallback
        )
        #expect(name == "launch-variant-b-preferred")
        for banned in ["winner", "best", "top", "ctr", "score", "recommended"] {
            #expect(!name.contains(banned))
        }
    }

    @Test func sanitizationMatchesTheExporter() throws {
        let base = ThumbnailVariantExportNaming.baseName(
            projectName: "  My / Big 🚀 Launch!! ",
            slot: .c,
            isPreferred: false,
            includeSlotToken: true,
            fallback: fallback
        )
        #expect(base == "my-big-launch-variant-c")
        let export = try ThumbnailExporter.preparedFileExport(
            content: Color.red.frame(width: 32, height: 18),
            options: ThumbnailExportOptions(),
            baseFileName: base
        )
        #expect(export.fileName == "\(base).png")
    }

    @Test func exportPlanIsSlotOrderedAndFlagsThreeVariantReadiness() {
        var set = ThumbnailVariantSet(
            seedDocument: ThumbnailDocument(configuration: SimpleMakerConfigurationModel()),
            editorMode: .simple,
            projectName: "Ep 5"
        )
        let single = ThumbnailVariantExportPlan.make(from: set, fallbackBaseName: fallback)
        #expect(single.entries.map(\.baseFileName) == [fallback])

        set.duplicateVariant(from: .a)
        set.setPreferred(.a)
        let two = ThumbnailVariantExportPlan.make(from: set, fallbackBaseName: fallback)
        #expect(two.isReadyForThreeVariantUpload == false)
        #expect(two.entries.map(\.slot) == [.a, .b])
        #expect(two.entries.map(\.baseFileName) == ["ep-5-variant-a-preferred", "ep-5-variant-b"])

        set.duplicateVariant(from: .b)
        let three = ThumbnailVariantExportPlan.make(from: set, fallbackBaseName: fallback)
        #expect(three.isReadyForThreeVariantUpload)
        #expect(three.entries.map(\.slot) == [.a, .b, .c])
        #expect(three.readinessNote.contains("exactly three thumbnails"))
        for banned in ["winner", "best", "ctr", "score", "perform"] {
            #expect(!three.readinessNote.lowercased().contains(banned))
        }
    }
}
