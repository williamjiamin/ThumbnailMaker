//
//  CustomizationControlComponentView.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/28.
//

import SwiftUI

struct CustomizationControlComponentView: View {
    @Binding var configuration: SimpleMakerConfigurationModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Aspect Ratio Section
            AspectRatioSelectorComponentView(selectedRatio: $configuration.selectedRatio)
            
            Divider()
                .padding(.vertical, 4)
            
            // Customize Appearance Section
            VStack(spacing: 8) {
                Text("Customize Appearance")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                
                HStack(spacing: 20) {
                    // Background color picker
                    VStack(alignment: .center, spacing: 4) {
                        Text("Background")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ColorPicker("", selection: $configuration.backgroundColor)
                            .labelsHidden()
                    }
                    .frame(width: 100, alignment: .center)
                    
                    // Text color picker
                    VStack(alignment: .center, spacing: 4) {
                        Text("Text Color")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ColorPicker("", selection: $configuration.textColor)
                            .labelsHidden()
                    }
                    .frame(width: 100, alignment: .center)
                    
                    // Text size slider
                    VStack(alignment: .center, spacing: 4) {
                        Text("Text Size")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: $configuration.textSize, in: 0.1...0.3)
                            .frame(width: 100)
                            .tint(.blue)
                    }
                }

            }
            
            Divider()
                .padding(.vertical, 4)
            
            // Text Position Section
            TextPositionSelectorView(
                verticalAlignment: $configuration.verticalAlignment,
                horizontalAlignment: $configuration.horizontalAlignment
            )
        }

        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)

    }
}

#Preview {
    CustomizationControlComponentView(configuration: .constant(SimpleMakerConfigurationModel()))
}
