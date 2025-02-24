//
//  PreviewComponentView.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/28.
//

import SwiftUI

struct PreviewComponentView: View {
    @Binding var simpleMakerConfiguration: SimpleMakerConfigurationModel
    let width: CGFloat
    let height: CGFloat
    
    var body: some View {
        thumbnailContent
    }
    
    @ViewBuilder
    private var thumbnailContent: some View {
        ZStack {
            Rectangle()
                .fill(simpleMakerConfiguration.backgroundColor)
            
            if let image = simpleMakerConfiguration.selectedImage {
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
            
            textWithFont
        }
        .frame(width: width, height: height)
        .clipped()
    }
    
    private var textWithFont: some View {
        let (font, needsFallback) = FontManager.shared.getFontForText(
            simpleMakerConfiguration.overlayText,
            selectedFont: simpleMakerConfiguration.selectedFont
        )
        
        return Text(simpleMakerConfiguration.overlayText)
            .font(.custom(
                font.rawValue,
                size: max(1, height * simpleMakerConfiguration.textSize)
            ))
            .onChange(of: needsFallback) { oldValue, newValue in
                simpleMakerConfiguration.usesFallbackFont = newValue
            }
            .foregroundColor(simpleMakerConfiguration.textColor)
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
