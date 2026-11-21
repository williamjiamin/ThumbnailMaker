//
//  BrandKitLibraryView.swift
//  ThumbnailMaker
//
//  FEATURE-08: brand kit library sheet. Pick the active kit, create /
//  duplicate / rename / delete kits (delete has an Undo toast), save the
//  selected layer's look as a named style, and apply a kit or style either to
//  the selected layer or to the whole project (an explicit choice, never
//  inferred). With no kits yet it opens straight into the kit editor.
//

import SwiftUI

struct BrandKitLibraryView<Editor: BrandKitLibraryEditing & ObservableObject>: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var editor: Editor
    /// Document layer id of the canvas selection (`ThumbnailLayerSelection.documentLayerID`).
    let selectedLayerID: String
    let allowsPremiumFonts: Bool

    @State private var editingKit: BrandKit?
    @State private var renamingKit: BrandKit?
    @State private var renameText = ""
    @State private var isNamingStyle = false
    @State private var styleNameText = ""
    @State private var deletedKit: (kit: BrandKit, index: Int)?
    @State private var statusMessage: String?

    private var library: BrandKitLibrary { editor.brandKitLibrary }

    var body: some View {
        if library.kits.isEmpty {
            BrandKitEditorView(
                brandKit: nil,
                allowsPremiumFonts: allowsPremiumFonts,
                saveBrandKit: { kit in
                    if let kit { editor.updateBrandKit(kit) }
                },
                applyBrandKit: { kit in
                    editor.updateBrandKit(kit)
                    editor.applyBrandKit(kit, to: .projectWide)
                }
            )
        } else {
            libraryBody
        }
    }

    private var libraryBody: some View {
        NavigationStack {
            Form {
                if editor.showingSaveAlert, let message = editor.saveError {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("brandKitLibraryError")
                        Button("Dismiss") {
                            editor.showingSaveAlert = false
                            editor.saveError = nil
                        }
                    }
                }

                projectBadgeSection
                kitsSection
                if let activeKit = library.activeKit {
                    applySection(for: activeKit)
                    stylesSection(for: activeKit)
                }
            }
            .navigationTitle("Brand Kits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetToolbarButton(.done) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if let kit = editor.createBrandKit() {
                            editingKit = kit
                        }
                    } label: {
                        Label("New Kit", systemImage: "plus")
                    }
                    .disabled(library.isFull)
                    .accessibilityIdentifier("brandKitAddButton")
                }
            }
            .safeAreaInset(edge: .bottom) { toast }
            .sheet(item: $editingKit) { kit in
                BrandKitEditorView(
                    brandKit: kit,
                    allowsPremiumFonts: allowsPremiumFonts,
                    saveBrandKit: { edited in
                        if let edited { editor.updateBrandKit(edited) }
                    },
                    applyBrandKit: { edited in
                        editor.updateBrandKit(edited)
                        editor.applyBrandKit(edited, to: .projectWide)
                    },
                    deleteBrandKit: { edited in
                        delete(edited)
                    }
                )
            }
            .alert(
                "Rename Brand Kit",
                isPresented: Binding(
                    get: { renamingKit != nil },
                    set: { if !$0 { renamingKit = nil } }
                )
            ) {
                TextField("Kit name", text: $renameText)
                    .accessibilityIdentifier("brandKitRenameField")
                Button("Cancel", role: .cancel) { renamingKit = nil }
                Button("Rename") {
                    if let kit = renamingKit {
                        editor.renameBrandKit(id: kit.id, to: renameText)
                    }
                    renamingKit = nil
                }
            }
            .alert("Save Layer Style", isPresented: $isNamingStyle) {
                TextField("Style name", text: $styleNameText)
                    .accessibilityIdentifier("layerStyleNameField")
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    if let style = editor.saveLayerStyle(named: styleNameText, fromLayerID: selectedLayerID) {
                        showStatus("Saved style \u{201C}\(style.name)\u{201D}")
                    }
                }
            } message: {
                Text("Saves the selected layer's colors and font as a reusable style in the active kit.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Sections

    private var projectBadgeSection: some View {
        Section {
            if let name = editor.appliedBrandKitDisplayName {
                if editor.appliedBrandKitIsMissing {
                    Label("Styled with \u{201C}\(name)\u{201D} (kit deleted, styling kept)", systemImage: "link.badge.plus")
                        .foregroundStyle(.secondary)
                } else {
                    Label("This project uses \u{201C}\(name)\u{201D}", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
            } else {
                Label("No brand kit applied to this project yet", systemImage: "seal")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("brandKitProjectBadge")
    }

    private var kitsSection: some View {
        Section {
            ForEach(library.kits) { kit in
                kitRow(kit)
            }
        } header: {
            Text("Kits")
        } footer: {
            Text("Tap a kit to make it active. Deleting a kit never changes projects you already styled with it.")
        }
    }

    private func kitRow(_ kit: BrandKit) -> some View {
        let isActive = kit.id == library.activeKitID
        return Button {
            editor.selectBrandKit(id: kit.id)
        } label: {
            HStack(spacing: 12) {
                paletteSwatches(kit)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kit.name)
                        .font(.custom(kit.primaryFont.postScriptName, size: 17))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(kit.styles.isEmpty ? "No saved styles" : "\(kit.styles.count) style\(kit.styles.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityIdentifier("brandKitActiveIndicator")
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(kit.name)
        .accessibilityValue(isActive ? "Active" : "")
        .accessibilityIdentifier("brandKitRow-\(kit.id)")
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(kit) } label: {
                Label("Delete", systemImage: "trash")
            }
            Button { editingKit = kit } label: {
                Label("Edit", systemImage: "slider.horizontal.3")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button { editingKit = kit } label: { Label("Edit", systemImage: "slider.horizontal.3") }
            Button {
                if editor.duplicateBrandKit(id: kit.id) != nil {
                    showStatus("Duplicated \u{201C}\(kit.name)\u{201D}")
                }
            } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                .disabled(library.isFull)
            Button {
                renameText = kit.name
                renamingKit = kit
            } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) { delete(kit) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func applySection(for kit: BrandKit) -> some View {
        Section {
            Button {
                if editor.applyBrandKit(kit, to: .projectWide) {
                    showStatus("Applied \u{201C}\(kit.name)\u{201D} to the whole project")
                } else {
                    showStatus("Project already matches \u{201C}\(kit.name)\u{201D}")
                }
            } label: {
                Label("Apply to Whole Project", systemImage: "rectangle.stack.fill")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("brandKitApplyProjectButton")

            Button {
                if editor.applyBrandKit(kit, to: .layer(selectedLayerID)) {
                    showStatus("Applied \u{201C}\(kit.name)\u{201D} to \(selectedLayerName)")
                } else {
                    showStatus("\(selectedLayerName) already matches or is locked")
                }
            } label: {
                Label("Apply to Selection: \(selectedLayerName)", systemImage: "square.dashed.inset.filled")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .disabled(!selectionAcceptsKit)
            .accessibilityIdentifier("brandKitApplySelectionButton")

            Button {
                editingKit = kit
            } label: {
                Label("Edit \u{201C}\(kit.name)\u{201D}", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("brandKitEditActiveButton")
        } header: {
            Text("Apply \u{201C}\(kit.name)\u{201D}")
        } footer: {
            Text("Whole project restyles the background, title, text layers and shapes (locked layers and images are skipped). Undo reverts it in one step.")
        }
    }

    private func stylesSection(for kit: BrandKit) -> some View {
        Section {
            if kit.styles.isEmpty {
                Text("Save a layer's look to reuse it on other layers and projects.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(kit.styles) { style in
                styleRow(style, kitID: kit.id)
            }
            Button {
                styleNameText = suggestedStyleName
                isNamingStyle = true
            } label: {
                Label("Save \(selectedLayerName) Look as Style", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .disabled(selectionTarget == nil)
            .accessibilityIdentifier("layerStyleSaveButton")
        } header: {
            Text("Layer Styles")
        }
    }

    private func styleRow(_ style: ThumbnailLayerStyle, kitID: String) -> some View {
        let matchesSelection = selectionTarget == style.target
        return HStack(spacing: 12) {
            styleSwatch(style)
            VStack(alignment: .leading, spacing: 2) {
                Text(style.name).lineLimit(1)
                Text(style.target.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Apply") {
                if editor.applyLayerStyle(style, to: .layer(selectedLayerID)) {
                    showStatus("Applied \u{201C}\(style.name)\u{201D} to \(selectedLayerName)")
                } else {
                    showStatus("\(selectedLayerName) already matches or is locked")
                }
            }
            .buttonStyle(.bordered)
            .disabled(!matchesSelection)
            .accessibilityIdentifier("layerStyleApplyButton-\(style.id)")
        }
        .frame(minHeight: 44)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                editor.deleteLayerStyle(id: style.id, fromKit: kitID)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                if editor.applyLayerStyle(style, to: .projectWide) {
                    showStatus("Applied \u{201C}\(style.name)\u{201D} to every \(style.target.displayName.lowercased()) layer")
                }
            } label: {
                Label("Apply to All \(style.target.displayName) Layers", systemImage: "rectangle.stack")
            }
            Button(role: .destructive) {
                editor.deleteLayerStyle(id: style.id, fromKit: kitID)
            } label: {
                Label("Delete Style", systemImage: "trash")
            }
        }
    }

    // MARK: Toast

    @ViewBuilder
    private var toast: some View {
        if let deletedKit {
            HStack {
                Text("Deleted \u{201C}\(deletedKit.kit.name)\u{201D}")
                    .lineLimit(1)
                Spacer()
                Button("Undo") {
                    editor.restoreBrandKit(deletedKit.kit, at: deletedKit.index)
                    self.deletedKit = nil
                }
                .fontWeight(.semibold)
                .accessibilityIdentifier("brandKitUndoDeleteButton")
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let statusMessage {
            Text(statusMessage)
                .font(.footnote)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .transition(.opacity)
                .accessibilityIdentifier("brandKitStatusMessage")
        }
    }

    // MARK: Helpers

    private var stylingDocument: ThumbnailDocument { editor.stylingDocument }

    private var selectedLayerName: String {
        switch selectedLayerID {
        case ThumbnailDocumentLayer.textID: return "Title"
        case ThumbnailDocumentLayer.backgroundID: return "Background"
        case ThumbnailDocumentLayer.profileID: return "Profile"
        default:
            return stylingDocument.layers.first { $0.id == selectedLayerID }?.name ?? "Selection"
        }
    }

    private var selectionTarget: ThumbnailLayerStyleTarget? {
        editor.layerStyleTarget(forLayerID: selectedLayerID)
    }

    private var selectionAcceptsKit: Bool {
        selectedLayerID == ThumbnailDocumentLayer.backgroundID || selectionTarget != nil
    }

    private var suggestedStyleName: String {
        let base = selectionTarget == .shape ? "Shape Style" : "Text Style"
        let existing = library.activeKit?.styles.map(\.name) ?? []
        return BrandKitLibrary.uniqueName(basedOn: base, existing: existing)
    }

    private func delete(_ kit: BrandKit) {
        if let removed = editor.deleteBrandKit(id: kit.id) {
            withAnimation { deletedKit = removed }
            let removedID = removed.kit.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                if deletedKit?.kit.id == removedID {
                    withAnimation { deletedKit = nil }
                }
            }
        }
    }

    private func showStatus(_ message: String) {
        withAnimation { statusMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if statusMessage == message {
                withAnimation { statusMessage = nil }
            }
        }
    }

    private func paletteSwatches(_ kit: BrandKit) -> some View {
        HStack(spacing: -6) {
            ForEach(Array(kit.palette.prefix(3).enumerated()), id: \.offset) { _, brandColor in
                Circle()
                    .fill(brandColor.color.color)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Color.primary.opacity(0.18), lineWidth: 1))
            }
        }
        .accessibilityHidden(true)
    }

    private func styleSwatch(_ style: ThumbnailLayerStyle) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill((style.fillColor ?? style.textColor ?? ThumbnailDocumentColor(color: .gray)).color)
            .frame(width: 28, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke((style.strokeColor?.color ?? Color.primary.opacity(0.18)), lineWidth: 2)
            )
            .overlay(
                Text(style.target == .text ? "Aa" : "")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .shadow(radius: 1)
            )
            .accessibilityHidden(true)
    }
}
