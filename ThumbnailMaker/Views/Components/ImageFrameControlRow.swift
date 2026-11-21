//
//  ImageFrameControlRow.swift
//  ThumbnailMaker
//
//  FEATURE-03: the "Image Frame" row in the canvas settings card. Every
//  control writes a new `ThumbnailImageFrameRecipe` through the bound
//  configuration exactly once per completed interaction, so the editor's
//  existing debounced autosave records one undo step and persists the draft.
//  The original image is never modified.
//

import SwiftUI

struct ImageFrameControlRow: View {
    @Binding var recipe: ThumbnailImageFrameRecipe
    let image: UIImage
    let ratio: AspectRatio
    @State private var showingEditor = false

    private var fitBinding: Binding<ThumbnailImageFitMode> {
        Binding(
            get: { recipe.fit },
            set: { newValue in
                guard newValue != recipe.fit else { return }
                recipe = recipe.with(fit: newValue)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "crop")
                    .font(.title3)
                    .foregroundColor(.blue)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Image Frame")
                        .font(.headline)
                    Text(summary)
                        .font(.caption)
                        .foregroundColor(.accessibleSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("imageFrameSummary")
                }

                Spacer()
            }

            Picker("Image frame", selection: fitBinding) {
                ForEach(ThumbnailImageFitMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("imageFrameFitPicker")

            HStack(spacing: 12) {
                Button {
                    showingEditor = true
                } label: {
                    Label("Adjust…", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("imageFrameAdjustButton")
                .accessibilityHint("Pan and zoom to choose which part of the image is shown.")

                Button {
                    recipe = .identity
                } label: {
                    Label("Reset Frame", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered)
                .disabled(recipe.isIdentity)
                .accessibilityIdentifier("imageFrameResetButton")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .sheet(isPresented: $showingEditor) {
            ImageFrameEditorView(
                initialRecipe: recipe,
                image: image,
                ratio: ratio,
                onCommit: { committed in
                    if committed != recipe {
                        recipe = committed
                    }
                }
            )
        }
    }

    private var summary: String {
        switch recipe.fit {
        case .fit where recipe.zoom <= 1:
            return "Whole image, letterboxed"
        case .stretch:
            return "Stretched to the canvas"
        default:
            return "\(recipe.fit.displayName) · \(String(format: "%.1f", recipe.zoom))× zoom"
        }
    }
}

#Preview {
    ImageFrameControlRow(
        recipe: .constant(.fillCentered),
        image: UIImage(systemName: "photo") ?? UIImage(),
        ratio: .ratio16_9
    )
}
