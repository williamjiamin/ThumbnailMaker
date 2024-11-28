//
//  SimpleMakerViewModel.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/28.
//

import SwiftUI
import PhotosUI

@MainActor
class SimpleMakerViewModel: ObservableObject {
    @Published var simpleMakerConfigration = SimpleMakerConfigurationModel()
    @Published var imageSelection: PhotosPickerItem?
    @Published var saveError: String?
    @State private var showingSaveAlert = false
//    i don't think it should be here
    @Published var selectedTab: Tab = .simpleMaker
    
    // Add a constant for preview proportion
    let controlsHeight: CGFloat = 380       // Increased to accommodate all sections
    let usableHeightProportion: CGFloat = 0.6  // Use 60% of the screen for the entire UI, leave 40% for keyboard
    let previewHeightProportion: CGFloat = 0.35  // Allocate 35% of the usable height to the preview
    let textFieldHeight: CGFloat = 50       // Fixed height for the text editor to reduce space
    
    
    func updateImage() async {
        if let data = try? await imageSelection?.loadTransferable(type: Data.self),
           let uiImage = UIImage(data: data) {
            simpleMakerConfigration.selectedImage = uiImage
        }
    }
    
    
    
    func saveImageWithOverlay(content: some View) {
        guard simpleMakerConfigration.selectedImage != nil else { return }
        
        let (targetWidth, targetHeight) = simpleMakerConfigration.selectedRatio.dimensions
        let renderer = ImageRenderer(content: content)
        
        // Configure renderer
        renderer.scale = 2
        renderer.colorMode = .nonLinear
        
        // Generate the final image
        if let renderedImage = renderer.uiImage {
            Task {
                do {
                    try await PhotosUI.PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAsset(from: renderedImage)
                    }
                    saveError = nil
                } catch {
                    saveError = "Failed to save: \(error.localizedDescription)"
                }
                showingSaveAlert = true
            }
        }
    }
    
    
    
    
}
