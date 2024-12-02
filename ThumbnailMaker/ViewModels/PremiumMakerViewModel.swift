//
//  PremiumMakerViewModel.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/28.
//

import SwiftUI
import PhotosUI

@MainActor
class PremiumMakerViewModel: ObservableObject {
    @Published var premiumMakerConfiguration = PremiumMakerConfigurationModel()
    @Published var imageSelection: PhotosPickerItem?
    @Published var saveError: String?
    @Published var showingSaveAlert = false
    @Published var isSaving = false
    @Published var profileImageSelection: PhotosPickerItem?
    @Published var showingProfileCropper = false
    @Published var tempProfileImage: UIImage?
    @Published var isPermissionError = false
    
    // Add a constant for preview proportion
    let usableHeightProportion: CGFloat = 0.6  // Use 60% of the screen for the entire UI, leave 40% for keyboard
    let previewHeightProportion: CGFloat = 0.35  // Allocate 35% of the usable height to the preview
    let textFieldHeight: CGFloat = 50       // Fixed height for the text editor to reduce space
    
    
    func updateImage() async {
        if let data = try? await imageSelection?.loadTransferable(type: Data.self) {
            // Create a new image instance from data
            if let uiImage = UIImage(data: data) {
                await MainActor.run {
                    premiumMakerConfiguration.selectedImage = uiImage
                }
            }
        }
    }
    
    
    
    func saveImageWithOverlay(content: some View) async {
        guard premiumMakerConfiguration.selectedImage != nil else { return }
        
        await MainActor.run {
            isSaving = true
        }
        
        let (targetWidth, targetHeight) = premiumMakerConfiguration.selectedRatio.dimensions
        let renderer = ImageRenderer(content: content)
        
        renderer.proposedSize = ProposedViewSize(width: targetWidth, height: targetHeight)
        renderer.scale = 2.0
        renderer.colorMode = .nonLinear
        
        if let renderedImage = renderer.uiImage {
            UIGraphicsBeginImageContextWithOptions(renderedImage.size, false, 2.0)
            renderedImage.draw(in: CGRect(origin: .zero, size: renderedImage.size))
            let optimizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            if let optimizedImage = optimizedImage {
                do {
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
                        
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAsset(from: optimizedImage)
                    }
                        
                    await MainActor.run {
                        saveError = nil
                        showingSaveAlert = true
                        isSaving = false
                        imageSelection = nil
                        profileImageSelection = nil
                    }
                } catch {
                    await MainActor.run {
                        if (error as NSError).domain == "PhotoPermissionError" {
                            isPermissionError = true
                            saveError = "This app needs permission to save photos. Please open Settings > Privacy & Security > Photos and allow access for this app."
                        } else {
                            isPermissionError = false
                            saveError = "Save failed: \(error.localizedDescription)"
                        }
                        showingSaveAlert = true
                        isSaving = false
                    }
                }
            } else {
                await MainActor.run {
                    saveError = "Failed to render image"
                    showingSaveAlert = true
                    isSaving = false
                }
            }
        }
    }
    
    func updateProfileImage() async {
        if let data = try? await profileImageSelection?.loadTransferable(type: Data.self) {
            // Create a separate image instance from data
            if let uiImage = UIImage(data: data) {
                await MainActor.run {
                    tempProfileImage = uiImage
                    showingProfileCropper = true
                }
            }
        }
    }
    
    func setProfileImage(_ image: UIImage) {
        if premiumMakerConfiguration.circularProfile == nil {
            premiumMakerConfiguration.circularProfile = CircularProfileConfig(
                image: image,
                position: .topRight,
                size: 0.2
            )
        } else {
            premiumMakerConfiguration.circularProfile?.image = image
        }
    }
    
    func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    func generateBatchImages(content: @escaping (String) -> some View) async {
        guard premiumMakerConfiguration.macroConfig.isEnabled else { return }
        
        let start = premiumMakerConfiguration.macroConfig.startNumber
        let end = premiumMakerConfiguration.macroConfig.endNumber
        let baseText = premiumMakerConfiguration.overlayText
        
        await MainActor.run {
            isSaving = true
        }
        
        for number in start...end {
            let text = premiumMakerConfiguration.macroConfig.appendPosition == .after ?
                "\(baseText) \(number)" : "\(number) \(baseText)"
            
            // Temporarily update the overlay text
            await MainActor.run {
                premiumMakerConfiguration.overlayText = text
            }
            
            // Generate and save the image
            await saveImageWithOverlay(content: content(text))
            
            // Small delay between saves to prevent overwhelming the system
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        // Restore original text
        await MainActor.run {
            premiumMakerConfiguration.overlayText = baseText
            isSaving = false
        }
    }
}
