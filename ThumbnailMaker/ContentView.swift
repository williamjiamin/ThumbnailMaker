//  ContentView.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/22.
//

import SwiftUI
import PhotosUI

enum AspectRatio: String, CaseIterable {
    case ratio16_9 = "16:9"
    case ratio9_16 = "9:16"
    case ratio1_1 = "1:1"
    case ratio4_3 = "4:3"
    case ratio3_4 = "3:4"
    
    var value: CGFloat {
        switch self {
        case .ratio16_9: return 16.0/9.0
        case .ratio9_16: return 9.0/16.0
        case .ratio1_1: return 1.0
        case .ratio4_3: return 4.0/3.0
        case .ratio3_4: return 3.0/4.0
        }
    }
    
    var dimensions: (width: CGFloat, height: CGFloat) {
        switch self {
        case .ratio16_9: return (1024, 576)
        case .ratio9_16: return (576, 1024)
        case .ratio1_1: return (1024, 1024)
        case .ratio4_3: return (1024, 768)
        case .ratio3_4: return (768, 1024)
        }
    }
}

struct ContentView: View {
    @State private var selectedImage: UIImage?
    @State private var imageSelection: PhotosPickerItem?
    @State private var overlayText: String = ""
    @State private var showingSaveAlert = false
    @State private var saveError: String?
    @FocusState private var isFocused : Bool
    @State private var selectedRatio: AspectRatio = .ratio16_9
    @State private var backgroundColor: Color = .yellow  // Default yellow as per current code
    @State private var textColor: Color = .white        // Default white as per current code
    @State private var textSize: CGFloat = 0.1          // Default 0.1 as per current code
    @State private var verticalAlignment: VerticalAlignment = .center
    @State private var horizontalAlignment: HorizontalAlignment = .center
    
    // Add a constant for preview proportion
    private let controlsHeight: CGFloat = 380       // Increased to accommodate all sections
    private let usableHeightProportion: CGFloat = 0.6  // Use 60% of the screen for the entire UI, leave 40% for keyboard
    private let previewHeightProportion: CGFloat = 0.35  // Allocate 35% of the usable height to the preview
    private let textFieldHeight: CGFloat = 50       // Fixed height for the text editor to reduce space
    
    // Add enum for alignment options
    enum VerticalAlignment: String, CaseIterable {
        case top = "Top"
        case center = "Center"
        case bottom = "Bottom"
    }

    enum HorizontalAlignment: String, CaseIterable {
        case leading = "Left"
        case center = "Center"
        case trailing = "Right"
    }
    
    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - 40
            let availableHeight = geometry.size.height * usableHeightProportion
            let previewHeight = availableHeight * previewHeightProportion
            let previewWidth = previewHeight * selectedRatio.value
            
            ScrollView { // Added ScrollView to allow scrolling when keyboard appears
                VStack(spacing: 24) { // Increased spacing between main sections
                    // Title Section
                    Text("William JM's Thumbnail Maker")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.top, 10)
                        .padding(.bottom, 20)
                    
                    // Top Controls Section
                    VStack(spacing: 16) {
                        // All controls container
                        VStack(spacing: 12) {
                            // Aspect Ratio Section
                            VStack(spacing: 8) {
                                Text("Choose Ratio")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(AspectRatio.allCases, id: \.self) { ratio in
                                            Button(ratio.rawValue) {
                                                selectedRatio = ratio
                                            }
                                            .padding(8)
                                            .background(selectedRatio == ratio ? Color.blue : Color.gray.opacity(0.3))
                                            .foregroundColor(.white)
                                            .cornerRadius(8)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            
                            Divider()
                            
                            // Customize Appearance Section
                            VStack(spacing: 8) {
                                Text("Customize Appearance")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal)
                                
                                HStack(spacing: 20) {
                                    // Background color picker
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Background")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        ColorPicker("", selection: $backgroundColor)
                                            .frame(width: 100)
                                    }
                                    
                                    // Text color picker
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Text Color")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        ColorPicker("", selection: $textColor)
                                            .frame(width: 100)
                                    }
                                    
                                    // Text size slider
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Text Size")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Slider(value: $textSize, in: 0.05...0.2)
                                            .frame(width: 100)
                                            .tint(.blue)
                                    }
                                }
                                .padding(.horizontal)
                            }
                            
                            Divider()
                            
                            // Text Position Section
                            VStack(spacing: 8) {
                                Text("Text Position")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal)
                                
                                VStack(spacing: 8) {
                                    // Vertical alignment
                                    HStack {
                                        Text("Vertical:")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Picker("", selection: $verticalAlignment) {
                                            ForEach(VerticalAlignment.allCases, id: \.self) { alignment in
                                                Text(alignment.rawValue).tag(alignment)
                                            }
                                        }
                                        .pickerStyle(.segmented)
                                    }
                                    
                                    // Horizontal alignment
                                    HStack {
                                        Text("Horizontal:")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Picker("", selection: $horizontalAlignment) {
                                            ForEach(HorizontalAlignment.allCases, id: \.self) { alignment in
                                                Text(alignment.rawValue).tag(alignment)
                                            }
                                        }
                                        .pickerStyle(.segmented)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical, 8)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        
                        // Action buttons
                        HStack(spacing: 20) {
                            PhotosPicker(selection: $imageSelection,
                                        matching: .images) {
                                Text("Select Image")
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            
                            if selectedImage != nil {
                                Button("Save The Thumbnail") {
                                    saveImageWithOverlay()
                                }
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: controlsHeight)
                    .padding(.bottom, 16) // Added padding to create space between controls and preview
                    
                    // Preview Section (fixed proportion of the usable height)
                    if let selectedImage {
                        thumbnailContent(
                            width: previewWidth,
                            height: previewHeight,
                            text: overlayText,
                            image: selectedImage
                        )
                        .frame(maxWidth: availableWidth, maxHeight: previewHeight)
                        .background(Color.clear)
                    } else {
                        ZStack {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: previewWidth, height: previewHeight)
                            Text("Select an image to preview")
                                .foregroundColor(.gray)
                                .font(.headline)
                        }
                        .frame(maxWidth: availableWidth, maxHeight: previewHeight)
                        .padding(.top, 10)
                    }
                    
                    // Text input (positioned directly below the preview)
                    TextField("Enter overlay text", text: $overlayText)
                        .padding(8)
                        .background(Color(uiColor: .systemGray5)) // Made the background slightly less transparent
                        .cornerRadius(8)
                        .frame(height: textFieldHeight)
                        .focused($isFocused)
                        .padding(.horizontal, 20)
                        .padding(.top, 16) // Added padding to separate text field from the preview
                        .padding(.bottom, 300) // Add more padding to allow for better scroll visibility in smaller devices
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.top, 10) // Add a bit of padding at the top
            }
            .background(Color(uiColor: .systemBackground))
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .contentShape(Rectangle())
        .simultaneousGesture(
                        TapGesture()
                            .onEnded { _ in
                                if isFocused {
                                    isFocused = false
                                }
                            }
                    )
        .onChange(of: imageSelection) { oldValue, newValue in
            Task {
                if let data = try? await newValue?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    selectedImage = uiImage
                }
            }
        }
        .alert("Save Status", isPresented: $showingSaveAlert) {
            Button("OK") {}
        } message: {
            Text(saveError ?? "Thumbnail saved successfully!")
        }
    }
    
    @MainActor
    private func saveImageWithOverlay() {
        guard let selectedImage else { return }
        
        let (targetWidth, targetHeight) = selectedRatio.dimensions
        
        let renderer = ImageRenderer(content:
            thumbnailContent(
                width: targetWidth,
                height: targetHeight,
                text: overlayText,
                image: selectedImage
            )
        )
        
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
    
    @ViewBuilder
    private func thumbnailContent(width: CGFloat, height: CGFloat, text: String, image: UIImage) -> some View {
        ZStack {
            Rectangle()
                .fill(backgroundColor)
            
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
            
            Text(text)
                .font(.system(size: height * textSize, weight: .bold))
                .foregroundColor(textColor)
                .shadow(color: .black, radius: 3, x: 1, y: 1)
                .multilineTextAlignment(horizontalAlignment == .center ? .center : 
                          horizontalAlignment == .leading ? .leading : .trailing)
                .frame(width: width * 0.9, alignment: horizontalAlignment == .center ? .center : 
                       horizontalAlignment == .leading ? .leading : .trailing)
                .frame(maxHeight: .infinity, alignment: verticalAlignment == .center ? .center :
                       verticalAlignment == .top ? .top : .bottom)
                .padding(.horizontal, width * 0.05)
                .padding(.vertical, height * 0.05)
        }
        .frame(width: width, height: height)
        .clipped()
    }
}

#Preview {
    ContentView()
}
