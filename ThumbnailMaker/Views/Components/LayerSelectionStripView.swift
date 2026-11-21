//
//  LayerSelectionStripView.swift
//  ThumbnailMaker
//
//  Created by OpenAI on 2026-06-14.
//

import SwiftUI

struct LayerSelectionStripView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selection: ThumbnailLayerSelection
    @Binding var layerRecords: [ThumbnailDocumentLayer]
    let layers: [ThumbnailLayerSelection]
    var moveLayerBackward: ((ThumbnailLayerSelection, [ThumbnailLayerSelection]) -> Void)? = nil
    var moveLayerForward: ((ThumbnailLayerSelection, [ThumbnailLayerSelection]) -> Void)? = nil
    var toggleLayerVisibility: ((ThumbnailLayerSelection) -> Void)? = nil
    var toggleLayerLock: ((ThumbnailLayerSelection) -> Void)? = nil
    var duplicateLayer: ((ThumbnailLayerSelection) -> Void)? = nil
    var deleteLayer: ((ThumbnailLayerSelection) -> Void)? = nil
    /// FEATURE-07: non-nil while multi-select is on; taps then toggle membership.
    var multiSelection: Binding<ThumbnailSelectionSet>? = nil
    @ScaledMetric(relativeTo: .body) private var layerIconSize: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var controlSize: CGFloat = 44

    var body: some View {
        if !layers.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)

                    Text("Layers")
                        .font(.headline)

                    Spacer()
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(displayLayers) { layer in
                            layerButton(layer)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("layerSelectionStrip")
        }
    }

    private func layerButton(_ layer: ThumbnailLayerSelection) -> some View {
        let isSelected = multiSelection.map { $0.wrappedValue.contains(layer) } ?? (selection == layer) // FEATURE-07
        let record = layerRecords.record(for: layer) ?? fallbackRecord(for: layer)
        let descriptor = descriptor(for: record, selection: layer)
        let isVisible = record.isVisible
        let isLocked = record.isLocked

        return VStack(alignment: .leading, spacing: 10) {
            Button {
                if let multiSelection { // FEATURE-07
                    multiSelection.wrappedValue.toggle(layer)
                    if multiSelection.wrappedValue.contains(layer) { selection = layer }
                } else {
                    selection = layer
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: descriptor.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: layerIconSize, height: layerIconSize)
                        .background(isSelected ? Color.blue.opacity(0.16) : Color(uiColor: .tertiarySystemBackground))
                        .clipShape(Circle())
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(descriptor.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                            .foregroundStyle(isVisible ? .primary : .secondary)

                        Text(descriptor.subtitle)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)

                        if let groupName = groupName(for: record) { // FEATURE-07
                            Text("In \(groupName)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.blue)
                                .accessibilityIdentifier("layerGroupBadge\(descriptor.identifierSuffix)")
                        }
                    }

                    Spacer(minLength: 0)

                    if multiSelection != nil { // FEATURE-07
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                            .accessibilityIdentifier("layerMultiSelectCheck\(descriptor.identifierSuffix)")
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(descriptor.selectionIdentifier)
            .accessibilityLabel("\(descriptor.title) layer")
            .accessibilityValue(accessibilityValue(for: layer, isSelected: isSelected, record: record))
            .accessibilityHint(multiSelection == nil
                ? "Selects this layer for canvas editing."
                : "Adds or removes this layer from the multi-selection.")

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: controlSize), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                layerIconButton(
                    systemName: isVisible ? "eye" : "eye.slash",
                    accessibilityIdentifier: "layerVisibility\(descriptor.identifierSuffix)",
                    accessibilityLabel: isVisible ? "Hide \(descriptor.title) layer" : "Show \(descriptor.title) layer",
                    accessibilityHint: "Toggles whether this layer appears in preview and export."
                ) {
                    if let toggleLayerVisibility {
                        toggleLayerVisibility(layer)
                    } else {
                        mutateLayerRecords { records in
                            records.toggleVisibility(for: layer)
                        }
                    }
                }

                layerIconButton(
                    systemName: isLocked ? "lock.fill" : "lock.open",
                    accessibilityIdentifier: "layerLock\(descriptor.identifierSuffix)",
                    accessibilityLabel: isLocked ? "Unlock \(descriptor.title) layer" : "Lock \(descriptor.title) layer",
                    accessibilityHint: "Toggles whether this layer can be moved, rotated, resized, or flipped."
                ) {
                    if let toggleLayerLock {
                        toggleLayerLock(layer)
                    } else {
                        mutateLayerRecords { records in
                            records.toggleLock(for: layer)
                        }
                    }
                }

                if layers.count > 1 {
                    layerIconButton(
                        systemName: "arrow.down",
                        accessibilityIdentifier: "layerMoveBackward\(descriptor.identifierSuffix)",
                        accessibilityLabel: layerRecords.canMoveBackward(layer, within: layers)
                            ? "Move \(descriptor.title) layer backward"
                            : "\(descriptor.title) layer is already at the back",
                        accessibilityHint: "Moves this layer lower in the visual stack.",
                        isDisabled: !layerRecords.canMoveBackward(layer, within: layers)
                    ) {
                        if let moveLayerBackward {
                            moveLayerBackward(layer, layers)
                        } else {
                            mutateLayerRecords { records in
                                records.moveBackward(layer, within: layers)
                            }
                        }
                    }

                    layerIconButton(
                        systemName: "arrow.up",
                        accessibilityIdentifier: "layerMoveForward\(descriptor.identifierSuffix)",
                        accessibilityLabel: layerRecords.canMoveForward(layer, within: layers)
                            ? "Move \(descriptor.title) layer forward"
                            : "\(descriptor.title) layer is already at the front",
                        accessibilityHint: "Moves this layer higher in the visual stack.",
                        isDisabled: !layerRecords.canMoveForward(layer, within: layers)
                    ) {
                        if let moveLayerForward {
                            moveLayerForward(layer, layers)
                        } else {
                            mutateLayerRecords { records in
                                records.moveForward(layer, within: layers)
                            }
                        }
                    }
                }

                if duplicateLayer != nil, case .content = layer {
                    layerIconButton(
                        systemName: "plus.square.on.square",
                        accessibilityIdentifier: "layerDuplicate\(descriptor.identifierSuffix)",
                        accessibilityLabel: "Duplicate \(descriptor.title) layer",
                        accessibilityHint: "Creates a copy of this layer."
                    ) {
                        duplicateLayer?(layer)
                    }
                }

                if deleteLayer != nil, case .content = layer {
                    layerIconButton(
                        systemName: "trash",
                        accessibilityIdentifier: "layerDelete\(descriptor.identifierSuffix)",
                        accessibilityLabel: "Delete \(descriptor.title) layer",
                        accessibilityHint: "Removes this layer from the thumbnail."
                    ) {
                        deleteLayer?(layer)
                    }
                }
            }
        }
        .frame(width: cardWidth, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? Color.blue.opacity(0.1) : Color(uiColor: .systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.blue : Color.primary.opacity(0.1), lineWidth: isSelected ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(isVisible ? 1 : 0.68)
    }

    private var cardWidth: CGFloat {
        let baseWidth: CGFloat
        if duplicateLayer != nil || deleteLayer != nil {
            baseWidth = layers.count > 1 ? 448 : 328
        } else {
            baseWidth = layers.count > 1 ? 348 : 228
        }

        let accessibilityExpansion = dynamicTypeSize.isAccessibilitySize
            ? min(96, max(0, controlSize - 44) * 2)
            : 0
        return baseWidth + accessibilityExpansion
    }

    private var displayLayers: [ThumbnailLayerSelection] {
        let sortedLayers = layerRecords.sortedSelections(layers)
        let hasContentLayer = sortedLayers.contains { selection in
            if case .content = selection {
                return true
            }
            return false
        }

        return hasContentLayer ? Array(sortedLayers.reversed()) : sortedLayers
    }

    private func mutateLayerRecords(_ mutate: (inout [ThumbnailDocumentLayer]) -> Void) {
        var updatedRecords = layerRecords
        mutate(&updatedRecords)
        layerRecords = updatedRecords
    }

    private func layerIconButton(
        systemName: String,
        accessibilityIdentifier: String,
        accessibilityLabel: String,
        accessibilityHint: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: controlSize, height: controlSize)
                .background(Color(uiColor: .tertiarySystemBackground))
                .clipShape(Circle())
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .help(accessibilityLabel)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.38 : 1)
    }

    private func accessibilityValue(
        for layer: ThumbnailLayerSelection,
        isSelected: Bool,
        record: ThumbnailDocumentLayer
    ) -> String {
        [
            isSelected ? "Selected" : "Not selected",
            record.isVisible ? "Visible" : "Hidden",
            record.isLocked ? "Locked" : "Unlocked",
            "Order \(displayLayers.firstIndex(of: layer).map { $0 + 1 } ?? 1) of \(layers.count)"
        ]
        .appending(groupName(for: record).map { "In \($0)" }) // FEATURE-07
        .joined(separator: ", ")
    }

    /// FEATURE-07: "Group N" for grouped layers.
    private func groupName(for record: ThumbnailDocumentLayer) -> String? {
        layerRecords.groupID(forLayerID: record.id).flatMap(layerRecords.groupDisplayName(for:))
    }

    private func fallbackRecord(for selection: ThumbnailLayerSelection) -> ThumbnailDocumentLayer {
        switch selection {
        case .textOverlay:
            return .defaultTextLayer
        case .profileOverlay:
            return .defaultProfileLayer
        case .content(let id):
            return ThumbnailDocumentLayer(
                id: id,
                kind: .shape,
                name: "Layer",
                zIndex: ThumbnailDocumentLayer.contentLayerZIndexStart
            )
        }
    }

    private func descriptor(
        for record: ThumbnailDocumentLayer,
        selection: ThumbnailLayerSelection
    ) -> LayerDescriptor {
        switch selection {
        case .textOverlay:
            return LayerDescriptor(
                title: record.name.isEmpty ? "Text" : record.name,
                subtitle: "Overlay",
                systemImage: "textformat",
                selectionIdentifier: "layerSelectionText",
                identifierSuffix: "Text"
            )
        case .profileOverlay:
            return LayerDescriptor(
                title: record.name.isEmpty ? "Profile" : record.name,
                subtitle: "Circle",
                systemImage: "person.crop.circle",
                selectionIdentifier: "layerSelectionProfile",
                identifierSuffix: "Profile"
            )
        case .content(let id):
            let ordinal = contentOrdinal(for: id, matching: record.content)
            if case .text = record.content {
                return LayerDescriptor(
                    title: record.name.isEmpty ? "Text \(ordinal)" : record.name,
                    subtitle: "Text Layer",
                    systemImage: "textformat",
                    selectionIdentifier: "layerSelectionTextLayer\(ordinal)",
                    identifierSuffix: "TextLayer\(ordinal)"
                )
            }

            if case .shape(let content) = record.content {
                return LayerDescriptor(
                    title: record.name.isEmpty ? "\(content.shapeKind.displayName) \(ordinal)" : record.name,
                    subtitle: content.shapeKind.layerSubtitle, // FEATURE-12
                    systemImage: content.shapeKind.systemImage,
                    selectionIdentifier: "layerSelectionShape\(ordinal)",
                    identifierSuffix: "Shape\(ordinal)"
                )
            }

            if case .image(let content) = record.content, content.isSticker {
                return LayerDescriptor(
                    title: record.name.isEmpty ? "Sticker \(ordinal)" : record.name,
                    subtitle: "Sticker Layer",
                    systemImage: "face.smiling",
                    selectionIdentifier: "layerSelectionSticker\(ordinal)",
                    identifierSuffix: "Sticker\(ordinal)"
                )
            }

            return LayerDescriptor(
                title: record.name.isEmpty ? "Image \(ordinal)" : record.name,
                subtitle: "Image Layer",
                systemImage: "photo.on.rectangle",
                selectionIdentifier: "layerSelectionImage\(ordinal)",
                identifierSuffix: "Image\(ordinal)"
            )
        }
    }

    private func contentOrdinal(for id: String, matching content: ThumbnailLayerContent?) -> Int {
        guard let content else {
            return contentOrdinal(for: id)
        }

        let contentLayerIDs = layerRecords
            .filter { layer in
                guard let layerContent = layer.content else { return false }
                switch (content, layerContent) {
                case (.image(let left), .image(let right)):
                    return left.isSticker == right.isSticker
                case (.text, .text), (.shape, .shape):
                    return true
                default:
                    return false
                }
            }
            .sorted { $0.zIndex < $1.zIndex }
            .map(\.id)

        return contentLayerIDs.firstIndex(of: id).map { $0 + 1 } ?? 1
    }

    private func contentOrdinal(for id: String) -> Int {
        let contentLayerIDs = layerRecords
            .filter { $0.content != nil }
            .sorted { $0.zIndex < $1.zIndex }
            .map(\.id)

        return contentLayerIDs.firstIndex(of: id).map { $0 + 1 } ?? 1
    }

    private struct LayerDescriptor {
        let title: String
        let subtitle: String
        let systemImage: String
        let selectionIdentifier: String
        let identifierSuffix: String
    }
}

#Preview {
    LayerSelectionStripView(
        selection: .constant(.textOverlay),
        layerRecords: .constant(ThumbnailDocumentLayer.defaultLayers(hasText: true, hasProfile: true)),
        layers: [.textOverlay, .profileOverlay]
    )
    .padding()
}

private extension Array where Element == String {
    func appending(_ element: String?) -> [String] {
        guard let element else { return self }
        return self + [element]
    }
}
