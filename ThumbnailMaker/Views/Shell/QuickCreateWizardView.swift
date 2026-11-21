//
//  QuickCreateWizardView.swift
//  ThumbnailMaker
//
//  SHELL (1.1.0 rebuild): the guided Quick Create wizard
//  (Template -> Text -> Style -> Export) with Cancel, Skip to Editor and a
//  step indicator. It only edits a `QuickCreateDraft`; the shell turns the
//  finished draft into a project in the editor.
//

import SwiftUI

enum QuickCreateFinishAction: Equatable {
    /// Open the result in the editor.
    case openEditor
    /// Open it in the editor and save a copy to Photos right away.
    case saveToPhotos
}

struct QuickCreateWizardView: View {
    let brandKits: [BrandKit]
    let allowsPremiumFonts: Bool
    let onCancel: () -> Void
    let onFinish: (QuickCreateDraft, QuickCreateFinishAction) -> Void

    @State private var draft = QuickCreateDraft()
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title
        case subtitle
    }

    private var fonts: [CustomFont] {
        allowsPremiumFonts ? CustomFont.allCases : CustomFont.basicFonts
    }

    private var selectedBrandKit: BrandKit? {
        draft.brandKitID.flatMap { id in brandKits.first { $0.id == id } }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                QuickCreateStepIndicator(current: draft.step)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(draft.step.prompt)
                            .font(.body)
                            .foregroundStyle(.secondary)

                        stepContent
                    }
                    .padding(20)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)

                footer
            }
            .navigationTitle("Quick Create")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .accessibilityIdentifier("quickCreateCancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Skip to Editor") {
                        focusedField = nil
                        onFinish(draft, .openEditor)
                    }
                    .accessibilityIdentifier("quickCreateSkipButton")
                    .accessibilityHint("Opens the editor with your choices so far.")
                }
            }
        }
        .accessibilityIdentifier("quickCreateWizard")
    }

    @ViewBuilder
    private var stepContent: some View {
        switch draft.step {
        case .template:
            templateStep
        case .text:
            livePreview
            textStep
        case .style:
            livePreview
            styleStep
        case .export:
            livePreview
            exportStep
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                if draft.step.previous != nil {
                    Button {
                        focusedField = nil
                        draft.goBack()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("quickCreateBackButton")
                }

                Spacer(minLength: 0)

                if draft.step == .export {
                    Button {
                        onFinish(draft, .saveToPhotos)
                    } label: {
                        Text("Save to Photos")
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("quickCreateSaveButton")
                    .accessibilityHint("Creates the project and saves the image to Photos.")

                    gradientCapsuleButton("Create", systemImage: "checkmark", identifier: "quickCreateFinishButton") {
                        onFinish(draft, .openEditor)
                    }
                } else {
                    gradientCapsuleButton("Next", systemImage: "chevron.right", identifier: "quickCreateNextButton") {
                        focusedField = nil
                        draft.goForward()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func gradientCapsuleButton(
        _ title: String,
        systemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(minHeight: 44)
            .background(QuickCreateTheme.gradient)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    // MARK: Live preview

    private var livePreview: some View {
        let document = draft.makeDocument(brandKit: selectedBrandKit)
        return QuickCreateDocumentPreview(document: document)
            .frame(maxHeight: 260)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview")
            .accessibilityValue(document.text.value.isEmpty ? "Blank canvas" : document.text.value)
            .accessibilityIdentifier("quickCreatePreview")
    }

    // MARK: Step 1 - Template

    private var templateStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Format")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(QuickCreateFormat.allCases) { format in
                        formatButton(format)
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(QuickCreateCategoryFilter.allCases) { filter in
                        chip(
                            filter.title,
                            systemImage: filter.systemImage,
                            isSelected: draft.categoryFilter == filter,
                            identifier: "quickCreateCategory-\(filter.rawValue)"
                        ) {
                            draft.selectCategory(filter)
                        }
                    }
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: 14)],
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(draft.visibleLayouts) { layout in
                    templateCard(layout)
                }
            }
        }
    }

    private func formatButton(_ format: QuickCreateFormat) -> some View {
        let isSelected = draft.format == format
        let ratio = format.aspectRatio.value
        let iconHeight: CGFloat = 26
        let iconWidth = min(40, max(16, iconHeight * ratio))
        return Button {
            draft.format = format
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isSelected ? QuickCreateTheme.gradientStart : Color.secondary, lineWidth: 1.5)
                    .frame(width: iconWidth, height: ratio >= 1 ? iconWidth / ratio : iconHeight)
                    .frame(height: 36)
                Text(format.ratioLabel)
                    .font(.caption.weight(.semibold))
                Text(format.platformLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minWidth: 64, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? QuickCreateTheme.gradientStart.opacity(0.14) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(format.ratioLabel), \(format.platformLabel)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("quickCreateFormat-\(format.rawValue)")
    }

    private func templateCard(_ layout: ThumbnailTemplate) -> some View {
        let isSelected = draft.templateID == layout.id
        var document = layout.document
        document.canvas.aspectRatioRawValue = draft.format.aspectRatio.rawValue
        return Button {
            draft.templateID = layout.id
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    if layout.isQuickCreateBlank {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(uiColor: .systemBackground))
                        VStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.title2)
                            Text("Blank")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        QuickCreateDocumentPreview(document: document)
                    }
                }
                .frame(height: 96)
                .frame(maxWidth: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            isSelected ? QuickCreateTheme.gradientStart : Color.secondary.opacity(0.25),
                            lineWidth: isSelected ? 3 : 1
                        )
                )
                Text(layout.name)
                    .font(.footnote.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(layout.name)
        .accessibilityValue(layout.category == .youtube ? "Template" : "\(layout.category.title) template")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("quickCreateTemplate-\(layout.id)")
    }

    // MARK: Step 2 - Text

    private var textStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("Title")
                TextField("Enter your title", text: $draft.title, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .title)
                    .submitLabel(.next)
                    .accessibilityLabel("Title")
                    .accessibilityIdentifier("quickCreateTitleField")
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionTitle("Subtitle")
                TextField("Optional subtitle", text: $draft.subtitle, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .subtitle)
                    .accessibilityLabel("Subtitle")
                    .accessibilityIdentifier("quickCreateSubtitleField")
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Font")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(fonts) { font in
                            chip(
                                font.displayName,
                                isSelected: draft.effectiveFont == font,
                                identifier: "quickCreateFont-\(font.rawValue)"
                            ) {
                                draft.font = font
                            }
                        }
                    }
                }
            }

            ColorPicker(selection: titleColorBinding, supportsOpacity: false) {
                Text("Title Color")
                    .font(.subheadline)
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("quickCreateTitleColor")
        }
    }

    private var titleColorBinding: Binding<Color> {
        Binding(
            get: { draft.effectiveTitleColor.color },
            set: { draft.titleColor = ThumbnailDocumentColor(color: $0) }
        )
    }

    // MARK: Step 3 - Style

    private var styleStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Text Style")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("Layout", isSelected: draft.textStylePresetID == nil, identifier: "quickCreateTextStyle-layout") {
                            draft.textStylePresetID = nil
                        }
                        ForEach(ThumbnailTextStylePreset.all(for: .overlay)) { preset in
                            chip(
                                preset.displayName,
                                isSelected: draft.textStylePresetID == preset.id,
                                identifier: "quickCreateTextStyle-\(preset.id)"
                            ) {
                                draft.textStylePresetID = preset.id
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Background")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("Layout", isSelected: draft.background == .layout, identifier: "quickCreateBackground-layout") {
                            draft.background = .layout
                        }
                        chip("Solid", isSelected: isSolidBackground, identifier: "quickCreateBackground-solid") {
                            if !isSolidBackground {
                                draft.background = .solid(draft.selectedLayout.document.canvas.backgroundColor)
                            }
                        }
                        ForEach(ThumbnailBackgroundFill.presets) { preset in
                            gradientSwatch(preset)
                        }
                    }
                }
                if case .solid = draft.background {
                    ColorPicker(selection: solidBackgroundBinding, supportsOpacity: false) {
                        Text("Background Color")
                            .font(.subheadline)
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("quickCreateBackgroundColor")
                }
            }

            if !brandKits.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("Brand Kit")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("None", isSelected: draft.brandKitID == nil, identifier: "quickCreateBrandKit-none") {
                                draft.brandKitID = nil
                            }
                            ForEach(brandKits) { kit in
                                chip(kit.name, isSelected: draft.brandKitID == kit.id, identifier: "quickCreateBrandKit-\(kit.id)") {
                                    draft.brandKitID = kit.id
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var isSolidBackground: Bool {
        if case .solid = draft.background { return true }
        return false
    }

    private var solidBackgroundBinding: Binding<Color> {
        Binding(
            get: {
                if case .solid(let color) = draft.background { return color.color }
                return draft.selectedLayout.document.canvas.backgroundColor.color
            },
            set: { draft.background = .solid(ThumbnailDocumentColor(color: $0)) }
        )
    }

    private func gradientSwatch(_ preset: ThumbnailBackgroundFill.Preset) -> some View {
        let isSelected = draft.background == .gradient(preset.fill)
        return Button {
            draft.background = .gradient(preset.fill)
        } label: {
            Circle()
                .fill(LinearGradient(gradient: preset.fill.gradient, startPoint: preset.fill.startPoint, endPoint: preset.fill.endPoint))
                .frame(width: 32, height: 32)
                .overlay(Circle().stroke(Color.primary.opacity(isSelected ? 0.8 : 0.15), lineWidth: 2))
                .minimumHitTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.name) gradient")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("quickCreateBackground-\(preset.id)")
    }

    // MARK: Step 4 - Export

    private var exportStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                sectionTitle("Size")
                Text(draft.format.exportPreset.name)
                    .font(.body.weight(.semibold))
                Text(draft.format.exportPreset.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("quickCreateExportSize")

            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("File Format")
                Picker("File format", selection: $draft.exportFormat) {
                    ForEach(ThumbnailExportFormat.allCases) { format in
                        Text(format.rawValue.uppercased()).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("quickCreateFileFormatPicker")
            }

            Text("You can change anything later in the editor, including the size, variants and every layer.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Pieces

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func chip(
        _ title: String,
        systemImage: String? = nil,
        isSelected: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.subheadline)
            .foregroundStyle(isSelected ? QuickCreateTheme.gradientStart : .primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                Capsule().fill(isSelected ? QuickCreateTheme.gradientStart.opacity(0.16) : Color(uiColor: .secondarySystemBackground))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// The 1.1.0 step indicator: four dots joined by a line, labels underneath.
struct QuickCreateStepIndicator: View {
    let current: QuickCreateStep

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(QuickCreateStep.allCases) { step in
                VStack(spacing: 4) {
                    Circle()
                        .fill(color(for: step))
                        .frame(width: step == current ? 12 : 8, height: step == current ? 12 : 8)
                        .frame(height: 12)
                    Text(step.title)
                        .font(.caption2)
                        .foregroundStyle(step == current ? QuickCreateTheme.gradientStart : .secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(alignment: .top) {
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 2)
                .padding(.top, 5)
                .padding(.horizontal, 30)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current.rawValue + 1) of \(QuickCreateStep.allCases.count)")
        .accessibilityValue(current.title)
        .accessibilityIdentifier("quickCreateStepIndicator")
    }

    private func color(for step: QuickCreateStep) -> Color {
        if step == current { return QuickCreateTheme.gradientStart }
        if step.rawValue < current.rawValue { return .green }
        return Color.secondary.opacity(0.4)
    }
}

/// A non-interactive, faithful render of a document (same view the editor
/// canvas and the exporters use), letterboxed to its aspect ratio.
struct QuickCreateDocumentPreview: View {
    let document: ThumbnailDocument

    var body: some View {
        let ratio = (AspectRatio(rawValue: document.canvas.aspectRatioRawValue) ?? .ratio16_9).value
        GeometryReader { proxy in
            let size = Self.fittedSize(ratio: ratio, in: proxy.size)
            PreviewComponentView(
                simpleMakerConfiguration: .constant(document.makeSimpleConfiguration()),
                width: size.width,
                height: size.height
            )
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(ratio, contentMode: .fit)
        .accessibilityHidden(true)
    }

    static func fittedSize(ratio: CGFloat, in container: CGSize) -> CGSize {
        guard container.width > 0, container.height > 0, ratio > 0 else { return CGSize(width: 1, height: 1) }
        let widthLimited = CGSize(width: container.width, height: container.width / ratio)
        if widthLimited.height <= container.height {
            return widthLimited
        }
        return CGSize(width: container.height * ratio, height: container.height)
    }
}
