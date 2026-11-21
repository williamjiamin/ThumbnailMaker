//
//  ThumbnailExportQueuePlanTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-10: the review plan lists exact names, sizes and conflicts, and
//  never silently changes a size or format.
//

import Foundation
import Testing
@testable import ThumbnailMaker

@MainActor
struct ThumbnailExportQueuePlanTests {
    private typealias Support = ExportQueueTestSupport

    @Test func threeVariantsTimesThreeSizesInSlotThenSizeOrder() {
        let plan = Support.plan()
        #expect(plan.jobs.count == 9)
        #expect(plan.jobs.map(\.id) == [
            "a-3840x2160", "a-1920x1080", "a-1280x720",
            "b-3840x2160", "b-1920x1080", "b-1280x720",
            "c-3840x2160", "c-1920x1080", "c-1280x720"
        ])
        #expect(plan.runnableJobs.count == 9)
        #expect(plan.summary == "9 files · 0 will replace · 0 blocked")
    }

    @Test func exactFileNames() {
        let plan = Support.plan()
        let names = plan.jobs.map(\.targetFileName)
        #expect(names[0] == "my-video-variant-a-3840x2160.jpg")
        #expect(names[4] == "my-video-variant-b-preferred-1920x1080.jpg")
        #expect(names[8] == "my-video-variant-c-1280x720.jpg")
        #expect(Set(names).count == 9)
        #expect(plan.jobs.allSatisfy { $0.format == .jpeg && $0.quality == 0.92 })
        #expect(plan.jobs[0].size == ThumbnailExportSize(width: 3840, height: 2160))
    }

    @Test func projectNameFallsBackToTheLibraryName() {
        let set = Support.threeVariantSet(projectName: "")
        let plan = ThumbnailExportQueuePlan.make(
            set: set,
            recipe: .youTubeABC,
            projectName: "Launch Day",
            fallbackBaseName: "youtube-thumbnail",
            destination: .init(displayName: "F", supportsFileNames: true),
            formatIsAvailable: { _ in true }
        )
        #expect(plan.jobs[0].fileName == "launch-day-variant-a-3840x2160.jpg")
    }

    @Test func singleVariantKeepsFallbackBaseNamePlusSize() {
        let plan = Support.plan(set: Support.singleVariantSet())
        #expect(plan.jobs.map(\.fileName) == [
            "youtube-thumbnail-3840x2160.jpg",
            "youtube-thumbnail-1920x1080.jpg",
            "youtube-thumbnail-1280x720.jpg"
        ])
    }

    @Test func selectionFiltersJobs() {
        var recipe = ThumbnailExportRecipe.youTubeABC
        recipe.variantSelection = .preferredOnly
        #expect(Support.plan(recipe: recipe).jobs.map(\.slot) == [.b, .b, .b])

        recipe.variantSelection = .only([.a, .c])
        #expect(Set(Support.plan(recipe: recipe).jobs.map(\.slot)) == [.a, .c])

        var noPreferred = Support.threeVariantSet()
        noPreferred.clearPreferred()
        recipe.variantSelection = .preferredOnly
        let empty = Support.plan(set: noPreferred, recipe: recipe)
        #expect(empty.jobs.isEmpty)
        #expect(empty.summary.contains("preferred"))
    }

    @Test func aspectMismatchIsBlockedNotCropped() {
        var recipe = ThumbnailExportRecipe.youTubeABC
        recipe.sizes.append(ThumbnailExportRecipeSize(preset: .shortFormCover))
        let plan = Support.plan(recipe: recipe)
        let vertical = plan.jobs.filter { $0.size == ThumbnailExportSize(width: 1080, height: 1920) }
        #expect(vertical.count == 3)
        for job in vertical {
            #expect(job.size == ThumbnailExportSize(width: 1080, height: 1920))
            #expect(job.fileName.hasSuffix("-1080x1920.jpg"))
            guard case .aspectMismatch? = job.blockedReason else {
                Issue.record("expected aspect mismatch, got \(String(describing: job.blockedReason))")
                continue
            }
            #expect(!job.isRunnable)
        }
        #expect(plan.summary == "9 files · 0 will replace · 3 blocked")
    }

    @Test func reelsCoverSizeMatchesReelsCanvas() {
        let set = Support.threeVariantSet(ratio: .ratioReelsCover)
        let recipe = ThumbnailExportRecipe(name: "Reels", sizes: [ThumbnailExportRecipeSize(preset: .instagramReelsCover)])
        let plan = Support.plan(set: set, recipe: recipe)
        #expect(plan.jobs.count == 3)
        #expect(plan.blockedJobs.isEmpty)
    }

    @Test(arguments: [
        (ThumbnailExportOverwritePolicy.keepBoth, ThumbnailExportJobConflict.existsWillRename("my-video-variant-a-3840x2160-2.jpg")),
        (.replace, .existsWillReplace),
        (.skip, .existsWillSkip)
    ])
    func existingFileFollowsPolicy(policy: ThumbnailExportOverwritePolicy, expected: ThumbnailExportJobConflict) {
        var recipe = ThumbnailExportRecipe.youTubeABC
        recipe.overwritePolicy = policy
        let destination = ThumbnailExportDestinationSnapshot(
            displayName: "Folder",
            existingFileNames: ["My-Video-Variant-A-3840x2160.JPG"],
            supportsFileNames: true
        )
        let plan = Support.plan(recipe: recipe, destination: destination)
        #expect(plan.jobs[0].conflict == expected)
        #expect(plan.jobs[1].conflict == .none)
        #expect(plan.conflictCount == 1)
        if policy == .skip {
            #expect(plan.runnableJobs.count == 8)
            #expect(plan.summary == "8 files · 0 will replace · 1 will skip · 0 blocked")
        } else if policy == .replace {
            #expect(plan.summary == "9 files · 1 will replace · 0 blocked")
        } else {
            #expect(plan.jobs[0].targetFileName == "my-video-variant-a-3840x2160-2.jpg")
        }
    }

    @Test func renamedNamesDoNotCollideWithEachOther() {
        let destination = ThumbnailExportDestinationSnapshot(
            displayName: "Folder",
            existingFileNames: ["solo.jpg", "solo-2.jpg"],
            supportsFileNames: true
        )
        var recipe = ThumbnailExportRecipe.youTubeABC
        recipe.namingIncludesSizeToken = false
        let plan = ThumbnailExportQueuePlan.make(
            set: Support.singleVariantSet(),
            recipe: recipe,
            projectName: "",
            fallbackBaseName: "solo",
            destination: destination,
            formatIsAvailable: { _ in true }
        )
        // Without the size token every size wants "solo.jpg": first renames, rest are duplicates.
        #expect(plan.jobs[0].conflict == .existsWillRename("solo-3.jpg"))
        #expect(plan.jobs[1].conflict == .duplicateInQueue)
        #expect(plan.jobs[2].conflict == .duplicateInQueue)
        #expect(plan.runnableJobs.count == 1)
    }

    @Test func duplicateSizesAreFlagged() {
        var recipe = ThumbnailExportRecipe.youTubeABC
        recipe.sizes.append(ThumbnailExportRecipeSize(width: 1280, height: 720))
        let plan = Support.plan(recipe: recipe)
        #expect(plan.jobs.count == 12)
        #expect(Set(plan.jobs.map(\.id)).count == 12)
        #expect(plan.jobs.filter { $0.conflict == .duplicateInQueue }.count == 3)
        #expect(plan.runnableJobs.count == 9)
    }

    @Test func photosHasNoConflicts() {
        let destination = ThumbnailExportDestinationSnapshot(
            displayName: "Photos",
            existingFileNames: ["my-video-variant-a-3840x2160.jpg"],
            supportsFileNames: false
        )
        let plan = Support.plan(destination: destination)
        #expect(plan.jobs.allSatisfy { $0.conflict == .none })
        #expect(!plan.destination.supportsFileNames)
        #expect(plan.summary == "9 files · 0 blocked")
    }

    @Test func unavailableFormatIsBlocked() {
        var recipe = ThumbnailExportRecipe.youTubeABC
        recipe.formatRawValue = ThumbnailExportFormat.webP.rawValue
        let plan = Support.plan(recipe: recipe, formatIsAvailable: { $0 != .webP })
        #expect(plan.blockedJobs.count == 9)
        #expect(plan.jobs.allSatisfy { $0.blockedReason == .formatUnavailable("WebP") && $0.format == .webP })

        recipe.formatRawValue = "avif"
        #expect(Support.plan(recipe: recipe).blockedJobs.count == 9)
    }

    @Test func outOfRangeSizeIsBlocked() {
        let recipe = ThumbnailExportRecipe(name: "Huge", sizes: [ThumbnailExportRecipeSize(width: 7680, height: 4320)])
        let plan = Support.plan(recipe: recipe)
        #expect(plan.jobs.allSatisfy { $0.blockedReason == .sizeOutOfRange })
    }

    @Test func emptyVariantIsBlocked() {
        let set = ThumbnailVariantSet(seedDocument: ThumbnailDocument(), editorMode: .simple)
        let plan = Support.plan(set: set)
        #expect(plan.jobs.allSatisfy { $0.blockedReason == .noContent })
    }

    @Test func uniqueNameIsCaseInsensitive() {
        let name = ThumbnailVariantExportNaming.uniqueName("A.jpg", taken: ["a.jpg", "a-2.jpg"])
        #expect(name == "A-3.jpg")
        #expect(ThumbnailVariantExportNaming.uniqueName("b.png", taken: ["a.png"]) == "b.png")
    }

    @Test func singleExportBaseNameIsUnchanged() {
        // Regression: the single-export rule the queue builds on.
        let plan = ThumbnailVariantExportPlan.make(from: Support.threeVariantSet(), fallbackBaseName: "youtube-thumbnail")
        #expect(plan.entries.map(\.baseFileName) == [
            "my-video-variant-a", "my-video-variant-b-preferred", "my-video-variant-c"
        ])
    }
}
