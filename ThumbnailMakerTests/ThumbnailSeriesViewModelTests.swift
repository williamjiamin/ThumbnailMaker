//
//  ThumbnailSeriesViewModelTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-15: the Series sheet's state, rendered through the FEATURE-10
//  queue runner (counting renderer + in-memory destination, no Photos).
//

import Foundation
import Testing
@testable import ThumbnailMaker

@MainActor
struct ThumbnailSeriesViewModelTests {
    private typealias Support = SeriesTestSupport

    private struct Harness {
        let directory: URL
        let model: ThumbnailSeriesViewModel
        let renderer: CountingExportRenderer
        let destination: InMemoryExportDestination
        let store: ThumbnailSeriesStore
    }

    private func makeHarness(
        directory: URL = SeriesTestSupport.makeTemporaryDirectory(),
        document: ThumbnailDocument = SeriesTestSupport.sourceDocument(),
        canRender: Bool = true
    ) -> Harness {
        let store = ThumbnailSeriesStore(directory: directory.appendingPathComponent("series", isDirectory: true))
        let renderer = CountingExportRenderer()
        let destination = InMemoryExportDestination()
        let model = ThumbnailSeriesViewModel(
            context: ThumbnailSeriesContext(
                editorMode: .simple,
                projectName: "My Show",
                currentDocument: document,
                store: store,
                currentExportOptions: ThumbnailExportOptions()
            ),
            canRender: canRender,
            recipeStore: ThumbnailExportRecipeStore(directory: directory.appendingPathComponent("recipes", isDirectory: true)),
            runner: ThumbnailExportQueueRunner(renderer: renderer),
            destination: destination,
            loadsRememberedFolder: false,
            previewRenderer: StubProjectPreviewRenderer(),
            formatIsAvailable: { _ in true },
            now: SeriesTestSupport.captureDate
        )
        return Harness(directory: directory, model: model, renderer: renderer, destination: destination, store: store)
    }

    /// Imports the 10-row fixture and adds the three images it names.
    private func importFixture(_ model: ThumbnailSeriesViewModel) {
        model.importCSV(Data(SeriesTestSupport.tenRowCSV.utf8))
        model.addImages([
            (SeriesTestSupport.imageData(color: .systemRed), "ep1.jpg"),
            (SeriesTestSupport.imageData(color: .systemGreen), "ep2.jpg"),
            (SeriesTestSupport.imageData(color: .systemPurple), "ep5.jpg")
        ])
    }

    @Test func fixtureRendersSevenRowsAndIsolatesThreeBadOnes() async {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let model = harness.model

        importFixture(model)

        #expect(model.rows.count == 10)
        #expect(model.report.renderableRowIDs.count == 7)
        #expect(model.report.errorRowCount == 3)
        #expect(model.rows.allSatisfy { $0.requestedImageName == nil })
        #expect(model.canRun)

        await model.render()

        #expect(harness.renderer.renderCount == 7)
        #expect(model.runner.succeededCount == 7)
        #expect(harness.destination.writtenNames.count == 7)
        #expect(harness.destination.writtenNames.first?.hasPrefix("my-show-1-") == true)
        #expect(harness.destination.writtenNames.contains { $0.hasPrefix("desk-special-") })
        #expect(model.status(for: model.rows[0].id) == .done(files: 1))
        #expect(model.status(for: model.rows[2].id) == .needsFixing)
        #expect(model.progressLabel == "7 exported · 3 rows skipped")
        // Rendered in table order, with each row's own title.
        #expect(harness.renderer.renderedSlotsAndSizes.first?.hasPrefix("Morning Routine-") == true)
    }

    @Test func failingRowDoesNotStopTheQueueAndRetryRedoesOnlyIt() async throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let model = harness.model
        importFixture(model)
        let plan = model.buildPlan()
        let failing = try #require(plan.queuePlan.jobs.dropFirst(3).first).targetFileName
        harness.destination.failingFileNames = [failing]
        harness.destination.failOnce = true

        await model.render()

        #expect(model.runner.succeededCount == 6)
        #expect(model.runner.failedCount == 1)
        #expect(model.canRetry)

        await model.retryFailed()

        #expect(model.runner.succeededCount == 7)
        #expect(harness.renderer.renderCount == 8)
        #expect(harness.destination.writtenNames.last == failing)
    }

    @Test func cancelStopsAfterTheCurrentRowAndRetryFinishesTheRest() async {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let model = harness.model
        importFixture(model)
        harness.destination.afterWrite = { count in
            if count == 3 { model.cancel() }
        }

        await model.render()

        #expect(model.runner.succeededCount == 3)
        #expect(model.runner.notRunCount == 4)
        #expect(harness.destination.writtenNames.count == 3)

        harness.destination.afterWrite = nil
        await model.retryFailed()

        #expect(model.runner.succeededCount == 7)
        #expect(harness.renderer.renderCount == 7)
    }

    @Test func premiumGateBlocksRenderingButNotAuthoring() async {
        let harness = makeHarness(canRender: false)
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let model = harness.model
        importFixture(model)

        #expect(model.report.renderableRowIDs.count == 7)
        #expect(!model.canRun)

        await model.render()

        #expect(harness.renderer.renderCount == 0)
        #expect(model.errorMessage != nil)
    }

    @Test func tableEditsUndoAndRedoWithKeystrokeCoalescing() throws {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let model = harness.model

        let rowID = try #require(model.addRow())
        model.setTitle("H", for: rowID)
        model.setTitle("Hi", for: rowID)
        model.setEpisode("4", for: rowID)

        #expect(model.rows.first?.title == "Hi")
        model.undo()
        #expect(model.rows.first?.episode == nil)
        #expect(model.rows.first?.title == "Hi")
        model.undo()
        #expect(model.rows.first?.title == "")
        model.undo()
        #expect(model.rows.isEmpty)
        #expect(!model.canUndo)

        model.redo()
        model.redo()
        #expect(model.rows.first?.title == "Hi")
        #expect(model.canRedo)
    }

    @Test func tableAndSourcePersistAndSourceIsNotRecapturedOnReopen() throws {
        let directory = Support.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = makeHarness(directory: directory, document: Support.sourceDocument(headline: "First Design"))
        let rowID = try #require(first.model.addRow())
        first.model.setTitle("Saved Row", for: rowID)
        let digest = first.model.source.digest

        let reopened = makeHarness(directory: directory, document: Support.sourceDocument(headline: "Edited Later"))

        #expect(reopened.model.rows.map(\.title) == ["Saved Row"])
        #expect(reopened.model.source.digest == digest)
        #expect(reopened.model.source.template.document.text.value == "First Design")

        reopened.model.recaptureFromCurrentDesign(now: Support.captureDate.addingTimeInterval(60))
        #expect(reopened.model.source.digest != digest)
        #expect(reopened.model.rows.map(\.title) == ["Saved Row"])
        #expect(reopened.store.load().source?.digest == reopened.model.source.digest)
    }

    @Test func personalTemplateBecomesTheSource() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let template = ThumbnailTemplate.capture(
            from: Support.sourceDocument(headline: "{title}!", episodeLayerText: nil),
            name: "Punchy",
            category: .youtube
        )

        harness.model.useTemplate(template)
        let rowID = harness.model.addRow()!
        harness.model.setTitle("Wow", for: rowID)

        #expect(harness.model.source.origin == .personalTemplate(id: template.id, name: "Punchy"))
        #expect(harness.model.document(for: harness.model.rows[0]).text.value == "Wow!")
    }

    @Test func csvOverTheRowLimitIsRejectedWithoutChangingTheTable() {
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.directory) }
        let model = harness.model
        let csv = (["title"] + (1...60).map { "Row \($0)" }).joined(separator: "\n")

        model.importCSV(Data(csv.utf8))
        #expect(model.rows.count == 60)
        model.importCSV(Data(csv.utf8))

        #expect(model.rows.count == 60)
        #expect(model.errorMessage != nil)
    }

    @Test func editorHookSnapshotsTheOpenDesignIntoTheProjectFolder() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)
        let editor = SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: root.appendingPathComponent("Drafts/simple.json")),
            brandKitStore: BrandKitStore(fileURL: root.appendingPathComponent("brand.json")),
            projectLibrary: library
        )
        editor.simpleMakerConfiguration.overlayText = "Captured Title"

        let context = editor.makeSeriesContext()
        let projectID = try #require(editor.activeProjectID)
        editor.simpleMakerConfiguration.overlayText = "Changed After"

        #expect(context.currentDocument.text.value == "Captured Title")
        #expect(context.editorMode == .simple)
        #expect(context.store.directory.path.hasPrefix(library.store.projectDirectory(id: projectID).path))
        #expect(editor.isSeriesAvailable)
    }
}
