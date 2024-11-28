//
//  SettingsView.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/28.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("About Me")) {
                    Text("William JM's Thumbnail Maker")
                }
                Section(header: Text("Upgrade")) {
                    Text("Upgrade to Pro to enjoy premium features")
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
