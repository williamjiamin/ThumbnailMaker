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
        if let data = try? await imageSelection?.loadTransferable(type: Data.self),
           let uiImage = UIImage(data: data) {
            premiumMakerConfiguration.selectedImage = uiImage
        }
    }
    
    
    
    func saveImageWithOverlay(content: some View) async {
        guard premiumMakerConfiguration.selectedImage != nil else { return }
        
        // Set initial state
        await MainActor.run {
            isSaving = true
        }
        
        let (targetWidth, targetHeight) = premiumMakerConfiguration.selectedRatio.dimensions
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
    
    func updateProfileImage() async {
        if let data = try? await profileImageSelection?.loadTransferable(type: Data.self),
           let uiImage = UIImage(data: data) {
            await MainActor.run {
                tempProfileImage = uiImage
                showingProfileCropper = true
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
}
