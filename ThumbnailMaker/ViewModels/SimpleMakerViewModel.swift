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
    @Published var isPermissionError = false
    
    let usableHeightProportion: CGFloat = 0.6
    let previewHeightProportion: CGFloat = 0.35
    let overlayCharacterLimit = 120
    
    func updateImage() async {
        if let data = try? await imageSelection?.loadTransferable(type: Data.self),
           let uiImage = UIImage(data: data) {
            await MainActor.run {
                simpleMakerConfiguration.selectedImage = uiImage
            }
        }
    }
    
    func saveImageWithOverlay(content: some View) async {
        guard simpleMakerConfiguration.selectedImage != nil else { return }
        
        await MainActor.run {
            isSaving = true
        }
        
        let (targetWidth, targetHeight) = simpleMakerConfiguration.selectedRatio.dimensions
        let renderer = ImageRenderer(content: content)
        
        renderer.proposedSize = ProposedViewSize(width: targetWidth, height: targetHeight)
        renderer.scale = 3
        renderer.colorMode = .nonLinear
        
        if let renderedImage = renderer.uiImage {
            do {
                // Check photo library authorization status first
                let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
                switch status {
                case .notDetermined:
                    let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized
                    if !granted {
                        throw NSError(domain: "PhotoPermissionError", code: 1, 
                                    userInfo: [NSLocalizedDescriptionKey: "Photo library access denied"])
                    }
                case .restricted, .denied:
                    throw NSError(domain: "PhotoPermissionError", code: 1, 
                                userInfo: [NSLocalizedDescriptionKey: "Photo library access denied"])
                case .authorized, .limited:
                    break
                @unknown default:
                    break
                }
                
                try await PhotosUI.PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: renderedImage)
                }
                
                await MainActor.run {
                    saveError = nil
                    showingSaveAlert = true
                    isSaving = false
                }
            } catch {
                await MainActor.run {
                    if (error as NSError).domain == "PhotoPermissionError" {
                        isPermissionError = true
                        saveError = "This app needs permission to save photos. Please open Settings > Privacy & Security > Photos and allow access for this app."
                    } else {
                        isPermissionError = false
                        saveError = "Failed to save: \(error.localizedDescription)"
                    }
                    showingSaveAlert = true
                    isSaving = false
                }
            }
        } else {
            await MainActor.run {
                isSaving = false
            }
        }
    }
    
    func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

