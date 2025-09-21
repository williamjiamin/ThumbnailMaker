//
//  PremiumMakerView.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/28.
//

import SwiftUI
import PhotosUI

struct PremiumMakerView: View {
    @StateObject private var viewModel = PremiumMakerViewModel()
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
    @State private var timerRefreshTrigger = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        Group {
            if purchaseManager.canAccessPremium {
                premiumContent
            } else {
                purchasePromptView
            }
        }
    }
    
    private var purchasePromptView: some View {
        VStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Premium Header
                    VStack(spacing: 12) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.linearGradient(colors: [.blue, .purple], 
                                                           startPoint: .topLeading, 
                                                           endPoint: .bottomTrailing))
                        
                        Text("Premium Maker")
                            .font(.title)
                            .bold()
                        
                        Text("Create Professional Thumbnails")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 60)
                    
                    // Feature List
                    VStack(alignment: .leading, spacing: 16) {
                        premiumFeatureRow(icon: "photo.circle", text: "Profile Image Overlay")
                        premiumFeatureRow(icon: "rectangle.stack", text: "Batch Generation")
                        premiumFeatureRow(icon: "slider.horizontal.3", text: "Advanced Controls")
                        premiumFeatureRow(icon: "square.and.arrow.down", text: "Unlimited Exports")
                    }
                    .padding(.horizontal, 32)
                    
                    Spacer()
                        .frame(height: 20)
                }
            }
            
            // Purchase and Restore Buttons in a footer
            VStack(spacing: 16) {
                if let product = purchaseManager.products.first {
                    Button(action: {
                        Task {
                            try? await purchaseManager.purchase()
                        }
                    }) {
                        Text("Upgrade to Premium (\(product.displayPrice))")
                            .bold()
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(colors: [.blue, .purple],
                                             startPoint: .leading,
                                             endPoint: .trailing)
                            )
                            .cornerRadius(16)
                    }
                }
                
                Button(action: {
                    Task {
                        await purchaseManager.restorePurchases()
                    }
                }) {
                    HStack {
                        if purchaseManager.isRestoringPurchases {
                            ProgressView()
                                .tint(.blue)
                        } else {
                            Text("Already purchased? Restore")
                                .font(.subheadline)
                        }
                    }
                    .foregroundColor(.blue)
                    .padding(.vertical, 12)
                }
                .disabled(purchaseManager.isRestoringPurchases)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
            .background(
                Color(uiColor: .systemBackground)
                    .shadow(color: .black.opacity(0.05), radius: 8, y: -4)
            )
        }
        .alert("Purchase Status", isPresented: $showingPurchaseMessage, presenting: purchaseMessage) { message in
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
        NavigationView {
            GeometryReader { geometry in
                let availableWidth = geometry.size.width - 40
                let availableHeight = geometry.size.height * viewModel.usableHeightProportion
                let previewHeight = availableHeight * viewModel.previewHeightProportion
                let previewWidth = previewHeight * viewModel.premiumMakerConfiguration.selectedRatio.value
                
                ScrollView {
                    // 1. Preview Section at top
                    PremiumPreviewComponentView(
                        premiumMakerConfiguration: viewModel.premiumMakerConfiguration,
                        width: previewWidth,
                        height: previewHeight,
                        fallbackStateDidChange: { usesFallback in
                            if viewModel.premiumMakerConfiguration.usesFallbackFont != usesFallback {
                                viewModel.premiumMakerConfiguration.usesFallbackFont = usesFallback
                            }
                        }
                    )
                    .frame(maxWidth: availableWidth, maxHeight: previewHeight)
                    .padding(.horizontal, 20)
                    
                    // 2. Text Input Field
                    TextField("Enter overlay text", text: $viewModel.premiumMakerConfiguration.overlayText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(uiColor: .systemGray6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            LinearGradient(colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                                                         startPoint: .leading,
                                                         endPoint: .trailing)
                                        )
                                )
                        )
                        .focused($focusedField, equals: .overlayText)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    
                    // 3. Core Controls Section
                    VStack(spacing: 16) {
                        // Canvas Settings
                        PremiumCustomizationControlComponentView(configuration: $viewModel.premiumMakerConfiguration)
                            .padding(.horizontal, 20)
                        
                        // Position and Size Controls
                        PremiumTextControlView(
                            textPosition: Binding(
                                get: { (viewModel.premiumMakerConfiguration.verticalAlignment,
                                       viewModel.premiumMakerConfiguration.horizontalAlignment) },
                                set: { newValue in
                                    viewModel.premiumMakerConfiguration.verticalAlignment = newValue.vertical
                                    viewModel.premiumMakerConfiguration.horizontalAlignment = newValue.horizontal
                                }
                            ),
                            profilePosition: Binding(
                                get: { viewModel.premiumMakerConfiguration.circularProfile?.position ?? .topRight },
                                set: { 
                                    if viewModel.premiumMakerConfiguration.circularProfile != nil {
                                        viewModel.premiumMakerConfiguration.circularProfile?.position = $0
                                    }
                                }
                            ),
                            profileSize: Binding(
                                get: { viewModel.premiumMakerConfiguration.circularProfile?.size ?? 0.2 },
                                set: { 
                                    if viewModel.premiumMakerConfiguration.circularProfile != nil {
                                        viewModel.premiumMakerConfiguration.circularProfile?.size = $0
                                    }
                                }
                            ),
                            textSize: $viewModel.premiumMakerConfiguration.textSize,
                            textColor: $viewModel.premiumMakerConfiguration.textColor,
                            selectedFont: $viewModel.premiumMakerConfiguration.selectedFont,
                            usesFallbackFont: $viewModel.premiumMakerConfiguration.usesFallbackFont,
                            previewText: $viewModel.premiumMakerConfiguration.overlayText
                        )
                        .padding(.horizontal, 20)
                    }
                    
                    // 4. Action Buttons
                    actionButtonsSection
                    
                    // 5. Batch Settings
                    batchSettingsSection
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .onTapGesture {
                focusedField = nil
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), 
                                              to: nil, 
                                              from: nil, 
                                              for: nil)
            }
            .ignoresSafeArea(.keyboard)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack {
                        Image(systemName: "star.circle.fill")
                            .foregroundStyle(.linearGradient(colors: [.blue, .purple], 
                                                           startPoint: .leading, 
                                                           endPoint: .trailing))
                        Text("Premium Maker")
                            .foregroundStyle(.linearGradient(colors: [.blue, .purple], 
                                                           startPoint: .leading, 
                                                           endPoint: .trailing))
                            .font(.headline)
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        isSettingsPresented.toggle()
                    }) {
                        Image(systemName: "gearshape")
                    }
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
                    message: Text("Thumbnail saved to Photos"),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
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
        .onChange(of: viewModel.imageSelection) { oldValue, newValue in
            Task {
                await viewModel.updateImage()
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
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 16) {
            // Primary actions row - Select Image and YouTube Import
            HStack(spacing: 12) {
                // Select Image button (library only)
                PhotosPicker(selection: $viewModel.imageSelection,
                           matching: .images) {
                    HStack {
                        Image(systemName: "photo")
                        Text("Select Image")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(colors: [.blue, .blue.opacity(0.8)],
                                     startPoint: .leading,
                                     endPoint: .trailing)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(10)
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
                    .background(
                        LinearGradient(colors: [.purple, .purple.opacity(0.8)],
                                     startPoint: .leading,
                                     endPoint: .trailing)
                    )
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
            
            // Secondary actions row - Profile and Save
            if viewModel.premiumMakerConfiguration.selectedImage != nil {
                HStack(spacing: 12) {
                    // Profile Image button
                    PhotosPicker(selection: $viewModel.profileImageSelection,
                               matching: .images) {
                        HStack {
                            Image(systemName: "person.crop.circle")
                            Text("Profile")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(colors: [.orange, .orange.opacity(0.8)],
                                         startPoint: .leading,
                                         endPoint: .trailing)
                        )
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    
                    // Save button
                    Button(action: {
                        focusedField = nil
                        let (targetWidth, targetHeight) = viewModel.premiumMakerConfiguration.selectedRatio.dimensions
                        let content = PremiumPreviewComponentView(
                            premiumMakerConfiguration: viewModel.premiumMakerConfiguration,
                            width: targetWidth,
                            height: targetHeight
                        )
                        Task {
                            await viewModel.saveImageWithOverlay(content: content)
                        }
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            if viewModel.isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Save")
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(colors: [.green, .green.opacity(0.8)],
                                         startPoint: .leading,
                                         endPoint: .trailing)
                        )
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(viewModel.isSaving)
                }
            }
        }
        .padding(.vertical, 16)
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
                            let (targetWidth, targetHeight) = viewModel.premiumMakerConfiguration.selectedRatio.dimensions
                            return PremiumPreviewComponentView(
                                premiumMakerConfiguration: PremiumMakerConfigurationModel(
                                    selectedImage: viewModel.premiumMakerConfiguration.selectedImage,
                                    overlayText: text,
                                    selectedRatio: viewModel.premiumMakerConfiguration.selectedRatio,
                                    backgroundColor: viewModel.premiumMakerConfiguration.backgroundColor,
                                    textColor: viewModel.premiumMakerConfiguration.textColor,
                                    textSize: viewModel.premiumMakerConfiguration.textSize,
                                    verticalAlignment: viewModel.premiumMakerConfiguration.verticalAlignment,
                                    horizontalAlignment: viewModel.premiumMakerConfiguration.horizontalAlignment,
                                    circularProfile: viewModel.premiumMakerConfiguration.circularProfile,
                                    macroConfig: viewModel.premiumMakerConfiguration.macroConfig
                                ),
                                width: targetWidth,
                                height: targetHeight
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
