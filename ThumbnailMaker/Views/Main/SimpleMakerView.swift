//
//  SimpleMakerView.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/28.
//

import SwiftUI
import PhotosUI

struct SimpleMakerView: View {
    @StateObject private var viewModel = SimpleMakerViewModel()
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
                let previewWidth = previewHeight * viewModel.simpleMakerConfiguration.selectedRatio.value
                
                ScrollViewReader { proxy in
                    ScrollView {
                        Color.clear.frame(height: 0).id(topID)
                        
                        // 1. Preview Section at top
                        PreviewComponentView(
                            simpleMakerConfiguration: viewModel.simpleMakerConfiguration,
                            width: previewWidth,
                            height: previewHeight
                        )
                        .frame(maxWidth: availableWidth, maxHeight: previewHeight)
                        .padding(.bottom, 16)
                        
                        // 2. Text Input Field
                        TextField("Enter overlay text", text: $viewModel.simpleMakerConfiguration.overlayText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(12)
                            .background(Color(uiColor: .systemGray5))
                            .cornerRadius(8)
                            .frame(height: viewModel.textFieldHeight)
                            .focused($isFocused)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                            .id(bottomID)
                        
                        // 3. Core Controls Section
                        VStack(spacing: 16) {
                            // Canvas Settings
                            CustomizationControlComponentView(configuration: $viewModel.simpleMakerConfiguration)
                                .padding(.horizontal, 20)
                            
                            // Action Buttons
                            HStack(spacing: 16) {
                                PhotosPicker(selection: $viewModel.imageSelection,
                                           matching: .images) {
                                    HStack {
                                        Image(systemName: "photo")
                                        Text("Select Image")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                                
                                if viewModel.simpleMakerConfiguration.selectedImage != nil {
                                    Button(action: {
                                        isFocused = false
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            let (targetWidth, targetHeight) = viewModel.simpleMakerConfiguration.selectedRatio.dimensions
                                            let content = PreviewComponentView(
                                                simpleMakerConfiguration: viewModel.simpleMakerConfiguration,
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
                                            Text(viewModel.isSaving ? "Saving..." : "Save")
                                            Image(systemName: "square.and.arrow.down")
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.green)
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                    }
                                    .disabled(viewModel.isSaving)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                        .padding(.bottom, 300) // Extra padding for keyboard
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .onTapGesture {
                isFocused = false
            }
            .ignoresSafeArea(.keyboard)
            .navigationTitle("Simple Maker")
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
        .onChange(of: viewModel.imageSelection) { oldValue, newValue in
            if newValue != nil {
                Task {
                    await viewModel.updateImage()
                }
            }
        }
    }
}

#Preview {
    SimpleMakerView()
}
