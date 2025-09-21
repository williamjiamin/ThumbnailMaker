//
//  PremiumPreviewComponentView.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/30.
//

import SwiftUI

struct PremiumPreviewComponentView: View {
    let premiumMakerConfiguration: PremiumMakerConfigurationModel
    let width: CGFloat
    let height: CGFloat
    var fallbackStateDidChange: ((Bool) -> Void)? = nil
    
    var body: some View {
        thumbnailContent
    }
    
    @ViewBuilder
    private var thumbnailContent: some View {
        ZStack {
            Rectangle()
                .fill(premiumMakerConfiguration.backgroundColor)
            
            if let image = premiumMakerConfiguration.selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
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
            }
            
            if let profile = premiumMakerConfiguration.circularProfile,
               let profileImage = profile.image {
                Image(uiImage: profileImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: width * profile.size)
                    .clipShape(Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: profile.position.alignment)
                    .padding(width * 0.05)
            }
            
            textWithFont
        }
        .frame(width: width, height: height)
        .clipped()
    }
    
    private var textWithFont: some View {
        let text = premiumMakerConfiguration.overlayText
        let fontSize = height * premiumMakerConfiguration.textSize
        
        let attributedText = FontManager.shared.getAttributedText(
            text,
            selectedFont: premiumMakerConfiguration.selectedFont,
            size: fontSize,
            color: premiumMakerConfiguration.textColor
        )
        
        // Check if any character uses fallback font
        let needsFallback = FontManager.shared.needsFallback(
            for: text,
            selectedFont: premiumMakerConfiguration.selectedFont
        )

        return Text(attributedText)
            .onAppear { fallbackStateDidChange?(needsFallback) }
            .onChange(of: needsFallback) { oldValue, newValue in
                fallbackStateDidChange?(newValue)
            }
            .truncationMode(.tail)
            .shadow(color: .black, radius: 3, x: 1, y: 1)
            .multilineTextAlignment(premiumMakerConfiguration.horizontalAlignment == .center ? .center :
                premiumMakerConfiguration.horizontalAlignment == .leading ? .leading : .trailing)
            .frame(width: width * 0.9, alignment: premiumMakerConfiguration.horizontalAlignment == .center ? .center :
                premiumMakerConfiguration.horizontalAlignment == .leading ? .leading : .trailing)
            .frame(maxHeight: .infinity, alignment: premiumMakerConfiguration.verticalAlignment == .center ? .center :
                premiumMakerConfiguration.verticalAlignment == .top ? .top : .bottom)
            .padding(.horizontal, width * 0.05)
            .padding(.vertical, height * 0.05)
    }
}

