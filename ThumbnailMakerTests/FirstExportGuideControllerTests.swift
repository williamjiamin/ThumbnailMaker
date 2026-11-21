//
//  FirstExportGuideControllerTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-13: controller persistence plus the view-model export-event hooks
//  that feed it.
//

import Foundation
import SwiftUI
import Testing
@testable import ThumbnailMaker

@MainActor
struct FirstExportGuideControllerTests {
    private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FirstExportGuideControllerTests-\(UUID().uuidString)", isDirectory: true)
    }

    private let fullSnapshot = FirstExportGuideSnapshot(
        hasVisual: true,
        hasTitle: true,
        hasSizeCheck: true,
        readinessScore: "90/100",
        readinessHasWarnings: false,
        hasExportableContent: true
    )

    @Test func everyMutationPersists() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FirstExportGuideStore(fileURL: directory.appendingPathComponent("guide.json"))
        let date = fixedDate
        let controller = FirstExportGuideController(store: store, now: { date })

        controller.offerIfFirstRun(snapshot: .empty)
        #expect(controller.presentation == .card)
        #expect(store.load().progress.status == .active)
        #expect(store.load().progress.startedAt == date)

        controller.pause()
        #expect(store.load().progress.status == .paused)
        #expect(controller.presentation == .resumePill)

        controller.resume()
        controller.observe(fullSnapshot)
        #expect(store.load().progress.currentStep == .export)

        controller.skip()
        #expect(store.load().progress.status == .skipped)
        #expect(controller.presentation == .hidden)

        // A fresh controller on the same file resumes the saved state.
        let relaunched = FirstExportGuideController(store: store, now: { date })
        #expect(relaunched.progress.status == .skipped)
        relaunched.showFromSettings()
        #expect(relaunched.progress.status == .active)
        #expect(relaunched.progress.currentStep == .export)
        #expect(controller.persistenceError == nil)
    }

    @Test func offerIsIdempotentAndSkipsExistingWork() {
        let controller = FirstExportGuideController(store: .inMemory())
        controller.offerIfFirstRun(snapshot: fullSnapshot)
        #expect(controller.progress.status == .notStarted)
        #expect(controller.presentation == .hidden)
        // A later empty canvas (e.g. tab switch) does not start it this launch.
        controller.offerIfFirstRun(snapshot: .empty)
        #expect(controller.progress.status == .notStarted)
    }

    @Test func premiumExportCompletesSharedGuideAndDismissHidesIt() {
        let controller = FirstExportGuideController(store: .inMemory())
        controller.offerIfFirstRun(snapshot: .empty)
        controller.recordExport(nil)
        #expect(controller.progress.status == .active)
        controller.recordExport(ThumbnailExportEvent(kind: .files, editorMode: .premium))
        #expect(controller.progress.status == .completed)
        #expect(controller.progress.lastEditorMode == .premium)
        #expect(controller.presentation == .completed)
        controller.dismissCompletion()
        #expect(controller.presentation == .hidden)
        // Settings can start it again; this resets guide progress only.
        controller.showFromSettings()
        #expect(controller.progress.status == .active)
        #expect(controller.progress.completedSteps.isEmpty)
    }

    @Test func saveFailureIsKeptInMemoryWithoutThrowing() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A regular file where the parent directory must be makes saving fail.
        let blocker = directory.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: blocker)
        let store = FirstExportGuideStore(fileURL: blocker.appendingPathComponent("guide.json"))
        let controller = FirstExportGuideController(store: store)
        controller.offerIfFirstRun(snapshot: .empty)
        #expect(controller.progress.status == .active)
        #expect(controller.persistenceError != nil)
    }

    // MARK: View-model export events

    private func makeSimple(in directory: URL) -> SimpleMakerViewModel {
        SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
    }

    private func makePremium(in directory: URL) -> PremiumMakerViewModel {
        PremiumMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
    }

    @Test func simpleFileExportAndShareProduceEventsWithoutDocumentChanges() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = makeSimple(in: directory)
        let configurationBefore = ThumbnailDocumentHistory.snapshot(viewModel.simpleMakerConfiguration.document)
        let canUndoBefore = viewModel.canUndo

        viewModel.handleFileExportCompletion(.failure(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)))
        #expect(viewModel.lastExportEvent == nil)
        viewModel.recordShareCompleted(false)
        #expect(viewModel.lastExportEvent == nil)

        viewModel.handleFileExportCompletion(.success(directory.appendingPathComponent("out.png")))
        let filesEvent = try #require(viewModel.lastExportEvent)
        #expect(filesEvent.kind == .files)
        #expect(filesEvent.editorMode == .simple)

        viewModel.recordShareCompleted(true)
        #expect(viewModel.lastExportEvent?.kind == .share)
        #expect(viewModel.lastExportEvent?.id != filesEvent.id)

        #expect(ThumbnailDocumentHistory.snapshot(viewModel.simpleMakerConfiguration.document) == configurationBefore)
        #expect(viewModel.canUndo == canUndoBefore)
    }

    @Test func simpleSizeCheckIsNotAnExport() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = makeSimple(in: directory)
        viewModel.simpleMakerConfiguration.overlayText = "Size check"
        await viewModel.checkExportSize(content: Text("Size check").frame(width: 64, height: 36))
        #expect(viewModel.exportReport != nil)
        #expect(viewModel.lastExportEvent == nil)
    }

    @Test func premiumFileExportAndShareProduceEvents() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = makePremium(in: directory)

        viewModel.recordShareCompleted(false)
        viewModel.handleFileExportCompletion(.failure(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)))
        #expect(viewModel.lastExportEvent == nil)

        viewModel.handleFileExportCompletion(.success(directory.appendingPathComponent("out.png")))
        #expect(viewModel.lastExportEvent?.kind == .files)
        #expect(viewModel.lastExportEvent?.editorMode == .premium)
        viewModel.recordShareCompleted(true)
        #expect(viewModel.lastExportEvent?.kind == .share)
    }
}
