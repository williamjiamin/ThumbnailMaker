//
//  CutoutRefinementView.swift
//  ThumbnailMaker
//
//  FEATURE-11: the "Refine Cutout" sheet shared by both editors. Erase and
//  restore brushes with size and softness, whole-mask feather, zoom/pan,
//  before/after, local undo and reset. Everything edits a LOCAL working
//  recipe; Done commits it once (one document undo step), Cancel discards.
//
//  The image is shown unrotated and unflipped: the mask lives in image space
//  and the canvas applies the layer transform afterwards.
//

import SwiftUI

struct CutoutRefinementView<Editor: ObservableObject & ThumbnailCutoutEditing>: View {
    @ObservedObject var editor: Editor
    let target: ThumbnailCutoutTarget
    @State private var source: ThumbnailCutoutSource?
    @State private var previewSource: UIImage?
    @State private var state = ThumbnailCutoutRefinementState(stored: nil)
    @State private var rendered: UIImage?
    @State private var renderError: String?
    @State private var mapping = ThumbnailCutoutCanvasMapping(canvasSize: .zero, imagePixelSize: .zero)
    @State private var zoomAtGestureStart: CGFloat?
    @State private var offsetAtGestureStart: CGSize?
    @State private var isConfirmingDiscard = false
    @State private var didLoad = false
    @Environment(\.dismiss) private var dismiss

    init(editor: Editor, target: ThumbnailCutoutTarget) {
        self.editor = editor
        self.target = target
    }

    var body: some View {
        NavigationStack {
            Group {
                if source != nil {
                    VStack(spacing: 0) {
                        canvas
                        controls
                    }
                } else if didLoad {
                    ContentUnavailableView(
                        "Nothing to Cut Out",
                        systemImage: "person.crop.rectangle",
                        description: Text("Add a photo or an image layer first.")
                    )
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(source.map { "Refine \($0.title)" } ?? "Refine Cutout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetToolbarButton(.cancel) {
                        if state.hasChanges {
                            isConfirmingDiscard = true
                        } else {
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("cutoutCancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    SheetToolbarButton(.done) {
                        editor.commitCutoutRefinement(state.result, for: target)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(source == nil)
                    .accessibilityIdentifier("cutoutDoneButton")
                }
            }
            .confirmationDialog("Discard cutout changes?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(state.hasChanges)
        .accessibilityIdentifier("cutoutRefinementSheet")
        .onAppear(perform: load)
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geometry in
            let currentMapping = mapping(for: geometry.size)
            ZStack {
                CutoutCheckerboard()
                if let image = state.showsBefore ? previewSource : (rendered ?? previewSource) {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: currentMapping.displayedRect.width, height: currentMapping.displayedRect.height)
                        .position(x: currentMapping.displayedRect.midX, y: currentMapping.displayedRect.midY)
                        .accessibilityHidden(true)
                }
                pendingStrokeOverlay(currentMapping)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(brushOrPanGesture(currentMapping))
            .simultaneousGesture(zoomGesture)
            .onAppear { mapping = currentMapping }
            .onChange(of: geometry.size) { _, newSize in
                mapping.canvasSize = newSize
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Cutout canvas")
            .accessibilityValue(state.showsBefore ? "Showing original" : state.working.accessibilitySummary)
            .accessibilityHint("Drag to \(state.tool == .move ? "move the zoomed photo" : state.tool.title.lowercased()). Pinch to zoom.")
            .accessibilityIdentifier("cutoutCanvas")
        }
        .frame(minHeight: 240)
        .overlay(alignment: .topLeading) {
            if let renderError {
                Label(renderError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(8)
                    .accessibilityIdentifier("cutoutRenderError")
            }
        }
        .overlay(alignment: .bottomTrailing) { zoomButtons }
    }

    private func mapping(for size: CGSize) -> ThumbnailCutoutCanvasMapping {
        var current = mapping
        current.canvasSize = size
        if let source {
            current.imagePixelSize = CGSize(width: source.pixelWidth, height: source.pixelHeight)
        }
        return current
    }

    @ViewBuilder
    private func pendingStrokeOverlay(_ mapping: ThumbnailCutoutCanvasMapping) -> some View {
        if !state.pendingPoints.isEmpty {
            let radius = mapping.viewRadius(forNormalizedRadius: state.brushRadius)
            let color: Color = state.tool == .restore ? .green : .red
            Path { path in
                let points = state.pendingPoints.map { mapping.viewPoint(for: $0) }
                guard let first = points.first else { return }
                path.move(to: first)
                if points.count == 1 {
                    path.addLine(to: first)
                }
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(color.opacity(0.45), style: StrokeStyle(lineWidth: radius * 2, lineCap: .round, lineJoin: .round))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func brushOrPanGesture(_ mapping: ThumbnailCutoutCanvasMapping) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if state.tool == .move {
                    let start = offsetAtGestureStart ?? self.mapping.offset
                    if offsetAtGestureStart == nil { offsetAtGestureStart = start }
                    self.mapping.offset = CGSize(
                        width: start.width + value.translation.width,
                        height: start.height + value.translation.height
                    )
                    return
                }
                guard let point = mapping.normalizedPoint(for: value.location) else { return }
                if state.pendingPoints.isEmpty {
                    state.beginStroke(at: point)
                } else {
                    state.continueStroke(to: point)
                }
            }
            .onEnded { _ in
                offsetAtGestureStart = nil
                if state.endStroke() {
                    state.showsBefore = false
                    refreshPreview()
                }
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                state.cancelStroke()
                let start = zoomAtGestureStart ?? mapping.zoom
                if zoomAtGestureStart == nil { zoomAtGestureStart = start }
                mapping.setZoom(start * value.magnification)
            }
            .onEnded { _ in zoomAtGestureStart = nil }
    }

    private var zoomButtons: some View {
        HStack(spacing: 6) {
            Button {
                mapping.setZoom(mapping.zoom / 1.5)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Zoom out")
            .disabled(mapping.zoom <= ThumbnailCutoutCanvasMapping.zoomRange.lowerBound)

            Button {
                mapping.setZoom(mapping.zoom * 1.5)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Zoom in")
            .disabled(mapping.zoom >= ThumbnailCutoutCanvasMapping.zoomRange.upperBound)
        }
        .buttonStyle(.bordered)
        .padding(8)
        .accessibilityIdentifier("cutoutZoomControls")
    }

    // MARK: Controls

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Brush", selection: $state.tool) {
                    ForEach(ThumbnailCutoutRefinementState.Tool.allCases) { tool in
                        Text(tool.title)
                            .tag(tool)
                            .accessibilityIdentifier(toolIdentifier(tool))
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("cutoutBrushModePicker")

                slider(
                    title: "Brush Size",
                    value: state.brushRadius,
                    range: ThumbnailCutoutRefinementState.brushRadiusRange,
                    identifier: "cutoutBrushSizeSlider",
                    set: { state.setBrushRadius($0) }
                )
                slider(
                    title: "Softness",
                    value: state.brushSoftness,
                    range: ThumbnailCutoutMask.softnessLimits,
                    identifier: "cutoutBrushSoftnessSlider",
                    set: { state.setBrushSoftness($0) }
                )
                slider(
                    title: "Edge Feather",
                    value: state.working.feather,
                    range: ThumbnailCutoutMask.featherLimits,
                    identifier: "cutoutFeatherSlider",
                    set: { state.setFeather($0) },
                    onEditingChanged: { isEditing in
                        if isEditing {
                            state.beginFeatherEdit()
                        } else {
                            refreshPreview()
                        }
                    },
                    onAccessibilityStep: {
                        state.beginFeatherEdit()
                        state.setFeather($0)
                        refreshPreview()
                    }
                )

                HStack(spacing: 10) {
                    Button {
                        state.showsBefore.toggle()
                    } label: {
                        Label(state.showsBefore ? "After" : "Before", systemImage: "square.split.2x1")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Compare with original")
                    .accessibilityValue(state.showsBefore ? "Showing original" : "Showing cutout")
                    .accessibilityIdentifier("cutoutBeforeAfterButton")

                    Button {
                        if state.undo() { refreshPreview() }
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!state.canUndo)
                    .accessibilityLabel("Undo stroke")
                    .accessibilityIdentifier("cutoutUndoStrokeButton")

                    Spacer(minLength: 0)

                    Button(role: .destructive) {
                        if state.reset() {
                            state.showsBefore = false
                            refreshPreview()
                        }
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.working.isIdentity)
                    .accessibilityHint("Restores the original photo")
                    .accessibilityIdentifier("cutoutResetButton")
                }

                Text(state.working.automaticBase == nil
                     ? "Tip: tap Cutout in the editor first for an automatic subject mask, then refine the edges here."
                     : "Erase removes, Restore brings back the original pixels. Your photo is never changed.")
                    .font(.footnote)
                    .foregroundColor(.accessibleSecondaryText)
            }
            .padding(16)
        }
        .frame(maxHeight: 330)
    }

    private func toolIdentifier(_ tool: ThumbnailCutoutRefinementState.Tool) -> String {
        switch tool {
        case .erase: "cutoutBrushModeErase"
        case .restore: "cutoutBrushModeRestore"
        case .move: "cutoutBrushModeMove"
        }
    }

    private func slider(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        identifier: String,
        set: @escaping (Double) -> Void,
        onEditingChanged: @escaping (Bool) -> Void = { _ in },
        onAccessibilityStep: ((Double) -> Void)? = nil
    ) -> some View {
        let percent = Self.percent(value, in: range)
        let binding = Binding<Double>(get: { value }, set: set)
        let step = (range.upperBound - range.lowerBound) / 20
        let nudge: (Double) -> Void = { delta in
            let next = min(range.upperBound, max(range.lowerBound, value + delta))
            if let onAccessibilityStep {
                onAccessibilityStep(next)
            } else {
                set(next)
            }
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(percent)
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.accessibleSecondaryText)
            }
            Slider(value: binding, in: range, onEditingChanged: onEditingChanged)
        }
        // APP-07: the visible title/value row and the slider are one
        // adjustable element, so no visible text is hidden from VoiceOver.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(percent)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(step)
            case .decrement: nudge(-step)
            @unknown default: break
            }
        }
        .accessibilityIdentifier(identifier)
    }

    static func percent(_ value: Double, in range: ClosedRange<Double>) -> String {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return "0%" }
        return "\(Int(((value - range.lowerBound) / span * 100).rounded()))%"
    }

    // MARK: Rendering

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let loaded = editor.cutoutSource(for: target) else { return }
        source = loaded
        state = ThumbnailCutoutRefinementState(stored: loaded.mask)
        mapping.imagePixelSize = CGSize(width: loaded.pixelWidth, height: loaded.pixelHeight)
        do {
            previewSource = try ThumbnailCutoutMaskRenderer.composited(
                loaded.image,
                mask: nil,
                maxDimension: ThumbnailCutoutMaskRenderer.previewMaxDimension
            )
        } catch {
            previewSource = loaded.image
        }
        refreshPreview()
    }

    private func refreshPreview() {
        guard let previewSource else { return }
        do {
            rendered = try ThumbnailCutoutMaskRenderer.composited(
                previewSource,
                mask: state.working,
                requireCompatibleSource: false
            )
            renderError = nil
        } catch {
            rendered = previewSource
            renderError = error.localizedDescription
        }
    }
}

private struct CutoutCheckerboard: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 12
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.92)))
            var row = 0
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : tile
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: y, width: tile, height: tile)), with: .color(Color(white: 0.78)))
                    x += tile * 2
                }
                y += tile
                row += 1
            }
        }
        .accessibilityHidden(true)
    }
}

/// FEATURE-11: the editors' entry point for the refinement sheet, shown next
/// to the existing Cutout button.
struct CutoutRefineButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CreatorActionIcon(
                systemName: "scribble.variable",
                colors: [.purple, .purple.opacity(0.82)]
            )
        }
        .accessibilityIdentifier("refineCutoutButton")
        .accessibilityLabel("Refine Cutout")
        .accessibilityHint("Erase or restore parts of the photo with a brush")
    }
}

extension View {
    /// FEATURE-11: presents the refinement sheet while `target` is non-nil.
    func cutoutRefinementSheet<Editor: ObservableObject & ThumbnailCutoutEditing>(
        editor: Editor,
        target: Binding<ThumbnailCutoutTarget?>
    ) -> some View {
        sheet(item: target) { item in
            CutoutRefinementView(editor: editor, target: item)
        }
    }
}
