//
//  ExportQueueView.swift
//  ThumbnailMaker
//
//  FEATURE-10: "Export All" sheet. Pick a recipe (variants x sizes, format,
//  optional file-size budget), pick a destination, REVIEW every file that will
//  be written, then run with progress, cancel, and retry of failed files.
//

import SwiftUI
import UniformTypeIdentifiers

struct ExportQueueView: View {
    @StateObject private var model: ExportQueueViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var isFolderPickerPresented = false
    @State private var isSaveAsPresented = false
    @State private var saveAsName = ""
    @State private var customWidth = 1920
    @State private var customHeight = 1080
    @State private var isDeleteConfirmationPresented = false

    init(context: @autoclosure @escaping () -> ThumbnailExportQueueContext) {
        _model = StateObject(wrappedValue: ExportQueueViewModel(context: context()))
    }

    init(model: @autoclosure @escaping () -> ExportQueueViewModel) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        NavigationStack {
            Form {
                recipeSection
                variantsSection
                sizesSection
                formatSection
                destinationSection
                reviewSection
                if dynamicTypeSize.isAccessibilitySize {
                    Section { runBar }
                }
            }
            .navigationTitle("Export All")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetToolbarButton(.done) { dismiss() }
                        .disabled(model.runner.isRunning)
                        .accessibilityIdentifier("exportQueueDoneButton")
                }
            }
            .pinnedActionBar(isInline: dynamicTypeSize.isAccessibilitySize) { runBar }
            .fileImporter(
                isPresented: $isFolderPickerPresented,
                allowedContentTypes: [.folder]
            ) { result in
                switch result {
                case .success(let url):
                    model.chooseFolder(url)
                case .failure(let error):
                    model.errorMessage = "Couldn't open that folder: \(error.localizedDescription)"
                }
            }
            .alert("Save Recipe", isPresented: $isSaveAsPresented) {
                TextField("Name", text: $saveAsName)
                    .accessibilityIdentifier("exportQueueRecipeNameField")
                Button("Save") { model.saveDraftAsNew(named: saveAsName) }
                Button("Cancel", role: .cancel) {}
            }
            .alert(
                "Export",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
            .confirmationDialog(
                "Delete this recipe?",
                isPresented: $isDeleteConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Delete Recipe", role: .destructive) { model.deleteSelectedRecipe() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You can undo this right after.")
            }
        }
        .interactiveDismissDisabled(model.runner.isRunning)
        .accessibilityIdentifier("exportQueueSheet")
    }

    // MARK: Recipe

    private var recipeSection: some View {
        Section {
            AccessibleMenuPicker("Recipe", valueName: model.selectedRecipe?.name ?? model.draft.name, selection: Binding(
                get: { model.selectedRecipeID },
                set: { model.selectRecipe($0) }
            )) {
                ForEach(model.availableRecipes) { recipe in
                    Text(recipe.name).tag(recipe.id)
                }
            }
            .accessibilityIdentifier("exportQueueRecipePicker")

            if model.hasUnsavedChanges {
                Text(model.isDraftReadOnly
                     ? "Edited. Save as a new recipe to keep these settings."
                     : "Edited. Update the recipe or revert.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    saveAsName = model.hasUnsavedChanges ? "" : "\(model.draft.name) copy"
                    isSaveAsPresented = true
                } label: {
                    Text("Save as New…").minimumHitTarget(alignment: .leading)
                }
                .accessibilityIdentifier("exportQueueSaveRecipe")

                if !model.isDraftReadOnly && model.hasUnsavedChanges {
                    Spacer()
                    Button { model.updateSelectedRecipe() } label: { Text("Update").minimumHitTarget() }
                        .accessibilityIdentifier("exportQueueUpdateRecipe")
                }

                if model.hasUnsavedChanges {
                    Spacer()
                    Button { model.revertDraft() } label: { Text("Revert").minimumHitTarget() }
                        .accessibilityIdentifier("exportQueueRevertRecipe")
                }

                if !(model.selectedRecipe?.isBuiltIn ?? true) {
                    Spacer()
                    Button(role: .destructive) { isDeleteConfirmationPresented = true } label: { Text("Delete").minimumHitTarget() }
                        .accessibilityIdentifier("exportQueueDeleteRecipe")
                }
            }
            .buttonStyle(.borderless)

            if let deleted = model.recentlyDeletedRecipe {
                HStack {
                    Text("Deleted \"\(deleted.name)\"")
                        .font(.footnote)
                    Spacer()
                    Button { model.undoDeleteRecipe() } label: { Text("Undo").minimumHitTarget() }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("exportQueueUndoDeleteRecipe")
                }
            }
        } header: {
            Text("Recipe")
        }
        .disabled(model.isEditingLocked)
    }

    // MARK: Variants

    private var variantsSection: some View {
        Section {
            ForEach(model.variantSlots) { slot in
                let variant = model.context.variantSet.variant(for: slot)
                Toggle(isOn: Binding(
                    get: { model.isSlotSelected(slot) },
                    set: { _ in model.toggleSlot(slot) }
                )) {
                    HStack(spacing: 6) {
                        Text("\(slot.displayLetter) · \(variant?.name ?? slot.defaultName)")
                        if model.context.variantSet.preferredSlot == slot {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                                .accessibilityLabel("Preferred, your pick")
                        }
                    }
                }
                .accessibilityIdentifier("exportQueueVariantToggle_\(slot.rawValue)")
            }

            if model.context.variantSet.preferredSlot != nil {
                Toggle("Only my preferred variant", isOn: Binding(
                    get: { model.draft.variantSelection.mode == .preferredOnly },
                    set: { model.setPreferredOnly($0) }
                ))
                .accessibilityIdentifier("exportQueuePreferredOnlyToggle")
            }
        } header: {
            Text("Variants")
        }
        .disabled(model.isEditingLocked)
    }

    // MARK: Sizes

    /// The width x height row needs about 360 pt; from xxLarge text up it
    /// stacks so no part of it is squeezed.
    private var stacksCustomSizeRow: Bool {
        dynamicTypeSize >= .xxLarge
    }

    private var sizesSection: some View {
        Section {
            ForEach(model.draft.sizes) { size in
                AnyLayout(stacksCustomSizeRow
                          ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                          : AnyLayout(HStackLayout())) {
                    Text(size.displayName)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("exportQueueSizeRow_\(size.token)")
                    Button(role: .destructive) {
                        model.removeSize(size)
                    } label: {
                        Image(systemName: "minus.circle")
                            .minimumHitTarget()
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(size.width) by \(size.height)")
                    .accessibilityIdentifier("exportQueueRemoveSize_\(size.token)")
                }
            }

            Menu {
                ForEach(ThumbnailExportPreset.all) { preset in
                    Button("\(preset.name) · \(preset.size.displayText)") {
                        model.addSize(preset: preset)
                    }
                }
            } label: {
                // A wrapping label: Label inside a Form menu stays on one line.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "plus.circle")
                        .accessibilityHidden(true)
                    Text("Add Preset Size")
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("exportQueueAddSize")

            // Side by side when it fits, stacked at large text sizes.
            AnyLayout(stacksCustomSizeRow
                      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                      : AnyLayout(HStackLayout())) {
                TextField("Width", value: $customWidth, format: .number)
                    .keyboardType(.numberPad)
                    .frame(
                        minWidth: 64,
                        maxWidth: stacksCustomSizeRow ? .infinity : 120,
                        minHeight: 44
                    )
                    .accessibilityIdentifier("exportQueueCustomWidth")
                    .accessibilityLabel("Custom width")
                if !stacksCustomSizeRow {
                    Text("x")
                        .fixedSize()
                        .accessibilityHidden(true)
                }
                TextField("Height", value: $customHeight, format: .number)
                    .keyboardType(.numberPad)
                    .frame(
                        minWidth: 64,
                        maxWidth: stacksCustomSizeRow ? .infinity : 120,
                        minHeight: 44
                    )
                    .accessibilityIdentifier("exportQueueCustomHeight")
                    .accessibilityLabel("Custom height")
                Spacer()
                Button {
                    model.addCustomSize(width: customWidth, height: customHeight)
                } label: {
                    Text("Add Custom")
                        .fixedSize(horizontal: false, vertical: true)
                        .minimumHitTarget()
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("exportQueueAddCustomSize")
            }

            Toggle("Add size to file names", isOn: Binding(
                get: { model.draft.namingIncludesSizeToken },
                set: { model.setIncludesSizeToken($0) }
            ))
        } header: {
            Text("Sizes")
        } footer: {
            Text("Sizes must match each variant's canvas shape. Nothing is cropped or stretched.")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(model.isEditingLocked)
    }

    // MARK: Format & budget

    private var formatBinding: Binding<ThumbnailExportFormat> {
        Binding(
            get: { model.draft.format ?? .jpeg },
            set: { model.setFormat($0) }
        )
    }

    private var formatOptions: some View {
        ForEach(ThumbnailExportFormat.allCases) { format in
            Text(format.displayName).tag(format)
        }
    }

    private var formatSection: some View {
        Section {
            Picker("Format", selection: formatBinding) {
                formatOptions
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("exportQueueFormatPicker")

            if model.draft.format?.supportsCompressionQuality ?? true {
                Stepper(
                    "Quality \(Int((model.draft.compressionQuality * 100).rounded()))%",
                    value: Binding(
                        get: { model.draft.compressionQuality },
                        set: { model.setQuality($0) }
                    ),
                    in: ThumbnailExportRecipe.qualityRange,
                    step: 0.05
                )
                .accessibilityIdentifier("exportQueueQualityStepper")
            }

            Toggle("Fit under a file size", isOn: Binding(
                get: { model.draft.fileSizeBudget != nil },
                set: { model.setBudgetEnabled($0) }
            ))
            .accessibilityIdentifier("exportQueueBudgetToggle")

            if let budget = model.draft.fileSizeBudget {
                Stepper(
                    "Max \(String(format: "%.1f", Double(budget.maxBytes) / 1_000_000)) MB",
                    value: Binding(
                        get: { Double(budget.maxBytes) / 1_000_000 },
                        set: { model.setBudgetMegabytes($0) }
                    ),
                    in: 0.1...50,
                    step: 0.1
                )
                .accessibilityIdentifier("exportQueueBudgetField")

                Stepper(
                    "Lowest quality \(Int((budget.qualityFloor * 100).rounded()))%",
                    value: Binding(
                        get: { budget.qualityFloor },
                        set: { model.setQualityFloor($0) }
                    ),
                    in: ThumbnailExportFileSizeBudget.minimumQualityFloor...1.0,
                    step: 0.05
                )
                .accessibilityIdentifier("exportQueueQualityFloorStepper")

                if model.draft.format == .png {
                    Text(ThumbnailExportFileSizeFitter.pngOverBudgetMessage)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Format")
        } footer: {
            Text("Only quality is lowered to fit a budget, never the size or format. A file that still doesn't fit is reported, not written.")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(model.isEditingLocked)
    }

    // MARK: Destination

    private var destinationSection: some View {
        Section {
            Text(model.snapshot.displayName)
                .accessibilityIdentifier("exportQueueDestinationLabel")

            if let note = model.destinationNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = model.destinationError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                Button { isFolderPickerPresented = true } label: { Text("Choose Folder…").minimumHitTarget(alignment: .leading) }
                    .accessibilityIdentifier("exportQueueChooseFolder")
                Spacer()
                Button { model.usePhotos() } label: { Text("Photos").minimumHitTarget() }
                    .accessibilityIdentifier("exportQueueDestinationPhotos")
            }
            .buttonStyle(.borderless)

            if model.snapshot.supportsFileNames {
                Picker("If a file exists", selection: Binding(
                    get: { model.draft.overwritePolicy },
                    set: { model.setOverwritePolicy($0) }
                )) {
                    ForEach(ThumbnailExportOverwritePolicy.allCases) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                .accessibilityIdentifier("exportQueueOverwritePicker")
            }
        } header: {
            Text("Destination")
        }
        .disabled(model.isEditingLocked)
    }

    // MARK: Review

    private var reviewSection: some View {
        Section {
            ForEach(model.plan.jobs) { job in
                jobRow(job)
            }
        } header: {
            Text("Review")
        } footer: {
            Text(model.plan.summary)
                .accessibilityIdentifier("exportQueueSummary")
        }
    }

    private func jobRow(_ job: ThumbnailExportQueueJob) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(job.targetFileName)
                .font(.subheadline.monospaced())
                .fixedSize(horizontal: false, vertical: true)
            Text("\(job.slot.displayLetter) · \(job.size.width) x \(job.size.height) · \(job.format.displayName) · \(job.destinationDisplayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let status = statusText(for: job) {
                Text(status.text)
                    .font(.caption)
                    .foregroundStyle(status.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("exportQueueJob_\(job.slot.rawValue)_\(job.size.width)x\(job.size.height)")
    }

    private func statusText(for job: ThumbnailExportQueueJob) -> (text: String, color: Color)? {
        if let blocked = job.blockedReason {
            return ("Blocked: \(blocked.message)", .red)
        }
        switch model.runner.state(for: job.id) {
        case .pending?:
            return ("Waiting", .secondary)
        case .running?:
            return ("Exporting…", .blue)
        case .succeeded(let outcome)?:
            let size = ThumbnailExportFileSize(byteCount: outcome.bytes).formatted
            var text = "Saved \(outcome.fileName) · \(size)"
            if outcome.qualityReduced {
                text += " · quality reduced to \(Int((outcome.quality * 100).rounded()))%"
            }
            return (text, .green)
        case .failed(let message)?:
            return ("Failed: \(message)", .red)
        case .skipped(let reason)?:
            return ("Skipped: \(reason)", .secondary)
        case .notRun?:
            return ("Not run", .orange)
        case nil:
            return job.conflict.badge.map { ($0, .orange) }
        }
    }

    // MARK: Run bar

    private var runBar: some View {
        VStack(spacing: 8) {
            if model.runner.isRunning {
                ProgressView(value: model.runner.progress)
                Text(model.runner.isCancelling
                     ? "Cancelling after the current file…"
                     : "Exporting \(min(model.runner.completedCount + 1, model.runner.totalCount)) of \(model.runner.totalCount)")
                    .font(.footnote)
                    .accessibilityIdentifier("exportQueueProgress")
                Button(role: .cancel) { model.cancel() } label: { Text("Cancel").minimumHitTarget() }
                    .disabled(model.runner.isCancelling)
                    .accessibilityIdentifier("exportQueueCancelButton")
            } else {
                if model.runner.hasFinishedRun {
                    Text(model.runner.resultSummary)
                        .font(.footnote.weight(.semibold))
                        .accessibilityIdentifier("exportQueueResult")
                }
                HStack {
                    if model.canRetry {
                        Button("Retry failed (\(model.runner.retryableJobIDs.count))") {
                            Task { await model.retryFailed() }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("exportQueueRetryFailedButton")
                    }
                    Button {
                        Task { await model.run() }
                    } label: {
                        Text("Export \(model.plan.runnableJobs.count) File\(model.plan.runnableJobs.count == 1 ? "" : "s")")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ProminentActionButtonStyle())
                    .disabled(!model.canRun)
                    .accessibilityIdentifier("exportQueueRunButton")
                }
            }
        }
        .padding()
        .background(.bar)
    }
}
