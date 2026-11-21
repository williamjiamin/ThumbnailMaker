//
//  TextStyleControlView.swift
//  ThumbnailMaker
//
//  FEATURE-04: preset chips + advanced controls for a ThumbnailTextStyle.
//  Writing through `style` flows into the editor configuration, whose didSet
//  already autosaves and coalesces edits into one undo step.
//

import SwiftUI

struct TextStyleControlView: View {
    @Binding var style: ThumbnailTextStyle?
    let role: ThumbnailTextRole
    /// EDITOR (1.1.0 parity): Effects / Shadow tabs over the same controls
    /// that used to sit behind one "Advanced" disclosure. nil = collapsed.
    @State private var activeTab: TextStyleInspectorTab?

    private var presets: [ThumbnailTextStylePreset] {
        ThumbnailTextStylePreset.all(for: role)
    }

    private var selectedPresetID: String? {
        guard let style else { return ThumbnailTextStylePreset.defaultID }
        // A preset is only "selected" while the style still equals it exactly.
        return presets.first { $0.style == style }?.id
    }

    /// First-touch materialisation: editing any control on a legacy (nil) style
    /// starts from the legacy approximation, so the export does not jump.
    private var editable: Binding<ThumbnailTextStyle> {
        Binding(
            get: { style ?? .legacyApproximation(for: role) },
            set: { newValue in
                var next = newValue.normalized()
                next.presetID = nil
                style = next
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Text Style")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Reset to default") {
                    style = nil
                }
                .font(.caption)
                .disabled(style == nil)
                .accessibilityIdentifier("textStyleResetButton")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets) { preset in
                        presetChip(preset)
                    }
                }
                .padding(.vertical, 2)
            }
            .accessibilityIdentifier("textStylePresetRow")

            tabBar

            switch activeTab {
            case .effects:
                effectsControls
                    .padding(.top, 4)
            case .shadow:
                shadowControls
                    .padding(.top, 4)
            case nil:
                EmptyView()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("textStyleControls")
    }

    private func presetChip(_ preset: ThumbnailTextStylePreset) -> some View {
        let isSelected = selectedPresetID == preset.id
        return Button {
            style = preset.style
        } label: {
            Text(preset.displayName)
                .font(.footnote.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor.opacity(0.2) : Color(uiColor: .tertiarySystemFill))
                )
                .overlay(
                    Capsule().stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("textStylePreset-\(preset.id)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(TextStyleInspectorTab.allCases) { tab in
                let isSelected = activeTab == tab
                Button {
                    withAnimation(.snappy) {
                        activeTab = isSelected ? nil : tab
                    }
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(uiColor: .tertiarySystemFill))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(tab.accessibilityIdentifier)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint(isSelected ? "Hides these controls." : "Shows \(tab.title.lowercased()) controls.")
            }
        }
    }

    @ViewBuilder
    private var effectsControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("Outline") {
                slider("Width", id: "textStyleOutlineWidth", value: editable.outlineWidth,
                       range: ThumbnailTextStyle.Limits.outlineWidth)
                colorRow("Outline color", id: "textStyleOutlineColor", color: editable.outlineColor)
            }

            section("Background panel") {
                Toggle("Panel", isOn: panelEnabledBinding)
                    .accessibilityIdentifier("textStylePanelToggle")
                if editable.wrappedValue.panelColor != nil {
                    colorRow("Panel color", id: "textStylePanelColor", color: panelColorBinding)
                    slider("Corner radius", id: "textStylePanelCornerRadius", value: editable.panelCornerRadius,
                           range: ThumbnailTextStyle.Limits.panelCornerRadius)
                }
                slider("Horizontal padding", id: "textStyleHorizontalPadding", value: editable.horizontalPadding,
                       range: ThumbnailTextStyle.Limits.padding)
                slider("Vertical padding", id: "textStyleVerticalPadding", value: editable.verticalPadding,
                       range: ThumbnailTextStyle.Limits.padding)
            }

            section("Spacing") {
                slider("Line spacing", id: "textStyleLineSpacing", value: editable.lineSpacing,
                       range: ThumbnailTextStyle.Limits.lineSpacing)
                slider("Letter spacing", id: "textStyleLetterSpacing", value: editable.letterSpacing,
                       range: ThumbnailTextStyle.Limits.letterSpacing)
            }

            section("Layout") {
                Picker("Alignment", selection: editable.alignment) {
                    ForEach(ThumbnailTextAlignment.allCases, id: \.self) { alignment in
                        Text(alignment.displayName).tag(alignment)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("textStyleAlignmentPicker")
                slider("Max width", id: "textStyleMaxWidth", value: editable.maxWidthFraction,
                       range: ThumbnailTextStyle.Limits.maxWidthFraction)
            }
        }
    }

    private var shadowControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Shadow", isOn: editable.isShadowEnabled)
                .accessibilityIdentifier("textStyleShadowToggle")
            if editable.wrappedValue.isShadowEnabled {
                slider("Blur", id: "textStyleShadowRadius", value: editable.shadowRadius,
                       range: ThumbnailTextStyle.Limits.shadowRadius)
                slider("Offset X", id: "textStyleShadowOffsetX", value: editable.shadowOffsetX,
                       range: ThumbnailTextStyle.Limits.shadowOffset)
                slider("Offset Y", id: "textStyleShadowOffsetY", value: editable.shadowOffsetY,
                       range: ThumbnailTextStyle.Limits.shadowOffset)
                colorRow("Shadow color", id: "textStyleShadowColor", color: editable.shadowColor)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func slider(
        _ title: String,
        id: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        let percent = Int((value.wrappedValue * 100).rounded())
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.footnote)
                Spacer()
                Text("\(percent)%")
                    .font(.footnote.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Slider(value: value, in: range)
                .accessibilityLabel(title)
                .accessibilityValue("\(percent) percent")
                .accessibilityIdentifier(id)
        }
    }

    private func colorRow(_ title: String, id: String, color: Binding<ThumbnailDocumentColor>) -> some View {
        ColorPicker(
            title,
            selection: Binding(
                get: { color.wrappedValue.color },
                set: { color.wrappedValue = ThumbnailDocumentColor(color: $0) }
            ),
            supportsOpacity: true
        )
        .font(.footnote)
        .accessibilityIdentifier(id)
    }

    private var panelEnabledBinding: Binding<Bool> {
        Binding(
            get: { editable.wrappedValue.panelColor != nil },
            set: { isOn in
                var next = editable.wrappedValue
                if isOn {
                    next.panelColor = next.panelColor
                        ?? ThumbnailDocumentColor(red: 0, green: 0, blue: 0, alpha: 0.55)
                    if next.panelCornerRadius == 0 { next.panelCornerRadius = 0.35 }
                } else {
                    next.panelColor = nil
                }
                editable.wrappedValue = next
            }
        )
    }

    private var panelColorBinding: Binding<ThumbnailDocumentColor> {
        Binding(
            get: { editable.wrappedValue.panelColor ?? ThumbnailDocumentColor(red: 0, green: 0, blue: 0, alpha: 0.55) },
            set: { editable.wrappedValue.panelColor = $0 }
        )
    }
}

/// EDITOR (1.1.0 parity): the text inspector's tab buttons.
enum TextStyleInspectorTab: String, CaseIterable, Identifiable {
    case effects
    case shadow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .effects: "Effects"
        case .shadow: "Shadow"
        }
    }

    var systemImage: String {
        switch self {
        case .effects: "sparkles"
        case .shadow: "shadow"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .effects: "textStyleEffectsTab"
        case .shadow: "textStyleShadowTab"
        }
    }
}
