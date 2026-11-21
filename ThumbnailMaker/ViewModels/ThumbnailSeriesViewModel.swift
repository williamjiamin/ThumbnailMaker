//
//  ThumbnailSeriesViewModel.swift
//  ThumbnailMaker
//
//  FEATURE-15: state behind the Series sheet. Owns the series table (with its
//  own undo/redo), the immutable source, per-row validation, and a FEATURE-10
//  queue runner that renders the rows. It never touches the editor's document
//  or history: the editor only hands over a snapshot of the open design.
//

import Combine
import Foundation
import UIKit

struct ThumbnailSeriesContext {
    var editorMode: ThumbnailDocumentEditorMode
    var projectName: String
    /// The open design (including unsaved edits) at the moment Series opened.
    var currentDocument: ThumbnailDocument
    var store: ThumbnailSeriesStore
    var currentExportOptions: ThumbnailExportOptions
}

enum ThumbnailSeriesRowStatus: Equatable {
    case idle
    case pending
    case rendering
    case done(files: Int)
    case failed(String)
    case skipped(String)
    case notRun
    case needsFixing
}

@MainActor
final class ThumbnailSeriesViewModel: ObservableObject {
    let context: ThumbnailSeriesContext
    let runner: ThumbnailExportQueueRunner
    let canRender: Bool

    @Published private(set) var series: ThumbnailSeries
    @Published private(set) var source: ThumbnailSeriesSource
    @Published private(set) var report = ThumbnailSeriesValidationReport(issues: [:], outputStems: [:], renderableRowIDs: [])
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var errorMessage: String?
    @Published var noticeMessage: String?
    @Published private(set) var recoveryNotices: [String] = []

    @Published private(set) var savedRecipes: [ThumbnailExportRecipe] = []
    @Published private(set) var selectedRecipeID: UUID
    @Published private(set) var destination: ThumbnailExportDestinationWriting?
    @Published private(set) var destinationSnapshot: ThumbnailExportDestinationSnapshot = .none
    @Published private(set) var destinationError: String?
    @Published private(set) var exportPlan: ThumbnailSeriesExportPlan?
    @Published private(set) var previews: [UUID: UIImage] = [:]

    private let store: ThumbnailSeriesStore
    private let recipeStore: ThumbnailExportRecipeStore
    private let formatIsAvailable: (ThumbnailExportFormat) -> Bool
    private let previewRenderer: ThumbnailProjectPreviewRendering
    private var history = ThumbnailSeriesRowsHistory()
    private var availableDigests: Set<String>
    private var lastEditKey: String?
    private var previewDigests: [UUID: String] = [:]
    private var runnerObservation: AnyCancellable?

    init(
        context: ThumbnailSeriesContext,
        canRender: Bool,
        recipeStore: ThumbnailExportRecipeStore = ThumbnailExportRecipeStore(),
        runner: ThumbnailExportQueueRunner? = nil,
        destination: ThumbnailExportDestinationWriting? = nil,
        loadsRememberedFolder: Bool = true,
        previewRenderer: ThumbnailProjectPreviewRendering = ThumbnailProjectPreviewRenderer(),
        formatIsAvailable: @escaping (ThumbnailExportFormat) -> Bool = { $0.canEncodeOnCurrentPlatform },
        now: Date = Date()
    ) {
        self.context = context
        self.canRender = canRender
        self.store = context.store
        self.recipeStore = recipeStore
        self.runner = runner ?? ThumbnailExportQueueRunner()
        self.formatIsAvailable = formatIsAvailable
        self.previewRenderer = previewRenderer

        let loaded = context.store.load()
        let source = loaded.source
            ?? ThumbnailSeriesSource.currentDesign(context.currentDocument, projectName: context.projectName, now: now)
        var series = loaded.series ?? ThumbnailSeries(
            name: ThumbnailSeries.cleanedName(context.projectName),
            createdAt: now,
            updatedAt: now
        )
        let isNewSource = loaded.source == nil
        series.sourceDigest = source.digest
        self.source = source
        self.series = series
        self.recoveryNotices = loaded.recoveryNotices
        self.availableDigests = context.store.availableAssetDigests()

        let library = recipeStore.load()
        savedRecipes = library.recipes
        let candidates = ThumbnailExportRecipe.builtIns
            + [ThumbnailExportRecipe.fromCurrentOptions(context.currentExportOptions)]
            + library.recipes
        selectedRecipeID = series.exportRecipeID.flatMap { id in candidates.first { $0.id == id }?.id }
            ?? ThumbnailExportRecipe.currentOptionsID

        if let destination {
            self.destination = destination
        } else if loadsRememberedFolder, let remembered = FolderExportDestination.rememberedFolder() {
            self.destination = remembered
        } else {
            self.destination = PhotosExportDestination()
        }

        runnerObservation = self.runner.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        if isNewSource {
            persistSource(source)
        }
        revalidate()
        refreshDestination()
    }

    // MARK: Table

    var rows: [ThumbnailSeriesRow] { series.rows }
    var isAtRowLimit: Bool { series.rows.count >= ThumbnailSeries.rowLimit }
    var isEditingLocked: Bool { runner.isRunning }

    func issues(for rowID: UUID) -> [ThumbnailSeriesRowIssue] { report.issues(for: rowID) }

    @discardableResult
    func addRow() -> UUID? {
        guard !isEditingLocked else { return nil }
        guard !isAtRowLimit else {
            errorMessage = ThumbnailSeriesCSVFileError.tooManyRows(limit: ThumbnailSeries.rowLimit).errorDescription
            return nil
        }
        let row = ThumbnailSeriesRow(title: "", episode: nextEpisodeSuggestion())
        editRows(key: nil) { $0.append(row) }
        return row.id
    }

    func setTitle(_ title: String, for rowID: UUID) {
        editRow(rowID, field: "title") { $0.title = title }
    }

    func setEpisode(_ episode: String, for rowID: UUID) {
        editRow(rowID, field: "episode") { $0.episode = episode.isEmpty ? nil : episode }
    }

    func setOutputName(_ name: String, for rowID: UUID) {
        editRow(rowID, field: "name") { $0.outputName = name.isEmpty ? nil : name }
    }

    func deleteRows(at offsets: IndexSet) {
        guard !isEditingLocked else { return }
        editRows(key: nil) { rows in
            for index in offsets.sorted(by: >) where rows.indices.contains(index) {
                rows.remove(at: index)
            }
        }
    }

    func deleteRow(_ rowID: UUID) {
        guard let index = series.rows.firstIndex(where: { $0.id == rowID }) else { return }
        deleteRows(at: IndexSet(integer: index))
    }

    func moveRows(from source: IndexSet, to destination: Int) {
        guard !isEditingLocked else { return }
        editRows(key: nil) { $0.move(fromOffsets: source, toOffset: destination) }
    }

    func undo() {
        guard !isEditingLocked, let previous = history.undo(current: series.rows) else { return }
        lastEditKey = nil
        applyRows(previous)
    }

    func redo() {
        guard !isEditingLocked, let next = history.redo(current: series.rows) else { return }
        lastEditKey = nil
        applyRows(next)
    }

    func rename(_ name: String) {
        let cleaned = ThumbnailSeries.cleanedName(name)
        guard cleaned != series.name else { return }
        series.name = cleaned
        seriesDidChange()
    }

    // MARK: CSV

    func importCSV(_ data: Data) {
        guard !isEditingLocked else { return }
        let result = ThumbnailSeriesCSVParser.parse(data)
        if let fileError = result.fileError {
            errorMessage = fileError.errorDescription
            return
        }
        let imported = ThumbnailSeriesCSVImporter.rows(from: result, images: knownImagesByName())
        guard !imported.rows.isEmpty else {
            errorMessage = "The file has a header but no rows."
            return
        }
        guard series.rows.count + imported.rows.count <= ThumbnailSeries.rowLimit else {
            errorMessage = "This would make \(series.rows.count + imported.rows.count) rows; a series can have up to \(ThumbnailSeries.rowLimit). Delete rows or import a shorter file."
            return
        }
        editRows(key: nil) { $0.append(contentsOf: imported.rows) }
        noticeMessage = imported.summary
    }

    func exportCSV() -> String {
        ThumbnailSeriesCSVWriter.csv(for: series.rows)
    }

    // MARK: Images

    /// Adds image files. Each is matched (case-insensitively) to rows whose
    /// CSV asked for that file name; any other image fills the next row that
    /// has no image, in table order.
    func addImages(_ files: [(data: Data, fileName: String)]) {
        guard !isEditingLocked, !files.isEmpty else { return }
        var rows = series.rows
        var failures: [String] = []
        var unplaced = 0
        for file in files {
            let ref: ThumbnailSeriesImageRef
            do {
                ref = try store.importImage(file.data, originalFileName: file.fileName)
                availableDigests.insert(ref.digest)
            } catch {
                failures.append(ThumbnailExportQueueRunner.message(for: error))
                continue
            }
            let key = file.fileName.lowercased()
            let matches = rows.indices.filter { rows[$0].imageRef == nil && rows[$0].requestedImageName?.lowercased() == key }
            if !matches.isEmpty {
                for index in matches {
                    rows[index].imageRef = ref
                    rows[index].requestedImageName = nil
                }
            } else if let index = rows.indices.first(where: { rows[$0].imageRef == nil && rows[$0].requestedImageName == nil }) {
                rows[index].imageRef = ref
            } else {
                unplaced += 1
            }
        }
        if rows != series.rows {
            editRows(key: nil) { $0 = rows }
        }
        var notes: [String] = []
        if unplaced > 0 { notes.append("\(unplaced) image\(unplaced == 1 ? "" : "s") didn't match any row.") }
        if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
        noticeMessage = notes.isEmpty ? nil : notes.joined(separator: " ")
    }

    func setImage(_ data: Data, fileName: String, for rowID: UUID) {
        guard !isEditingLocked else { return }
        do {
            let ref = try store.importImage(data, originalFileName: fileName)
            availableDigests.insert(ref.digest)
            editRow(rowID, field: nil) {
                $0.imageRef = ref
                $0.requestedImageName = nil
            }
        } catch {
            errorMessage = ThumbnailExportQueueRunner.message(for: error)
        }
    }

    func clearImage(for rowID: UUID) {
        editRow(rowID, field: nil) {
            $0.imageRef = nil
            $0.requestedImageName = nil
        }
    }

    // MARK: Source (immutable; replaced only by an explicit action)

    func recaptureFromCurrentDesign(now: Date = Date()) {
        replaceSource(
            ThumbnailSeriesSource.currentDesign(context.currentDocument, projectName: context.projectName, now: now)
        )
    }

    func useTemplate(_ template: ThumbnailTemplate, now: Date = Date()) {
        replaceSource(ThumbnailSeriesSource.personalTemplate(template, currentDocument: context.currentDocument, now: now))
    }

    private func replaceSource(_ newSource: ThumbnailSeriesSource) {
        guard !isEditingLocked else { return }
        guard persistSource(newSource) else { return }
        source = newSource
        series.sourceDigest = newSource.digest
        runner.reset()
        previews = [:]
        previewDigests = [:]
        seriesDidChange()
    }

    @discardableResult
    private func persistSource(_ source: ThumbnailSeriesSource) -> Bool {
        do {
            try store.saveSource(source)
            return true
        } catch {
            errorMessage = "Couldn't save the series source: \(ThumbnailExportQueueRunner.message(for: error))"
            return false
        }
    }

    // MARK: Row documents & previews

    func document(for row: ThumbnailSeriesRow) -> ThumbnailDocument {
        ThumbnailSeriesRecipe.document(
            for: row,
            in: source,
            imageData: row.imageRef.flatMap { store.assetData($0.digest) }
        )
    }

    func loadPreview(for rowID: UUID) async {
        guard let row = series.rows.first(where: { $0.id == rowID }) else { return }
        let document = document(for: row)
        let digest = ThumbnailSeriesRecipe.documentDigest(document)
        guard previewDigests[rowID] != digest else { return }
        previewDigests[rowID] = digest
        guard let data = await previewRenderer.previewPNGData(for: document, maxPixelWidth: 320),
              let image = UIImage(data: data) else { return }
        // Only keep it if the row did not change while rendering.
        if previewDigests[rowID] == digest {
            previews[rowID] = image
        }
    }

    // MARK: Export (FEATURE-10 queue)

    var availableRecipes: [ThumbnailExportRecipe] {
        ThumbnailExportRecipe.builtIns
            + [ThumbnailExportRecipe.fromCurrentOptions(context.currentExportOptions)]
            + savedRecipes
    }

    var selectedRecipe: ThumbnailExportRecipe {
        availableRecipes.first { $0.id == selectedRecipeID }
            ?? ThumbnailExportRecipe.fromCurrentOptions(context.currentExportOptions)
    }

    func selectRecipe(_ id: UUID) {
        guard !isEditingLocked, availableRecipes.contains(where: { $0.id == id }) else { return }
        selectedRecipeID = id
        series.exportRecipeID = id
        runner.reset()
        seriesDidChange()
    }

    var destinationNote: String? {
        destination is PhotosExportDestination ? PhotosExportDestination.namesNotKeptNote : nil
    }

    func usePhotos() {
        guard !isEditingLocked else { return }
        destination = PhotosExportDestination()
        runner.reset()
        exportPlan = nil
        refreshDestination()
    }

    func chooseFolder(_ url: URL) {
        guard !isEditingLocked else { return }
        FolderExportDestination.remember(url)
        destination = FolderExportDestination(folderURL: url)
        runner.reset()
        exportPlan = nil
        refreshDestination()
    }

    /// Re-reads the destination. The plan itself (which composes every row's
    /// document) is only built when rendering, never on each keystroke.
    func refreshDestination() {
        guard let destination else {
            destinationSnapshot = .none
            destinationError = "Choose where to export."
            return
        }
        do {
            destinationSnapshot = try destination.snapshot()
            destinationError = nil
        } catch {
            destinationSnapshot = ThumbnailExportDestinationSnapshot(displayName: destination.displayName, supportsFileNames: true)
            destinationError = ThumbnailExportQueueRunner.message(for: error)
        }
    }

    /// Files a run would write, before conflicts: renderable rows x sizes.
    var plannedFileCount: Int { report.renderableRowIDs.count * selectedRecipe.sizes.count }

    var planSummary: String {
        let files = plannedFileCount
        var parts = ["\(report.renderableRowIDs.count) of \(series.rows.count) rows ready", "\(files) file\(files == 1 ? "" : "s")"]
        let fixing = report.errorRowCount
        if fixing > 0 { parts.append("\(fixing) need fixing") }
        return parts.joined(separator: " · ")
    }

    var canRun: Bool {
        canRender && !runner.isRunning && destination != nil && destinationError == nil && plannedFileCount > 0
    }

    var canRetry: Bool {
        canRender && !runner.isRunning && runner.hasFinishedRun && !runner.retryableJobIDs.isEmpty
    }

    var progressLabel: String {
        if runner.isRunning {
            return "Rendering \(runner.completedCount) of \(runner.totalCount)"
        }
        guard runner.hasFinishedRun else { return planSummary }
        var label = runner.resultSummary
        let skippedRows = exportPlan?.skippedRowIDs.count ?? 0
        if skippedRows > 0 { label += " · \(skippedRows) row\(skippedRows == 1 ? "" : "s") skipped" }
        return label
    }

    func render() async {
        guard canRender else {
            errorMessage = "Rendering a series is part of Premium. You can still build and check the table."
            return
        }
        refreshDestination()
        guard canRun, let destination else { return }
        let plan = buildPlan()
        exportPlan = plan
        guard !plan.queuePlan.runnableJobs.isEmpty else {
            errorMessage = plan.queuePlan.emptyReason
                ?? plan.queuePlan.blockedJobs.first?.blockedReason?.message
                ?? "Nothing to render."
            return
        }
        await runner.run(plan.queuePlan, destination: destination)
        refreshDestination()
    }

    func cancel() {
        runner.cancel()
    }

    func retryFailed() async {
        guard canRetry else { return }
        let ids = runner.retryableJobIDs
        refreshDestination()
        guard destinationError == nil, let destination else { return }
        let plan = buildPlan()
        exportPlan = plan
        await runner.run(plan.queuePlan, destination: destination, onlyJobIDs: ids)
        refreshDestination()
    }

    func status(for rowID: UUID) -> ThumbnailSeriesRowStatus {
        if report.hasError(rowID) { return .needsFixing }
        guard let exportPlan else { return .idle }
        let states = exportPlan.jobIDs(for: rowID).compactMap { runner.state(for: $0) }
        guard !states.isEmpty else { return .idle }
        if states.contains(.running) { return .rendering }
        for state in states {
            if case .failed(let message) = state { return .failed(message) }
        }
        if states.contains(.notRun) { return .notRun }
        if states.contains(.pending) { return .pending }
        let done = states.filter { if case .succeeded = $0 { return true }; return false }.count
        if done > 0 { return .done(files: done) }
        for state in states {
            if case .skipped(let reason) = state { return .skipped(reason) }
        }
        return .idle
    }

    /// The FEATURE-10 plan for the current table, recipe and destination.
    func buildPlan() -> ThumbnailSeriesExportPlan {
        let store = self.store
        return ThumbnailSeriesExportPlan.make(
            series: series,
            source: source,
            report: report,
            recipe: selectedRecipe,
            destination: destinationSnapshot,
            imageData: { store.assetData($0) },
            formatIsAvailable: formatIsAvailable
        )
    }

    // MARK: Plumbing

    private func editRow(_ rowID: UUID, field: String?, _ change: (inout ThumbnailSeriesRow) -> Void) {
        guard !isEditingLocked, let index = series.rows.firstIndex(where: { $0.id == rowID }) else { return }
        var row = series.rows[index]
        change(&row)
        if row != series.rows[index] {
            // Any edit by the user supersedes a CSV parse error on that row.
            row.importError = nil
        }
        guard row != series.rows[index] else { return }
        let key = field.map { "\(rowID.uuidString)-\($0)" }
        editRows(key: key) { $0[index] = row }
    }

    /// Records undo (coalescing consecutive keystrokes in the same field).
    private func editRows(key: String?, _ change: (inout [ThumbnailSeriesRow]) -> Void) {
        var rows = series.rows
        change(&rows)
        guard rows != series.rows else { return }
        if key == nil || key != lastEditKey {
            history.record(series.rows)
        }
        lastEditKey = key
        applyRows(rows)
    }

    private func applyRows(_ rows: [ThumbnailSeriesRow]) {
        series.rows = rows
        if !runner.isRunning { runner.reset() }
        seriesDidChange()
    }

    private func seriesDidChange() {
        series.updatedAt = Date()
        canUndo = history.canUndo
        canRedo = history.canRedo
        revalidate()
        if !runner.isRunning { exportPlan = nil }
        do {
            try store.save(series)
        } catch {
            errorMessage = "Couldn't save the series: \(ThumbnailExportQueueRunner.message(for: error))"
        }
    }

    private func revalidate() {
        report = ThumbnailSeriesValidator.validate(series: series, source: source, availableImageDigests: availableDigests)
        let valid = Set(series.rows.map(\.id))
        previews = previews.filter { valid.contains($0.key) }
    }

    private func knownImagesByName() -> [String: ThumbnailSeriesImageRef] {
        var images: [String: ThumbnailSeriesImageRef] = [:]
        for row in series.rows {
            if let ref = row.imageRef { images[ref.originalFileName.lowercased()] = ref }
        }
        return images
    }

    private func nextEpisodeSuggestion() -> String? {
        guard let last = series.rows.last?.episodeValue, let number = Int(last) else { return nil }
        return String(number + 1)
    }
}
