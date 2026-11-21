//
//  PremiumMakerView.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/28.
//

import SwiftUI
import Combine
import PhotosUI
import UniformTypeIdentifiers

struct PremiumMakerView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var viewModel: PremiumMakerViewModel
    @Environment(\.showCreateHome) private var showCreateHome // SHELL
    @ObservedObject private var templateLibrary = PersonalTemplateLibraryModel.shared // FEATURE-05
    @State private var isProjectLibraryPresented = false // FEATURE-01
    @StateObject private var purchaseManager = PurchaseManager.shared
    @FocusState private var focusedField: TextFieldFocus?
    @State private var isSettingsPresented: Bool = false
    @State private var showingPurchaseMessage = false
    @State private var purchaseMessage: String?
    @Namespace private var bottomID
    @Namespace private var topID
    @State private var showingPurchaseAlert = false
    @State private var showingToast = false
    @State private var toastMessage = ""
    @State private var showingMacroSettings = false
    @State private var showingYouTubeInput = false
    @State private var showingQuotaLimit = false
    @State private var isTemplateGalleryPresented = false
    @State private var isBrandKitEditorPresented = false
    @State private var showsSafeZoneGuide = true
    @State private var timerRefreshTrigger = Date()
    @State private var selectedLayer: ThumbnailLayerSelection = .textOverlay
    @State private var arrangeState = ThumbnailArrangeUIState() // FEATURE-07
    @State private var isArrangeExpanded = CompactEditorLayoutPolicy.expandsArrangePanelByDefault // APP-08
    @State private var variantsSectionExpandedOverride: Bool? // APP-08
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
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// SHELL: the app shell owns the editor model so switching between Home
    /// and the Pro editor never drops unsaved work.
    init(viewModel: PremiumMakerViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? PremiumMakerViewModel(projectLibrary: .shared))
    }
    
    var body: some View {
        Group {
            if purchaseManager.canAccessPremium {
                premiumContent
            } else {
                purchasePromptView
                    .overlay(alignment: .topLeading) { // SHELL: a way back to Home
                        if let showCreateHome {
                            CreateHomeToolbarButton(action: showCreateHome)
                                .padding(.leading, 8)
                        }
                    }
            }
        }
    }
    
    private var purchasePromptView: some View {
        // SUB: redesigned paywall (weekly / monthly / lifetime) replaces the lifetime-only prompt.
        PremiumPaywallView(presentation: .embedded, headline: "Premium Maker")
            .alert("Purchase Status", isPresented: $showingPurchaseMessage, presenting: purchaseMessage) { _ in
                Button("OK", role: .cancel) { }
            } message: { message in
                Text(message)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowPurchaseMessage"))) { notification in
                if let message = notification.userInfo?["message"] as? String {
                    purchaseMessage = message
                    showingPurchaseMessage = true
                }
            }
    }
    
    private var premiumContent: some View {
        NavigationStack {
            GeometryReader { geometry in
                makerContent(in: geometry)
            }
            .onTapGesture {
                focusedField = nil
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), 
                                              to: nil, 
                                              from: nil, 
                                              for: nil)
            }
            .ignoresSafeArea(.keyboard)
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { // SHELL
                    if let showCreateHome {
                        CreateHomeToolbarButton {
                            focusedField = nil
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
                        focusedField = nil
                        isTemplateGalleryPresented = true
                    } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                    .accessibilityIdentifier("templatesButton")
                    .accessibilityLabel("Templates")

                    AdjustmentsToolbarButton(isEnabled: viewModel.hasAdjustableImages) { // FEATURE-14
                        focusedField = nil
                        viewModel.commitEditorStateNow()
                        isAdjustmentsPresented = true
                    }

                    UndoRedoToolbarButtons(
                        canUndo: viewModel.canUndo,
                        canRedo: viewModel.canRedo,
                        undo: {
                            focusedField = nil
                            viewModel.undo()
                        },
                        redo: {
                            focusedField = nil
                            viewModel.redo()
                        }
                    )
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showingToast {
                ToastView(message: toastMessage)
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
            aspectRatio: viewModel.premiumMakerConfiguration.selectedRatio,
            addEmoji: { emoji in
                if let layer = viewModel.addEmojiSticker(emoji) { selectedLayer = layer }
            },
            addDrawing: { result in selectedLayer = viewModel.addDrawing(result) },
            drawingBackground: { size in
                PremiumPreviewComponentView(
                    premiumMakerConfiguration: viewModel.premiumMakerConfiguration,
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
                    return viewModel.premiumMakerConfiguration.document
                }
            ) { template, mode in
                focusedField = nil
                templateLibrary.reportApplication(viewModel.applyTemplate(template, mode: mode))
                normalizeSelectedLayer()
                isTemplateGalleryPresented = false
            }
        }
        .templateApplicationWarningsAlert(library: templateLibrary)
        .sheet(isPresented: $isBackgroundSheetPresented) { // EDITOR
            EditorBackgroundSheet(
                photoSelection: $viewModel.imageSelection,
                backgroundColor: $viewModel.premiumMakerConfiguration.backgroundColor,
                hasPhoto: viewModel.premiumMakerConfiguration.selectedImage != nil,
                commit: viewModel.commitEditorStateNow
            ) {
                // SHELL x EDITOR: the BG entry point also offers solid / gradient fills.
                BackgroundFillControlRow(
                    backgroundColor: $viewModel.premiumMakerConfiguration.backgroundColor,
                    fill: $viewModel.premiumMakerConfiguration.backgroundFill
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
                recentAssets: ThumbnailAssetLibrary.recentAssets(in: viewModel.premiumMakerConfiguration.layers),
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
        .sheet(isPresented: $isBrandKitEditorPresented) {
            BrandKitLibraryView( // FEATURE-08
                editor: viewModel,
                selectedLayerID: selectedLayer.documentLayerID,
                allowsPremiumFonts: purchaseManager.canAccessPremium
            )
        }
        .sheet(isPresented: $viewModel.showingProfileCropper) {
            if let image = viewModel.tempProfileImage {
                CircularImageCropperView(
                    isPresented: $viewModel.showingProfileCropper,
                    originalImage: image
                ) { croppedImage in
                    viewModel.setProfileImage(croppedImage)
                }
            }
        }
        .sheet(isPresented: $showingYouTubeInput) {
            // On dismiss
            focusedField = nil
        } content: {
            YouTubeURLInputView { image, title in
                viewModel.premiumMakerConfiguration.selectedImage = image
                if !title.isEmpty {
                    viewModel.premiumMakerConfiguration.overlayText = title
                }
                focusedField = nil
            }
        }
        .sheet(isPresented: $showingQuotaLimit) {
            QuotaLimitView()
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
                PremiumPreviewComponentView(
                    premiumMakerConfiguration: pane.document.makePremiumConfiguration(),
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
            Task {
                await viewModel.updateImage()
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
        .onChange(of: viewModel.profileImageSelection) { oldValue, newValue in
            if newValue != nil {
                Task {
                    await viewModel.updateProfileImage()
                }
            }
        }
        .overlay {
            if viewModel.isBatchGenerating {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                
                BatchProgressView(
                    progress: viewModel.batchProgress,
                    currentNumber: viewModel.currentBatchNumber,
                    totalCount: viewModel.premiumMakerConfiguration.macroConfig.totalCount,
                    onCancel: {
                        viewModel.cancelBatchGeneration()
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showingMacroSettings) {
            MacroSettingsView(
                macroConfig: $viewModel.premiumMakerConfiguration.macroConfig,
                hasSelectedImage: viewModel.premiumMakerConfiguration.selectedImage != nil,
                baseText: viewModel.premiumMakerConfiguration.overlayText
            )
        }
        .onChange(of: focusedField) { _, field in
            // EDITOR: finishing a text edit settles it into one undo step right away.
            if field == nil { viewModel.commitEditorStateNow() }
        }
        .onChange(of: viewModel.premiumMakerConfiguration.overlayText) { oldValue, newValue in
            viewModel.reconcileLayersForCurrentOverlays()
            normalizeSelectedLayer()
        }
        .onChange(of: viewModel.premiumMakerConfiguration.circularProfile?.image != nil) { oldValue, newValue in
            viewModel.reconcileLayersForCurrentOverlays()
            normalizeSelectedLayer()
        }
        .onChange(of: viewModel.premiumMakerConfiguration.layers) { oldValue, newValue in
            normalizeSelectedLayer()
        }
        .onChange(of: viewModel.lastExportEvent) { _, event in // FEATURE-13: a first export here completes the shared guide
            FirstExportGuideController.shared.recordExport(event)
        }
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

    /// APP-08: canvas, words and layers first; secondary tools collapse.
    private func compactEditorLayout(in geometry: GeometryProxy) -> some View {
        let availableWidth = max(1, geometry.size.width - 2 * CompactEditorLayoutPolicy.horizontalInset)
        let canvasSize = CompactEditorLayoutPolicy.canvasSize(
            viewport: geometry.size,
            aspectRatio: viewModel.premiumMakerConfiguration.selectedRatio.value
        )

        return ScrollView {
            VStack(spacing: 0) {
                previewSection(
                    width: canvasSize.width,
                    height: canvasSize.height,
                    maxWidth: availableWidth
                )
                .padding(.top, 8)
                variantWarningSection
                textInputSection
                quickAddStripSection // EDITOR: right under the canvas + words
                    .padding(.top, 12)
                layerStripSection(includesArrange: false)
                coreControlsSection
                quickActionsSection // EDITOR
                    .padding(.top, 12)
                compactArrangeSection
                compactVariantsSection
                smallPreviewSection
                actionButtonsSection
                batchSettingsSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityIdentifier("premiumCompactEditorLayout")
    }

    private func regularEditorLayout(in geometry: GeometryProxy) -> some View {
        let rightPaneWidth = min(420, max(320, geometry.size.width * 0.34))
        let leftPaneWidth = max(360, geometry.size.width - rightPaneWidth)
        let canvasHeightByWidth = max(
            1,
            (leftPaneWidth - 40) / viewModel.premiumMakerConfiguration.selectedRatio.value
        )
        let maxCanvasHeight = max(1, geometry.size.height * 0.78)
        let previewHeight = min(canvasHeightByWidth, maxCanvasHeight)
        let previewWidth = previewHeight * viewModel.premiumMakerConfiguration.selectedRatio.value

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
                    variantBarSection
                    textInputSection
                    layerStripSection(includesArrange: true)
                    quickActionsSection // EDITOR
                    coreControlsSection
                    regularActionButtonsSection
                    batchSettingsSection
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(width: rightPaneWidth)
            .background(Color(uiColor: .secondarySystemBackground).opacity(0.35))
        }
        .accessibilityIdentifier("premiumRegularEditorLayout")
    }

    private func previewSection(width: CGFloat, height: CGFloat, maxWidth: CGFloat) -> some View {
        PremiumPreviewComponentView(
            premiumMakerConfiguration: $viewModel.premiumMakerConfiguration,
            width: width,
            height: height,
            isInteractive: true,
            safeZone: activeSafeZone,
            selectedOverlay: $selectedLayer,
            fallbackStateDidChange: { usesFallback in
                if viewModel.premiumMakerConfiguration.usesFallbackFont != usesFallback {
                    viewModel.premiumMakerConfiguration.usesFallbackFont = usesFallback
                }
            }
        )
        .environment(\.thumbnailShowsOriginalAdjustments, isComparingAdjustments) // FEATURE-14
        .frame(maxWidth: maxWidth, maxHeight: height)
        .padding(.horizontal, 20)
    }

    private var textInputSection: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $viewModel.premiumMakerConfiguration.overlayText)
                .font(.body)
                .focused($focusedField, equals: .overlayText)
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .frame(minHeight: 96, idealHeight: 112, maxHeight: 180)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(uiColor: .systemGray6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    LinearGradient(
                                        colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                )
                .accessibilityLabel("Overlay text")

            if viewModel.premiumMakerConfiguration.overlayText.isEmpty {
                Text("Enter overlay text")
                    .foregroundStyle(Color.accessibleSecondaryText)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button("Done") {
                        focusedField = nil
                    }
                    .accessibilityIdentifier("premiumOverlayTextKeyboardDoneButton")
                    .accessibilityLabel("Done editing overlay text")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
    }

    private func layerStripSection(includesArrange: Bool) -> some View {
        VStack(spacing: 12) { // FEATURE-07: strip + arrange panel
        LayerSelectionStripView(
            selection: $selectedLayer,
            layerRecords: $viewModel.premiumMakerConfiguration.layers,
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
        .padding(.top, 12)
    }

    // MARK: EDITOR (1.1.0 parity) quick-add strip + quick actions

    private var quickAddStripSection: some View {
        EditorQuickAddStripView(
            imageLayerSelection: $viewModel.layerImageSelection,
            openBackground: {
                focusedField = nil
                isBackgroundSheetPresented = true
            },
            addText: {
                focusedField = nil
                selectedLayer = viewModel.addTextLayer()
            },
            addShape: { selectedLayer = viewModel.addShapeLayer($0) },
            addCallout: { selectedLayer = viewModel.addCalloutLayer($0) },
            openStickers: {
                focusedField = nil
                assetLibrarySection = .stickers
            },
            openLibrary: {
                focusedField = nil
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
            aspectRatio: viewModel.premiumMakerConfiguration.selectedRatio,
            isVisible: viewModel.hasExportableContent,
            accessibilitySummary: smallPreviewAccessibilitySummary
        ) { size in
            PremiumPreviewComponentView(
                premiumMakerConfiguration: viewModel.premiumMakerConfiguration,
                width: size.width,
                height: size.height
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var smallPreviewAccessibilitySummary: String? {
        let text = viewModel.premiumMakerConfiguration.overlayText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : "Visible title text: \(text)"
    }

    private var coreControlsSection: some View {
        VStack(spacing: 16) {
            // FEATURE-12: shape / arrow / badge / callout inspector.
            if let shapeContent = ShapeLayerControlView.binding(
                layers: $viewModel.premiumMakerConfiguration.layers,
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
                    isPremium: true,
                    canvasAspectRatio: viewModel.premiumMakerConfiguration.selectedRatio
                )
                .padding(.horizontal, 20)

                PremiumCustomizationControlComponentView(
                    configuration: $viewModel.premiumMakerConfiguration,
                    showsSafeZoneGuide: $showsSafeZoneGuide
                )
                .padding(.horizontal, 20)
            } else {
                PremiumCustomizationControlComponentView(
                    configuration: $viewModel.premiumMakerConfiguration,
                    showsSafeZoneGuide: $showsSafeZoneGuide
                )
                .padding(.horizontal, 20)

                PremiumTextControlView(
                    selectedLayer: $selectedLayer,
                    textTransform: $viewModel.premiumMakerConfiguration.textTransform,
                    profileTransform: $viewModel.premiumMakerConfiguration.profileTransform,
                    textColor: $viewModel.premiumMakerConfiguration.textColor,
                    selectedFont: $viewModel.premiumMakerConfiguration.selectedFont,
                    usesFallbackFont: $viewModel.premiumMakerConfiguration.usesFallbackFont,
                    previewText: $viewModel.premiumMakerConfiguration.overlayText,
                    textStyle: $viewModel.premiumMakerConfiguration.textStyle, // FEATURE-04
                    autoFit: $viewModel.premiumMakerConfiguration.overlayAutoFit // GAPS
                )
                .padding(.horizontal, 20)
            }
        }
    }

    private var selectedTextLayerContent: Binding<ThumbnailTextLayerContent>? {
        guard case .content(let layerID) = selectedLayer,
              let layer = viewModel.premiumMakerConfiguration.layers.record(id: layerID),
              case .text(let currentContent) = layer.content else {
            return nil
        }

        return Binding(
            get: {
                guard let layer = viewModel.premiumMakerConfiguration.layers.record(id: layerID),
                      case .text(let content) = layer.content else {
                    return currentContent
                }
                return content
            },
            set: { nextContent in
                viewModel.premiumMakerConfiguration.layers.updateTextContent(id: layerID) { content in
                    content = nextContent
                }
            }
        )
    }

    private var activeSafeZone: ThumbnailSafeZone? {
        showsSafeZoneGuide ? viewModel.premiumMakerConfiguration.exportOptions.activeSafeZone : nil
    }

    private var editableLayers: [ThumbnailLayerSelection] {
        viewModel.selectableLayerSelections
    }

    // MARK: FEATURE-02 variants

    private var variantBarSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            variantsAndSizesContent
                .padding(.horizontal, 20)
            variantWarningSection
        }
        .padding(.top, 12)
    }

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
        .padding(.top, 12)
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
        .padding(.top, 12)
    }

    private var variantsAndSizesContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            ThumbnailVariantBarView(
                variantSet: viewModel.variantSet,
                isDisabled: viewModel.isBatchGenerating,
                select: { slot in
                    focusedField = nil
                    viewModel.selectVariant(slot)
                    normalizeSelectedLayer()
                },
                duplicate: {
                    focusedField = nil
                    viewModel.duplicateActiveVariant()
                    normalizeSelectedLayer()
                },
                compare: {
                    focusedField = nil
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
                    focusedField = nil
                    viewModel.commitEditorStateNow()
                    isExportQueuePresented = true
                }
            )

            SeriesEntryButton(isEnabled: viewModel.isSeriesAvailable) { // FEATURE-15
                focusedField = nil
                isSeriesPresented = true
            }

            ThumbnailFormatSection(editor: viewModel, isDisabled: viewModel.isBatchGenerating) // FEATURE-09
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
            .padding(.top, 8)
        }
    }

    private func normalizeSelectedLayer() {
        let layers = editableLayers
        guard !layers.contains(selectedLayer), let firstLayer = layers.first else { return }
        selectedLayer = firstLayer
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 16) {
            // Primary actions row - emoji, drawing, cutout and YouTube Import
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
                spacing: 12
            ) {
                // GAPS: photo, image, sticker, text, shape and brand kit are
                // added from the quick-add strip (and its Library) only.
                // DONOR: meme-maker emoji stickers + PencilKit drawing.
                Button {
                    focusedField = nil
                    isEmojiPickerPresented = true
                } label: {
                    donorActionLabel("Emoji", systemImage: "face.smiling.inverse", colors: [.yellow, .orange.opacity(0.82)])
                }
                .accessibilityIdentifier("addEmojiStickerButton")
                .accessibilityLabel("Add Emoji Sticker")

                Button {
                    focusedField = nil
                    isDrawingPresented = true
                } label: {
                    donorActionLabel("Draw", systemImage: "pencil.tip.crop.circle", colors: [.red, .pink.opacity(0.82)])
                }
                .accessibilityIdentifier("addDrawingButton")
                .accessibilityLabel("Draw")

                if viewModel.canRemoveBackground(from: selectedLayer) {
                    Button {
                        focusedField = nil
                        Task {
                            await viewModel.removeBackground(from: selectedLayer)
                        }
                    } label: {
                        HStack {
                            if viewModel.isProcessingSubject {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "person.crop.rectangle")
                            }
                            Text(viewModel.isProcessingSubject ? "Cutting Out" : "Cutout")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            LinearGradient(
                                colors: [.pink, .pink.opacity(0.82)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .accessibilityIdentifier("removeBackgroundButton")
                    .accessibilityLabel("Remove Background")
                    .accessibilityValue(viewModel.isProcessingSubject ? "Busy" : "")
                    .disabled(viewModel.isProcessingSubject)

                    Button { // FEATURE-11
                        focusedField = nil
                        cutoutRefinementTarget = viewModel.cutoutTarget(for: selectedLayer)
                    } label: {
                        Label("Refine", systemImage: "scribble.variable")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                LinearGradient(
                                    colors: [.purple, .purple.opacity(0.82)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .accessibilityIdentifier("refineCutoutButton")
                    .accessibilityLabel("Refine Cutout")
                    .disabled(viewModel.isProcessingSubject)
                }
                
                // YouTube Import button
                Button(action: {
                    focusedField = nil
                    
                    // Check quota before showing YouTube input
                    let importStatus = PurchaseManager.shared.youtubeImportsRemaining
                    if importStatus <= 0 {
                        showingQuotaLimit = true
                    } else {
                        showingYouTubeInput = true
                    }
                }) {
                    HStack {
                        Image(systemName: "play.rectangle.fill")
                        Text("YouTube Import")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        LinearGradient(colors: [.purple, .purple.opacity(0.8)],
                                     startPoint: .leading,
                                     endPoint: .trailing)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
            
            // Secondary actions row - Profile and export
            if viewModel.hasExportableContent {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 58), spacing: 12)],
                    spacing: 12
                ) {
                    // Profile Image button
                    PhotosPicker(selection: $viewModel.profileImageSelection,
                               matching: .images) {
                        CreatorActionIcon(
                            systemName: "person.crop.circle",
                            colors: [.orange, .orange.opacity(0.8)]
                        )
                    }
                    .accessibilityLabel("Add Profile Image")
                    
                    // Save button
                    Button(action: {
                        focusedField = nil
                        let targetSize = viewModel.premiumMakerConfiguration.exportOptions.outputSize.cgSize
                        let content = PremiumPreviewComponentView(
                            premiumMakerConfiguration: viewModel.premiumMakerConfiguration,
                            width: targetSize.width,
                            height: targetSize.height
                        )
                        Task {
                            await viewModel.saveImageWithOverlay(content: content)
                        }
                    }) {
                        CreatorActionIcon(
                            systemName: "square.and.arrow.down",
                            colors: [.green, .green.opacity(0.8)],
                            isLoading: viewModel.isSaving
                        )
                    }
                    .accessibilityLabel("Save to Photos")
                    .accessibilityValue(viewModel.isSaving ? "Busy" : "")
                    .disabled(viewModel.isSaving || viewModel.isPreparingShare || viewModel.isPreparingFileExport)

                    // Share button
                    Button(action: {
                        focusedField = nil
                        let targetSize = viewModel.premiumMakerConfiguration.exportOptions.outputSize.cgSize
                        let content = PremiumPreviewComponentView(
                            premiumMakerConfiguration: viewModel.premiumMakerConfiguration,
                            width: targetSize.width,
                            height: targetSize.height
                        )
                        Task {
                            await viewModel.shareImageWithOverlay(content: content)
                        }
                    }) {
                        CreatorActionIcon(
                            systemName: "square.and.arrow.up",
                            colors: [.indigo, .indigo.opacity(0.8)],
                            isLoading: viewModel.isPreparingShare
                        )
                    }
                    .accessibilityLabel("Share Export")
                    .accessibilityValue(viewModel.isPreparingShare ? "Busy" : "")
                    .disabled(viewModel.isSaving || viewModel.isPreparingShare || viewModel.isPreparingFileExport)

                    // Files button
                    Button(action: {
                        focusedField = nil
                        let targetSize = viewModel.premiumMakerConfiguration.exportOptions.outputSize.cgSize
                        let content = PremiumPreviewComponentView(
                            premiumMakerConfiguration: viewModel.premiumMakerConfiguration,
                            width: targetSize.width,
                            height: targetSize.height
                        )
                        Task {
                            await viewModel.prepareFileExport(content: content)
                        }
                    }) {
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

                TitleIdeasStripView(
                    ideas: viewModel.titleIdeas,
                    applyIdea: { idea in
                        focusedField = nil
                        viewModel.apply(idea: idea)
                        normalizeSelectedLayer()
                    }
                )

                ExportReadinessPanel(
                    report: viewModel.exportReport,
                    readinessReport: ThumbnailReadinessAnalyzer.analyze(
                        viewModel.premiumMakerConfiguration
                    ),
                    isChecking: viewModel.isCheckingExportSize,
                    canCheckSize: viewModel.hasExportableContent,
                    suggestions: viewModel.actionableSuggestions,
                    applySuggestion: { suggestion in
                        focusedField = nil
                        Task {
                            await viewModel.applyAsync(suggestion)
                            normalizeSelectedLayer()
                        }
                    }
                ) {
                    focusedField = nil
                    let targetSize = viewModel.premiumMakerConfiguration.exportOptions.outputSize.cgSize
                    let content = PremiumPreviewComponentView(
                        premiumMakerConfiguration: viewModel.premiumMakerConfiguration,
                        width: targetSize.width,
                        height: targetSize.height
                    )
                    Task {
                        await viewModel.checkExportSize(content: content)
                    }
                }
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

    /// DONOR: label matching the list-style add buttons above.
    private func donorActionLabel(_ title: String, systemImage: String, colors: [Color]) -> some View {
        HStack {
            Image(systemName: systemImage)
            Text(title)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
        .foregroundColor(.white)
        .cornerRadius(10)
    }

    private var regularActionButtonsSection: some View {
        VStack(spacing: 16) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 58), spacing: 12)],
                spacing: 12
            ) {
                // GAPS: photo, image, sticker, text, shape and brand kit are
                // added from the quick-add strip (and its Library) only.
                // DONOR: meme-maker emoji stickers + PencilKit drawing.
                DonorAddLayerIconButtons(
                    showEmojiPicker: {
                        focusedField = nil
                        isEmojiPickerPresented = true
                    },
                    showDrawing: {
                        focusedField = nil
                        isDrawingPresented = true
                    }
                )

                if viewModel.canRemoveBackground(from: selectedLayer) {
                    Button {
                        focusedField = nil
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
                        focusedField = nil
                        cutoutRefinementTarget = viewModel.cutoutTarget(for: selectedLayer)
                    }
                    .disabled(viewModel.isProcessingSubject)
                }

                Button {
                    focusedField = nil
                    let importStatus = PurchaseManager.shared.youtubeImportsRemaining
                    if importStatus <= 0 {
                        showingQuotaLimit = true
                    } else {
                        showingYouTubeInput = true
                    }
                } label: {
                    CreatorActionIcon(
                        systemName: "play.rectangle.fill",
                        colors: [.purple, .purple.opacity(0.8)]
                    )
                }
                .accessibilityIdentifier("youtubeImportButton")
                .accessibilityLabel("YouTube Import")
            }

            if viewModel.hasExportableContent {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 58), spacing: 12)],
                    spacing: 12
                ) {
                    PhotosPicker(selection: $viewModel.profileImageSelection, matching: .images) {
                        CreatorActionIcon(
                            systemName: "person.crop.circle",
                            colors: [.orange, .orange.opacity(0.8)]
                        )
                    }
                    .accessibilityLabel("Add Profile Image")

                    Button {
                        focusedField = nil
                        let targetSize = viewModel.premiumMakerConfiguration.exportOptions.outputSize.cgSize
                        let content = PremiumPreviewComponentView(
                            premiumMakerConfiguration: viewModel.premiumMakerConfiguration,
                            width: targetSize.width,
                            height: targetSize.height
                        )
                        Task {
                            await viewModel.saveImageWithOverlay(content: content)
                        }
                    } label: {
                        CreatorActionIcon(
                            systemName: "square.and.arrow.down",
                            colors: [.green, .green.opacity(0.8)],
                            isLoading: viewModel.isSaving
                        )
                    }
                    .accessibilityLabel("Save to Photos")
                    .accessibilityValue(viewModel.isSaving ? "Busy" : "")
                    .disabled(viewModel.isSaving || viewModel.isPreparingShare || viewModel.isPreparingFileExport)

                    Button {
                        focusedField = nil
                        let targetSize = viewModel.premiumMakerConfiguration.exportOptions.outputSize.cgSize
                        let content = PremiumPreviewComponentView(
                            premiumMakerConfiguration: viewModel.premiumMakerConfiguration,
                            width: targetSize.width,
                            height: targetSize.height
                        )
                        Task {
                            await viewModel.shareImageWithOverlay(content: content)
                        }
                    } label: {
                        CreatorActionIcon(
                            systemName: "square.and.arrow.up",
                            colors: [.indigo, .indigo.opacity(0.8)],
                            isLoading: viewModel.isPreparingShare
                        )
                    }
                    .accessibilityLabel("Share Export")
                    .accessibilityValue(viewModel.isPreparingShare ? "Busy" : "")
                    .disabled(viewModel.isSaving || viewModel.isPreparingShare || viewModel.isPreparingFileExport)

                    Button {
                        focusedField = nil
                        let targetSize = viewModel.premiumMakerConfiguration.exportOptions.outputSize.cgSize
                        let content = PremiumPreviewComponentView(
                            premiumMakerConfiguration: viewModel.premiumMakerConfiguration,
                            width: targetSize.width,
                            height: targetSize.height
                        )
                        Task {
                            await viewModel.prepareFileExport(content: content)
                        }
                    } label: {
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

                TitleIdeasStripView(
                    ideas: viewModel.titleIdeas,
                    applyIdea: { idea in
                        focusedField = nil
                        viewModel.apply(idea: idea)
                        normalizeSelectedLayer()
                    }
                )

                ExportReadinessPanel(
                    report: viewModel.exportReport,
                    readinessReport: ThumbnailReadinessAnalyzer.analyze(
                        viewModel.premiumMakerConfiguration
                    ),
                    isChecking: viewModel.isCheckingExportSize,
                    canCheckSize: viewModel.hasExportableContent,
                    suggestions: viewModel.actionableSuggestions,
                    applySuggestion: { suggestion in
                        focusedField = nil
                        Task {
                            await viewModel.applyAsync(suggestion)
                            normalizeSelectedLayer()
                        }
                    }
                ) {
                    focusedField = nil
                    let targetSize = viewModel.premiumMakerConfiguration.exportOptions.outputSize.cgSize
                    let content = PremiumPreviewComponentView(
                        premiumMakerConfiguration: viewModel.premiumMakerConfiguration,
                        width: targetSize.width,
                        height: targetSize.height
                    )
                    Task {
                        await viewModel.checkExportSize(content: content)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 20)
    }
    
    private var batchSettingsSection: some View {
        HStack(spacing: 12) {
            Button(action: {
                showingMacroSettings = true
            }) {
                HStack {
                    Image(systemName: "gearshape.2")
                    Text("Batch Settings")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(colors: [Color(uiColor: .secondarySystemBackground), 
                                          Color(uiColor: .secondarySystemBackground).opacity(0.8)],
                                 startPoint: .leading,
                                 endPoint: .trailing)
                )
                .cornerRadius(8)
            }
            
            if viewModel.premiumMakerConfiguration.macroConfig.isEnabled {
                Button(action: {
                    focusedField = nil
                    Task {
                        await viewModel.generateBatchImages { text in
                            let targetSize = viewModel.premiumMakerConfiguration.exportOptions.outputSize.cgSize
                            return PremiumPreviewComponentView(
                                premiumMakerConfiguration: PremiumMakerConfigurationModel(
                                    selectedImage: viewModel.premiumMakerConfiguration.selectedImage,
                                    imageRecipe: viewModel.premiumMakerConfiguration.imageRecipe,
                                    overlayText: text,
                                    selectedRatio: viewModel.premiumMakerConfiguration.selectedRatio,
                                    backgroundColor: viewModel.premiumMakerConfiguration.backgroundColor,
                                    textColor: viewModel.premiumMakerConfiguration.textColor,
                                    textSize: viewModel.premiumMakerConfiguration.textSize,
                                    verticalAlignment: viewModel.premiumMakerConfiguration.verticalAlignment,
                                    horizontalAlignment: viewModel.premiumMakerConfiguration.horizontalAlignment,
                                    textTransform: viewModel.premiumMakerConfiguration.textTransform,
                                    circularProfile: viewModel.premiumMakerConfiguration.circularProfile,
                                    profileTransform: viewModel.premiumMakerConfiguration.profileTransform,
                                    macroConfig: viewModel.premiumMakerConfiguration.macroConfig,
                                    selectedFont: viewModel.premiumMakerConfiguration.selectedFont,
                                    usesFallbackFont: viewModel.premiumMakerConfiguration.usesFallbackFont,
                                    textStyle: viewModel.premiumMakerConfiguration.textStyle, // FEATURE-04
                                    exportOptions: viewModel.premiumMakerConfiguration.exportOptions
                                ),
                                width: targetSize.width,
                                height: targetSize.height
                            )
                        }
                    }
                }) {
                    HStack {
                        if viewModel.isSaving {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(viewModel.isSaving ? "Generating..." : "Generate Batch")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(colors: [.orange, .orange.opacity(0.8)],
                                     startPoint: .leading,
                                     endPoint: .trailing)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(viewModel.isSaving || viewModel.premiumMakerConfiguration.selectedImage == nil)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 300)
    }
    
    private func premiumFeatureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 32)
            
            Text(text)
                .font(.body)
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
    }
}



//
//struct PremiumMakerView: View {
//    var body: some View {
//        
//    Text("Hello")
//    }
//    
//    
//    
//}


#Preview {
    PremiumMakerView()
}
