//
//  ThumbnailDrawingSheet.swift
//  ThumbnailMaker
//
//  DONOR (Simple Meme Maker Editor/DrawingMode.swift): PencilKit freehand
//  drawing over the thumbnail. PencilKit rather than a home-made brush
//  engine: it is the drawing surface of Notes and Markup, so pens, eraser,
//  colour picker, finger and Apple Pencil input, pressure and undo behave the
//  way people already know. Done places the strokes as a transparent PNG
//  image layer (see ThumbnailDrawingPlacement); Cancel discards them.
//

import PencilKit
import SwiftUI
import UIKit

/// A finished drawing, ready to become an image layer.
struct ThumbnailDrawingResult: Equatable {
    var pngData: Data
    var placement: ThumbnailDrawingPlacement.Placement
}

enum ThumbnailDrawingRenderer {
    /// A transparent PNG of the strokes at DOCUMENT resolution, plus where it
    /// goes. nil for an empty drawing.
    @MainActor
    static func render(
        _ drawing: PKDrawing,
        surface: CGSize,
        document: CGSize
    ) -> ThumbnailDrawingResult? {
        guard !drawing.strokes.isEmpty else { return nil }
        let bounds = ThumbnailDrawingPlacement.paddedBounds(drawing.bounds, surface: surface)
        guard !bounds.isNull,
              let placement = ThumbnailDrawingPlacement.placement(of: bounds, surface: surface) else {
            return nil
        }
        let scale = ThumbnailDrawingPlacement.pixelsPerPoint(surface: surface, document: document)
        // Light, so ink colours are the ones picked rather than their
        // dark-mode inversions — the thumbnail is artwork, not interface.
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: bounds, scale: scale)
        }
        guard let data = image.pngData() else { return nil }
        return ThumbnailDrawingResult(pngData: data, placement: placement)
    }
}

/// Full-screen drawing over the current thumbnail.
struct ThumbnailDrawingSheet<Background: View>: View {
    let aspectRatio: AspectRatio
    let onPlace: (ThumbnailDrawingResult) -> Void
    @ViewBuilder let background: (CGSize) -> Background

    @Environment(\.dismiss) private var dismiss
    @State private var drawing = PKDrawing()
    @State private var surface: CGSize = .zero

    private var documentSize: CGSize {
        ThumbnailDrawingPlacement.documentPixelSize(for: aspectRatio)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let size = ThumbnailDrawingPlacement.fittedSurface(for: documentSize, in: proxy.size)
                ZStack {
                    // The thumbnail as it is, underneath, so a circle goes
                    // round the thing it is meant to circle.
                    background(size)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    ThumbnailPencilCanvas(drawing: $drawing)
                        .accessibilityIdentifier("drawingCanvas")
                        .accessibilityLabel("Drawing canvas")
                }
                .frame(width: size.width, height: size.height)
                .clipped()
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                .onAppear { surface = size }
                .onChange(of: size) { _, newValue in surface = newValue }
            }
            .padding(16)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Draw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("drawingCancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { place() }
                        .fontWeight(.semibold)
                        .disabled(drawing.strokes.isEmpty)
                        .accessibilityIdentifier("drawingDoneButton")
                }
            }
        }
    }

    private func place() {
        if let result = ThumbnailDrawingRenderer.render(drawing, surface: surface, document: documentSize) {
            onPlace(result)
        }
        dismiss()
    }
}

/// PencilKit's canvas with the system tool picker.
struct ThumbnailPencilCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeCoordinator() -> Coordinator { Coordinator(drawing: $drawing) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        // Fingers draw too: most people have no Pencil, and a canvas that
        // ignores their finger looks broken.
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool = PKInkingTool(.marker, color: .systemRed, width: 12)

        let picker = PKToolPicker()
        picker.setVisible(true, forFirstResponder: canvas)
        picker.addObserver(canvas)
        context.coordinator.picker = picker
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {}

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var drawing: Binding<PKDrawing>
        /// Held so the picker lives as long as the canvas.
        var picker: PKToolPicker?

        init(drawing: Binding<PKDrawing>) { self.drawing = drawing }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
        }
    }
}
