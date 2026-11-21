//
//  ThumbnailFormatStripView.swift
//  ThumbnailMaker
//
//  FEATURE-09: the "Sizes" strip under the variant bar. One chip per
//  alternate size (live thumbnail + clip badge), an "Add size" menu, and a
//  context menu per chip. `ThumbnailFormatSection` wires it to either
//  editor, including the size editor sheet, so each main view needs a single
//  line to host the feature.
//

import SwiftUI

/// Renders a configuration as a canvas. Implemented by both editor
/// configuration types with their existing preview views.
protocol ThumbnailFormatCanvasRenderable: ThumbnailFormatEditableConfiguration {
    associatedtype FormatCanvas: View
    @MainActor
    static func formatCanvas(
        _ configuration: Binding<Self>,
        size: CGSize,
        isInteractive: Bool,
        safeZone: ThumbnailSafeZone?,
        selection: Binding<ThumbnailLayerSelection>
    ) -> FormatCanvas
}

extension SimpleMakerConfigurationModel: ThumbnailFormatCanvasRenderable {
    @MainActor
    static func formatCanvas(
        _ configuration: Binding<SimpleMakerConfigurationModel>,
        size: CGSize,
        isInteractive: Bool,
        safeZone: ThumbnailSafeZone?,
        selection: Binding<ThumbnailLayerSelection>
    ) -> PreviewComponentView {
        PreviewComponentView(
            simpleMakerConfiguration: configuration,
            width: size.width,
            height: size.height,
            isTextInteractive: isInteractive,
            safeZone: safeZone,
            selectedOverlay: selection
        )
    }
}

extension PremiumMakerConfigurationModel: ThumbnailFormatCanvasRenderable {
    @MainActor
    static func formatCanvas(
        _ configuration: Binding<PremiumMakerConfigurationModel>,
        size: CGSize,
        isInteractive: Bool,
        safeZone: ThumbnailSafeZone?,
        selection: Binding<ThumbnailLayerSelection>
    ) -> PremiumPreviewComponentView {
        PremiumPreviewComponentView(
            premiumMakerConfiguration: configuration,
            width: size.width,
            height: size.height,
            isInteractive: isInteractive,
            safeZone: safeZone,
            selectedOverlay: selection
        )
    }
}

struct ThumbnailFormatEditorRequest: Identifiable, Equatable {
    let id: String
}

/// Hosts the strip and the size editor for one editor view model.
struct ThumbnailFormatSection<Editor: ThumbnailFormatEditing & ObservableObject>: View
where Editor.FormatConfiguration: ThumbnailFormatCanvasRenderable {
    @ObservedObject var editor: Editor
    var isDisabled = false
    @State private var editingFormat: ThumbnailFormatEditorRequest?

    private typealias Configuration = Editor.FormatConfiguration

    var body: some View {
        ThumbnailFormatStripView(
            previews: editor.alternateFormatPreviews(),
            availableKinds: editor.availableFormatKinds,
            canAdd: editor.canCreateAlternateFormat && !isDisabled,
            add: { kind in
                if let id = editor.createAlternateFormat(kind) {
                    editingFormat = ThumbnailFormatEditorRequest(id: id)
                }
            },
            edit: { id in editingFormat = ThumbnailFormatEditorRequest(id: id) },
            export: { id in exportFormat(id) },
            repropose: { id in editor.reproposeAlternateFormat(id) },
            remove: { id in editor.removeAlternateFormat(id) }
        ) { preview, size in
            Configuration.formatCanvas(
                .constant(preview.configuration),
                size: size,
                isInteractive: false,
                safeZone: nil,
                selection: .constant(.textOverlay)
            )
        }
        .onChange(of: editor.alternateFormats.map(\.id)) { _, ids in
            // Undo can remove a size while its editor is open.
            if let request = editingFormat, !ids.contains(request.id) {
                editingFormat = nil
            }
        }
        .sheet(item: $editingFormat) { request in
            editorSheet(for: request)
        }
    }

    @ViewBuilder
    private func editorSheet(for request: ThumbnailFormatEditorRequest) -> some View {
        if let kind = ThumbnailFormatKind(rawValue: request.id),
           let initial = editor.resolvedFormatConfiguration(request.id),
           let format = editor.formatEditorConfiguration.formatSet?.format(id: request.id) {
            ThumbnailFormatEditorView<Configuration>(
                kind: kind,
                initial: initial,
                initiallyDetached: Set(format.detachedText.keys),
                masterText: { editor.masterFormatText($0) },
                proposal: { editor.proposedFormatConfiguration(request.id) },
                clipFlags: { editor.formatClipFlags(forWorking: $0, kind: kind) },
                onDone: { working, detached in
                    editor.commitAlternateFormatEdit(request.id, edited: working, detachedTextLayerIDs: detached)
                },
                onExport: { working, detached in
                    editor.commitAlternateFormatEdit(request.id, edited: working, detachedTextLayerIDs: detached)
                    editingFormat = nil
                    // Let the sheet finish dismissing before the file exporter presents.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        exportFormat(request.id)
                    }
                }
            )
        } else {
            ContentUnavailableView("Size unavailable", systemImage: "rectangle.dashed")
        }
    }

    private func exportFormat(_ id: String) {
        editor.prepareAlternateFormatExport(id) { configuration, size in
            Configuration.formatCanvas(
                .constant(configuration),
                size: size,
                isInteractive: false,
                safeZone: nil,
                selection: .constant(.textOverlay)
            )
        }
    }
}

struct ThumbnailFormatStripView<Configuration: ThumbnailFormatEditableConfiguration, Thumbnail: View>: View {
    let previews: [ThumbnailFormatPreview<Configuration>]
    let availableKinds: [ThumbnailFormatKind]
    let canAdd: Bool
    let add: (ThumbnailFormatKind) -> Void
    let edit: (String) -> Void
    let export: (String) -> Void
    let repropose: (String) -> Void
    let remove: (String) -> Void
    @ViewBuilder let thumbnail: (ThumbnailFormatPreview<Configuration>, CGSize) -> Thumbnail

    private static var chipHeight: CGFloat { 64 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "aspectratio")
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
                Text("Sizes")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                addMenu
            }

            if previews.isEmpty {
                Text("Add a square or vertical version of this design. Sizes stay linked to it and never change the original.")
                    .font(.caption)
                    .foregroundColor(.accessibleSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(previews) { preview in
                            chip(preview)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("formatStrip")
    }

    private var addMenu: some View {
        Menu {
            ForEach(availableKinds) { kind in
                Button {
                    add(kind)
                } label: {
                    Label(kind.displayName, systemImage: kind.systemImage)
                }
                .accessibilityIdentifier("formatAdd_\(kind.rawValue)")
            }
        } label: {
            Label("Add size", systemImage: "plus")
                .labelStyle(.titleAndIcon)
                .font(.subheadline)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .disabled(!canAdd || availableKinds.isEmpty)
        .accessibilityIdentifier("formatAddMenu")
    }

    private func chip(_ preview: ThumbnailFormatPreview<Configuration>) -> some View {
        let kind = preview.format.kind
        let ratio = kind.aspectRatio.value
        let size = CGSize(width: Self.chipHeight * ratio, height: Self.chipHeight)
        return Button {
            edit(preview.id)
        } label: {
            VStack(spacing: 4) {
                thumbnail(preview, size)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if !preview.flags.isEmpty {
                            Text("\(preview.flags.count)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.orange))
                                .offset(x: 6, y: -6)
                                .accessibilityIdentifier("formatClipBadge_\(kind.rawValue)")
                        }
                    }
                    .allowsHitTesting(false)
                Text(kind.shortName)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("formatChip_\(kind.rawValue)")
        .accessibilityLabel(kind.displayName)
        .accessibilityValue(preview.flags.isEmpty ? "No layout warnings" : "\(preview.flags.count) layout warnings")
        .accessibilityHint("Opens the size editor")
        .contextMenu {
            Button { edit(preview.id) } label: { Label("Edit", systemImage: "slider.horizontal.3") }
            Button { export(preview.id) } label: { Label("Export", systemImage: "square.and.arrow.up") }
            Button { repropose(preview.id) } label: { Label("Re-propose layout", systemImage: "wand.and.stars") }
            Button(role: .destructive) { remove(preview.id) } label: { Label("Remove size", systemImage: "trash") }
        }
    }
}
