//
//  AdjustmentsPanelView.swift
//  ThumbnailMaker
//
//  FEATURE-14: the "Adjust" sheet shared by both editors - brightness,
//  contrast, saturation, blur and vignette for the photo, the profile photo,
//  or any image layer, plus built-in and saved looks, hold-to-compare and
//  reset. All edits are non-destructive recipes on the layer record.
//

import SwiftUI

struct AdjustmentsPanelView<Editor: ObservableObject & ThumbnailImageAdjustmentEditing>: View {
    @ObservedObject var editor: Editor
    @Binding var isComparing: Bool
    @StateObject private var looks: ThumbnailLookLibraryController
    @State private var selectedTargetID: String?
    @State private var isSaveLookPromptPresented = false
    @State private var newLookName = ""
    @State private var renamingLook: ThumbnailLook?
    @State private var renameText = ""
    @Environment(\.dismiss) private var dismiss

    init(
        editor: Editor,
        isComparing: Binding<Bool>,
        initialTarget: ThumbnailAdjustmentTarget? = nil,
        lookController: ThumbnailLookLibraryController? = nil
    ) {
        self.editor = editor
        self._isComparing = isComparing
        self._looks = StateObject(wrappedValue: lookController ?? ThumbnailLookLibraryController())
        self._selectedTargetID = State(initialValue: initialTarget?.layerID)
    }

    /// Maps the editor's selected layer to an adjustment target, if it is an image.
    static func initialTarget(
        for selection: ThumbnailLayerSelection,
        in editor: Editor
    ) -> ThumbnailAdjustmentTarget? {
        let target: ThumbnailAdjustmentTarget
        switch selection {
        case .profileOverlay:
            target = .profileImage
        case .content(let id):
            target = .contentLayer(id)
        case .textOverlay:
            return nil
        }
        return editor.canAdjust(target) ? target : nil
    }

    private var images: [ThumbnailAdjustableImage] {
        editor.adjustableImages
    }

    private var target: ThumbnailAdjustmentTarget? {
        images.first(where: { $0.id == selectedTargetID })?.target ?? images.first?.target
    }

    var body: some View {
        NavigationStack {
            Group {
                if let target {
                    controls(for: target)
                } else {
                    ContentUnavailableView(
                        "No Photo to Adjust",
                        systemImage: "photo",
                        description: Text("Add a photo or an image layer, then adjust it here.")
                    )
                }
            }
            .navigationTitle("Adjust")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    SheetToolbarButton(.done) { dismiss() }
                        .accessibilityIdentifier("adjustmentsDoneButton")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .accessibilityIdentifier("adjustmentsPanel")
        .onDisappear {
            isComparing = false
            editor.commitAdjustmentsEdit()
        }
        .alert("Save Look", isPresented: $isSaveLookPromptPresented) {
            TextField("Look name", text: $newLookName)
                .accessibilityIdentifier("adjustmentsLookNameField")
            Button("Save") {
                if let target {
                    looks.saveLook(named: newLookName, adjustments: editor.adjustments(for: target))
                }
                newLookName = ""
            }
            Button("Cancel", role: .cancel) { newLookName = "" }
        } message: {
            Text("Saves the current adjustments so you can reuse them on other photos. Up to \(ThumbnailLookLibrary.nameCharacterLimit) characters.")
        }
        .alert(
            "Rename Look",
            isPresented: Binding(
                get: { renamingLook != nil },
                set: { if !$0 { renamingLook = nil } }
            )
        ) {
            TextField("Look name", text: $renameText)
            Button("Rename") {
                if let renamingLook {
                    looks.renameLook(id: renamingLook.id, to: renameText)
                }
                renamingLook = nil
            }
            Button("Cancel", role: .cancel) { renamingLook = nil }
        }
        .alert(
            "Looks",
            isPresented: Binding(
                get: { looks.errorMessage != nil },
                set: { if !$0 { looks.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { looks.errorMessage = nil }
        } message: {
            Text(looks.errorMessage ?? "")
        }
    }

    // MARK: Controls

    private func controls(for target: ThumbnailAdjustmentTarget) -> some View {
        let current = editor.adjustments(for: target)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if images.count > 1 {
                    Picker("Adjusting", selection: Binding(
                        get: { target.layerID },
                        set: { newValue in
                            editor.commitAdjustmentsEdit()
                            selectedTargetID = newValue
                        }
                    )) {
                        ForEach(images) { image in
                            Text(image.title).tag(image.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("adjustmentsTargetPicker")
                }

                compareAndResetRow(target: target, current: current)

                looksRow(target: target, current: current)

                VStack(spacing: 14) {
                    slider(
                        "Brightness", keyPath: \.brightness,
                        range: ThumbnailImageAdjustments.brightnessRange,
                        identifier: "adjustmentsBrightnessSlider", target: target,
                        format: ThumbnailImageAdjustments.signedPercent
                    )
                    slider(
                        "Contrast", keyPath: \.contrast,
                        range: ThumbnailImageAdjustments.contrastRange,
                        identifier: "adjustmentsContrastSlider", target: target,
                        format: ThumbnailImageAdjustments.percent
                    )
                    slider(
                        "Saturation", keyPath: \.saturation,
                        range: ThumbnailImageAdjustments.saturationRange,
                        identifier: "adjustmentsSaturationSlider", target: target,
                        format: ThumbnailImageAdjustments.percent
                    )
                    slider(
                        "Blur", keyPath: \.blur,
                        range: ThumbnailImageAdjustments.blurRange,
                        identifier: "adjustmentsBlurSlider", target: target,
                        format: { value in
                            value <= 0 ? "Off" : ThumbnailImageAdjustments.percent(value / ThumbnailImageAdjustments.blurRange.upperBound)
                        }
                    )
                    slider(
                        "Vignette", keyPath: \.vignette,
                        range: ThumbnailImageAdjustments.vignetteRange,
                        identifier: "adjustmentsVignetteSlider", target: target,
                        format: { value in value <= 0 ? "Off" : ThumbnailImageAdjustments.percent(value) }
                    )
                }
            }
            .padding(20)
        }
    }

    private func compareAndResetRow(target: ThumbnailAdjustmentTarget, current: ThumbnailImageAdjustments) -> some View {
        HStack(spacing: 12) {
            Label(isComparing ? "Showing Original" : "Hold to Compare", systemImage: "square.split.2x1")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isComparing ? Color.accentColor.opacity(0.25) : Color(uiColor: .secondarySystemBackground))
                )
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !isComparing { isComparing = true }
                        }
                        .onEnded { _ in isComparing = false }
                )
                .opacity(current.isNeutral ? 0.5 : 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Compare with original")
                .accessibilityValue(isComparing ? "Showing original" : "Showing adjusted")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { isComparing.toggle() }
                .accessibilityIdentifier("adjustmentsCompareButton")

            Spacer()

            Button(role: .destructive) {
                isComparing = false
                editor.resetAdjustments(for: target)
            } label: {
                Label("Reset", systemImage: "arrow.uturn.backward")
                    .frame(minHeight: 44)
            }
            .disabled(current.isNeutral)
            .accessibilityHint("Restores the original photo")
            .accessibilityIdentifier("adjustmentsResetButton")
        }
    }

    private func looksRow(target: ThumbnailAdjustmentTarget, current: ThumbnailImageAdjustments) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Looks")
                    .font(.headline)
                Spacer()
                Button {
                    newLookName = ""
                    isSaveLookPromptPresented = true
                } label: {
                    Label("Save Look", systemImage: "plus")
                        .font(.subheadline)
                }
                .disabled(current.isNeutral)
                .accessibilityIdentifier("adjustmentsSaveLookButton")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(looks.allLooks) { look in
                        let isActive = current == look.adjustments.clamped()
                        Button {
                            isComparing = false
                            editor.applyLook(look, to: target)
                        } label: {
                            Text(look.name)
                                .font(.subheadline.weight(isActive ? .semibold : .regular))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 36)
                                .background(
                                    Capsule().fill(isActive ? Color.accentColor.opacity(0.25) : Color(uiColor: .secondarySystemBackground))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(look.name) look")
                        .accessibilityValue(isActive ? "Applied" : "")
                        .accessibilityIdentifier("adjustmentLook-\(look.id)")
                        .contextMenu {
                            if !look.isBuiltIn {
                                Button {
                                    renameText = look.name
                                    renamingLook = look
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    looks.deleteLook(id: look.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func slider(
        _ title: String,
        keyPath: WritableKeyPath<ThumbnailImageAdjustments, Double>,
        range: ClosedRange<Double>,
        identifier: String,
        target: ThumbnailAdjustmentTarget,
        format: @escaping (Double) -> String
    ) -> some View {
        let value = editor.adjustments(for: target)[keyPath: keyPath]
        let binding = Binding<Double>(
            get: { editor.adjustments(for: target)[keyPath: keyPath] },
            set: { newValue in
                var next = editor.adjustments(for: target)
                next[keyPath: keyPath] = newValue
                editor.updateAdjustments(next, for: target)
            }
        )
        let nudge: (Double) -> Void = { delta in
            var next = editor.adjustments(for: target)
            next[keyPath: keyPath] = min(range.upperBound, max(range.lowerBound, next[keyPath: keyPath] + delta))
            editor.setAdjustments(next, for: target)
        }

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(format(value))
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.accessibleSecondaryText)
            }

            Slider(value: binding, in: range) { isEditing in
                if !isEditing {
                    editor.commitAdjustmentsEdit()
                }
            }
        }
        // APP-07: the title and value row are the slider's visible label, so
        // the whole row is one adjustable element (nothing visible is hidden).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            let accessibilityStep = (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment:
                nudge(accessibilityStep)
            case .decrement:
                nudge(-accessibilityStep)
            @unknown default:
                break
            }
        }
        .accessibilityIdentifier(identifier)
    }
}

/// FEATURE-14: the editors' toolbar entry point for the adjustments sheet.
struct AdjustmentsToolbarButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "slider.horizontal.3")
        }
        .disabled(!isEnabled)
        .accessibilityIdentifier("adjustmentsButton")
        .accessibilityLabel("Adjust photo")
        .accessibilityHint(isEnabled ? "Brightness, contrast, saturation, blur, vignette and looks" : "Add a photo first")
    }
}
