//
//  ThumbnailFormatEditorView.swift
//  ThumbnailMaker
//
//  FEATURE-09: full-screen editor for one alternate size. It edits a local
//  copy of the resolved size (layout, image frame, per-size visibility and
//  unlinked text) and hands it back on Done, which the view model folds into
//  the size's overrides as a single undo step. Nothing here can change the
//  original design: there are no add/delete/style controls, and linked text
//  is read-only.
//

import SwiftUI

struct ThumbnailFormatEditorView<Configuration: ThumbnailFormatCanvasRenderable>: View {
    let kind: ThumbnailFormatKind
    let masterText: (String) -> String?
    let proposal: () -> Configuration?
    let clipFlags: (Configuration) -> [ThumbnailFormatClipFlag]
    let onDone: (Configuration, Set<String>) -> Void
    let onExport: (Configuration, Set<String>) -> Void

    @State private var working: Configuration
    @State private var detached: Set<String>
    @State private var selection: ThumbnailLayerSelection
    @State private var showsSafeZone = true
    @Environment(\.dismiss) private var dismiss

    init(
        kind: ThumbnailFormatKind,
        initial: Configuration,
        initiallyDetached: Set<String>,
        masterText: @escaping (String) -> String?,
        proposal: @escaping () -> Configuration?,
        clipFlags: @escaping (Configuration) -> [ThumbnailFormatClipFlag],
        onDone: @escaping (Configuration, Set<String>) -> Void,
        onExport: @escaping (Configuration, Set<String>) -> Void
    ) {
        self.kind = kind
        self.masterText = masterText
        self.proposal = proposal
        self.clipFlags = clipFlags
        self.onDone = onDone
        self.onExport = onExport
        _working = State(initialValue: initial)
        _detached = State(initialValue: initiallyDetached)
        _selection = State(initialValue: Self.selections(in: initial).first ?? .textOverlay)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    canvasSection
                    layerSection
                    if let image = working.selectedImage {
                        ImageFrameControlRow(recipe: $working.imageRecipe, image: image, ratio: kind.aspectRatio)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
                    }
                    clipSection
                    actionSection
                }
                .padding(20)
            }
            .navigationTitle(kind.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetToolbarButton(.cancel) { dismiss() }
                        .accessibilityIdentifier("formatEditorCancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    SheetToolbarButton(.done) {
                        onDone(working, detached)
                        dismiss()
                    }
                    .accessibilityIdentifier("formatEditorDoneButton")
                }
            }
        }
        .accessibilityIdentifier("formatEditorSheet")
    }

    // MARK: Canvas

    private var canvasSize: CGSize {
        let ratio = kind.aspectRatio.value
        let width = min(340, 420 * ratio)
        return CGSize(width: width, height: width / ratio)
    }

    private var canvasSection: some View {
        VStack(spacing: 8) {
            Configuration.formatCanvas(
                $working,
                size: canvasSize,
                isInteractive: true,
                safeZone: showsSafeZone ? kind.preset.safeZone : nil,
                selection: $selection
            )
            .frame(width: canvasSize.width, height: canvasSize.height)
            .accessibilityIdentifier("formatEditorCanvas")

            Toggle("Show \(kind.preset.platform) safe zone", isOn: $showsSafeZone)
                .font(.footnote)
            Text("Moves, sizes and framing here apply to this size only. Colours, fonts and images stay linked to the original.")
                .font(.caption)
                .foregroundColor(.accessibleSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Layers

    private static func selections(in configuration: Configuration) -> [ThumbnailLayerSelection] {
        configuration.layers
            .filter { $0.kind != .background }
            .filter { $0.content != nil || $0.id == ThumbnailDocumentLayer.textID || $0.id == ThumbnailDocumentLayer.profileID }
            .sorted { $0.zIndex > $1.zIndex }
            .map { layer in
                switch layer.id {
                case ThumbnailDocumentLayer.textID: .textOverlay
                case ThumbnailDocumentLayer.profileID: .profileOverlay
                default: .content(layer.id)
                }
            }
    }

    private var selectedRecord: ThumbnailDocumentLayer? {
        working.layers.record(id: selection.documentLayerID)
    }

    private var selectedIsText: Bool {
        guard let record = selectedRecord else { return false }
        if record.id == ThumbnailDocumentLayer.textID { return true }
        if case .text = record.content { return true }
        return false
    }

    @ViewBuilder
    private var layerSection: some View {
        let selections = Self.selections(in: working)
        if !selections.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Layer")
                    .font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selections, id: \.self) { item in
                            let record = working.layers.record(id: item.documentLayerID)
                            Button {
                                selection = item
                            } label: {
                                Text(record?.name ?? "Layer")
                                    .font(.subheadline)
                                    .strikethrough(record?.isVisible == false)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(item == selection ? Color.blue.opacity(0.2) : Color(uiColor: .tertiarySystemFill)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("formatLayerChip_\(item.documentLayerID)")
                            .accessibilityAddTraits(item == selection ? .isSelected : [])
                        }
                    }
                }

                if let record = selectedRecord {
                    HStack(spacing: 12) {
                        Button {
                            working.layers.setVisible(!record.isVisible, for: selection)
                        } label: {
                            Label(record.isVisible ? "Hide in this size" : "Show in this size",
                                  systemImage: record.isVisible ? "eye.slash" : "eye")
                                .frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("formatLayerHideToggle")

                        Button {
                            resetSelectedLayer()
                        } label: {
                            Label("Reset layout", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("formatLayerResetButton")
                    }
                }

                if selectedIsText {
                    textLinkSection
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
        }
    }

    private var textLinkSection: some View {
        let layerID = selection.documentLayerID
        let isLinked = !detached.contains(layerID)
        return VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { isLinked },
                set: { linked in setTextLinked(linked, layerID: layerID) }
            )) {
                Label(isLinked ? "Linked to original" : "Unlinked for this size",
                      systemImage: isLinked ? "link" : "link.badge.plus")
            }
            .accessibilityIdentifier("formatTextLinkToggle")

            TextField("Text for this size", text: textBinding(layerID))
                .textFieldStyle(.roundedBorder)
                .disabled(isLinked)
                .accessibilityIdentifier("formatDetachedTextField")
            Text(isLinked
                 ? "Edit in the original to change every size."
                 : "This size keeps its own text. Link it again to follow the original.")
                .font(.caption)
                .foregroundColor(.accessibleSecondaryText)
        }
    }

    private func textBinding(_ layerID: String) -> Binding<String> {
        Binding(
            get: {
                if layerID == ThumbnailDocumentLayer.textID { return working.overlayText }
                if case .text(let content) = working.layers.record(id: layerID)?.content { return content.value }
                return ""
            },
            set: { value in
                guard detached.contains(layerID) else { return }
                // Clearing unlinked text relinks it on Done (see ThumbnailFormatLinker).
                if layerID == ThumbnailDocumentLayer.textID {
                    working.overlayText = value
                } else {
                    working.layers.updateTextContent(id: layerID) { $0.value = value }
                }
            }
        )
    }

    private func setTextLinked(_ linked: Bool, layerID: String) {
        if linked {
            detached.remove(layerID)
            if let original = masterText(layerID) {
                if layerID == ThumbnailDocumentLayer.textID {
                    working.overlayText = original
                } else {
                    working.layers.updateTextContent(id: layerID) { $0.value = original }
                }
            }
        } else {
            detached.insert(layerID)
        }
    }

    private func resetSelectedLayer() {
        guard let proposal = proposal() else { return }
        let layerID = selection.documentLayerID
        var document = working.imagelessDocument
        guard let geometry = ThumbnailLayerGeometry.extract(layerID: layerID, from: proposal.imagelessDocument) else { return }
        geometry.apply(to: &document, layerID: layerID)
        working = working.replacingDocument(document)
    }

    /// Fresh layout; text follows the editor's current link choices.
    private func reproposeKeepingUnlinkedText() {
        guard let proposed = proposal() else { return }
        var next = proposed
        let current = working
        func value(for layerID: String) -> String? {
            detached.contains(layerID) ? textBinding(layerID).wrappedValue : masterText(layerID)
        }
        if let text = value(for: ThumbnailDocumentLayer.textID), !current.overlayText.isEmpty || !text.isEmpty {
            next.overlayText = text
        }
        for layer in next.layers {
            if case .text = layer.content, let text = value(for: layer.id) {
                next.layers.updateTextContent(id: layer.id) { $0.value = text }
            }
        }
        working = next
    }

    // MARK: Clipping

    @ViewBuilder
    private var clipSection: some View {
        let flags = clipFlags(working)
        VStack(alignment: .leading, spacing: 8) {
            Text("Layout check")
                .font(.headline)
            if flags.isEmpty {
                Label("Everything fits this size.", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            } else {
                ForEach(flags) { flag in
                    Label(flag.message, systemImage: flag.systemImage)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("formatClipFlag_\(flag.layerID)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("formatClipFlagList")
    }

    // MARK: Actions

    private var actionSection: some View {
        HStack(spacing: 12) {
            Button {
                reproposeKeepingUnlinkedText()
            } label: {
                Label("Re-propose", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("formatEditorReproposeButton")

            Button {
                onExport(working, detached)
            } label: {
                Label("Export this size", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("formatEditorExportButton")
        }
    }
}
