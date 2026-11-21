//
//  SaveAsTemplateSheet.swift
//  ThumbnailMaker
//
//  FEATURE-05: capture the current design as a personal template.
//

import SwiftUI

struct SaveAsTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: PersonalTemplateLibraryModel
    let document: ThumbnailDocument
    var onSaved: (ThumbnailTemplate) -> Void = { _ in }

    @State private var name: String
    @State private var category: ThumbnailTemplateCategory = .youtube
    @State private var isFavorite = false
    @State private var backgroundPolicy: ThumbnailTemplateSlotPolicy = .replaceFromProject
    @State private var profilePolicy: ThumbnailTemplateSlotPolicy = .replaceFromProject
    @State private var keepsHeadline = false
    @State private var retainedLayerIDs: Set<String> = []
    @State private var saveError: String?

    init(
        library: PersonalTemplateLibraryModel,
        document: ThumbnailDocument,
        onSaved: @escaping (ThumbnailTemplate) -> Void = { _ in }
    ) {
        self.library = library
        self.document = document
        self.onSaved = onSaved
        let headline = document.text.value.trimmingCharacters(in: .whitespacesAndNewlines)
        _name = State(initialValue: headline.isEmpty ? "My Template" : String(headline.prefix(40)))
    }

    private var imageLayers: [ThumbnailDocumentLayer] {
        document.layers
            .filter { if case .image = $0.content { return true } else { return false } }
            .sorted { $0.zIndex > $1.zIndex }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Template name", text: $name)
                        .accessibilityIdentifier("saveTemplateNameField")
                    AccessibleMenuPicker("Category", valueName: category.title, selection: $category) {
                        ForEach(ThumbnailTemplateCategory.allCases, id: \.self) { category in
                            Label(category.title, systemImage: category.systemImage).tag(category)
                        }
                    }
                    Toggle("Favorite", isOn: $isFavorite)
                        .accessibilityIdentifier("saveTemplateFavoriteToggle")
                }

                Section {
                    AccessibleMenuPicker("Background image", valueName: backgroundPolicy.displayName, selection: $backgroundPolicy) {
                        ForEach(ThumbnailTemplateSlotPolicy.allCases) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    if document.profile != nil {
                        AccessibleMenuPicker("Profile photo", valueName: profilePolicy.displayName, selection: $profilePolicy) {
                            ForEach(ThumbnailTemplateSlotPolicy.allCases) { policy in
                                Text(policy.displayName).tag(policy)
                            }
                        }
                    }
                    Toggle("Keep this headline", isOn: $keepsHeadline)
                } header: {
                    Text("When applied")
                } footer: {
                    Text("\"Use project's\" pulls in the image of whatever project you apply the template to. \"Leave empty\" reminds you to add one. \"Keep template's\" saves this image inside the template.")
                }

                if !imageLayers.isEmpty {
                    Section {
                        ForEach(imageLayers) { layer in
                            Toggle(layer.name, isOn: Binding(
                                get: { retainedLayerIDs.contains(layer.id) },
                                set: { isOn in
                                    if isOn { retainedLayerIDs.insert(layer.id) } else { retainedLayerIDs.remove(layer.id) }
                                }
                            ))
                        }
                    } header: {
                        Text("Images to keep (logo, watermark)")
                    } footer: {
                        Text("Images you don't keep are left out, so unrelated media is never copied into new projects.")
                    }
                }
            }
            .navigationTitle("Save as Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetToolbarButton(.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    SheetToolbarButton(.save) { save() }
                        .disabled(trimmedName.isEmpty)
                        .accessibilityIdentifier("saveTemplateConfirmButton")
                }
            }
            .alert(
                "Couldn't Save Template",
                isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
            ) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func save() {
        if let template = library.saveTemplate(
            from: document,
            name: trimmedName,
            category: category,
            isFavorite: isFavorite,
            retainedLayerIDs: retainedLayerIDs,
            backgroundPolicy: backgroundPolicy,
            profilePolicy: profilePolicy,
            titlePolicy: keepsHeadline ? .retained : .replaceFromProject
        ) {
            onSaved(template)
            dismiss()
        } else {
            saveError = library.errorMessage ?? "The template could not be saved."
            library.errorMessage = nil
        }
    }
}
