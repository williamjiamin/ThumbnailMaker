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
    @Published var simpleMakerConfiguration = SimpleMakerConfigurationModel()
    @Published var imageSelection: PhotosPickerItem?
    @Published var saveError: String?
    @Published var showingSaveAlert = false
    @Published var isSaving = false
//    i don't think it should be here
    
    // Add a constant for preview proportion
    let usableHeightProportion: CGFloat = 0.6  // Use 60% of the screen for the entire UI, leave 40% for keyboard
    let previewHeightProportion: CGFloat = 0.35  // Allocate 35% of the usable height to the preview
    let textFieldHeight: CGFloat = 50       // Fixed height for the text editor to reduce space
    
    
    func updateImage() async {
        if let data = try? await imageSelection?.loadTransferable(type: Data.self),
           let uiImage = UIImage(data: data) {
            simpleMakerConfiguration.selectedImage = uiImage
        }
    }
    
    
    
    func saveImageWithOverlay(content: some View) async {
        guard simpleMakerConfiguration.selectedImage != nil else { return }
        
        let (targetWidth, targetHeight) = simpleMakerConfiguration.selectedRatio.dimensions
        let renderer = ImageRenderer(content: content)
        
        renderer.proposedSize = ProposedViewSize(width: targetWidth, height: targetHeight)
        renderer.scale = 3
        renderer.colorMode = .nonLinear
        
        if let renderedImage = renderer.uiImage {
            withAnimation {
                isSaving = true
            }
            
            do {
                try await PhotosUI.PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: renderedImage)
                }
                withAnimation {
                    saveError = nil
                    showingSaveAlert = true
                    isSaving = false
                }
            } catch {
                withAnimation {
                    saveError = "Failed to save: \(error.localizedDescription)"
                    showingSaveAlert = true
                    isSaving = false
                }
            }
        }
    }
    
    
    
}
