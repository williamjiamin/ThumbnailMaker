//
//  CustomizationControlComponentView.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/28.
//

import SwiftUI

struct CustomizationControlComponentView: View {
    @Binding var configuration: SimpleMakerConfigurationModel
    @State private var showingRatioDrawer = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Canvas Settings Section
            HStack(spacing: 0) {
                // Left side - Aspect Ratio Button
                Button(action: {
                    withAnimation {
                        showingRatioDrawer = true
                    }
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Aspect Ratio")
                                .font(.headline)
                            Text(configuration.selectedRatio.rawValue)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal)
                }
                .frame(maxWidth: .infinity)
                
                Divider()
                    .frame(height: 40)
                    .padding(.horizontal)
                
                // Right side - Background Color
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
            
            Divider()
                .padding(.vertical, 2)
            
            // Customize Appearance Section
            VStack(spacing: 8) {
                Text("Customize Appearance")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                
                HStack(spacing: 20) {
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
                .padding(.vertical, 2)
            
            // Text Position Section
            TextPositionSelectorView(
                verticalAlignment: $configuration.verticalAlignment,
                horizontalAlignment: $configuration.horizontalAlignment
            )
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .sheet(isPresented: $showingRatioDrawer) {
            AspectRatioDrawerView(
                selectedRatio: $configuration.selectedRatio,
                isPresented: $showingRatioDrawer,
                onDismiss: {
                    showingRatioDrawer = false
                }
            )
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
        }
    }
}

#Preview {
    CustomizationControlComponentView(configuration: .constant(SimpleMakerConfigurationModel()))
}
