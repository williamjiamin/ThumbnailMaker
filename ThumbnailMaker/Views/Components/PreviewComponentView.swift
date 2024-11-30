//
//  PreviewComponentView.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/28.
//

import SwiftUI

struct PreviewComponentView: View {
    let simpleMakerConfiguration: SimpleMakerConfigurationModel
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
            
            Text(simpleMakerConfiguration.overlayText)
                .font(.system(size: height * simpleMakerConfiguration.textSize, weight: .bold))
                .foregroundColor(simpleMakerConfiguration.textColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .shadow(color: .black, radius: 3, x: 1, y: 1)
                .multilineTextAlignment(simpleMakerConfiguration.horizontalAlignment == .center ? .center :
                    simpleMakerConfiguration.horizontalAlignment == .leading ? .leading : .trailing)
                .frame(width: width * 0.9, alignment: simpleMakerConfiguration.horizontalAlignment == .center ? .center :
                    simpleMakerConfiguration.horizontalAlignment == .leading ? .leading : .trailing)
                .frame(maxHeight: .infinity, alignment: simpleMakerConfiguration.verticalAlignment == .center ? .center :
                    simpleMakerConfiguration.verticalAlignment == .top ? .top : .bottom)
                .padding(.horizontal, width * 0.05)
                .padding(.vertical, height * 0.05)
        }
        .frame(width: width, height: height)
        .clipped()
    }
}

//#Preview {
//    PreviewComponentView()
//}
