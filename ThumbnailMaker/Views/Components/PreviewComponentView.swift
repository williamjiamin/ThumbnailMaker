//
//  PreviewComponentView.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/28.
//

import SwiftUI

struct PreviewComponentView: View {
    let simpleMakerConfigration: SimpleMakerConfigurationModel
    let width: CGFloat
    let height: CGFloat
    
    var body: some View {
        thumbnailContent
    }
    
    
    @ViewBuilder
    private var thumbnailContent: some View {
        ZStack {
            Rectangle()
                .fill(simpleMakerConfigration.backgroundColor)
            
            if let image =  simpleMakerConfigration.selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
            
            Text(simpleMakerConfigration.overlayText)
                .font(.system(size: height * simpleMakerConfigration.textSize, weight: .bold))
                .foregroundColor(simpleMakerConfigration.textColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .shadow(color: .black, radius: 3, x: 1, y: 1)
                .multilineTextAlignment(simpleMakerConfigration.horizontalAlignment == .center ? .center :
                                            simpleMakerConfigration.horizontalAlignment == .leading ? .leading : .trailing)
                .frame(width: width * 0.9, alignment: simpleMakerConfigration.horizontalAlignment == .center ? .center :
                        simpleMakerConfigration.horizontalAlignment == .leading ? .leading : .trailing)
                .frame(maxHeight: .infinity, alignment: simpleMakerConfigration.verticalAlignment == .center ? .center :
                        simpleMakerConfigration.verticalAlignment == .top ? .top : .bottom)
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
