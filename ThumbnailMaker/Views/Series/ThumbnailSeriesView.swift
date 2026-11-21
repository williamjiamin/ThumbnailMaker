//
//  ThumbnailSeriesView.swift
//  ThumbnailMaker
//
//  FEATURE-15: the Series sheet. Freeze a source (the open design or a
//  personal template), fill a table of rows by hand or from CSV, check each
//  row, then render every valid row through the FEATURE-10 export queue.
//

import SwiftUI
import UniformTypeIdentifiers

struct ThumbnailSeriesView: View {
    @StateObject private var model: ThumbnailSeriesViewModel
    let personalTemplates: [ThumbnailTemplate]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum ImportMode {
        case csv
        case images
        case folder
    }

    @State private var importMode: ImportMode?
    @State private var isRecaptureConfirmationPresented = false
    @State private var pendingTemplate: ThumbnailTemplate?
    @State private var isHelpPresented = false
    @State private var csvShareURL: URL?
    @State private var isRenaming = false
    @State private var nameDraft = ""

    init(
        context: @autoclosure @escaping () -> ThumbnailSeriesContext,
        canRender: Bool,
        personalTemplates: [ThumbnailTemplate]
    ) {
        _model = StateObject(wrappedValue: ThumbnailSeriesViewModel(context: context(), canRender: canRender))
        self.personalTemplates = personalTemplates
    }

    var body: some View {
        NavigationStack {
            List {
                if !model.recoveryNotices.isEmpty {
                    Section {
                        ForEach(model.recoveryNotices, id: \.self) { notice in
                            Label(notice, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                        }
                    }
                }
                sourceSection
                rowsSection
                exportSection
                if dynamicTypeSize.isAccessibilitySize {
                    Section { runBar }
                }
            }
            .navigationTitle(model.series.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .pinnedActionBar(isInline: dynamicTypeSize.isAccessibilitySize) { runBar }
            .fileImporter(
                isPresented: Binding(
                    get: { importMode != nil },
                    set: { if !$0 { importMode = nil } }
                ),
                allowedContentTypes: allowedImportTypes,
                allowsMultipleSelection: importMode == .images
            ) { result in
                handleImport(result)
            }
            .alert(
                "Series",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
            .alert("Rename Series", isPresented: $isRenaming) {
                TextField("Name", text: $nameDraft)
                Button("Save") { model.rename(nameDraft) }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Replace the series source?",
                isPresented: $isRecaptureConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Use Current Design") { model.recaptureFromCurrentDesign() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every row will be rendered from the design that is open now. Rows are kept.")
            }
            .confirmationDialog(
                "Use this template for every row?",
                isPresented: Binding(
                    get: { pendingTemplate != nil },
                    set: { if !$0 { pendingTemplate = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Use \(pendingTemplate?.name ?? "Template")") {
                    if let pendingTemplate { model.useTemplate(pendingTemplate) }
                    pendingTemplate = nil
                }
                Button("Cancel", role: .cancel) { pendingTemplate = nil }
            } message: {
                Text("Rows are kept. The template's own slot settings decide which parts each row fills.")
            }
            .sheet(isPresented: $isHelpPresented) {
                ThumbnailSeriesCSVHelpView()
            }
            .sheet(item: Binding(
                get: { csvShareURL.map(ShareableURL.init) },
                set: { csvShareURL = $0?.url }
            )) { item in
                ShareSheet(activityItems: [item.url])
            }
        }
        .interactiveDismissDisabled(model.runner.isRunning)
        .accessibilityIdentifier("seriesSheet")
    }

    private struct ShareableURL: Identifiable {
        let url: URL
        var id: String { url.path }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            SheetToolbarButton(.done) { dismiss() }
                .disabled(model.runner.isRunning)
                .accessibilityIdentifier("seriesDoneButton")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            UndoRedoToolbarButtons(
                canUndo: model.canUndo,
                canRedo: model.canRedo,
                undo: model.undo,
                redo: model.redo
            )
            Menu {
                Button {
                    model.addRow()
                } label: {
                    Label("Add Row", systemImage: "plus")
                }
                .disabled(model.isAtRowLimit)
                .accessibilityIdentifier("seriesAddRowButton")

                Button {
                    importMode = .csv
                } label: {
                    Label("Import CSV…", systemImage: "tablecells")
                }
                .accessibilityIdentifier("seriesImportCSVButton")

                Button {
                    importMode = .images
                } label: {
                    Label("Add Image Files…", systemImage: "photo.on.rectangle")
                }
                .accessibilityIdentifier("seriesImportImagesButton")

                Button {
                    exportCSV()
                } label: {
                    Label("Export Table as CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(model.rows.isEmpty)
                .accessibilityIdentifier("seriesExportCSVButton")

                Button {
                    nameDraft = model.series.name
                    isRenaming = true
                } label: {
                    Label("Rename Series", systemImage: "pencil")
                }

                Button {
                    isHelpPresented = true
                } label: {
                    Label("CSV Format", systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier("seriesCSVHelpButton")
            } label: {
                Image(systemName: "plus.circle")
            }
            .disabled(model.isEditingLocked)
            .accessibilityIdentifier("seriesAddMenu")
            .accessibilityLabel("Add rows")
        }
    }

    // MARK: Source

    private var sourceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(model.source.origin.displayName)
                        .font(.headline)
                    Spacer()
                    Label("Locked", systemImage: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        .accessibilityIdentifier("seriesImmutableBadge")
                }
                Text("Captured \(model.source.capturedAt.formatted(date: .abbreviated, time: .shortened)). Editing the design later doesn't change this series.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Use {title} and {episode} in the design's text to place them exactly; otherwise the title replaces the headline.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("seriesSourceCard")

            Button("Use Current Design Instead…") { isRecaptureConfirmationPresented = true }
                .disabled(model.isEditingLocked)
                .accessibilityIdentifier("seriesRecaptureButton")

            if !personalTemplates.isEmpty {
                Menu("Use a Personal Template…") {
                    ForEach(personalTemplates) { template in
                        Button(template.name) { pendingTemplate = template }
                    }
                }
                .disabled(model.isEditingLocked)
                .accessibilityIdentifier("seriesUseTemplateMenu")
            }
        } header: {
            Text("Source")
        }
    }

    // MARK: Rows

    @ViewBuilder
    private var emptyStateButtons: some View {
        Button("Add Row") { model.addRow() }
            .fixedSize()
            .accessibilityIdentifier("seriesEmptyAddRowButton")
        Button("Import CSV…") { importMode = .csv }
            .fixedSize()
            .accessibilityIdentifier("seriesEmptyImportCSVButton")
    }

    private var rowsSection: some View {
        Section {
            if model.rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No rows yet.")
                        .font(.headline)
                    Text("Add a row for each video, or import a CSV with a title column.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    // Side by side when they fit, stacked at large text sizes.
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            emptyStateButtons
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            emptyStateButtons
                        }
                    }
                    .buttonStyle(TintedCapsuleButtonStyle())
                }
                .padding(.vertical, 6)
            } else {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                    ThumbnailSeriesRowView(model: model, row: row, index: index)
                        .swipeActions {
                            Button(role: .destructive) {
                                model.deleteRow(row.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onMove { model.moveRows(from: $0, to: $1) }
            }
        } header: {
            Text("Rows (\(model.rows.count)/\(ThumbnailSeries.rowLimit))")
        } footer: {
            if let notice = model.noticeMessage {
                Text(notice)
                    .accessibilityIdentifier("seriesNotice")
            }
        }
    }

    // MARK: Export

    private var exportSection: some View {
        Section {
            Picker("Recipe", selection: Binding(
                get: { model.selectedRecipeID },
                set: { model.selectRecipe($0) }
            )) {
                ForEach(model.availableRecipes) { recipe in
                    Text(recipe.name).tag(recipe.id)
                }
            }
            .accessibilityIdentifier("seriesRecipePicker")

            Text(model.selectedRecipe.sizes.map(\.displayName).joined(separator: ", "))
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.destinationSnapshot.displayName)
                if let note = model.destinationNote {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
                if let error = model.destinationError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            HStack {
                Button("Choose Folder…") { importMode = .folder }
                    .accessibilityIdentifier("seriesChooseFolderButton")
                Spacer()
                Button("Photos") { model.usePhotos() }
                    .accessibilityIdentifier("seriesDestinationPhotos")
            }
            .buttonStyle(.borderless)

            if !model.canRender {
                Label("Rendering a series is part of Premium. You can build and check the table for free.", systemImage: "lock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("seriesPremiumNote")
            }
        } header: {
            Text("Export")
        } footer: {
            Text("Uses the same export recipes, file-size limits and destinations as Export All.")
        }
        .disabled(model.isEditingLocked)
    }

    // MARK: Run bar

    private var runBar: some View {
        VStack(spacing: 8) {
            if model.runner.isRunning {
                ProgressView(value: model.runner.progress)
            }
            Text(model.runner.isCancelling ? "Cancelling after the current file…" : model.progressLabel)
                .font(.footnote.weight(model.runner.hasFinishedRun ? .semibold : .regular))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("seriesProgressLabel")
            HStack {
                if model.runner.isRunning {
                    Button("Cancel", role: .cancel) { model.cancel() }
                        .buttonStyle(.bordered)
                        .disabled(model.runner.isCancelling)
                        .accessibilityIdentifier("seriesCancelButton")
                } else {
                    if model.canRetry {
                        Button("Retry (\(model.runner.retryableJobIDs.count))") {
                            Task { await model.retryFailed() }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("seriesRetryButton")
                    }
                    Button {
                        Task { await model.render() }
                    } label: {
                        Text("Render \(model.plannedFileCount) File\(model.plannedFileCount == 1 ? "" : "s")")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ProminentActionButtonStyle())
                    .disabled(!model.canRun)
                    .accessibilityIdentifier("seriesRenderButton")
                }
            }
        }
        .padding()
        .background(.bar)
    }

    // MARK: Import / export plumbing

    private var allowedImportTypes: [UTType] {
        switch importMode {
        case .csv: return [.commaSeparatedText, .plainText, .text]
        case .images: return [.image]
        case .folder: return [.folder]
        case nil: return [.item]
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        let mode = importMode
        importMode = nil
        switch result {
        case .failure(let error):
            model.errorMessage = "Couldn't open that file: \(error.localizedDescription)"
        case .success(let urls):
            switch mode {
            case .csv:
                guard let url = urls.first else { return }
                do {
                    model.importCSV(try readScoped(url))
                } catch {
                    model.errorMessage = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
                }
            case .images:
                var files: [(data: Data, fileName: String)] = []
                for url in urls {
                    do {
                        files.append((try readScoped(url), url.lastPathComponent))
                    } catch {
                        model.errorMessage = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
                    }
                }
                model.addImages(files)
            case .folder:
                if let url = urls.first { model.chooseFolder(url) }
            case nil:
                break
            }
        }
    }

    private func readScoped(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    private func exportCSV() {
        let stem = ThumbnailVariantExportNaming.sanitized(model.series.name)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(stem.isEmpty ? "series" : stem).csv")
        do {
            try Data(model.exportCSV().utf8).write(to: url, options: .atomic)
            csvShareURL = url
        } catch {
            model.errorMessage = "Couldn't prepare the CSV: \(error.localizedDescription)"
        }
    }
}

/// FEATURE-15: the editors' entry point, shown under the variant bar.
struct SeriesEntryButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Make a Series…", systemImage: "rectangle.stack.badge.plus")
                .font(.subheadline)
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .accessibilityIdentifier("seriesButton")
        .accessibilityHint("Render one thumbnail per video from a table of titles")
    }
}
