//  ContentView.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/22.
//

import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var viewModel = SimpleMakerViewModel()
    @FocusState private var isFocused: Bool
    @State private var isSettingsPresented: Bool = false
    
    var body: some View {
        ZStack {
            NavigationView {
                GeometryReader { geometry in
                    let availableWidth = geometry.size.width - 40
                    let availableHeight = geometry.size.height * viewModel.usableHeightProportion
                    let previewHeight = availableHeight * viewModel.previewHeightProportion
                    let previewWidth = previewHeight * viewModel.simpleMakerConfigration.selectedRatio.value
                    
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(spacing: 24) {
                                // Controls Section
                                VStack(spacing: 16) {
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
                                                viewModel.saveImageWithOverlay(content: PreviewComponentView(
                                                    simpleMakerConfigration: viewModel.simpleMakerConfigration,
                                                    width: previewWidth,
                                                    height: previewHeight
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
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                            .padding(.top, 10)
                        }
                        .padding(.bottom, 8)
                        
                        Spacer()
                        
                        // Bottom menu bar
                        TabBarView(selectedTab: $viewModel.selectedTab)
                    }
                }
                .navigationTitle("William JM's " + viewModel.selectedTab.rawValue)
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
        }
        .animation(.default, value: isSettingsPresented)
        .onChange(of: viewModel.imageSelection) { _ in
            Task {
                await viewModel.updateImage()
            }
        }
    }
}

#Preview {
    ContentView()
}
