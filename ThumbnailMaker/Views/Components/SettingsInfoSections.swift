//
//  SettingsInfoSections.swift
//  ThumbnailMaker
//
//  GAPS (1.1.0 parity): the Settings FEATURES list and SUPPORT section.
//

import SwiftUI

enum AppSupportLinks {
    static let appStoreID = "6738887943"
    /// The public support / marketing site (GitHub Pages).
    static let supportSite = URL(string: "https://williamjiamin.github.io/ThumbnailMaker/")!
    /// Opens the App Store "Write a Review" sheet for this app.
    static let writeReview = URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")!
}

struct SettingsFeature: Identifiable, Equatable {
    let title: String
    let systemImage: String
    var id: String { title }

    static let all: [SettingsFeature] = [
        SettingsFeature(title: "Multiple aspect ratios for every platform", systemImage: "photo.on.rectangle"),
        SettingsFeature(title: "AI background removal & text effects", systemImage: "wand.and.stars"),
        SettingsFeature(title: "Batch generate thumbnails for video series", systemImage: "square.stack.3d.up.fill"),
        SettingsFeature(title: "Save projects on your device", systemImage: "folder.fill"),
        SettingsFeature(title: "Works completely offline", systemImage: "wifi.slash"),
    ]
}

struct SettingsFeaturesSection: View {
    var body: some View {
        Section(header: Text("Features")) {
            ForEach(SettingsFeature.all) { feature in
                Label {
                    Text(feature.title)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: feature.systemImage)
                        .foregroundStyle(QuickCreateTheme.gradientStart)
                }
            }
        }
        .accessibilityIdentifier("settingsFeaturesSection")
    }
}

struct SettingsSupportSection: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section(header: Text("Support")) {
            Button {
                openURL(AppSupportLinks.supportSite)
            } label: {
                supportLabel("Help & Support", systemImage: "questionmark.circle", external: true)
            }
            .accessibilityIdentifier("settingsSupportLink")
            .accessibilityHint("Opens the Simple Thumbnail support site.")

            Button {
                openURL(AppSupportLinks.writeReview)
            } label: {
                supportLabel("Rate Simple Thumbnail", systemImage: "star.bubble", external: true)
            }
            .accessibilityIdentifier("settingsRateAppButton")
            .accessibilityHint("Opens the App Store to write a review.")

            NavigationLink {
                LegalDocumentView(title: "Privacy Policy", documentName: "privacy_policy")
            } label: {
                supportLabel("Privacy Policy", systemImage: "hand.raised", external: false)
            }
            .accessibilityIdentifier("settingsPrivacyPolicyLink")

            NavigationLink {
                LegalDocumentView(title: "Terms of Service", documentName: "terms_of_service")
            } label: {
                supportLabel("Terms of Service", systemImage: "doc.text", external: false)
            }
            .accessibilityIdentifier("settingsTermsLink")
        }
    }

    private func supportLabel(_ title: String, systemImage: String, external: Bool) -> some View {
        HStack {
            Label {
                Text(title)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(QuickCreateTheme.gradientStart)
            }
            if external {
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }
}
