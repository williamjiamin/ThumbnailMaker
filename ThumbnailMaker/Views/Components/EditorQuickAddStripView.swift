//
//  EditorQuickAddStripView.swift
//  ThumbnailMaker
//
//  EDITOR (1.1.0 parity): the compact strip under the canvas —
//  BG | Text Image Shape Sticker | Library — shared by both editors. Every
//  button forwards to an existing view-model intent supplied by the host
//  editor, so adding a layer is still exactly one undo step.
//

import PhotosUI
import SwiftUI

struct EditorQuickAddStripView: View {
    @Binding var imageLayerSelection: PhotosPickerItem?
    let openBackground: () -> Void
    let addText: () -> Void
    let addShape: (ThumbnailShapeKind) -> Void
    let addCallout: (ThumbnailCalloutPreset) -> Void
    let openStickers: () -> Void
    let openLibrary: () -> Void
    @ScaledMetric(relativeTo: .caption) private var itemMinWidth: CGFloat = 52

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button(action: openBackground) {
                    itemLabel("BG", systemImage: "photo.artframe")
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("quickAddBackground")
                .accessibilityLabel("Background")
                .accessibilityHint("Opens background photo and color controls.")

                separator

                Button(action: addText) {
                    itemLabel("Text", systemImage: "textformat")
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("quickAddText")
                .accessibilityLabel("Quick Add Text")

                PhotosPicker(selection: $imageLayerSelection, matching: .images) {
                    itemLabel("Image", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("quickAddImage")
                .accessibilityLabel("Quick Add Image")

                Menu {
                    Button {
                        addShape(.rectangle)
                    } label: {
                        Label("Rectangle", systemImage: "rectangle")
                    }
                    Button {
                        addShape(.ellipse)
                    } label: {
                        Label("Ellipse", systemImage: "oval")
                    }
                    ShapeCalloutMenuSection(add: addCallout)
                } label: {
                    itemLabel("Shape", systemImage: "square.on.circle")
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("quickAddShape")
                .accessibilityLabel("Quick Add Shape")

                Button(action: openStickers) {
                    itemLabel("Sticker", systemImage: "face.smiling")
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("quickAddSticker")
                .accessibilityLabel("Quick Add Sticker")
                .accessibilityHint("Opens the sticker library.")

                separator

                Button(action: openLibrary) {
                    itemLabel("Library", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("quickAddLibrary")
                .accessibilityLabel("Asset Library")
                .accessibilityHint("Photos, stickers, images used in this project and brand logos.")
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editorQuickAddStrip")
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.15))
            .frame(width: 1, height: 32)
            .padding(.horizontal, 2)
            .accessibilityHidden(true)
    }

    private func itemLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .accessibilityHidden(true) // the control carries the spoken label
        }
        .frame(minWidth: itemMinWidth, minHeight: 48)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
    }
}

// MARK: - Background

/// BG entry point: background photo and colour. Gradients plug into
/// `accessory` (another worker owns them); it is empty by default.
struct EditorBackgroundSheet<Accessory: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var photoSelection: PhotosPickerItem?
    @Binding var backgroundColor: Color
    let hasPhoto: Bool
    let commit: () -> Void
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Photo")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        PhotosPicker(selection: $photoSelection, matching: .images) {
                            Label(hasPhoto ? "Replace Photo" : "Choose Photo", systemImage: "photo")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier("backgroundPhotoPicker")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Color")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        ColorPicker("Background Color", selection: $backgroundColor, supportsOpacity: false)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("backgroundColorPicker")
                        Text("The color shows wherever the photo does not cover the canvas.")
                            .font(.footnote)
                            .foregroundStyle(Color.accessibleSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    accessory()
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Background")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    SheetToolbarButton(.done) { dismiss() }
                        .accessibilityIdentifier("backgroundSheetDoneButton")
                }
            }
        }
        .onChange(of: photoSelection) { _, newValue in
            if newValue != nil { dismiss() }
        }
        .onDisappear(perform: commit)
        .accessibilityIdentifier("backgroundSheet")
    }
}

extension EditorBackgroundSheet where Accessory == EmptyView {
    init(
        photoSelection: Binding<PhotosPickerItem?>,
        backgroundColor: Binding<Color>,
        hasPhoto: Bool,
        commit: @escaping () -> Void
    ) {
        self.init(
            photoSelection: photoSelection,
            backgroundColor: backgroundColor,
            hasPhoto: hasPhoto,
            commit: commit,
            accessory: { EmptyView() }
        )
    }
}

// MARK: - Unified asset library

enum AssetLibrarySection: String, CaseIterable, Identifiable {
    case photos, stickers, recent, brand
    var id: String { rawValue }

    var title: String {
        switch self {
        case .photos: "Photos"
        case .stickers: "Stickers"
        case .recent: "Used in This Project"
        case .brand: "Brand Kit"
        }
    }
}

struct AssetLibrarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var imageLayerSelection: PhotosPickerItem?
    @Binding var stickerLayerSelection: PhotosPickerItem?
    let initialSection: AssetLibrarySection
    let recentAssets: [ThumbnailAssetLibraryItem]
    let brandAssets: [ThumbnailAssetLibraryItem]
    /// GAPS: the one place to open the brand kit editor. The host presents
    /// it after this sheet has dismissed.
    var manageBrandKits: (() -> Void)? = nil
    let insert: (ThumbnailAssetLibraryItem) -> Void
    var openVideo: (() -> Void)? = nil // FRAME
    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = 64

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        photosSection
                        gridSection(.stickers, items: ThumbnailAssetLibrary.builtInStickers, emptyText: "")
                        gridSection(
                            .recent,
                            items: recentAssets,
                            emptyText: "Images and stickers you add to this project appear here for quick reuse."
                        )
                        gridSection(
                            .brand,
                            items: brandAssets,
                            emptyText: "Add a logo to a brand kit to reuse it here."
                        )
                        if let manageBrandKits {
                            Button {
                                manageBrandKits()
                                dismiss()
                            } label: {
                                Label("Brand Kit", systemImage: "paintpalette")
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .background(Color(uiColor: .secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("brandKitButton")
                            .accessibilityLabel("Brand Kit")
                            .accessibilityHint("Edit brand kits: colors, fonts and logos.")
                        }
                    }
                    .padding(20)
                }
                .onAppear {
                    if initialSection != .photos {
                        proxy.scrollTo(initialSection.id, anchor: .top)
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetToolbarButton(.close) { dismiss() }
                        .accessibilityIdentifier("assetLibraryCloseButton")
                }
            }
        }
        .onChange(of: imageLayerSelection) { _, newValue in
            if newValue != nil { dismiss() }
        }
        .onChange(of: stickerLayerSelection) { _, newValue in
            if newValue != nil { dismiss() }
        }
        .accessibilityIdentifier("assetLibrarySheet")
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(.photos)
            PhotosPicker(selection: $imageLayerSelection, matching: .images) {
                Label("Photo as Image Layer", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Photo as Image Layer")
            .accessibilityIdentifier("assetLibraryPhotoImage")
            PhotosPicker(selection: $stickerLayerSelection, matching: .images) {
                Label("Photo as Sticker", systemImage: "face.smiling")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Photo as Sticker")
            .accessibilityIdentifier("assetLibraryPhotoSticker")
            if let openVideo { // FRAME
                Button {
                    openVideo()
                    dismiss()
                } label: {
                    Label("Grab Frame from Video", systemImage: "film")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 12)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("assetLibraryVideoFrame")
                .accessibilityHint("Pick a video and use one of its frames as the background or an image layer.")
            }
        }
        .id(AssetLibrarySection.photos.id)
    }

    private func gridSection(
        _ section: AssetLibrarySection,
        items: [ThumbnailAssetLibraryItem],
        emptyText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(section)
            if items.isEmpty {
                Text(emptyText)
                    .font(.footnote)
                    .foregroundStyle(Color.accessibleSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: tileSize), spacing: 10)], spacing: 10) {
                    ForEach(items) { item in
                        tile(item)
                    }
                }
            }
        }
        .id(section.id)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("assetLibrarySection_\(section.rawValue)")
    }

    private func sectionHeader(_ section: AssetLibrarySection) -> some View {
        Text(section.title)
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }

    private func tile(_ item: ThumbnailAssetLibraryItem) -> some View {
        Button {
            insert(item)
            dismiss()
        } label: {
            Group {
                if let image = UIImage(data: item.imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "photo")
                }
            }
            .padding(6)
            .frame(width: tileSize, height: tileSize)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityHint(item.insertKind == .sticker ? "Adds this as a sticker layer." : "Adds this as an image layer.")
        .accessibilityIdentifier(item.accessibilityIdentifier)
    }
}

// MARK: - Actions

/// Quick action buttons for the selected layer. Each is one undo step.
struct LayerQuickActionsView<Editor: ThumbnailQuickActionEditing & ObservableObject>: View {
    @ObservedObject var editor: Editor
    @Binding var selection: ThumbnailLayerSelection
    @ScaledMetric(relativeTo: .body) private var controlSize: CGFloat = 44

    var body: some View {
        if editor.selectableLayerSelections.contains(selection) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Actions")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ThumbnailQuickAction.allCases) { action in
                            actionButton(action)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("layerQuickActions")
        }
    }

    private func actionButton(_ action: ThumbnailQuickAction) -> some View {
        let isEnabled = editor.canPerformQuickAction(action, on: selection)
        return Button {
            let outcome = editor.performQuickAction(action, on: selection)
            selection = outcome.selection
            UIAccessibility.post(notification: .announcement, argument: outcome.announcement)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: controlSize, height: controlSize)
                    .background(Color(uiColor: .tertiarySystemBackground))
                    .foregroundStyle(action.isDestructive ? Color.red : Color.accentColor)
                    .clipShape(Circle())
                    .opacity(isEnabled ? 1 : 0.38)
                    .accessibilityHidden(true)
                Text(action.shortTitle)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true) // the button carries the spoken label
            }
            .frame(minWidth: controlSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(action.accessibilityIdentifier)
        .accessibilityLabel(action.title)
        .help(action.title)
    }
}
