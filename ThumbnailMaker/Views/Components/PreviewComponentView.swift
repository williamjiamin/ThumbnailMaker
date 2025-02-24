//
//  PreviewComponentView.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/28.
//

import SwiftUI

struct PreviewComponentView: View {
    @Binding var simpleMakerConfiguration: SimpleMakerConfigurationModel
    @Environment(\.colorScheme) private var colorScheme
    let width: CGFloat
    let height: CGFloat
    
    var body: some View {
        thumbnailContent
    }
    
    @ViewBuilder
    private var thumbnailContent: some View {
        ZStack {
            Rectangle()
                .fill(simpleMakerConfiguration.backgroundColor == Color(uiColor: .secondarySystemBackground) 
                    ? (colorScheme == .dark ? Color(uiColor: .secondarySystemBackground) : .white)
                    : simpleMakerConfiguration.backgroundColor)
            
            if let image = simpleMakerConfiguration.selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Selected thumbnail image")
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("Select an Image")
                        .font(.headline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .accessibilityLabel("Image selection placeholder")
            }
            
            textWithFont
        }
        .frame(width: width, height: height)
        .clipped()
    }
    
    private var textWithFont: some View {
        let text = simpleMakerConfiguration.overlayText
        let fontSize = max(1, height * simpleMakerConfiguration.textSize)
        
        let attributedText = FontManager.shared.getAttributedText(
            text,
            selectedFont: simpleMakerConfiguration.selectedFont,
            size: fontSize,
            color: simpleMakerConfiguration.textColor
        )
        
        // Check if any character uses fallback font
        let needsFallback = text.unicodeScalars.contains { scalar in
            let script = FontManager.shared.getScript(for: scalar)
            return !simpleMakerConfiguration.selectedFont.supportedScripts.contains(script)
        }
        
        return Text(attributedText)
            .onChange(of: needsFallback) { oldValue, newValue in
                simpleMakerConfiguration.usesFallbackFont = newValue
            }
            .truncationMode(.tail)
            .shadow(color: .black, radius: 3, x: 1, y: 1)
            .multilineTextAlignment(simpleMakerConfiguration.horizontalAlignment == .center ? .center :
                simpleMakerConfiguration.horizontalAlignment == .leading ? .leading : .trailing)
            .frame(width: width * 0.9, alignment: simpleMakerConfiguration.horizontalAlignment == .center ? .center :
                simpleMakerConfiguration.horizontalAlignment == .leading ? .leading : .trailing)
            .frame(maxHeight: height * 0.9, alignment: simpleMakerConfiguration.verticalAlignment == .center ? .center :
                simpleMakerConfiguration.verticalAlignment == .top ? .top : .bottom)
            .padding(.horizontal, width * 0.05)
            .padding(.vertical, height * 0.05)
    }
}

//#Preview {
//    PreviewComponentView()
//}
