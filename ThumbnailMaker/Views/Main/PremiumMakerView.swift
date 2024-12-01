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
    @FocusState private var isFocused: Bool
    @State private var isSettingsPresented: Bool = false
    @Namespace private var bottomID
    @Namespace private var topID
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                let availableWidth = geometry.size.width - 40
                let availableHeight = geometry.size.height * viewModel.usableHeightProportion
                let previewHeight = availableHeight * viewModel.previewHeightProportion
                let previewWidth = previewHeight * viewModel.premiumMakerConfiguration.selectedRatio.value
                
                ScrollViewReader { proxy in
                    ScrollView {
                        // Invisible anchor point for top scrolling
                        Color.clear.frame(height: 0).id(topID)
                        
                        // Controls Section
                        VStack(spacing: 0) {
                            PremiumCustomizationControlComponentView(configuration: $viewModel.premiumMakerConfiguration)
                        
                            
                            // Action buttons
                            HStack(spacing: 20) {
                                PhotosPicker(selection: $viewModel.imageSelection,
                                           matching: .images) {
                                    Text("Select Image")
                                        .padding()
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                }
                                
                                if viewModel.premiumMakerConfiguration.selectedImage != nil {
                                    PhotosPicker(selection: $viewModel.profileImageSelection,
                                               matching: .images) {
                                        Text("Add Profile")
                                            .padding()
                                            .background(Color.blue)
                                            .foregroundColor(.white)
                                            .cornerRadius(8)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                    }
                                    
                                    Button(action: {
                                        // First unfocus the text field
                                        isFocused = false
                                        
                                        // Wait briefly for the unfocus animation to complete
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            let (targetWidth, targetHeight) = viewModel.premiumMakerConfiguration.selectedRatio.dimensions
                                            let content = PremiumPreviewComponentView(
                                                premiumMakerConfiguration: viewModel.premiumMakerConfiguration,
                                                width: targetWidth,
                                                height: targetHeight
                                            )
                                            Task {
                                                await viewModel.saveImageWithOverlay(content: content)
                                            }
                                        }
                                    }) {
                                        HStack {
                                            if viewModel.isSaving {
                                                ProgressView()
                                                    .tint(.white)
                                            }
                                            Text(viewModel.isSaving ? "Saving..." : "Save The Thumbnail")
                                        }
                                    }
                                    .disabled(viewModel.isSaving)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                            }
                            
                            if viewModel.premiumMakerConfiguration.circularProfile != nil {
                                ProfilePositionControlView(
                                    position: Binding(
                                        get: { viewModel.premiumMakerConfiguration.circularProfile?.position ?? .topRight },
                                        set: { viewModel.premiumMakerConfiguration.circularProfile?.position = $0 }
                                    )
                                )
                            }
                            
                            // .padding(.horizontal)
                            // .padding(.vertical, 8)
                        }
                        
                        // Preview Section
                        PremiumPreviewComponentView(
                            premiumMakerConfiguration: viewModel.premiumMakerConfiguration,
                            width: previewWidth,
                            height: previewHeight
                        )
                        .frame(maxWidth: availableWidth, maxHeight: previewHeight)
                        
                        // Text input
                        TextField("Enter overlay text", text: $viewModel.premiumMakerConfiguration.overlayText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(8)
                            .background(Color(uiColor: .systemGray5))
                            .cornerRadius(8)
                            .frame(height: viewModel.textFieldHeight)
                            .focused($isFocused)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 300)
                            .id(bottomID)
                            .onChange(of: isFocused) { oldValue, newValue in
                                withAnimation {
                                    if newValue {
                                        proxy.scrollTo(bottomID, anchor: .bottom)
                                    } else {
                                        proxy.scrollTo(topID, anchor: .top)
                                    }
                                }
                            }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .padding(.bottom, 8)
                .scrollDismissesKeyboard(.immediately)
            }
            .onTapGesture {
                isFocused = false
            }
            .ignoresSafeArea(.keyboard)
            .navigationTitle("William JM's Premium Maker")
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
        .alert(isPresented: $viewModel.showingSaveAlert) {
            if let error = viewModel.saveError {
                Alert(
                    title: Text("Save Failed"),
                    message: Text(error),
                    dismissButton: .default(Text("OK"))
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
