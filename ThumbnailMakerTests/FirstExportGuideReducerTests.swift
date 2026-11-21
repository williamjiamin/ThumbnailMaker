//
//  FirstExportGuideReducerTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-13: pure step derivation and status machine of the first-export guide.
//

import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct FirstExportGuideReducerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(
        visual: Bool = false,
        title: Bool = false,
        sizeCheck: Bool = false
    ) -> FirstExportGuideSnapshot {
        FirstExportGuideSnapshot(
            hasVisual: visual,
            hasTitle: title,
            hasSizeCheck: sizeCheck,
            readinessScore: "80/100",
            readinessHasWarnings: false,
            hasExportableContent: visual || title
        )
    }

    private func event(_ kind: ThumbnailExportEventKind, _ mode: ThumbnailDocumentEditorMode = .simple) -> ThumbnailExportEvent {
        ThumbnailExportEvent(kind: kind, date: now, editorMode: mode)
    }

    private func active() -> FirstExportGuideProgress {
        FirstExportGuideReducer.reduce(FirstExportGuideProgress(), .start(now))
    }

    @Test func emptySnapshotSatisfiesNothingAndStartsAtAddVisual() {
        let satisfied = FirstExportGuideReducer.satisfiedSteps(.empty, exported: false)
        #expect(satisfied.isEmpty)
        #expect(FirstExportGuideReducer.nextStep(satisfied) == .addVisual)
    }

    @Test func stepsAreSatisfiedInAnyOrder() {
        #expect(FirstExportGuideReducer.satisfiedSteps(snapshot(visual: true), exported: false) == [.addVisual])
        #expect(FirstExportGuideReducer.satisfiedSteps(snapshot(title: true), exported: false) == [.writeTitle])
        let titleAndCheck = FirstExportGuideReducer.satisfiedSteps(snapshot(title: true, sizeCheck: true), exported: false)
        #expect(titleAndCheck == [.writeTitle, .checkReadiness])
        #expect(FirstExportGuideReducer.nextStep(titleAndCheck) == .addVisual)
    }

    @Test func sizeCheckAloneNeverCompletesExportStep() {
        var progress = active()
        progress = FirstExportGuideReducer.reduce(progress, .observe(snapshot(visual: true, title: true, sizeCheck: true)))
        #expect(progress.status == .active)
        #expect(!progress.completedStepSet.contains(.export))
        #expect(progress.currentStep == .export)
    }

    @Test func startingOnExistingWorkJumpsToExportStep() {
        let full = snapshot(visual: true, title: true, sizeCheck: true)
        let progress = FirstExportGuideReducer.reduce(active(), .observe(full))
        #expect(progress.completedSteps == [.addVisual, .writeTitle, .checkReadiness])
        #expect(progress.currentStep == .export)
    }

    @Test func guidedJourneyCompletesAndShowsCompletionOnce() {
        var progress = active()
        #expect(progress.startedAt == now)
        progress = FirstExportGuideReducer.reduce(progress, .observe(snapshot(visual: true)))
        #expect(progress.currentStep == .writeTitle)
        progress = FirstExportGuideReducer.reduce(progress, .observe(snapshot(visual: true, title: true)))
        #expect(progress.currentStep == .checkReadiness)
        progress = FirstExportGuideReducer.reduce(progress, .observe(snapshot(visual: true, title: true, sizeCheck: true)))
        progress = FirstExportGuideReducer.reduce(progress, .exportSucceeded(event(.files)))
        #expect(progress.status == .completed)
        #expect(progress.completedAt == now)
        #expect(progress.firstExportKind == .files)
        #expect(progress.completedSteps == FirstExportGuideStep.allCases)
        #expect(FirstExportGuideReducer.presentation(for: progress) == .completed)
        progress = FirstExportGuideReducer.reduce(progress, .dismissCompletion)
        #expect(FirstExportGuideReducer.presentation(for: progress) == .hidden)
    }

    @Test(arguments: [FirstExportGuideStatus.notStarted, .skipped])
    func directJourneyCompletesSilently(status: FirstExportGuideStatus) {
        let progress = FirstExportGuideReducer.reduce(
            FirstExportGuideProgress(status: status),
            .exportSucceeded(event(.share, .premium))
        )
        #expect(progress.status == .completed)
        #expect(progress.firstExportKind == .share)
        #expect(progress.lastEditorMode == .premium)
        #expect(FirstExportGuideReducer.presentation(for: progress) == .hidden)
    }

    @Test func pausedGuideCompletesWithCelebration() {
        var progress = FirstExportGuideReducer.reduce(active(), .pause(now))
        progress = FirstExportGuideReducer.reduce(progress, .exportSucceeded(event(.photos)))
        #expect(progress.status == .completed)
        #expect(FirstExportGuideReducer.presentation(for: progress) == .completed)
    }

    @Test func pauseResumeSkipAndRestart() {
        var progress = FirstExportGuideReducer.reduce(active(), .observe(snapshot(visual: true)))
        progress = FirstExportGuideReducer.reduce(progress, .pause(now))
        #expect(progress.status == .paused)
        #expect(progress.currentStep == .writeTitle)
        #expect(progress.completedSteps == [.addVisual])
        #expect(FirstExportGuideReducer.presentation(for: progress) == .resumePill)

        // Paused progress does not follow the editor.
        let ignored = FirstExportGuideReducer.reduce(progress, .observe(.empty))
        #expect(ignored == progress)

        progress = FirstExportGuideReducer.reduce(progress, .resume(now))
        #expect(progress.status == .active)
        #expect(progress.currentStep == .writeTitle)

        progress = FirstExportGuideReducer.reduce(progress, .skip(now))
        #expect(progress.status == .skipped)
        #expect(FirstExportGuideReducer.presentation(for: progress) == .hidden)
        progress = FirstExportGuideReducer.reduce(progress, .resume(now))
        #expect(progress.status == .active)

        progress = FirstExportGuideReducer.reduce(progress, .restart)
        #expect(progress == FirstExportGuideProgress())
    }

    @Test func deletingContentReopensStepButCompletionNeverRegresses() {
        var progress = FirstExportGuideReducer.reduce(active(), .observe(snapshot(visual: true, title: true)))
        progress = FirstExportGuideReducer.reduce(progress, .observe(snapshot(title: true)))
        #expect(progress.currentStep == .addVisual)
        #expect(progress.completedSteps == [.writeTitle])

        progress = FirstExportGuideReducer.reduce(progress, .exportSucceeded(event(.photos)))
        let afterDelete = FirstExportGuideReducer.reduce(progress, .observe(.empty))
        #expect(afterDelete.status == .completed)
        #expect(afterDelete.completedStepSet.contains(.export))
        // A second export does not overwrite the first-export record.
        let second = FirstExportGuideReducer.reduce(afterDelete, .exportSucceeded(event(.share)))
        #expect(second.firstExportKind == .photos)
        #expect(FirstExportGuideReducer.reduce(second, .start(now)).status == .completed)
    }

    @Test func launchOfferOnlyForTrueFirstRun() {
        #expect(FirstExportGuideReducer.shouldOfferOnLaunch(FirstExportGuideProgress(), snapshot: .empty))
        #expect(!FirstExportGuideReducer.shouldOfferOnLaunch(FirstExportGuideProgress(), snapshot: snapshot(title: true)))
        #expect(!FirstExportGuideReducer.shouldOfferOnLaunch(FirstExportGuideProgress(status: .skipped), snapshot: .empty))
        #expect(!FirstExportGuideReducer.shouldOfferOnLaunch(FirstExportGuideProgress(status: .completed), snapshot: .empty))
        var future = FirstExportGuideProgress()
        future.schemaVersion = 99
        #expect(!FirstExportGuideReducer.shouldOfferOnLaunch(future, snapshot: .empty))
        #expect(FirstExportGuideReducer.presentation(for: future) == .hidden)
    }

    @Test func snapshotFromSimpleConfigurationReadsLayersWithoutMutation() throws {
        var configuration = SimpleMakerConfigurationModel()
        configuration.overlayText = "   "
        #expect(FirstExportGuideSnapshot.make(simple: configuration, exportReport: nil).hasTitle == false)

        configuration.layers.append(ThumbnailDocumentLayer.textLayer(value: "Big news"))
        configuration.layers.append(ThumbnailDocumentLayer.shapeLayer())
        let before = configuration.layers
        let snap = FirstExportGuideSnapshot.make(simple: configuration, exportReport: nil)
        #expect(snap.hasTitle)
        #expect(snap.hasVisual)
        #expect(!snap.hasSizeCheck)
        #expect(snap.readinessScore != nil)
        #expect(configuration.layers == before)

        let report = ThumbnailExportReport(byteCount: 1024, options: configuration.exportOptions)
        #expect(FirstExportGuideSnapshot.make(simple: configuration, exportReport: report).hasSizeCheck)
    }

    @Test func snapshotFromPremiumCountsProfileImageAsVisual() throws {
        var configuration = PremiumMakerConfigurationModel()
        #expect(!FirstExportGuideSnapshot.make(premium: configuration, exportReport: nil).hasVisual)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        var profile = configuration.circularProfile ?? CircularProfileConfig()
        profile.image = image
        configuration.circularProfile = profile
        #expect(FirstExportGuideSnapshot.make(premium: configuration, exportReport: nil).hasVisual)
    }
}
