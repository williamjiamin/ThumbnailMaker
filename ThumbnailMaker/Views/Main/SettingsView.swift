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
    @State private var purchaseMessage: String?
    @State private var showingPurchaseMessage = false
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("About")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Simple Thumbnail Maker")
                            .font(.headline)
                    
                        
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
                    VStack(alignment: .leading, spacing: 16) {
                        // Current Status Group
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
                                        Image(systemName: "gift.fill")
                                            .foregroundColor(.blue)
                                        Text("\(purchaseManager.remainingFreeTries) Premium Tries Available")
                                            .fontWeight(.medium)
                                            .foregroundColor(.blue)
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(6)
                                } else {
                                    HStack {
                                        Image(systemName: "gift")
                                            .foregroundColor(.secondary)
                                        Text("No free tries remaining")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            } else {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Premium Version Active")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        
                        // Apple ID Info - Simplified
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Premium is linked to your Apple ID")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Use 'Restore Purchases' when switching devices")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Action Buttons Group
                        VStack(spacing: 12) {
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
                            
                            // Restore button
                            Button(action: {
                                Task {
                                    await purchaseManager.restorePurchases()
                                }
                            }) {
                                HStack {
                                    if purchaseManager.isRestoringPurchases {
                                        ProgressView()
                                            .tint(.blue)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                        Text("Restore Purchases")
                                    }
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
                            .disabled(purchaseManager.isRestoringPurchases)
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
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowPurchaseMessage"))) { notification in
                if let message = notification.userInfo?["message"] as? String {
                    purchaseMessage = message
                    showingPurchaseMessage = true
                }
            }
            .alert("Purchase Status", isPresented: $showingPurchaseMessage, presenting: purchaseMessage) { message in
                Button("OK", role: .cancel) { }
            } message: { message in
                Text(message)
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
