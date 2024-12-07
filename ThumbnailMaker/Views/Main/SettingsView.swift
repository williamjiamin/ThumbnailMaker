//
//  SettingsView.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/28.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var purchaseManager = PurchaseManager.shared
    @Environment(\.openURL) private var openURL
    
   
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("About")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Simple Thumbnail Maker")
                            .font(.headline)
                        
                        Text("Version 1.0.0")
                            .foregroundColor(.secondary)
                        
                        Text("Created by a content creator for content creators")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        
                        Text("As a content creator myself, I built this app to solve the frustrating challenges of creating thumbnails for different platforms. It helps you:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            bulletPoint("Avoid copyright issues by using your own photos")
                            bulletPoint("Batch generate thumbnails for video series")
                            bulletPoint("Create thumbnails in different aspect ratios")
                            bulletPoint("Work completely offline with your local photos")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("Premium Status")) {
                    VStack(alignment: .leading, spacing: 12) {
                        // Status Information Group
                        VStack(alignment: .leading, spacing: 8) {
                            if purchaseManager.purchasedProductIDs.isEmpty {
                                HStack {
                                    Image(systemName: "star")
                                        .foregroundColor(.secondary)
                                    Text("Free Version")
                                        .foregroundColor(.secondary)
                                }
                                
                                if purchaseManager.remainingFreeTries > 0 {
                                    HStack {
                                        Image(systemName: "gift")
                                            .foregroundColor(.secondary)
                                        Text("\(purchaseManager.remainingFreeTries) free premium tries remaining")
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    HStack {
                                        Image(systemName: "xmark.circle")
                                            .foregroundColor(.secondary)
                                        Text("No free tries remaining")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            } else {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Premium Version")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        
                        // Divider between info and actions
                        Divider()
                            .padding(.vertical, 4)
                        
                        // Action Buttons Group
                        VStack(alignment: .leading, spacing: 12) {
                            // Upgrade button - show only if not premium
                            if purchaseManager.purchasedProductIDs.isEmpty,
                               let product = purchaseManager.products.first {
                                Button(action: {
                                    Task {
                                        try? await purchaseManager.purchase()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "crown")
                                        Text("Upgrade to Premium (\(product.displayPrice))")
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 8)
                                    .background(Color.blue)
                                    .cornerRadius(8)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            
                            // Restore button - always show
                            Button(action: {
                                Task {
                                    await purchaseManager.restorePurchases()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Restore Purchases")
                                }
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.blue, lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("Legal")) {
                    NavigationLink("Terms of Service") {
                        LegalDocumentView(title: "Terms of Service", documentName: "terms_of_service")
                    }
                    
                    NavigationLink("Privacy Policy") {
                        LegalDocumentView(title: "Privacy Policy", documentName: "privacy_policy")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// Helper view for bullet points
private func bulletPoint(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 4) {
        Text("•")
        Text(text)
    }
}

#Preview {
    SettingsView()
}
