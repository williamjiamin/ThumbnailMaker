//  ContentView.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/22.
//

import SwiftUI
import Foundation

/// SHELL (1.1.0 rebuild): the root tab shell - Create / Projects / Settings.
/// Create shows the "Create a Thumbnail" home, the Quick Create wizard and
/// the editors; Projects is the project library; Settings is Settings.
/// The shell owns both editor models, so moving between Home, the editors
/// and the Projects tab never drops unsaved work.
struct ContentView: View {
    @State private var selectedTab: AppShellTab = .create
    @State private var createStage: CreateStage
    @State private var isQuickCreatePresented = false
    /// Held (not observed) so the shell does not re-render - and re-inject
    /// its environment into the editor - on every keystroke; the pieces that
    /// need live editor state observe it themselves.
    @State private var simpleEditor = SimpleMakerViewModel(projectLibrary: .shared)
    /// Created on first use, like the old lazily-built Premium tab.
    @State private var premiumEditor: PremiumMakerViewModel?
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @State private var projectsEditorFilter: ProjectsTabEditorFilter = .simple // GAPS

    init() {
        let initialStage = CreateStage.initial(arguments: ProcessInfo.processInfo.arguments)
        _createStage = State(initialValue: initialStage)
        if initialStage == .premiumEditor {
            _premiumEditor = State(initialValue: PremiumMakerViewModel(projectLibrary: .shared))
        }
    }
    
    var body: some View {
        TabView(selection: tabSelection) {
            createTab
                .tabItem {
                    Label("Create", systemImage: "paintbrush.pointed.fill")
                        .accessibilityIdentifier("createTab")
                }
                .tag(AppShellTab.create)

            projectsTab
                .tabItem {
                    Label("Projects", systemImage: "folder.fill")
                        .accessibilityIdentifier("projectsTab")
                }
                .tag(AppShellTab.projects)

            SettingsView(showsDoneButton: false) {
                showEditor(.simpleEditor)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
                    .accessibilityIdentifier("settingsTab")
            }
            .tag(AppShellTab.settings)
        }
        .onChange(of: projectsEditorFilter) { _, filter in // GAPS
            if filter == .premium, premiumEditor == nil {
                premiumEditor = PremiumMakerViewModel(projectLibrary: .shared)
            }
        }
        .sheet(isPresented: $isQuickCreatePresented) {
            QuickCreateWizardView(
                brandKits: simpleEditor.brandKitLibrary.kits,
                allowsPremiumFonts: purchaseManager.canAccessPremium,
                onCancel: { isQuickCreatePresented = false },
                onFinish: finishQuickCreate
            )
            .interactiveDismissDisabled()
        }
        #if DEBUG && targetEnvironment(macCatalyst)
        .task {
            await MacAppStoreScreenshotRenderer.renderIfRequested()
        }
        #endif
    }

    @ViewBuilder
    private var createTab: some View {
        switch createStage {
        case .home:
            ShellCreateHome(
                editor: simpleEditor,
                onQuickCreate: { isQuickCreatePresented = true },
                onStartFromScratch: {
                    simpleEditor.startFromScratch()
                    showEditor(.simpleEditor)
                },
                onContinue: { showEditor(.simpleEditor) },
                onOpenProEditor: { showEditor(.premiumEditor) }
            )
        case .simpleEditor:
            SimpleMakerView(viewModel: simpleEditor)
                .environment(\.showCreateHome, showHome)
        case .premiumEditor:
            if let premiumEditor {
                PremiumMakerView(viewModel: premiumEditor)
                    .environment(\.showCreateHome, showHome)
            }
        }
    }

    /// GAPS: the Projects tab lists Simple AND Premium projects (switched
    /// with a segmented control) and opens each in its own editor.
    @ViewBuilder
    private var projectsTab: some View {
        switch projectsEditorFilter {
        case .simple:
            ShellProjectsTab(editor: simpleEditor, filter: $projectsEditorFilter) {
                showEditor(.simpleEditor)
            }
        case .premium:
            if let premiumEditor {
                ShellProjectsTab(editor: premiumEditor, filter: $projectsEditorFilter) {
                    showEditor(.premiumEditor)
                }
            } else {
                // Built on first switch (see onChange below).
                ProgressView()
            }
        }
    }

    private var showHome: () -> Void {
        {
            simpleEditor.commitEditorStateNow()
            premiumEditor?.commitEditorStateNow()
            createStage = .home
        }
    }

    /// Re-tapping the selected Create tab returns to Home (the standard
    /// "tap the tab to go back to its root" gesture).
    private var tabSelection: Binding<AppShellTab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if newTab == .create, selectedTab == .create, createStage != .home {
                    showHome()
                }
                selectedTab = newTab
            }
        )
    }

    private func showEditor(_ stage: CreateStage) {
        if stage == .premiumEditor, premiumEditor == nil {
            premiumEditor = PremiumMakerViewModel(projectLibrary: .shared)
        }
        createStage = stage
        selectedTab = .create
    }

    private func finishQuickCreate(_ draft: QuickCreateDraft, action: QuickCreateFinishAction) {
        let succeeded = simpleEditor.finishQuickCreate(draft)
        if succeeded {
            // FEATURE-13: the wizard counts as onboarding; never double up.
            FirstExportGuideController.shared.recordQuickCreateCompleted()
        }
        isQuickCreatePresented = false
        showEditor(.simpleEditor)

        guard succeeded, action == .saveToPhotos else { return }
        let configuration = simpleEditor.simpleMakerConfiguration
        let size = configuration.exportOptions.outputSize.cgSize
        let content = PreviewComponentView(
            simpleMakerConfiguration: .constant(configuration),
            width: size.width,
            height: size.height
        )
        Task {
            await simpleEditor.saveImageWithOverlay(content: content)
        }
    }
}

/// Create home fed with live editor state (for "Continue ...").
private struct ShellCreateHome: View {
    @ObservedObject var editor: SimpleMakerViewModel
    let onQuickCreate: () -> Void
    let onStartFromScratch: () -> Void
    let onContinue: () -> Void
    let onOpenProEditor: () -> Void

    private var continueProjectName: String? {
        guard editor.hasWorkInProgress else { return nil }
        let name = editor.activeProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "current design" : name
    }

    var body: some View {
        CreateHomeView(
            continueProjectName: continueProjectName,
            onQuickCreate: onQuickCreate,
            onStartFromScratch: onStartFromScratch,
            onContinue: onContinue,
            onOpenProEditor: onOpenProEditor
        )
    }
}

/// The Projects tab: the project library of the chosen editor. Projects
/// stay grouped by editor (a Premium project keeps its profile photo and
/// batch settings), and opening one switches to the editor it belongs to.
private struct ShellProjectsTab<Editor: ThumbnailProjectEditing & ObservableObject>: View {
    @ObservedObject var editor: Editor
    @Binding var filter: ProjectsTabEditorFilter
    let onProjectOpened: () -> Void

    private var switcher: some View {
        Picker("Editor", selection: $filter) {
            ForEach(ProjectsTabEditorFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("projectsEditorPicker")
    }

    var body: some View {
        if let projectLibrary = editor.projectLibrary, editor.isProjectLibraryAvailable {
            ProjectLibraryView(
                editor: editor,
                library: projectLibrary,
                onProjectOpened: onProjectOpened,
                showsDoneButton: false,
                header: AnyView(switcher)
            )
        } else {
            NavigationStack {
                VStack(spacing: 16) {
                    switcher
                        .padding(.horizontal, 20)
                    ContentUnavailableView(
                        "Projects Unavailable",
                        systemImage: "folder",
                        description: Text("Projects are saved on this device once the editor can store them.")
                    )
                }
                .navigationTitle("Projects")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

#Preview {
    ContentView()
}

#if DEBUG && targetEnvironment(macCatalyst)
private enum MacAppStoreScreenshotRenderer {
    private static let width: CGFloat = 1280
    private static let height: CGFloat = 800

    @MainActor
    static func renderIfRequested() {
        guard let path = renderPathArgument() else {
            return
        }

        let outputURL = URL(fileURLWithPath: path)

        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let content = MacAppStoreScreenshotView()
                .frame(width: width, height: height)

            let renderer = ImageRenderer(content: content)
            renderer.proposedSize = ProposedViewSize(width: width, height: height)
            renderer.scale = 1
            renderer.colorMode = .nonLinear

            guard let image = renderer.uiImage, let data = image.pngData() else {
                fputs("Could not render Mac App Store screenshot.\n", stderr)
                exit(1)
            }

            try data.write(to: outputURL, options: .atomic)
            exit(0)
        } catch {
            fputs("Could not write Mac App Store screenshot: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func renderPathArgument() -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-RenderMacAppStoreScreenshot") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard valueIndex < arguments.endIndex else {
            return nil
        }

        let value = arguments[valueIndex]
        return value.hasPrefix("-") ? nil : value
    }
}

private struct MacAppStoreScreenshotView: View {
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            editor
            inspector
        }
        .frame(width: 1280, height: 800)
        .background(Color(uiColor: .systemBackground))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Simple Thumbnail")
                .font(.system(size: 22, weight: .bold))

            sidebarButton("Premium", systemImage: "star.fill", selected: true)
            sidebarButton("Templates", systemImage: "square.grid.2x2", selected: false)
            sidebarButton("Brand Kit", systemImage: "paintpalette.fill", selected: false)
            sidebarButton("Export", systemImage: "square.and.arrow.up", selected: false)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("Canvas")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("YouTube Thumbnail")
                    .font(.headline)
                Text("1280 x 720")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 220, height: 800)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Premium Editor")
                    .font(.system(size: 28, weight: .bold))
                Spacer()
                Label("Snap", systemImage: "scope")
                Label("Undo", systemImage: "arrow.uturn.backward")
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(uiColor: .tertiarySystemBackground))

                thumbnailCanvas
                    .frame(width: 720, height: 405)
                    .shadow(color: .black.opacity(0.22), radius: 22, y: 14)

                alignmentGuide(x: 640, y: 386, vertical: true)
                alignmentGuide(x: 628, y: 400, vertical: false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            layerStrip
        }
        .padding(24)
        .frame(width: 740, height: 800)
        .background(Color(uiColor: .systemBackground))
    }

    private var thumbnailCanvas: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.14),
                    Color(red: 0.10, green: 0.35, blue: 0.65),
                    Color(red: 1.00, green: 0.72, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(.white.opacity(0.16))
                .frame(width: 360, height: 360)
                .offset(x: 238, y: -90)

            VStack(alignment: .leading, spacing: 10) {
                Text("AI THUMBNAIL")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(.yellow)
                Text("BIG REVEAL")
                    .font(.system(size: 64, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.75), radius: 3, x: 3, y: 4)
                Text("Before / After in 10 minutes")
                    .font(.system(size: 24, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .foregroundStyle(.black)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 46)

            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom))
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 102))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .frame(width: 172, height: 172)
            .overlay(Circle().stroke(.white, lineWidth: 8))
            .offset(x: 228, y: 92)

            selectionChrome
                .frame(width: 392, height: 140)
                .offset(x: -136, y: -28)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var selectionChrome: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.white, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))

            let handlePoints = [
                CGPoint(x: -196, y: -70),
                CGPoint(x: 196, y: -70),
                CGPoint(x: -196, y: 70),
                CGPoint(x: 196, y: 70)
            ]

            ForEach(handlePoints.indices, id: \.self) { index in
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .shadow(radius: 2)
                    .offset(x: handlePoints[index].x, y: handlePoints[index].y)
            }

            Image(systemName: "arrow.clockwise")
                .font(.system(size: 18, weight: .bold))
                .padding(8)
                .foregroundStyle(.black)
                .background(.white)
                .clipShape(Circle())
                .offset(x: 0, y: -92)
        }
    }

    private var layerStrip: some View {
        HStack(spacing: 12) {
            layerChip("Text", "BIG REVEAL", selected: true)
            layerChip("Image", "Face Cutout", selected: false)
            layerChip("Shape", "Gradient Glow", selected: false)
            layerChip("Sticker", "Arrow", selected: false)
        }
        .frame(height: 84)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Inspector")
                .font(.system(size: 24, weight: .bold))

            inspectorGroup("Layer", rows: [
                ("Name", "Headline"),
                ("Blend", "Normal"),
                ("Opacity", "100%")
            ])

            inspectorGroup("Text Style", rows: [
                ("Font", "Impact"),
                ("Outline", "8 px"),
                ("Shadow", "Strong")
            ])

            inspectorGroup("Export", rows: [
                ("Format", "PNG"),
                ("Preset", "YouTube"),
                ("Quality", "100%")
            ])

            Spacer()

            HStack {
                Label("Ready", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                Spacer()
                Text("Small preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 320, height: 800)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func sidebarButton(_ title: String, systemImage: String, selected: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(selected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func layerChip(_ title: String, _ subtitle: String, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.headline)
        }
        .padding(14)
        .frame(width: 162, height: 72, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.16) : Color(uiColor: .secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func inspectorGroup(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            ForEach(rows, id: \.0) { row in
                HStack {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(row.1)
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
            }
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func alignmentGuide(x: CGFloat, y: CGFloat, vertical: Bool) -> some View {
        Rectangle()
            .fill(Color.cyan.opacity(0.75))
            .frame(width: vertical ? 2 : 640, height: vertical ? 440 : 2)
            .position(x: x, y: y)
    }
}
#endif
