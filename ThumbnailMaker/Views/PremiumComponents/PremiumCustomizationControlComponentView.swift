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
    @Binding var showsSafeZoneGuide: Bool
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
                                .foregroundColor(.accessibleSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
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
                    Image(systemName: "paintpalette.fill")
                        .font(.headline)
                        .foregroundColor(.accessibleSecondaryText)
                        .accessibilityHidden(true)
                    ColorPicker("", selection: $configuration.backgroundColor)
                        .labelsHidden()
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Background color")
                        .accessibilityValue("Custom color")
                        .accessibilityHint("Opens the color picker to change the thumbnail background.")
                }
                .frame(width: 100, alignment: .center)
                .padding(.trailing)
            }
            .padding(.vertical, 8)

            Divider()

            // SHELL: solid / gradient background fill.
            BackgroundFillControlRow(
                backgroundColor: $configuration.backgroundColor,
                fill: $configuration.backgroundFill
            )

            Divider()

            // FEATURE-03: non-destructive image framing (fit / fill / focal / zoom).
            if let image = configuration.selectedImage {
                ImageFrameControlRow(
                    recipe: $configuration.imageRecipe,
                    image: image,
                    ratio: configuration.selectedRatio
                )

                Divider()
            }

            ExportSettingsSummaryRow(
                selectedRatio: $configuration.selectedRatio,
                options: $configuration.exportOptions
            )

            if let safeZone = configuration.exportOptions.activeSafeZone {
                Divider()

                SafeZoneGuideToggle(
                    isOn: $showsSafeZoneGuide,
                    safeZone: safeZone
                )
            }
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
    PremiumCustomizationControlComponentView(
        configuration: .constant(PremiumMakerConfigurationModel()),
        showsSafeZoneGuide: .constant(true)
    )
}
