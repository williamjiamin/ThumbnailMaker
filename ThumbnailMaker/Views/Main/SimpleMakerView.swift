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
                let previewWidth = previewHeight * viewModel.simpleMakerConfigration.selectedRatio.value
                
                ScrollViewReader { proxy in
                    ScrollView {
                        // Controls Section
                        VStack(spacing: 16) {
                            Color.clear.frame(height: 1).id(topID)
                            
                            CustomizationControlComponentView(configuration: $viewModel.simpleMakerConfigration)
                                .frame(height: viewModel.controlsHeight)
                                .padding(.bottom, 16)
                            
                            // Action buttons
                            HStack(spacing: 20) {
                                PhotosPicker(selection: $viewModel.imageSelection,
                                           matching: .images) {
                                    Text("Select Image")
                                        .padding()
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                                
                                if viewModel.simpleMakerConfigration.selectedImage != nil {
                                    Button("Save The Thumbnail") {
                                        let (targetWidth, targetHeight) = viewModel.simpleMakerConfigration.selectedRatio.dimensions
                                        viewModel.saveImageWithOverlay(content: PreviewComponentView(
                                            simpleMakerConfigration: viewModel.simpleMakerConfigration,
                                            width: targetWidth,
                                            height: targetHeight
                                        ))
                                    }
                                    .padding()
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal)
                        }
                        
                        // Preview Section
                        PreviewComponentView(
                            simpleMakerConfigration: viewModel.simpleMakerConfigration,
                            width: previewWidth,
                            height: previewHeight
                        )
                        .frame(maxWidth: availableWidth, maxHeight: previewHeight)
                        
                        // Text input
                        TextField("Enter overlay text", text: $viewModel.simpleMakerConfigration.overlayText)
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
                    .padding(.top, 10)
                }
                .padding(.bottom, 8)
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
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
        .onChange(of: viewModel.imageSelection) { oldValue, newValue in
            Task {
                await viewModel.updateImage()
            }
        }
    }
}

#Preview {
    SimpleMakerView()
}
