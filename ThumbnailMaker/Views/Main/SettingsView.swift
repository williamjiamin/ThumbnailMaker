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
    @State private var isDebugMode: Bool = DebugSettings.isDebugMode
    /// SHELL: false when Settings is a tab (nothing to dismiss).
    private let showsDoneButton: Bool
    /// SHELL: what "Show first-export guide" does after updating the guide.
    private let onShowFirstExportGuide: (() -> Void)?

    init(showsDoneButton: Bool = true, onShowFirstExportGuide: (() -> Void)? = nil) {
        self.showsDoneButton = showsDoneButton
        self.onShowFirstExportGuide = onShowFirstExportGuide
    }
    
    var body: some View {
        NavigationView {
            List {
                SettingsAppHeader() // SHELL: 1.1.0 header (icon, name, version)

                SubscriptionSettingsSection(purchaseManager: purchaseManager) // SUB

                SettingsFeaturesSection() // GAPS: 1.1.0 feature list

                SettingsSupportSection() // GAPS: contact, rate, privacy, terms

                FirstExportGuideSettingsRow { // FEATURE-13
                    if let onShowFirstExportGuide {
                        onShowFirstExportGuide()
                    } else {
                        dismiss()
                    }
                }

                if ThumbnailPerformanceDiagnostics.isAvailable { // APP-09
                    Section(header: Text("Diagnostics")) {
                        NavigationLink("Performance") { PerformanceDiagnosticsView() }
                            .accessibilityIdentifier("settings.performanceDiagnostics")
                    }
                }

                #if DEBUG
                Section(header: Text("Developer Settings")) {
                    // Display debug mode status (read-only)
                    HStack {
                        Image(systemName: "ladybug.fill")
                            .foregroundColor(.red)
                        Text("Debug Mode: \(DebugSettings.isDebugMode ? "ON" : "OFF")")
                        Spacer()
                        Text("Change in code")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        if DebugSettings.isDebugMode {
                            Text("Current Debug Settings:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        
                            Label("Premium Quota: \(DebugSettings.premiumQuotaLimit)", systemImage: "number.circle")
                                .font(.caption)
                        
                            Label("Reset Time: 3 minutes", systemImage: "clock")
                                .font(.caption)
                        } else {
                            Text("Production Settings:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                
                            Label("Premium Quota: \(DebugSettings.productionPremiumQuotaLimit)", systemImage: "number.circle")
                                .font(.caption)
                                
                            Label("Reset Time: 24 hours", systemImage: "clock")
                                .font(.caption)
                        }
                        
                        Button(action: {
                            // Force reset YouTube imports
                            UserDefaults.standard.removeObject(forKey: "lastYoutubeImportReset")
                            UserDefaults.standard.synchronize()
                        }) {
                            Label("Force Reset Quota", systemImage: "arrow.counterclockwise.circle")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDoneButton {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        SheetToolbarButton(.done) {
                            dismiss()
                        }
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

/// SHELL: the 1.1.0 Settings header - app icon, name and version.
private struct SettingsAppHeader: View {
    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }

    var body: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [QuickCreateTheme.gradientStart, QuickCreateTheme.gradientEnd],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .accessibilityHidden(true)
                Text("Simple Thumbnail")
                    .font(.title3.weight(.semibold))
                Text(versionText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settingsAppVersion")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    SettingsView()
}
