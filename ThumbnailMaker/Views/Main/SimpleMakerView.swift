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
                
                ScrollView {
                    // 1. Preview Section at top
                    PreviewComponentView(
                        simpleMakerConfiguration: viewModel.simpleMakerConfiguration,
                        width: previewWidth,
                        height: previewHeight
                    )
                    .frame(maxWidth: availableWidth, maxHeight: previewHeight)
                    .padding(.horizontal, 20)
                    
                    // 2. Text Input Field
                    TextField("Enter overlay text", text: $viewModel.simpleMakerConfiguration.overlayText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(uiColor: .systemGray5))
                        )
                        .focused($isFocused)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    
                    // 3. Core Controls Section
                    VStack(spacing: 16) {
                        // Canvas Settings
                        CustomizationControlComponentView(configuration: $viewModel.simpleMakerConfiguration)
                            .padding(.horizontal, 20)
                        
                        // Text Position Controls
                        TextPositionControlView(
                            verticalAlignment: $viewModel.simpleMakerConfiguration.verticalAlignment,
                            horizontalAlignment: $viewModel.simpleMakerConfiguration.horizontalAlignment,
                            textSize: $viewModel.simpleMakerConfiguration.textSize,
                            textColor: $viewModel.simpleMakerConfiguration.textColor
                        )
                        .padding(.horizontal, 20)
                    }
                    
                    // 4. Action Buttons
                    HStack(spacing: 12) {
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
                        
                        if viewModel.simpleMakerConfiguration.selectedImage != nil {
                            Button(action: {
                                isFocused = false
                                let (targetWidth, targetHeight) = viewModel.simpleMakerConfiguration.selectedRatio.dimensions
                                let content = PreviewComponentView(
                                    simpleMakerConfiguration: viewModel.simpleMakerConfiguration,
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
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 300)
                }
                .frame(maxWidth: .infinity, alignment: .top)
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
