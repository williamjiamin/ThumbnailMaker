//
//  PersonalTemplateSectionsView.swift
//  ThumbnailMaker
//
//  FEATURE-05: "Favorites", "My Templates" and "Recently Deleted" sections of
//  the template gallery, with rename / favourite / duplicate / delete /
//  restore management.
//

import SwiftUI

struct PersonalTemplateSectionsView: View {
    @ObservedObject var library: PersonalTemplateLibraryModel
    let onApply: (ThumbnailTemplate) -> Void

    @State private var renamingTemplate: ThumbnailTemplate?
    @State private var renameText = ""
    @State private var showsTrash = false

    private var favorites: [ThumbnailTemplate] { library.favoriteTemplates }
    private var others: [ThumbnailTemplate] { library.activeTemplates.filter { !$0.isFavorite } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !favorites.isEmpty {
                section(title: "Favorites", systemImage: "star.fill", templates: favorites)
            }
            if !others.isEmpty {
                section(title: "My Templates", systemImage: "person.crop.square", templates: others)
            }
            if library.activeTemplates.isEmpty {
                Label("Save a design you like to reuse it here.", systemImage: "square.and.arrow.down")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("personalTemplatesEmptyState")
            }
            if !library.trashedTemplates.isEmpty {
                trashSection
            }
        }
        .alert(
            "Rename Template",
            isPresented: Binding(get: { renamingTemplate != nil }, set: { if !$0 { renamingTemplate = nil } })
        ) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingTemplate = nil }
            Button("Rename") {
                if let template = renamingTemplate {
                    library.rename(id: template.id, to: renameText)
                }
                renamingTemplate = nil
            }
        }
    }

    private func section(title: String, systemImage: String, templates: [ThumbnailTemplate]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(templates) { template in
                    card(template)
                }
            }
        }
    }

    private func card(_ template: ThumbnailTemplate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                onApply(template)
            } label: {
                TemplateSwatch(template: template)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("personalTemplateCard-\(template.id)")
            .accessibilityLabel("Apply \(template.name) template")

            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(template.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(summary(for: template))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    library.setFavorite(!template.isFavorite, id: template.id)
                } label: {
                    Image(systemName: template.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(template.isFavorite ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("personalTemplateFavorite-\(template.id)")
                .accessibilityLabel(template.isFavorite ? "Remove from favorites" : "Add to favorites")
                Menu {
                    managementActions(for: template)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("personalTemplateMenu-\(template.id)")
                .accessibilityLabel("More actions for \(template.name)")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contextMenu { managementActions(for: template) }
    }

    @ViewBuilder
    private func managementActions(for template: ThumbnailTemplate) -> some View {
        Button {
            renameText = template.name
            renamingTemplate = template
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button {
            library.duplicate(id: template.id)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        Button(role: .destructive) {
            library.moveToTrash(id: template.id)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var trashSection: some View {
        DisclosureGroup(isExpanded: $showsTrash) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Deleted templates are kept for 30 days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(library.trashedTemplates) { template in
                    HStack {
                        Text(template.name)
                            .lineLimit(1)
                        Spacer()
                        Button("Restore") {
                            library.restore(id: template.id)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("personalTemplateRestore-\(template.id)")
                        Button(role: .destructive) {
                            library.purge(id: template.id)
                        } label: {
                            Image(systemName: "trash.slash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete \(template.name) permanently")
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Label("Recently Deleted (\(library.trashedTemplates.count))", systemImage: "trash")
                .font(.headline)
        }
        .accessibilityIdentifier("personalTemplatesTrash")
    }

    private func summary(for template: ThumbnailTemplate) -> String {
        var parts = [template.category.title]
        let kept = template.slots.retainedLayerIDs.count
        if kept > 0 {
            parts.append("\(kept) kept image\(kept == 1 ? "" : "s")")
        }
        if template.slots.backgroundImage == .placeholder {
            parts.append("empty background")
        }
        return parts.joined(separator: " · ")
    }
}

/// Swatch preview shared by personal cards (same look as built-in cards).
struct TemplateSwatch: View {
    let template: ThumbnailTemplate

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.clear)
            .background { // SHELL: gradient-aware swatch
                ThumbnailBackgroundFillView(
                    fill: template.document.canvas.backgroundFill,
                    color: template.document.canvas.backgroundColor.color
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .overlay {
                if let data = template.document.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .overlay(alignment: .center) {
                Text(template.document.text.value)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(template.document.text.color.color)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.center)
                    .padding(12)
            }
            .aspectRatio(
                (AspectRatio(rawValue: template.document.canvas.aspectRatioRawValue) ?? .ratio16_9).value,
                contentMode: .fit
            )
            .clipped()
    }
}

extension View {
    /// FEATURE-05: shows what a template left for the creator to finish.
    func templateApplicationWarningsAlert(library: PersonalTemplateLibraryModel) -> some View {
        modifier(TemplateApplicationWarningsAlert(library: library))
    }
}

private struct TemplateApplicationWarningsAlert: ViewModifier {
    @ObservedObject var library: PersonalTemplateLibraryModel

    func body(content: Content) -> some View {
        content.alert(
            "Template Applied",
            isPresented: Binding(
                get: { !library.applicationWarnings.isEmpty },
                set: { if !$0 { library.applicationWarnings = [] } }
            )
        ) {
            Button("OK", role: .cancel) { library.applicationWarnings = [] }
        } message: {
            Text(library.applicationWarnings.map(\.message).joined(separator: "\n\n"))
        }
    }
}
