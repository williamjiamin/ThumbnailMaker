//
//  ShapeLayerControlView.swift
//  ThumbnailMaker
//
//  FEATURE-12: inspector card for a selected shape layer (arrows, badges,
//  callouts, and the legacy rectangle/ellipse). Continuous controls write
//  through the binding (debounced into one undo step, closed on release);
//  discrete controls are bracketed by `commit` so each is its own undo step.
//

import SwiftUI

struct ShapeLayerControlView: View {
    @Binding var content: ThumbnailShapeLayerContent
    let brandPalette: [BrandColor]
    /// Settles history (the editor's `commitEditorStateNow`).
    let commit: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showsMore = false

    private var kind: ThumbnailShapeKind { content.shapeKind }
    private var geometry: ThumbnailResolvedShapeGeometry { content.resolvedGeometry }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding()

            let presets = ThumbnailCalloutPreset.restylePresets(for: kind)
            if !presets.isEmpty {
                Divider()
                presetRow(presets)
                    .padding(.vertical, 10)
            }

            Divider()
            colorSection
                .padding()

            if !brandPalette.isEmpty {
                Divider()
                brandRow
                    .padding(.vertical, 10)
            }

            if hasDetailControls {
                Divider()
                if horizontalSizeClass == .regular {
                    detailControls
                        .padding()
                } else {
                    DisclosureGroup(isExpanded: $showsMore) {
                        detailControls
                            .padding(.top, 8)
                    } label: {
                        Text("More")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("shapeMoreDisclosure")
                    .padding(.horizontal)
                }
            }
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shapeLayerControls")
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.systemImage)
                .font(.title3)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName)
                    .font(.headline)
                Text(kind.layerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func presetRow(_ presets: [ThumbnailCalloutPreset]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presets) { preset in
                    Button {
                        discrete { $0 = preset.restyle($0) }
                    } label: {
                        Label(preset.title, systemImage: preset.systemImage)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(Color(uiColor: .tertiarySystemBackground))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("shapePresetChip-\(preset.id)")
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                ColorPicker(kind == .line ? "Color" : "Fill", selection: colorBinding(\.fillColor))
                    .accessibilityIdentifier("shapeFillColorPicker")
                    .frame(minHeight: 44)

                if kind != .line {
                    Toggle("Outline", isOn: strokeEnabledBinding)
                        .accessibilityIdentifier("shapeStrokeToggle")
                        .frame(minHeight: 44)
                }
            }

            if kind != .line, content.strokeColor != nil {
                ColorPicker("Outline color", selection: strokeColorBinding)
                    .accessibilityIdentifier("shapeStrokeColorPicker")
                    .frame(minHeight: 44)
            }

            if kind == .line || content.strokeColor != nil {
                labeledSlider(
                    kind == .line ? "Thickness" : "Outline width",
                    value: $content.strokeWidth,
                    range: kind == .line ? 0.004...0.05 : 0...0.04,
                    identifier: "shapeStrokeWidthSlider"
                )
            }
        }
    }

    private var brandRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Text("Brand")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(brandPalette) { brandColor in
                    Button {
                        discrete { content in
                            if content.shapeKind == .line {
                                content.fillColor = brandColor.color
                            } else if content.fillColor.alpha < 0.05, content.strokeColor != nil {
                                content.strokeColor = brandColor.color
                            } else {
                                content.fillColor = brandColor.color
                                if var label = content.label {
                                    label.color = ThumbnailCalloutPreset.contrastingLabelColor(on: brandColor.color)
                                    content.label = label
                                }
                            }
                        }
                    } label: {
                        Circle()
                            .fill(brandColor.color.color)
                            .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
                            .frame(width: 30, height: 30)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Use brand color \(brandColor.name)")
                    .accessibilityIdentifier("shapeBrandSwatch-\(brandColor.id)")
                }
            }
            .padding(.horizontal)
        }
    }

    private var hasDetailControls: Bool {
        kind != .rectangle || kind.supportsLabel
    }

    @ViewBuilder
    private var detailControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            if kind.isArrowFamily {
                headPicker("Start", value: headBinding(start: true), identifier: "shapeArrowStartHeadPicker")
                headPicker("End", value: headBinding(start: false), identifier: "shapeArrowEndHeadPicker")
            }
            if kind == .arrow {
                labeledSlider(
                    "Shaft thickness",
                    value: geometryBinding(\.shaftThickness, resolved: geometry.shaftThickness),
                    range: ThumbnailShapeGeometryRecipe.shaftThicknessRange,
                    identifier: "shapeArrowThicknessSlider"
                )
                labeledSlider(
                    "Head length",
                    value: geometryBinding(\.headLength, resolved: geometry.headLength),
                    range: ThumbnailShapeGeometryRecipe.headLengthRange,
                    identifier: "shapeArrowHeadLengthSlider"
                )
            }
            if kind == .line {
                labeledSlider(
                    "Curve",
                    value: geometryBinding(\.curvature, resolved: geometry.curvature),
                    range: ThumbnailShapeGeometryRecipe.curvatureRange,
                    identifier: "shapeCurvatureSlider"
                )
            }
            if kind == .burst {
                Stepper(
                    "Points: \(geometry.burstPoints)",
                    value: burstPointsBinding,
                    in: ThumbnailShapeGeometryRecipe.burstPointsRange
                )
                .frame(minHeight: 44)
                .accessibilityIdentifier("shapeBurstPointsStepper")
            }
            if kind == .callout {
                tailMenu
                labeledSlider(
                    "Tail length",
                    value: geometryBinding(\.tailLength, resolved: geometry.tailLength),
                    range: ThumbnailShapeGeometryRecipe.tailLengthRange,
                    identifier: "shapeCalloutTailLengthSlider"
                )
            }
            if kind == .pill || kind == .callout {
                labeledSlider(
                    "Corners",
                    value: geometryBinding(\.cornerRadius, resolved: geometry.cornerRadius),
                    range: ThumbnailShapeGeometryRecipe.cornerRadiusRange,
                    identifier: "shapeCornerSlider"
                )
            }
            if kind.supportsLabel {
                labelControls
            }
        }
    }

    private var tailMenu: some View {
        Menu {
            ForEach(ThumbnailCalloutTailDirection.allCases) { direction in
                Button {
                    discrete { $0.editGeometry { $0.tailDirection = direction } }
                } label: {
                    if direction == geometry.tailDirection {
                        Label(direction.displayName, systemImage: "checkmark")
                    } else {
                        Text(direction.displayName)
                    }
                }
                .accessibilityIdentifier("shapeCalloutTail-\(direction.rawValue)")
            }
        } label: {
            HStack {
                Text("Tail")
                Spacer()
                Text(geometry.tailDirection.displayName)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
            .frame(minHeight: 44)
        }
        .accessibilityIdentifier("shapeCalloutTailMenu")
        .accessibilityValue(geometry.tailDirection.displayName)
    }

    @ViewBuilder
    private var labelControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Label (optional)", text: labelTextBinding)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 44)
                .accessibilityIdentifier("shapeLabelField")
                .accessibilityLabel("Shape label text")
                .onSubmit(commit)

            if content.label != nil {
                HStack(spacing: 16) {
                    ColorPicker("Label color", selection: labelColorBinding)
                        .accessibilityIdentifier("shapeLabelColorPicker")
                        .frame(minHeight: 44)

                    Menu {
                        ForEach(CustomFont.allCases) { font in
                            Button(font.displayName) {
                                discrete { content in
                                    content.label?.font = font
                                }
                            }
                        }
                    } label: {
                        Label(content.label?.font.displayName ?? "Font", systemImage: "textformat")
                            .lineLimit(1)
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("shapeLabelFontMenu")
                }

                Toggle("Bold label", isOn: labelBoldBinding)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("shapeLabelBoldToggle")

                labeledSlider(
                    "Label size",
                    value: labelSizeBinding,
                    range: ThumbnailShapeLabel.sizeFractionRange,
                    identifier: "shapeLabelSizeSlider"
                )
            }
        }
    }

    // MARK: Building blocks

    private func headPicker(
        _ title: String,
        value: Binding<ThumbnailArrowheadStyle>,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title) head")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("\(title) head", selection: value) {
                ForEach(ThumbnailArrowheadStyle.allCases) { style in
                    Image(systemName: style.systemImage)
                        .accessibilityLabel(style.displayName)
                        .tag(style)
                }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            .accessibilityIdentifier(identifier)
        }
    }

    private func labeledSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: value, in: range) { isEditing in
                if !isEditing { commit() }
            }
            .frame(minHeight: 44)
            .accessibilityLabel(title)
            .accessibilityIdentifier(identifier)
        }
    }

    /// One undo step: settle pending edits, mutate, settle again.
    private func discrete(_ mutate: (inout ThumbnailShapeLayerContent) -> Void) {
        var next = content
        mutate(&next)
        guard next != content else { return }
        commit()
        content = next
        commit()
    }

    // MARK: Bindings

    private func colorBinding(_ keyPath: WritableKeyPath<ThumbnailShapeLayerContent, ThumbnailDocumentColor>) -> Binding<Color> {
        Binding(
            get: { content[keyPath: keyPath].color },
            set: { content[keyPath: keyPath] = ThumbnailDocumentColor(color: $0) }
        )
    }

    private var strokeColorBinding: Binding<Color> {
        Binding(
            get: { (content.strokeColor ?? ThumbnailCalloutPreset.white).color },
            set: { content.strokeColor = ThumbnailDocumentColor(color: $0) }
        )
    }

    private var strokeEnabledBinding: Binding<Bool> {
        Binding(
            get: { content.strokeColor != nil },
            set: { isOn in
                discrete { content in
                    content.strokeColor = isOn ? (content.strokeColor ?? ThumbnailCalloutPreset.white) : nil
                    if isOn, content.strokeWidth <= 0 { content.strokeWidth = 0.006 }
                }
            }
        )
    }

    private func headBinding(start: Bool) -> Binding<ThumbnailArrowheadStyle> {
        Binding(
            get: { start ? geometry.startHead : geometry.endHead },
            set: { style in
                discrete { content in
                    content.editGeometry { recipe in
                        if start { recipe.startHead = style } else { recipe.endHead = style }
                    }
                }
            }
        )
    }

    private func geometryBinding(
        _ keyPath: WritableKeyPath<ThumbnailShapeGeometryRecipe, Double?>,
        resolved: Double
    ) -> Binding<Double> {
        Binding(
            get: { resolved },
            set: { value in content.editGeometry { $0[keyPath: keyPath] = value } }
        )
    }

    private var burstPointsBinding: Binding<Int> {
        Binding(
            get: { geometry.burstPoints },
            set: { value in discrete { $0.editGeometry { $0.burstPoints = value } } }
        )
    }

    private var labelTextBinding: Binding<String> {
        Binding(
            get: { content.label?.text ?? "" },
            set: { text in
                let limited = String(text.prefix(ThumbnailShapeLabel.characterLimit))
                if limited.isEmpty {
                    content.label = nil
                } else if var label = content.label {
                    label.text = limited
                    content.label = label
                } else {
                    content.label = ThumbnailShapeLabel(
                        text: limited,
                        color: ThumbnailCalloutPreset.contrastingLabelColor(on: content.fillColor)
                    )
                }
            }
        )
    }

    private var labelColorBinding: Binding<Color> {
        Binding(
            get: { (content.label?.color ?? ThumbnailCalloutPreset.white).color },
            set: { color in content.label?.color = ThumbnailDocumentColor(color: color) }
        )
    }

    private var labelBoldBinding: Binding<Bool> {
        Binding(
            get: { content.label?.isBold ?? true },
            set: { isBold in discrete { $0.label?.isBold = isBold } }
        )
    }

    private var labelSizeBinding: Binding<Double> {
        Binding(
            get: { content.label?.effectiveSizeFraction ?? 0.5 },
            set: { value in content.label?.sizeFraction = value }
        )
    }
}

extension ShapeLayerControlView {
    /// Binding to the selected shape layer's content, or nil when the
    /// selection is not a shape. Mirrors the main views' text-layer binding.
    @MainActor
    static func binding(
        layers: Binding<[ThumbnailDocumentLayer]>,
        selection: ThumbnailLayerSelection?
    ) -> Binding<ThumbnailShapeLayerContent>? {
        guard case .content(let layerID)? = selection,
              let layer = layers.wrappedValue.record(id: layerID),
              case .shape(let currentContent) = layer.content else {
            return nil
        }
        return Binding(
            get: {
                guard let layer = layers.wrappedValue.record(id: layerID),
                      case .shape(let content) = layer.content else {
                    return currentContent
                }
                return content
            },
            set: { nextContent in
                layers.wrappedValue.updateShapeContent(id: layerID) { $0 = nextContent }
            }
        )
    }
}
