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
    private let termsURL = URL(string: "https://yourapp.com/terms")!
    private let privacyURL = URL(string: "https://yourapp.com/privacy")!
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("About Me")) {
                    Text("William JM's Thumbnail Maker")
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
                    // In-app versions
                    NavigationLink("Terms of Service") {
                        LegalDocumentView(title: "Terms of Service", documentName: "terms_of_service")
                    }
                    
                    NavigationLink("Privacy Policy") {
                        LegalDocumentView(title: "Privacy Policy", documentName: "privacy_policy")
                    }
                    
                    // Web versions
                    Button("Terms of Service (Web)") {
                        openURL(termsURL)
                    }
                    
                    Button("Privacy Policy (Web)") {
                        openURL(privacyURL)
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

#Preview {
    SettingsView()
}
