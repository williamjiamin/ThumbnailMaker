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
    @Namespace private var bottomID
    @Namespace private var topID
    @State private var showingPurchaseAlert = false
    @State private var showingToast = false
    @State private var toastMessage = ""
    @State private var showingMacroSettings = false
    
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
        VStack(spacing: 20) {
            Text("Unlock Premium Features")
                .font(.title)
                .bold()
            
            Text("You've used all your free trials. Upgrade to continue creating professional thumbnails.")
                .multilineTextAlignment(.center)
                .padding()
            
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
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
            } else {
                ProgressView()
                    .padding()
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
                
                ScrollViewReader { proxy in
                    ScrollView {
                        Color.clear.frame(height: 0).id(topID)
                        
                        // 1. Preview Section at top
                        PremiumPreviewComponentView(
                            premiumMakerConfiguration: viewModel.premiumMakerConfiguration,
                            width: previewWidth,
                            height: previewHeight
                        )
                        .frame(maxWidth: availableWidth, maxHeight: previewHeight)
                        .padding(.bottom, 16)
                        
                        // 2. Text Input Field
                        TextField("Enter overlay text", text: $viewModel.premiumMakerConfiguration.overlayText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(12)
                            .background(Color(uiColor: .systemGray5))
                            .cornerRadius(8)
                            .frame(height: viewModel.textFieldHeight)
                            .focused($focusedField, equals: .overlayText)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                            .id(bottomID)
                        
                        // 3. Core Controls Section
                        VStack(spacing: 16) {
                            // Canvas Settings
                            PremiumCustomizationControlComponentView(configuration: $viewModel.premiumMakerConfiguration)
                                .padding(.horizontal, 20)
                            
                            // Position and Size Controls
                            UnifiedPositionControlView(
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
                                textColor: $viewModel.premiumMakerConfiguration.textColor
                            )
                            .padding(.horizontal, 20)
                        }
                        
                        // 4. Action Buttons
                        HStack(spacing: 12) {
                            PhotosPicker(selection: $viewModel.imageSelection,
                                       matching: .images) {
                                HStack {
                                    Image(systemName: "photo")
                                    Text("Image")
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            
                            if viewModel.premiumMakerConfiguration.selectedImage != nil {
                                PhotosPicker(selection: $viewModel.profileImageSelection,
                                           matching: .images) {
                                    HStack {
                                        Image(systemName: "person.crop.circle")
                                        Text("Profile")
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                                
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
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                                .disabled(viewModel.isSaving)
                            }
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 20)
                        
                        // 5. Batch Settings
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
                                .background(Color(uiColor: .secondarySystemBackground))
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
                                    .background(Color.orange)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                                .disabled(viewModel.isSaving || viewModel.premiumMakerConfiguration.selectedImage == nil)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 300)
                    }
                    .onChange(of: focusedField) { oldValue, newValue in
                        withAnimation {
                            if newValue != nil {
                                proxy.scrollTo(bottomID, anchor: .bottom)
                            } else {
                                proxy.scrollTo(topID, anchor: .top)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .padding(.bottom, 8)
                .scrollDismissesKeyboard(.immediately)
            }
            .onTapGesture {
                focusedField = nil
            }
            .ignoresSafeArea(.keyboard)
            .navigationTitle("Premium Maker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
