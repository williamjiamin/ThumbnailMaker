//
//  ProjectLibraryView.swift
//  ThumbnailMaker
//
//  FEATURE-01: project library sheet (search, open, rename, duplicate,
//  trash/restore, permanent delete) and the toolbar entry point that also
//  shows the autosave state.
//

import SwiftUI
import UIKit

/// Toolbar button: opens the library and shows whether the current project
/// is saved, saving, or failed to save.
struct ProjectToolbarButton: View {
    let projectName: String
    let saveState: DraftSaveState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "folder")
                statusBadge
                    .offset(x: 4, y: 3)
            }
        }
        .accessibilityIdentifier("projectsButton")
        .accessibilityLabel("Projects")
        .accessibilityValue("\(projectName), \(ProjectSaveStatusText.text(for: saveState))")
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch saveState {
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.red)
        case .saving:
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
        default:
            EmptyView()
        }
    }
}

enum ProjectSaveStatusText {
    static func text(for state: DraftSaveState) -> String {
        switch state {
        case .idle:
            return "Not saved yet"
        case .saving:
            return "Saving…"
        case .saved(let date):
            return "Saved \(date.formatted(date: .omitted, time: .shortened))"
        case .failed:
            return "Save failed"
        }
    }
}

struct ProjectLibraryView<Editor: ThumbnailProjectEditing & ObservableObject>: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var editor: Editor
    @ObservedObject var library: ThumbnailProjectLibrary

    @State private var searchText = ""
    @State private var renamingProject: ThumbnailProjectSummary?
    @State private var renameText = ""
    @State private var purgeCandidate: ThumbnailProjectSummary?
    @State private var showsTrash = false
    // FEATURE-06: .thumbproj import/export
    @State private var isProjectImporterPresented = false
    @State private var isProjectExporterPresented = false
    @State private var projectExportDocument: ThumbnailProjectFileDocument?
    @State private var transferBanner: ProjectTransferBanner?
    /// SHELL: when the library is a tab, opening a project hands control to
    /// the editor through this instead of dismissing a sheet.
    var onProjectOpened: (() -> Void)? = nil
    var showsDoneButton = true
    /// GAPS: optional content above the search field (the Projects tab puts
    /// its Simple / Premium switcher here).
    var header: AnyView? = nil

    private func finish() {
        if let onProjectOpened {
            onProjectOpened()
        } else {
            dismiss()
        }
    }

    private var mode: ThumbnailDocumentEditorMode { Editor.projectEditorMode }

    /// APP-07: an in-content search field. Unlike the navigation-bar search
    /// bar, it grows with Dynamic Type instead of clipping its placeholder.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            // Vertical axis: the placeholder wraps instead of clipping at
            // large text sizes.
            TextField("Search projects", text: $searchText, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("projectSearchField")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .minimumHitTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let header { header }
                    searchField
                    statusBanner
                    if let transferBanner { // FEATURE-06
                        ProjectTransferBannerView(banner: transferBanner) { self.transferBanner = nil }
                    }
                    if editor.showingSaveAlert, let actionError = editor.saveError {
                        errorBanner(actionError) {
                            editor.showingSaveAlert = false
                            editor.saveError = nil
                        }
                        .accessibilityIdentifier("projectActionError")
                    }
                    if let libraryError = library.libraryError {
                        errorBanner(libraryError) { library.libraryError = nil }
                    }
                    projectGrid
                    trashSection
                }
                .padding(20)
            }
            .modifier(ProjectPackageExporterModifier( // FEATURE-06
                isPresented: $isProjectExporterPresented,
                document: $projectExportDocument,
                banner: $transferBanner
            ))
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDoneButton {
                    ToolbarItem(placement: .cancellationAction) {
                        SheetToolbarButton(.done) { dismiss() }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if editor.createNewProject() {
                            finish()
                        }
                    } label: {
                        Label("New Project", systemImage: "plus")
                    }
                    .accessibilityIdentifier("newProjectButton")
                }
                ToolbarItem(placement: .topBarTrailing) { // FEATURE-06
                    Button {
                        transferBanner = nil
                        isProjectImporterPresented = true
                    } label: {
                        Label("Import Project", systemImage: "square.and.arrow.down")
                    }
                    .accessibilityIdentifier("importProjectButton")
                }
            }
            .alert(
                "Rename Project",
                isPresented: Binding(
                    get: { renamingProject != nil },
                    set: { if !$0 { renamingProject = nil } }
                )
            ) {
                TextField("Project name", text: $renameText)
                    .accessibilityIdentifier("projectRenameField")
                Button("Cancel", role: .cancel) { renamingProject = nil }
                Button("Rename") {
                    if let project = renamingProject {
                        editor.renameProject(project.id, to: renameText)
                    }
                    renamingProject = nil
                }
            }
            .confirmationDialog(
                "Delete Permanently?",
                isPresented: Binding(
                    get: { purgeCandidate != nil },
                    set: { if !$0 { purgeCandidate = nil } }
                ),
                titleVisibility: .visible,
                presenting: purgeCandidate
            ) { project in
                Button("Delete \"\(project.name)\"", role: .destructive) {
                    editor.purgeProject(project.id)
                    purgeCandidate = nil
                }
                Button("Cancel", role: .cancel) { purgeCandidate = nil }
            } message: { _ in
                Text("This removes the project and its files from this device. It can't be undone.")
            }
        }
        .fileImporter( // FEATURE-06
            isPresented: $isProjectImporterPresented,
            allowedContentTypes: [.thumbnailMakerProject],
            allowsMultipleSelection: false
        ) { result in
            handleProjectImport(result)
        }
        .accessibilityIdentifier("projectLibrarySheet")
    }

    // MARK: Sections

    @ViewBuilder
    private var statusBanner: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(editor.activeProjectName.isEmpty ? "Current project" : editor.activeProjectName)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ProjectSaveStatusText.text(for: editor.draftSaveState))
                    .font(.caption)
                    .foregroundStyle(editor.draftSaveState.failureMessage == nil ? Color.secondary : Color.red)
                    .accessibilityIdentifier("projectSaveStatus")
            }
            Spacer()
            if editor.draftSaveState.failureMessage != nil {
                Button("Retry") { editor.retryDraftSave() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("projectRetrySaveButton")
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func errorBanner(_ message: String, dismissAction: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
            Spacer(minLength: 0)
            Button(action: dismissAction) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var projectGrid: some View {
        let projects = library.projects(matching: searchText, editorMode: mode)
        if projects.isEmpty {
            Text(searchText.isEmpty ? "No projects yet." : "No projects match \"\(searchText)\".")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(projects) { project in
                    ProjectCardView(
                        project: project,
                        isCurrent: project.id == editor.activeProjectID,
                        previewRevision: library.previewRevisions[project.id, default: 0],
                        loadPreview: { await library.previewData(for: project.id) },
                        open: { open(project) }
                    )
                    .contextMenu { liveActions(for: project) }
                    .overlay(alignment: .topTrailing) {
                        Menu {
                            liveActions(for: project)
                        } label: {
                            Image(systemName: "ellipsis.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.55))
                                .font(.title3)
                                .padding(6)
                        }
                        .accessibilityLabel("Actions for \(project.name)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func liveActions(for project: ThumbnailProjectSummary) -> some View {
        if project.isReadable {
            Button {
                open(project)
            } label: {
                Label("Open", systemImage: "arrow.up.forward.app")
            }
            Button {
                renameText = project.name
                renamingProject = project
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button { // FEATURE-06
                exportPackage(for: project)
            } label: {
                Label("Export Project…", systemImage: "square.and.arrow.up")
            }
        }
        Button {
            editor.duplicateProject(project.id)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        Button(role: .destructive) {
            editor.trashProject(project.id)
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }

    @ViewBuilder
    private var trashSection: some View {
        let trashed = library.trashedProjects(editorMode: mode)
        if !trashed.isEmpty {
            DisclosureGroup(isExpanded: $showsTrash) {
                VStack(spacing: 8) {
                    ForEach(trashed) { project in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let deletedAt = project.metadata.deletedAt {
                                    Text("Trashed \(deletedAt.formatted(.relative(presentation: .named)))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Restore") {
                                editor.restoreProject(project.id)
                            }
                            .buttonStyle(.bordered)
                            Button(role: .destructive) {
                                purgeCandidate = project
                            } label: {
                                Image(systemName: "trash.slash")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Delete \(project.name) permanently")
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Label("Trash (\(trashed.count))", systemImage: "trash")
                    .font(.headline)
            }
            .accessibilityIdentifier("projectTrashSection")
        }
    }

    // MARK: FEATURE-06 import/export

    private func exportPackage(for project: ThumbnailProjectSummary) {
        transferBanner = nil
        switch editor.exportProjectPackage(project.id) {
        case .success(let document):
            projectExportDocument = document
            isProjectExporterPresented = true
        case .failure(let error):
            transferBanner = ProjectTransferBanner(message: error.userMessage, isError: true)
        }
    }

    private func handleProjectImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            guard (error as NSError).code != NSUserCancelledError else { return }
            transferBanner = ProjectTransferBanner(
                message: ThumbnailProjectPackageError.unreadable(error.localizedDescription).userMessage,
                isError: true
            )
        case .success(let urls):
            guard let url = urls.first else { return }
            switch editor.importProjectPackage(from: url) {
            case .success(let outcome):
                if outcome.plan.notices.isEmpty && outcome.warnings.isEmpty {
                    finish()
                } else {
                    transferBanner = ProjectTransferBanner(message: outcome.message, isError: false)
                }
            case .failure(let error):
                transferBanner = ProjectTransferBanner(message: error.userMessage, isError: true)
            }
        }
    }

    private func open(_ project: ThumbnailProjectSummary) {
        if editor.switchToProject(project.id) {
            finish()
        }
    }
}

private struct ProjectCardView: View {
    let project: ThumbnailProjectSummary
    let isCurrent: Bool
    let previewRevision: Int
    let loadPreview: () async -> Data?
    let open: () -> Void

    @State private var previewImage: UIImage?

    private var statusText: String {
        isCurrent
            ? "Open now"
            : "Edited \(project.metadata.updatedAt.formatted(.relative(presentation: .named)))"
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(uiColor: .tertiarySystemFill))
                    if !project.isReadable {
                        VStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title2)
                            Text("Couldn't open")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.orange)
                    } else if let previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.accentColor, lineWidth: 3)
                    }
                }

                Text(project.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
        .disabled(!project.isReadable)
        // APP-07: one element per card that says which project is open.
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("projectCard-\(project.id.uuidString)")
        .accessibilityLabel(project.name)
        .accessibilityValue(project.isReadable ? statusText : "Can't be opened")
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(project.isReadable ? "Opens this project." : "")
        .accessibilityAction {
            if project.isReadable { open() }
        }
        .task(id: previewRevision) {
            if let data = await loadPreview() {
                previewImage = UIImage(data: data)
            }
        }
    }
}
