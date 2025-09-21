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
    @StateObject private var purchaseManager = PurchaseManager.shared
    @FocusState private var isFocused: Bool
    @State private var isSettingsPresented: Bool = false
    @Namespace private var bottomID
    @Namespace private var topID
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let availableWidth = geometry.size.width - 40
                let availableHeight = geometry.size.height * viewModel.usableHeightProportion
                let previewHeight = availableHeight * viewModel.previewHeightProportion
                let previewWidth = previewHeight * viewModel.simpleMakerConfiguration.selectedRatio.value

                ScrollView {
                    VStack(spacing: 20) {
                        // 1. Preview Section at top
                        PreviewComponentView(
                            simpleMakerConfiguration: $viewModel.simpleMakerConfiguration,
                            width: previewWidth,
                            height: previewHeight
                        )
                        .frame(maxWidth: availableWidth, maxHeight: previewHeight)
                        .padding(.horizontal, 20)

                        // 2. Text Input Field
                        OverlayTextEditor(
                            text: $viewModel.simpleMakerConfiguration.overlayText,
                            placeholder: "Add overlay text",
                            characterLimit: viewModel.overlayCharacterLimit,
                            focus: $isFocused
                        )
                        .padding(.horizontal, 20)

                        // 3. Core Controls Section
                        VStack(spacing: 16) {
                            // Canvas Settings
                            CustomizationControlComponentView(
                                configuration: $viewModel.simpleMakerConfiguration,
                                isPremium: purchaseManager.canAccessPremium
                            )
                            .padding(.horizontal, 20)
                            
                            // Text Controls
                            TextControlView(
                                verticalAlignment: $viewModel.simpleMakerConfiguration.verticalAlignment,
                                horizontalAlignment: $viewModel.simpleMakerConfiguration.horizontalAlignment,
                                textSize: $viewModel.simpleMakerConfiguration.textSize,
                                textColor: $viewModel.simpleMakerConfiguration.textColor,
                                selectedFont: $viewModel.simpleMakerConfiguration.selectedFont,
                                usesFallbackFont: $viewModel.simpleMakerConfiguration.usesFallbackFont,
                                previewText: $viewModel.simpleMakerConfiguration.overlayText,
                                isPremium: purchaseManager.canAccessPremium
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
                                        simpleMakerConfiguration: $viewModel.simpleMakerConfiguration,
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
                        
                        
                    }
                }
                .scrollDismissesKeyboard(.immediately)
                .simultaneousGesture(
                    TapGesture().onEnded { _ in
                        isFocused = false
                    }
                )
            }
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
