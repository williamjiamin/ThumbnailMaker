//
//  AspectRatioSelectorComponentView.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/28.
//

import SwiftUI

struct AspectRatioSelectorComponentView: View {
    @Binding var selectedRatio: AspectRatio
    
    var body: some View {
        VStack(spacing: 8) {
            Text("Aspect Ratio")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(AspectRatio.allCases, id: \.self) { ratio in
                        Button(action: {
                            selectedRatio = ratio
                        }) {
                            Text(ratio.rawValue)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(selectedRatio == ratio ? Color.blue : Color.gray.opacity(0.2))
                                .foregroundColor(selectedRatio == ratio ? .white : .primary)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

#Preview {
    AspectRatioSelectorComponentView(selectedRatio: .constant(.ratio16_9))
}
