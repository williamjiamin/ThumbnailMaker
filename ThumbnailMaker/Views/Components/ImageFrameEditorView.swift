//
//  ImageFrameEditorView.swift
//  ThumbnailMaker
//
//  FEATURE-03: pan / pinch / zoom sheet for choosing which part of the
//  original image is shown. Gestures only change local state (cheap: no
//  document re-encoding per frame); "Done" hands back one recipe, which the
//  caller writes once, producing a single undo step. "Cancel" discards.
//

import SwiftUI

struct ImageFrameEditorView: View {
    let image: UIImage
    let ratio: AspectRatio
    let onCommit: (ThumbnailImageFrameRecipe) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ThumbnailImageFrameRecipe
    private let startingDraft: ThumbnailImageFrameRecipe
    @GestureState private var panTranslation: CGSize = .zero
    @GestureState private var magnification: CGFloat = 1

    init(
        initialRecipe: ThumbnailImageFrameRecipe,
        image: UIImage,
        ratio: AspectRatio,
        onCommit: @escaping (ThumbnailImageFrameRecipe) -> Void
    ) {
        self.image = image
        self.ratio = ratio
        self.onCommit = onCommit
        // Panning a letterboxed image does nothing, so opening the editor on
        // the untouched default starts from a centred fill instead.
        let start = initialRecipe.isIdentity ? ThumbnailImageFrameRecipe.fillCentered : initialRecipe
        startingDraft = start
        _draft = State(initialValue: start)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                GeometryReader { proxy in
                    let frameSize = Self.frameSize(fitting: proxy.size, ratio: ratio)
                    let live = liveRecipe(frameSize: frameSize)
                    Image(uiImage: image)
                        .framed(ThumbnailImageGeometry.solve(
                            sourceSize: image.size,
                            frameSize: frameSize,
                            recipe: live
                        ))
                        .background(Color(uiColor: .secondarySystemBackground))
                        .overlay(
                            Rectangle()
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                        )
                        .contentShape(Rectangle())
                        .gesture(dragGesture(frameSize: frameSize))
                        .simultaneousGesture(magnifyGesture(frameSize: frameSize))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityElement()
                        .accessibilityLabel("Image framing preview")
                        .accessibilityValue(
                            "\(live.fit.displayName), \(String(format: "%.1f", live.zoom)) times zoom"
                        )
                        .accessibilityIdentifier("imageFrameEditorCanvas")
                }
                .frame(minHeight: 220)

                VStack(alignment: .leading, spacing: 12) {
                    Picker("Frame mode", selection: fitBinding) {
                        ForEach(ThumbnailImageFitMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("imageFrameEditorFitPicker")

                    HStack {
                        Image(systemName: "minus.magnifyingglass")
                            .accessibilityHidden(true)
                        Slider(
                            value: zoomBinding,
                            in: ThumbnailImageFrameRecipe.zoomLimits
                        )
                        .disabled(draft.fit == .stretch)
                        .accessibilityLabel("Zoom")
                        .accessibilityValue(String(format: "%.1f times", draft.zoom))
                        .accessibilityIdentifier("imageFrameZoomSlider")
                        Image(systemName: "plus.magnifyingglass")
                            .accessibilityHidden(true)
                    }

                    Text(draft.fit == .stretch
                         ? "Stretch fills the canvas and distorts the image."
                         : "Drag to reposition, pinch or use the slider to zoom. Your original photo is never changed.")
                        .font(.caption)
                        .foregroundColor(.accessibleSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
            .navigationTitle("Adjust Image Frame")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetToolbarButton(.cancel) { dismiss() }
                        .accessibilityIdentifier("imageFrameEditorCancelButton")
                }
                ToolbarItem(placement: .principal) {
                    Button("Reset") { draft = .fillCentered }
                        .disabled(draft == .fillCentered)
                        .accessibilityIdentifier("imageFrameEditorResetButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    SheetToolbarButton(.done) {
                        // Confirming without touching anything is not an edit.
                        if draft != startingDraft {
                            onCommit(draft)
                        }
                        dismiss()
                    }
                    .accessibilityIdentifier("imageFrameEditorDoneButton")
                }
            }
        }
        .presentationDetents([.large])
    }

    private var fitBinding: Binding<ThumbnailImageFitMode> {
        Binding(get: { draft.fit }, set: { draft = draft.with(fit: $0) })
    }

    private var zoomBinding: Binding<Double> {
        Binding(get: { draft.zoom }, set: { draft = draft.with(zoom: $0) })
    }

    private func liveRecipe(frameSize: CGSize) -> ThumbnailImageFrameRecipe {
        guard panTranslation != .zero || magnification != 1 else { return draft }
        return ThumbnailImageFrameRecipe.applying(
            panTranslation: panTranslation,
            magnification: magnification,
            to: draft,
            sourceSize: image.size,
            frameSize: frameSize
        )
    }

    private func dragGesture(frameSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($panTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                draft = ThumbnailImageFrameRecipe.applying(
                    panTranslation: value.translation,
                    magnification: 1,
                    to: draft,
                    sourceSize: image.size,
                    frameSize: frameSize
                )
            }
    }

    private func magnifyGesture(frameSize: CGSize) -> some Gesture {
        MagnifyGesture()
            .updating($magnification) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                draft = ThumbnailImageFrameRecipe.applying(
                    panTranslation: .zero,
                    magnification: value.magnification,
                    to: draft,
                    sourceSize: image.size,
                    frameSize: frameSize
                )
            }
    }

    static func frameSize(fitting available: CGSize, ratio: AspectRatio) -> CGSize {
        let width = max(1, available.width - 32)
        let height = max(1, available.height)
        let aspect = ratio.value
        if width / height > aspect {
            return CGSize(width: height * aspect, height: height)
        }
        return CGSize(width: width, height: width / aspect)
    }
}
