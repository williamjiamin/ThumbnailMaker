//
//  TemplateGalleryView.swift
//  ThumbnailMaker
//

import SwiftUI
import UIKit

struct TemplateGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let templates: [ThumbnailTemplate]
    // FEATURE-05: personal templates + application mode. All optional so the
    // legacy `TemplateGalleryView(templates:onSelect:)` call shape still works.
    private let personalLibrary: PersonalTemplateLibraryModel?
    private let currentDocument: (() -> ThumbnailDocument)?
    private let onApply: (ThumbnailTemplate, ThumbnailTemplateApplicationMode) -> Void
    @State private var applicationMode: ThumbnailTemplateApplicationMode = .composition
    @State private var saveSheetItem: IdentifiedDocument?

    init(
        templates: [ThumbnailTemplate] = ThumbnailTemplate.allBuiltIns, // SHELL: + Quick Create layouts
        onSelect: @escaping (ThumbnailTemplate) -> Void
    ) {
        self.init(templates: templates, personalLibrary: nil, currentDocument: nil) { template, _ in
            onSelect(template)
        }
    }

    init(
        templates: [ThumbnailTemplate] = ThumbnailTemplate.allBuiltIns, // SHELL: + Quick Create layouts
        personalLibrary: PersonalTemplateLibraryModel?,
        currentDocument: (() -> ThumbnailDocument)?,
        onApply: @escaping (ThumbnailTemplate, ThumbnailTemplateApplicationMode) -> Void
    ) {
        self.templates = templates
        self.personalLibrary = personalLibrary
        self.currentDocument = currentDocument
        self.onApply = onApply
    }

    private func onSelect(_ template: ThumbnailTemplate) {
        onApply(template, applicationMode)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let personalLibrary { // FEATURE-05
                        personalHeader(personalLibrary)
                        PersonalTemplateSectionsView(library: personalLibrary) { template in
                            onSelect(template)
                            dismiss()
                        }
                    }
                    ForEach(ThumbnailTemplateCategory.allCases, id: \.self) { category in
                        let categoryTemplates = templates.filter { $0.category == category }
                        if !categoryTemplates.isEmpty {
                            templateSection(category: category, templates: categoryTemplates)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetToolbarButton(.done) {
                        dismiss()
                    }
                }
            }
            .sheet(item: $saveSheetItem) { item in
                if let personalLibrary {
                    SaveAsTemplateSheet(library: personalLibrary, document: item.document)
                }
            }
            .alert(
                "Template Library",
                isPresented: Binding(
                    get: { personalLibrary?.errorMessage != nil || personalLibrary?.recoveryNotice != nil },
                    set: { isPresented in
                        if !isPresented {
                            personalLibrary?.errorMessage = nil
                            personalLibrary?.recoveryNotice = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(personalLibrary?.errorMessage ?? personalLibrary?.recoveryNotice ?? "")
            }
        }
    }

    // FEATURE-05
    @ViewBuilder
    private func personalHeader(_ library: PersonalTemplateLibraryModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Apply as", selection: $applicationMode) {
                ForEach(ThumbnailTemplateApplicationMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("templateApplicationModePicker")

            if let currentDocument {
                Button {
                    saveSheetItem = IdentifiedDocument(document: currentDocument())
                } label: {
                    Label("Save Current Design as Template", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("saveAsTemplateButton")
            }
        }
    }

    private func templateSection(
        category: ThumbnailTemplateCategory,
        templates: [ThumbnailTemplate]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(category.title, systemImage: category.systemImage)
                .font(.headline)
                .foregroundStyle(.primary)

            // APP-07: a plain (non-lazy) grid so every card keeps its text at
            // any Dynamic Type size; one column at accessibility sizes.
            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(Self.rows(of: templates, columns: gridColumnCount), id: \.first?.id) { row in
                    GridRow {
                        ForEach(row) { template in
                            templateButton(template)
                        }
                        ForEach(row.count..<gridColumnCount, id: \.self) { _ in
                            Color.clear
                                .gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                    }
                }
            }
        }
    }

    private func templateButton(_ template: ThumbnailTemplate) -> some View {
        Button {
            onSelect(template)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.clear)
                    .background { // SHELL: gradient-aware swatch
                        ThumbnailBackgroundFillView(
                            fill: template.document.canvas.backgroundFill,
                            color: template.document.canvas.backgroundColor.color
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .overlay(alignment: .center) {
                        // TEMPLATES: the real canvas renderer at card size, so
                        // fonts, text styles, badges and arrows show as applied.
                        TemplateCardPreview(template: template)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            // Sample artwork; the card's label names the template.
                            .accessibilityHidden(true)
                    }
                    .aspectRatio(templateAspectRatio(template), contentMode: .fit)

                VStack(alignment: .leading, spacing: 3) {
                    Text(template.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(templatePresetSummary(template))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let note = ThumbnailTemplate.curatedEntry(id: template.id)?.layoutNote { // TEMPLATES
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        // APP-07: one element per card; the sample artwork and preset line are
        // summarized by the label and value instead of read piecemeal.
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("templateCard-\(template.id)")
        .accessibilityLabel("Apply \(template.name) template")
        .accessibilityValue(templateAccessibilityValue(template))
        .accessibilityHint("Keeps your current images and applies this layout, text style, export preset, and canvas size.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onSelect(template)
            dismiss()
        }
    }

    private var gridColumnCount: Int {
        if dynamicTypeSize.isAccessibilitySize { return 1 }
        return horizontalSizeClass == .regular ? 3 : 2
    }

    static func rows(of templates: [ThumbnailTemplate], columns: Int) -> [[ThumbnailTemplate]] {
        let columns = max(1, columns)
        return stride(from: 0, to: templates.count, by: columns).map {
            Array(templates[$0..<min($0 + columns, templates.count)])
        }
    }

    private func templateAspectRatio(_ template: ThumbnailTemplate) -> CGFloat {
        let aspectRatio = AspectRatio(rawValue: template.document.canvas.aspectRatioRawValue) ?? .ratio16_9
        return aspectRatio.value
    }

    private func templateAccessibilityValue(_ template: ThumbnailTemplate) -> String {
        let base = "\(template.category.title), \(templatePresetSummary(template))"
        guard let note = ThumbnailTemplate.curatedEntry(id: template.id)?.layoutNote else { return base }
        return "\(base), \(note)"
    }

    private func templatePresetSummary(_ template: ThumbnailTemplate) -> String {
        guard let preset = ThumbnailExportPreset.all.first(where: {
            $0.id == template.document.export.presetID
        }) else {
            return template.document.export.presetID
        }

        return "\(preset.name) · \(preset.size.displayText)"
    }
}

extension ThumbnailTemplateCategory { // FEATURE-05: internal so the save sheet can use it
    var title: String {
        switch self {
        case .youtube:
            "YouTube"
        case .shortForm:
            "Short Form"
        case .podcast:
            "Podcast"
        case .gaming:
            "Gaming"
        case .vlog:
            "Vlog"
        case .tutorial:
            "Tutorial"
        case .reaction:
            "Reaction"
        case .beforeAfter:
            "Before / After"
        case .listicle:
            "Top Lists"
        case .news:
            "News"
        case .minimal:
            "Minimal"
        }
    }

    var systemImage: String {
        switch self {
        case .youtube:
            "play.rectangle.fill"
        case .shortForm:
            "rectangle.portrait.fill"
        case .podcast:
            "mic.fill"
        case .gaming:
            "gamecontroller.fill"
        case .vlog:
            "camera.fill"
        case .tutorial:
            "book.fill"
        case .reaction:
            "face.smiling.fill"
        case .beforeAfter:
            "rectangle.split.2x1.fill"
        case .listicle:
            "list.number"
        case .news:
            "newspaper.fill"
        case .minimal:
            "circle.lefthalf.filled"
        }
    }
}

/// TEMPLATES: a card-sized snapshot of a template, drawn by the same
/// renderer the export queue uses, so fonts, text styles, badges and arrows
/// show exactly as applied. A still image (not a live canvas) keeps the
/// sample artwork out of the accessibility tree and cheap to scroll. A
/// curated layout also outlines where the creator's subject goes.
private struct TemplateCardPreview: View {
    let template: ThumbnailTemplate
    @Environment(\.displayScale) private var displayScale
    @State private var snapshot: UIImage?

    @MainActor private static var cache: [String: UIImage] = [:]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let snapshot {
                    Image(uiImage: snapshot)
                        .resizable()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                if let focal = ThumbnailTemplate.curatedEntry(id: template.id)?.focalRegion {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .frame(width: focal.width * proxy.size.width, height: focal.height * proxy.size.height)
                        .offset(x: focal.minX * proxy.size.width, y: focal.minY * proxy.size.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .task(id: proxy.size) {
                snapshot = Self.snapshot(of: template, size: proxy.size, scale: displayScale)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @MainActor
    private static func snapshot(of template: ThumbnailTemplate, size: CGSize, scale: CGFloat) -> UIImage? {
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard width > 0, height > 0 else { return nil }
        let key = "\(template.id)-\(width)x\(height)"
        if let cached = cache[key] { return cached }
        let image = try? ThumbnailQueueDocumentRenderer().render(
            template.document,
            size: ThumbnailExportSize(width: width, height: height)
        )
        if let image { cache[key] = image }
        return image
    }
}

// FEATURE-05: `.sheet(item:)` needs Identifiable.
private struct IdentifiedDocument: Identifiable {
    let id = UUID()
    let document: ThumbnailDocument
}

#Preview {
    TemplateGalleryView { _ in }
}
