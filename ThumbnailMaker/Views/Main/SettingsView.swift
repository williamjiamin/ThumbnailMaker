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
    
    // Use your actual website URLs
    private let termsURL = URL(string: "https://learn-it-free.com/terms-of-service-for-simple-thumbnail-maker/")!
    private let privacyURL = URL(string: "https://learn-it-free.com/privacy-policy-for-simple-thumbnail-maker/")!
    
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
                    if purchaseManager.purchasedProductIDs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Free Version")
                                .foregroundColor(.secondary)
                            if purchaseManager.remainingFreeTries > 0 {
                                Text("\(purchaseManager.remainingFreeTries) free premium tries remaining")
                                    .foregroundColor(.blue)
                            } else {
                                Text("No free tries remaining")
                                    .foregroundColor(.secondary)
                            }
                            
                            if let product = purchaseManager.products.first {
                                Button(action: {
                                    Task {
                                        try? await purchaseManager.purchase()
                                    }
                                }) {
                                    Text("Upgrade to Premium (\(product.displayPrice))")
                                        .foregroundColor(.blue)
                                }
                                .padding(.top, 4)
                            }
                        }
                    } else {
                        Text("Premium Version")
                            .foregroundColor(.green)
                    }
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
