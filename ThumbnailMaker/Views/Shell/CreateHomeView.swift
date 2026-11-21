//
//  CreateHomeView.swift
//  ThumbnailMaker
//
//  SHELL (1.1.0 rebuild): the Create tab's landing screen - "Create a
//  Thumbnail" with a gradient Quick Create button and an outlined Start
//  from Scratch button, plus shortcuts back into existing work.
//

import SwiftUI

struct CreateHomeView: View {
    let continueProjectName: String?
    let onQuickCreate: () -> Void
    let onStartFromScratch: () -> Void
    let onContinue: () -> Void
    let onOpenProEditor: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 24)

                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 56, weight: .regular))
                        .foregroundStyle(QuickCreateTheme.gradient)
                        .accessibilityHidden(true)

                    VStack(spacing: 8) {
                        Text("Create a Thumbnail")
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        Text("Start with a guided flow or jump into the pro editor.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 12) {
                        Button(action: onQuickCreate) {
                            Label("Quick Create", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(QuickCreateTheme.gradient)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("quickCreateButton")
                        .accessibilityHint("Guided steps: template, text, style and export.")

                        Button(action: onStartFromScratch) {
                            Label("Start from Scratch", systemImage: "slider.horizontal.3")
                                .font(.headline)
                                .foregroundStyle(QuickCreateTheme.gradientStart)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(QuickCreateTheme.gradientStart.opacity(0.6), lineWidth: 1.5)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("startFromScratchButton")
                        .accessibilityHint("Opens the editor with a blank canvas.")
                    }

                    VStack(spacing: 4) {
                        if let continueProjectName {
                            Button(action: onContinue) {
                                Label("Continue \u{201C}\(continueProjectName)\u{201D}", systemImage: "arrow.uturn.forward")
                                    .font(.subheadline.weight(.semibold))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                            .accessibilityIdentifier("continueEditingButton")
                        }

                        Button(action: onOpenProEditor) {
                            Label("Open Pro Editor", systemImage: "star.circle")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityIdentifier("openProEditorButton")
                        .accessibilityHint("Profile photo, YouTube import and more.")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Simple Thumbnail")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("createHomeView")
        }
    }
}

#Preview {
    CreateHomeView(
        continueProjectName: "My Video",
        onQuickCreate: {},
        onStartFromScratch: {},
        onContinue: {},
        onOpenProEditor: {}
    )
}
