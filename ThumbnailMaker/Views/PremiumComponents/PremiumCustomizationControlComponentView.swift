//
//  PremiumCustomizationControlComponentView.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/30.
//

import Foundation
import SwiftUI

struct PremiumCustomizationControlComponentView: View {
    @Binding var configuration: PremiumMakerConfigurationModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Canvas Settings Section
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("Canvas Settings")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(AspectRatio.allCases, id: \.self) { ratio in
                                Button(action: {
                                    configuration.selectedRatio = ratio
                                }) {
                                    Text(ratio.rawValue)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(configuration.selectedRatio == ratio ? Color.blue : Color.gray.opacity(0.2))
                                        .foregroundColor(configuration.selectedRatio == ratio ? .white : .primary)
                                        .cornerRadius(8)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                Divider()
                    .frame(height: 40)
                    .padding(.horizontal)
                
                VStack(alignment: .center, spacing: 4) {
                    Text("Background")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ColorPicker("", selection: $configuration.backgroundColor)
                        .labelsHidden()
                }
                .frame(width: 100, alignment: .center)
                .padding(.trailing)
            }
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(12)
        }
    }
}

#Preview {
    PremiumCustomizationControlComponentView(configuration: .constant(PremiumMakerConfigurationModel()))
}
