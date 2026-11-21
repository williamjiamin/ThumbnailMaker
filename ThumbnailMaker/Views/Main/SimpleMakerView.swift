//
//  SimpleMakerView.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/28.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct SimpleMakerView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var viewModel: SimpleMakerViewModel
    @Environment(\.showCreateHome) private var showCreateHome // SHELL
    @ObservedObject private var templateLibrary = PersonalTemplateLibraryModel.shared // FEATURE-05
    @State private var isProjectLibraryPresented = false // FEATURE-01
    @StateObject private var purchaseManager = PurchaseManager.shared
    @FocusState private var isFocused: Bool
    @State private var isSettingsPresented: Bool = false
    @State private var isTemplateGalleryPresented: Bool = false
    @State private var isBrandKitEditorPresented: Bool = false
    @State private var showsSafeZoneGuide = true
    @State private var selectedLayer: ThumbnailLayerSelection = .textOverlay
    @State private var arrangeState = ThumbnailArrangeUIState() // FEATURE-07
    @State private var isVariantComparePresented = false // FEATURE-02
    @State private var isExportQueuePresented = false // FEATURE-10
    @State private var isSeriesPresented = false // FEATURE-15
    @State private var isAdjustmentsPresented = false // FEATURE-14
    @State private var isEmojiPickerPresented = false // DONOR
    @State private var isDrawingPresented = false // DONOR
    @State private var isComparingAdjustments = false // FEATURE-14
    @State private var cutoutRefinementTarget: ThumbnailCutoutTarget? // FEATURE-11
    @State private var isBackgroundSheetPresented = false // EDITOR
    @State private var assetLibrarySection: AssetLibrarySection? // EDITOR
    @State private var isVideoFrameGrabberPresented = false // FRAME
    @State private var opensVideoGrabberAfterLibrary = false // FRAME
    @State private var opensBrandKitAfterLibrary = false // GAPS
    @ObservedObject private var firstExportGuide = FirstExportGuideController.shared // FEATURE-13
    @State private var isArrangeExpanded = CompactEditorLayoutPolicy.expandsArrangePanelByDefault // APP-08
    @State private var variantsSectionExpandedOverride: Bool? // APP-08
    @Namespace private var bottomID
    @Namespace private var topID

    /// SHELL: the app shell owns the editor model so Quick Create and the
    /// Projects tab work on the same document; previews make their own.
    init(viewModel: SimpleMakerViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? SimpleMakerViewModel(projectLibrary: .shared))
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                makerContent(in: geometry)
                .scrollDismissesKeyboard(.immediately)
                .simultaneousGesture(
                    TapGesture().onEnded { _ in
                        isFocused = false
                    }
                )
            }
            .navigationTitle("Simple Maker")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { // SHELL
                    // On a phone the bar is full (a fourth leading item clips
                    // the title); there, re-tapping the Create tab goes Home.
                    if let showCreateHome, horizontalSizeClass == .regular {
                        CreateHomeToolbarButton {
                            isFocused = false
                            viewModel.commitEditorStateNow()
                            showCreateHome()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        isSettingsPresented.toggle()
                    }) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("settingsButton")
                    .accessibilityLabel("Settings")
                }
                // FEATURE-01: project library entry point + save state
                ToolbarItem(placement: .navigationBarLeading) {
                    if viewModel.isProjectLibraryAvailable {
                        ProjectToolbarButton(
                            projectName: viewModel.activeProjectName,
                            saveState: viewModel.draftSaveState
                        ) {
                            viewModel.commitEditorStateNow()
                            isProjectLibraryPresented = true
                        }
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        isFocused = false
                        isTemplateGalleryPresented = true
                    } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                    .accessibilityIdentifier("templatesButton")
                    .accessibilityLabel("Templates")

                    AdjustmentsToolbarButton(isEnabled: viewModel.hasAdjustableImages) { // FEATURE-14
                        isFocused = false
                        viewModel.commitEditorStateNow()
                        isAdjustmentsPresented = true
                    }

                    UndoRedoToolbarButtons(
                        canUndo: viewModel.canUndo,
                        canRedo: viewModel.canRedo,
                        undo: {
                            isFocused = false
                            viewModel.undo()
                        },
                        redo: {
                            isFocused = false
                            viewModel.redo()
                        }
                    )
                }
            }
        }
        .alert(isPresented: $viewModel.showingSaveAlert) {
            if let error = viewModel.saveError {
                Alert(
                    title: Text("Save Failed"),
                    message: Text(error),
                    primaryButton: viewModel.isPermissionError ? 
                        .default(Text("Open Settings"), action: {
                            viewModel.openSettings()
                        }) : .default(Text("OK")),
                    secondaryButton: .cancel(Text("Cancel"))
                )
            } else {
                Alert(
                    title: Text("Success"),
                    message: Text(viewModel.successMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
        .modifier(DonorLayerSheetsModifier(
            isEmojiPickerPresented: $isEmojiPickerPresented,
            isDrawingPresented: $isDrawingPresented,
            aspectRatio: viewModel.simpleMakerConfiguration.selectedRatio,
            addEmoji: { emoji in
                if let layer = viewModel.addEmojiSticker(emoji) { selectedLayer = layer }
            },
            addDrawing: { result in selectedLayer = viewModel.addDrawing(result) },
            drawingBackground: { size in
                PreviewComponentView(
                    simpleMakerConfiguration: $viewModel.simpleMakerConfiguration,
                    width: size.width,
                    height: size.height
                )
            }
        ))
        // FEATURE-01: project library sheet
        .sheet(isPresented: $isProjectLibraryPresented) {
            if let projectLibrary = viewModel.projectLibrary {
                ProjectLibraryView(editor: viewModel, library: projectLibrary)
            }
        }
        .onChange(of: viewModel.activeProjectID) { _, _ in
            selectedLayer = .textOverlay
        }
        // FEATURE-05: personal templates, save-as-template, style-only mode
        .sheet(isPresented: $isTemplateGalleryPresented, onDismiss: {
            templateLibrary.presentPendingWarnings()
        }) {
            TemplateGalleryView(
                personalLibrary: templateLibrary,
                currentDocument: {
                    viewModel.commitEditorStateNow()
                    return viewModel.simpleMakerConfiguration.document
                }
            ) { template, mode in
                isFocused = false
                templateLibrary.reportApplication(viewModel.applyTemplate(template, mode: mode))
                selectTextLayerIfAvailable()
                isTemplateGalleryPresented = false
            }
        }
        .templateApplicationWarningsAlert(library: templateLibrary)
        .sheet(isPresented: $isBrandKitEditorPresented) {
            BrandKitLibraryView( // FEATURE-08
                editor: viewModel,
                selectedLayerID: selectedLayer.documentLayerID,
                allowsPremiumFonts: purchaseManager.canAccessPremium
            )
        }
        .sheet(isPresented: $isBackgroundSheetPresented) { // EDITOR
            EditorBackgroundSheet(
                photoSelection: $viewModel.imageSelection,
                backgroundColor: $viewModel.simpleMakerConfiguration.backgroundColor,
                hasPhoto: viewModel.simpleMakerConfiguration.selectedImage != nil,
                commit: viewModel.commitEditorStateNow
            ) {
                // SHELL x EDITOR: the BG entry point also offers solid / gradient fills.
                BackgroundFillControlRow(
                    backgroundColor: $viewModel.simpleMakerConfiguration.backgroundColor,
                    fill: $viewModel.simpleMakerConfiguration.backgroundFill
                )
            }
        }
        .sheet(item: $assetLibrarySection, onDismiss: { // EDITOR
            // FRAME: the library hands off to the video grabber after it closes.
            if opensVideoGrabberAfterLibrary {
                opensVideoGrabberAfterLibrary = false
                isVideoFrameGrabberPresented = true
            }
            presentPendingBrandKitEditor() // GAPS
        }) { section in
            AssetLibrarySheet(
                imageLayerSelection: $viewModel.layerImageSelection,
                stickerLayerSelection: $viewModel.stickerImageSelection,
                initialSection: section,
                recentAssets: ThumbnailAssetLibrary.recentAssets(in: viewModel.simpleMakerConfiguration.layers),
                brandAssets: ThumbnailAssetLibrary.brandAssets(in: viewModel.brandKitLibrary),
                manageBrandKits: { opensBrandKitAfterLibrary = true } // GAPS
            ) { item in
                if let inserted = viewModel.insertLibraryAsset(item) {
                    selectedLayer = inserted
                }
            } openVideo: {
                opensVideoGrabberAfterLibrary = true
            }
        }
        .sheet(isPresented: $isVideoFrameGrabberPresented) { // FRAME
            VideoFrameGrabberSheet { data, destination in
                let outcome = viewModel.applyVideoFrame(data, as: destination)
                if let selection = outcome.selection { selectedLayer = selection }
                return outcome.applied
            }
        }
        .sheet(isPresented: $isAdjustmentsPresented) { // FEATURE-14
            AdjustmentsPanelView(
                editor: viewModel,
                isComparing: $isComparingAdjustments,
                initialTarget: AdjustmentsPanelView.initialTarget(for: selectedLayer, in: viewModel)
            )
        }
        .cutoutRefinementSheet(editor: viewModel, target: $cutoutRefinementTarget) // FEATURE-11
        .sheet(isPresented: $isSeriesPresented) { // FEATURE-15
            ThumbnailSeriesView(
                context: viewModel.makeSeriesContext(),
                canRender: purchaseManager.canAccessPremium,
                personalTemplates: templateLibrary.activeTemplates
            )
        }
        .sheet(isPresented: $isExportQueuePresented) { // FEATURE-10
            ExportQueueView(context: viewModel.exportQueueContext)
        }
        .sheet(isPresented: $isVariantComparePresented) { // FEATURE-02
            ThumbnailVariantCompareView(
                makeComparison: { viewModel.variantComparison(previewSize: $0) },
                readinessNote: viewModel.variantExportPlan.readinessNote,
                setPreferred: { viewModel.setPreferredVariant($0) },
                edit: { slot in
                    viewModel.selectVariant(slot)
                    normalizeSelectedLayer()
                }
            ) { pane, size in
                PreviewComponentView(
                    simpleMakerConfiguration: .constant(pane.document.makeSimpleConfiguration()),
                    width: size.width,
                    height: size.height
                )
            }
        }
        .sheet(item: $viewModel.shareItem) { item in
            ShareSheet(activityItems: [item.url], onComplete: viewModel.recordShareCompleted) // FEATURE-13
        }
        .fileExporter(
            isPresented: $viewModel.isFileExporterPresented,
            document: ThumbnailFileDocument(data: viewModel.fileExport?.data ?? Data()),
            contentType: viewModel.fileExport?.contentType ?? .png,
            defaultFilename: viewModel.fileExport?.fileName ?? "thumbnailmaker-export.png"
        ) { result in
            viewModel.handleFileExportCompletion(result)
        }
        .onChange(of: viewModel.imageSelection) { oldValue, newValue in
            if newValue != nil {
                Task {
                    await viewModel.updateImage()
                }
            }
        }
        .onChange(of: viewModel.layerImageSelection) { oldValue, newValue in
            if newValue != nil {
                Task {
                    if let layerSelection = await viewModel.addImageLayerFromSelection() {
                        selectedLayer = layerSelection
                    }
                }
            }
        }
        .onChange(of: viewModel.stickerImageSelection) { oldValue, newValue in
            if newValue != nil {
                Task {
                    if let layerSelection = await viewModel.addStickerLayerFromSelection() {
                        selectedLayer = layerSelection
                    }
                }
            }
        }
        .onChange(of: isFocused) { _, focused in
            // EDITOR: finishing a text edit settles it into one undo step right
            // away, so Undo (and ⌘Z) is available the moment the keyboard closes.
            if !focused { viewModel.commitEditorStateNow() }
        }
        .onChange(of: viewModel.simpleMakerConfiguration.overlayText) { oldValue, newValue in
            viewModel.reconcileLayersForCurrentOverlays()
            normalizeSelectedLayer()
        }
        .onChange(of: viewModel.simpleMakerConfiguration.layers) { oldValue, newValue in
            normalizeSelectedLayer()
        }
        .firstExportGuideTracking( // FEATURE-13
            firstExportGuide,
            snapshot: firstExportGuideSnapshot,
            exportEvent: viewModel.lastExportEvent,
            offersOnLaunch: true
        )
        .appReviewPrompt(after: viewModel.lastExportEvent) // GAPS
    }

    @ViewBuilder
    private func makerContent(in geometry: GeometryProxy) -> some View {
        if usesRegularEditorLayout(in: geometry) {
            regularEditorLayout(in: geometry)
        } else {
            compactEditorLayout(in: geometry)
        }
    }

    private func usesRegularEditorLayout(in geometry: GeometryProxy) -> Bool {
        horizontalSizeClass == .regular
            && geometry.size.width >= 820
            && !dynamicTypeSize.isAccessibilitySize
    }

    /// APP-08: on a phone the canvas, the words and the layer strip come
    /// first; secondary tools (arrange, variants, sizes, series) collapse
    /// into cards below them instead of pushing the canvas off screen.
    private func compactEditorLayout(in geometry: GeometryProxy) -> some View {
        let availableWidth = max(1, geometry.size.width - 2 * CompactEditorLayoutPolicy.horizontalInset)
        let canvasSize = CompactEditorLayoutPolicy.canvasSize(
            viewport: geometry.size,
            aspectRatio: viewModel.simpleMakerConfiguration.selectedRatio.value
        )

        return ScrollView {
            VStack(spacing: 16) {
                firstExportGuideSection // FEATURE-13
                previewSection(
                    width: canvasSize.width,
                    height: canvasSize.height,
                    maxWidth: availableWidth
                )
                variantWarningSection
                textInputSection(isCompact: true)
                quickAddStripSection // EDITOR: right under the canvas + words
                layerStripSection(includesArrange: false)
                coreControlsSection
                quickActionsSection // EDITOR
                compactArrangeSection
                compactVariantsSection
                smallPreviewSection
                actionButtonsSection
            }
            .padding(.top, 8)
        }
        .accessibilityIdentifier("simpleCompactEditorLayout")
    }

    private func regularEditorLayout(in geometry: GeometryProxy) -> some View {
        let rightPaneWidth = min(420, max(320, geometry.size.width * 0.34))
        let leftPaneWidth = max(360, geometry.size.width - rightPaneWidth)
        let canvasHeightByWidth = max(
            1,
            (leftPaneWidth - 40) / viewModel.simpleMakerConfiguration.selectedRatio.value
        )
        let maxCanvasHeight = max(1, geometry.size.height * 0.78)
        let previewHeight = min(canvasHeightByWidth, maxCanvasHeight)
        let previewWidth = previewHeight * viewModel.simpleMakerConfiguration.selectedRatio.value

        return HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    previewSection(
                        width: previewWidth,
                        height: previewHeight,
                        maxWidth: leftPaneWidth - 40
                    )
                    quickAddStripSection // EDITOR
                    smallPreviewSection
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(width: leftPaneWidth)
            .background(Color(uiColor: .systemBackground))

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    firstExportGuideSection // FEATURE-13
                    variantBarSection
                    textInputSection(isCompact: false)
                    layerStripSection(includesArrange: true)
                    quickActionsSection // EDITOR
                    coreControlsSection
                    actionButtonsSection
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(width: rightPaneWidth)
            .background(Color(uiColor: .secondarySystemBackground).opacity(0.35))
        }
        .accessibilityIdentifier("simpleRegularEditorLayout")
    }

    private func previewSection(width: CGFloat, height: CGFloat, maxWidth: CGFloat) -> some View {
        PreviewComponentView(
            simpleMakerConfiguration: $viewModel.simpleMakerConfiguration,
            width: width,
            height: height,
            isTextInteractive: true,
            safeZone: activeSafeZone,
            selectedOverlay: $selectedLayer
        )
        .environment(\.thumbnailShowsOriginalAdjustments, isComparingAdjustments) // FEATURE-14
        .frame(maxWidth: maxWidth, maxHeight: height)
        .padding(.horizontal, 20)
    }

    private func textInputSection(isCompact: Bool) -> some View {
        OverlayTextEditor(
            text: $viewModel.simpleMakerConfiguration.overlayText,
            placeholder: "Add overlay text",
            characterLimit: viewModel.overlayCharacterLimit,
            focus: $isFocused,
            isCompact: isCompact
        )
        .padding(.horizontal, 20)
    }

    private func layerStripSection(includesArrange: Bool) -> some View {
        VStack(spacing: 12) { // FEATURE-07: strip + arrange panel
        LayerSelectionStripView(
            selection: $selectedLayer,
            layerRecords: $viewModel.simpleMakerConfiguration.layers,
            layers: editableLayers,
            moveLayerBackward: { layer, layers in
                viewModel.moveLayerBackward(layer, within: layers)
            },
            moveLayerForward: { layer, layers in
                viewModel.moveLayerForward(layer, within: layers)
            },
            toggleLayerVisibility: { layer in
                viewModel.toggleLayerVisibility(layer)
            },
            toggleLayerLock: { layer in
                viewModel.toggleLayerLock(layer)
            },
            duplicateLayer: { layer in
                if let duplicatedLayer = viewModel.duplicateLayer(layer) {
                    selectedLayer = duplicatedLayer
                }
            },
            deleteLayer: { layer in
                selectedLayer = viewModel.deleteLayer(layer) ?? .textOverlay
                normalizeSelectedLayer()
            },
            multiSelection: arrangeState.isMultiSelectMode ? $arrangeState.selection : nil // FEATURE-07
        )
        if includesArrange {
            ArrangePanelView(editor: viewModel, state: $arrangeState, primary: $selectedLayer) // FEATURE-07
        }
        }
        .padding(.horizontal, 20)
    }

    // MARK: EDITOR (1.1.0 parity) quick-add strip + quick actions

    private var quickAddStripSection: some View {
        EditorQuickAddStripView(
            imageLayerSelection: $viewModel.layerImageSelection,
            openBackground: {
                isFocused = false
                isBackgroundSheetPresented = true
            },
            addText: {
                isFocused = false
                selectedLayer = viewModel.addTextLayer()
            },
            addShape: { selectedLayer = viewModel.addShapeLayer($0) },
            addCallout: { selectedLayer = viewModel.addCalloutLayer($0) },
            openStickers: {
                isFocused = false
                assetLibrarySection = .stickers
            },
            openLibrary: {
                isFocused = false
                assetLibrarySection = .photos
            }
        )
        .padding(.horizontal, 20)
    }

    private var quickActionsSection: some View {
        LayerQuickActionsView(editor: viewModel, selection: $selectedLayer)
            .padding(.horizontal, 20)
    }

    private var smallPreviewSection: some View {
        ThumbnailSmallPreviewPanel(
            aspectRatio: viewModel.simpleMakerConfiguration.selectedRatio,
            isVisible: viewModel.hasExportableContent,
            accessibilitySummary: smallPreviewAccessibilitySummary
        ) { size in
            PreviewComponentView(
                simpleMakerConfiguration: $viewModel.simpleMakerConfiguration,
                width: size.width,
                height: size.height
            )
        }
        .padding(.horizontal, 20)
    }

    private var smallPreviewAccessibilitySummary: String? {
        let text = viewModel.simpleMakerConfiguration.overlayText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : "Visible title text: \(text)"
    }

    private var coreControlsSection: some View {
        VStack(spacing: 16) {
            // FEATURE-12: shape / arrow / badge / callout inspector.
            if let shapeContent = ShapeLayerControlView.binding(
                layers: $viewModel.simpleMakerConfiguration.layers,
                selection: selectedLayer
            ) {
                ShapeLayerControlView(
                    content: shapeContent,
                    brandPalette: viewModel.brandKit?.palette ?? [],
                    commit: viewModel.commitEditorStateNow
                )
                .padding(.horizontal, 20)
            }

            if let selectedTextLayerContent {
                TextLayerContentControlView(
                    content: selectedTextLayerContent,
                    characterLimit: viewModel.overlayCharacterLimit,
                    isPremium: purchaseManager.canAccessPremium,
                    canvasAspectRatio: viewModel.simpleMakerConfiguration.selectedRatio
                )
                .padding(.horizontal, 20)

                CustomizationControlComponentView(
                    configuration: $viewModel.simpleMakerConfiguration,
                    showsSafeZoneGuide: $showsSafeZoneGuide,
                    isPremium: purchaseManager.canAccessPremium
                )
                .padding(.horizontal, 20)
            } else {
                CustomizationControlComponentView(
                    configuration: $viewModel.simpleMakerConfiguration,
                    showsSafeZoneGuide: $showsSafeZoneGuide,
                    isPremium: purchaseManager.canAccessPremium
                )
                .padding(.horizontal, 20)

                TextControlView(
                    textColor: $viewModel.simpleMakerConfiguration.textColor,
                    textTransform: $viewModel.simpleMakerConfiguration.textTransform,
                    selectedFont: $viewModel.simpleMakerConfiguration.selectedFont,
                    usesFallbackFont: $viewModel.simpleMakerConfiguration.usesFallbackFont,
                    previewText: $viewModel.simpleMakerConfiguration.overlayText,
                    textStyle: $viewModel.simpleMakerConfiguration.textStyle, // FEATURE-04
                    isPremium: purchaseManager.canAccessPremium,
                    autoFit: $viewModel.simpleMakerConfiguration.overlayAutoFit // GAPS
                )
                .padding(.horizontal, 20)
            }
        }
    }

    private var selectedTextLayerContent: Binding<ThumbnailTextLayerContent>? {
        guard case .content(let layerID) = selectedLayer,
              let layer = viewModel.simpleMakerConfiguration.layers.record(id: layerID),
              case .text(let currentContent) = layer.content else {
            return nil
        }

        return Binding(
            get: {
                guard let layer = viewModel.simpleMakerConfiguration.layers.record(id: layerID),
                      case .text(let content) = layer.content else {
                    return currentContent
                }
                return content
            },
            set: { nextContent in
                viewModel.simpleMakerConfiguration.layers.updateTextContent(id: layerID) { content in
                    content = nextContent
                }
            }
        )
    }

    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 58), spacing: 12)],
                spacing: 12
            ) {
                // GAPS: photo, image, sticker, text, shape and brand kit are
                // added from the quick-add strip (and its Library) only.
                // DONOR: meme-maker emoji stickers + PencilKit drawing.
                DonorAddLayerIconButtons(
                    showEmojiPicker: {
                        isFocused = false
                        isEmojiPickerPresented = true
                    },
                    showDrawing: {
                        isFocused = false
                        isDrawingPresented = true
                    }
                )

                if viewModel.canRemoveBackground(from: selectedLayer) {
                    Button {
                        isFocused = false
                        Task {
                            await viewModel.removeBackground(from: selectedLayer)
                        }
                    } label: {
                        CreatorActionIcon(
                            systemName: "person.crop.rectangle",
                            colors: [.pink, .pink.opacity(0.82)],
                            isLoading: viewModel.isProcessingSubject
                        )
                    }
                    .accessibilityIdentifier("removeBackgroundButton")
                    .accessibilityLabel("Remove Background")
                    .accessibilityValue(viewModel.isProcessingSubject ? "Busy" : "")
                    .disabled(viewModel.isProcessingSubject)

                    CutoutRefineButton { // FEATURE-11
                        isFocused = false
                        cutoutRefinementTarget = viewModel.cutoutTarget(for: selectedLayer)
                    }
                    .disabled(viewModel.isProcessingSubject)
                }

                if viewModel.hasExportableContent {
                    Button(action: saveImage) {
                        CreatorActionIcon(
                            systemName: "square.and.arrow.down",
                            colors: [.green, .green.opacity(0.8)],
                            isLoading: viewModel.isSaving
                        )
                    }
                    .accessibilityLabel("Save to Photos")
                    .accessibilityValue(viewModel.isSaving ? "Busy" : "")
                    .disabled(viewModel.isSaving || viewModel.isPreparingShare || viewModel.isPreparingFileExport)

                    Button(action: shareImage) {
                        CreatorActionIcon(
                            systemName: "square.and.arrow.up",
                            colors: [.indigo, .indigo.opacity(0.8)],
                            isLoading: viewModel.isPreparingShare
                        )
                    }
                    .accessibilityLabel("Share Export")
                    .accessibilityValue(viewModel.isPreparingShare ? "Busy" : "")
                    .disabled(viewModel.isSaving || viewModel.isPreparingShare || viewModel.isPreparingFileExport)

                    Button(action: prepareFileExport) {
                        CreatorActionIcon(
                            systemName: "folder",
                            colors: [.teal, .teal.opacity(0.8)],
                            isLoading: viewModel.isPreparingFileExport
                        )
                    }
                    .accessibilityLabel("Export to Files")
                    .accessibilityValue(viewModel.isPreparingFileExport ? "Busy" : "")
                    .disabled(viewModel.isSaving || viewModel.isPreparingShare || viewModel.isPreparingFileExport)
                }
            }

            TitleIdeasStripView(
                ideas: viewModel.titleIdeas,
                applyIdea: { idea in
                    isFocused = false
                    viewModel.apply(idea: idea)
                    selectTextLayerIfAvailable()
                }
            )

            ExportReadinessPanel(
                report: viewModel.exportReport,
                readinessReport: ThumbnailReadinessAnalyzer.analyze(
                    viewModel.simpleMakerConfiguration
                ),
                isChecking: viewModel.isCheckingExportSize,
                canCheckSize: viewModel.hasExportableContent,
                suggestions: viewModel.actionableSuggestions,
                applySuggestion: { suggestion in
                    isFocused = false
                    Task {
                        await viewModel.applyAsync(suggestion)
                        selectTextLayerIfAvailable()
                    }
                }
            ) {
                checkExportSize()
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
    }

    /// GAPS: Library -> Brand Kit opens the editor once the Library is gone.
    private func presentPendingBrandKitEditor() {
        guard opensBrandKitAfterLibrary else { return }
        opensBrandKitAfterLibrary = false
        isBrandKitEditorPresented = true
    }

    private func saveImage() {
        isFocused = false
        let targetSize = viewModel.simpleMakerConfiguration.exportOptions.outputSize.cgSize
        let content = PreviewComponentView(
            simpleMakerConfiguration: $viewModel.simpleMakerConfiguration,
            width: targetSize.width,
            height: targetSize.height
        )
        Task {
            await viewModel.saveImageWithOverlay(content: content)
        }
    }

    private func shareImage() {
        isFocused = false
        let targetSize = viewModel.simpleMakerConfiguration.exportOptions.outputSize.cgSize
        let content = PreviewComponentView(
            simpleMakerConfiguration: $viewModel.simpleMakerConfiguration,
            width: targetSize.width,
            height: targetSize.height
        )
        Task {
            await viewModel.shareImageWithOverlay(content: content)
        }
    }

    private func prepareFileExport() {
        isFocused = false
        let targetSize = viewModel.simpleMakerConfiguration.exportOptions.outputSize.cgSize
        let content = PreviewComponentView(
            simpleMakerConfiguration: $viewModel.simpleMakerConfiguration,
            width: targetSize.width,
            height: targetSize.height
        )
        Task {
            await viewModel.prepareFileExport(content: content)
        }
    }

    private func checkExportSize() {
        isFocused = false
        let targetSize = viewModel.simpleMakerConfiguration.exportOptions.outputSize.cgSize
        let content = PreviewComponentView(
            simpleMakerConfiguration: $viewModel.simpleMakerConfiguration,
            width: targetSize.width,
            height: targetSize.height
        )
        Task {
            await viewModel.checkExportSize(content: content)
        }
    }

    private var activeSafeZone: ThumbnailSafeZone? {
        showsSafeZoneGuide ? viewModel.simpleMakerConfiguration.exportOptions.activeSafeZone : nil
    }

    private var editableLayers: [ThumbnailLayerSelection] {
        viewModel.selectableLayerSelections
    }

    private func selectTextLayerIfAvailable() {
        if editableLayers.contains(.textOverlay) {
            selectedLayer = .textOverlay
        } else {
            normalizeSelectedLayer()
        }
    }

    // MARK: FEATURE-02 variants

    private var variantBarSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            variantsAndSizesContent
                .padding(.horizontal, 20)
            variantWarningSection
        }
    }

    /// APP-08: compact width keeps variants, sizes and series one tap away
    /// but collapsed, unless they already hold work.
    /// APP-08: on a phone the selected layer's inspector sits right under
    /// the strip; the arrange tools follow as a collapsed card.
    private var compactArrangeSection: some View {
        ArrangePanelView( // FEATURE-07
            editor: viewModel,
            state: $arrangeState,
            primary: $selectedLayer,
            isExpanded: $isArrangeExpanded
        )
        .padding(.horizontal, 20)
    }

    private var compactVariantsSection: some View {
        CompactDisclosureSection(
            title: "Variants & Sizes",
            systemImage: "square.on.square",
            summary: ThumbnailAccessibilityText.variantsSectionSummary(
                variantCount: viewModel.variantSet.variants.count,
                activeVariantName: viewModel.variantSet.activeVariant.name,
                alternateSizeCount: viewModel.alternateFormats.count
            ),
            identifier: "compactVariantsSection",
            isExpanded: Binding(
                get: {
                    variantsSectionExpandedOverride ?? CompactEditorLayoutPolicy.expandsVariantsSectionByDefault(
                        variantCount: viewModel.variantSet.variants.count,
                        alternateSizeCount: viewModel.alternateFormats.count
                    )
                },
                set: { variantsSectionExpandedOverride = $0 }
            )
        ) {
            variantsAndSizesContent
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
    }

    private var variantsAndSizesContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            ThumbnailVariantBarView(
                variantSet: viewModel.variantSet,
                isDisabled: false,
                select: { slot in
                    isFocused = false
                    viewModel.selectVariant(slot)
                    normalizeSelectedLayer()
                },
                duplicate: {
                    isFocused = false
                    viewModel.duplicateActiveVariant()
                    normalizeSelectedLayer()
                },
                compare: {
                    isFocused = false
                    viewModel.commitEditorStateNow()
                    isVariantComparePresented = true
                },
                rename: { viewModel.renameVariant($0, to: $1) },
                setPreferred: { viewModel.setPreferredVariant($0) },
                remove: { slot in
                    viewModel.removeVariant(slot)
                    normalizeSelectedLayer()
                },
                exportAll: { // FEATURE-10
                    isFocused = false
                    viewModel.commitEditorStateNow()
                    isExportQueuePresented = true
                }
            )

            SeriesEntryButton(isEnabled: viewModel.isSeriesAvailable) { // FEATURE-15
                isFocused = false
                isSeriesPresented = true
            }

            ThumbnailFormatSection(editor: viewModel) // FEATURE-09: alternate sizes
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var variantWarningSection: some View {
        if let warning = viewModel.variantWarning {
            VariantWarningBanner(message: warning) {
                viewModel.dismissVariantWarning()
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: FEATURE-13 first-export guide

    private var firstExportGuideSnapshot: FirstExportGuideSnapshot {
        FirstExportGuideSnapshot.make(
            simple: viewModel.simpleMakerConfiguration,
            exportReport: viewModel.exportReport
        )
    }

    @ViewBuilder
    private var firstExportGuideSection: some View {
        if firstExportGuide.presentation != .hidden {
            FirstExportGuideCard(
                guide: firstExportGuide,
                snapshot: firstExportGuideSnapshot,
                actions: FirstExportGuideActions(
                    imageSelection: $viewModel.imageSelection,
                    openTemplates: {
                        isFocused = false
                        isTemplateGalleryPresented = true
                    },
                    focusTitle: {
                        // The editor's tap-to-dismiss gesture clears focus on
                        // this same tap, so focus after it has run.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(200))
                            isFocused = true
                        }
                    },
                    checkSize: checkExportSize,
                    saveToPhotos: saveImage,
                    exportToFiles: prepareFileExport,
                    share: shareImage,
                    startNewProject: viewModel.isProjectLibraryAvailable && viewModel.hasExportableContent
                        ? { isFocused = false; viewModel.createNewProject() }
                        : nil,
                    isBusy: viewModel.isSaving || viewModel.isPreparingShare
                        || viewModel.isPreparingFileExport || viewModel.isCheckingExportSize
                )
            )
            .padding(.horizontal, 20)
        }
    }

    private func normalizeSelectedLayer() {
        let layers = editableLayers
        if layers.contains(selectedLayer) {
            return
        }

        if let firstLayer = layers.first {
            selectedLayer = firstLayer
        }
    }
    
    private func premiumFeatureTeaser(icon: String, text: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.linearGradient(colors: [.blue, .purple],
                                               startPoint: .topLeading,
                                               endPoint: .bottomTrailing))
            Text(text)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            NotificationCenter.default.post(
                name: Notification.Name("ShowPremiumUpgrade"),
                object: nil
            )
        }
    }
}

#Preview {
    SimpleMakerView()
}
