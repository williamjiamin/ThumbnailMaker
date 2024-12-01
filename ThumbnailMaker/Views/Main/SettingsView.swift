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
                
                Section(header: Text("User Agreement")) {
                    Text("Terms of Service")
                    Text("Privacy Policy")
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
