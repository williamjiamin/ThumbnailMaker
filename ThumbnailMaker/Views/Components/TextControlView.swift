import SwiftUI

struct TextControlView: View {
    @Binding var textColor: Color
    @Binding var textTransform: ThumbnailOverlayTransform
    @Binding var selectedFont: CustomFont
    @Binding var usesFallbackFont: Bool
    @Binding var previewText: String
    /// FEATURE-04
    @Binding var textStyle: ThumbnailTextStyle?
    let isPremium: Bool
    /// GAPS: main-title auto-fit (hidden when nil).
    var autoFit: Binding<Bool>? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Font and Color Section
            HStack(spacing: 0) {
                // Left side - Font Picker
                FontPickerView(
                    selectedFont: $selectedFont,
                    usesFallbackFont: $usesFallbackFont,
                    previewText: $previewText,
                    isPremium: isPremium
                )
                .frame(maxWidth: .infinity)
                
                Divider()
                    .frame(height: 40)
                    .padding(.horizontal)
                
                // Right side - Text Color
                VStack(alignment: .center, spacing: 4) {
                    Text("Color")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ColorPicker("", selection: $textColor)
                        .labelsHidden()
                }
                .frame(width: 100, alignment: .center)
                .padding(.trailing)
            }
            .padding(.vertical, 8)
            
            Divider()

            if let autoFit { // GAPS
                OverlayAutoFitToggleRow(isOn: autoFit)
                    .padding()
                Divider()
            }

            // FEATURE-04: text style presets + advanced controls.
            TextStyleControlView(style: $textStyle, role: .overlay)
                .padding()

            Divider()
            
            VStack(alignment: .leading, spacing: 14) {
                OverlayTransformStatusView(
                    title: "Text Canvas",
                    transform: $textTransform,
                    size: nil
                )
            }
            .padding()
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct TextLayerContentControlView: View {
    @Binding var content: ThumbnailTextLayerContent
    let characterLimit: Int
    let isPremium: Bool
    /// Canvas shape the overflow warning is measured on.
    var canvasAspectRatio: AspectRatio = .ratio16_9
    @State private var usesFallbackFont = false
    @FocusState private var isEditingText: Bool

    private var isOverLimit: Bool {
        content.value.count > characterLimit
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Layer text", text: $content.value)
                    .textFieldStyle(.roundedBorder)
                    .focused($isEditingText)
                    .accessibilityIdentifier("textLayerContentField")
                    .accessibilityLabel("Text layer words")
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") {
                                isEditingText = false
                            }
                            .accessibilityIdentifier("textLayerContentKeyboardDoneButton")
                        }
                    }

                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .imageScale(.small)
                    Text("\(content.value.count)/\(characterLimit)")
                        .monospacedDigit()
                }
                .font(.footnote)
                .foregroundStyle(isOverLimit ? Color.red : Color.accessibleSecondaryText)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Text layer character count")
                .accessibilityValue("\(content.value.count) of \(characterLimit)")
            }
            .padding()

            Divider()

            HStack(spacing: 0) {
                FontPickerView(
                    selectedFont: selectedFontBinding,
                    usesFallbackFont: $usesFallbackFont,
                    previewText: $content.value,
                    isPremium: isPremium
                )
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 40)
                    .padding(.horizontal)

                VStack(alignment: .center, spacing: 4) {
                    Text("Color")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ColorPicker("", selection: colorBinding)
                        .labelsHidden()
                        .accessibilityIdentifier("textLayerColorPicker")
                        .accessibilityLabel("Text layer color")
                }
                .frame(width: 100, alignment: .center)
                .padding(.trailing)
            }
            .padding(.vertical, 8)

            Divider()

            // DONOR: meme-maker auto-fit + "too long for its box" warning.
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $content.isAutoFitEnabled) {
                    Label("Auto-fit text to box", systemImage: "arrow.down.right.and.arrow.up.left")
                }
                .accessibilityIdentifier("textLayerAutoFitToggle")
                .accessibilityHint("Shrinks the text until it fits its box. The size becomes a maximum.")

                if content.overflowsBox(canvasSize: ThumbnailReadinessCanvas.size(for: canvasAspectRatio)) {
                    Label("Too long for its box — it will be cut off.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("textLayerOverflowWarning")
                }
            }
            .padding()

            Divider()

            // FEATURE-04: per-layer text style.
            TextStyleControlView(style: $content.style, role: .contentLayer)
                .padding()

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                OverlayTransformStatusView(
                    title: "Text Layer Canvas",
                    transform: $content.transform,
                    size: CGFloat(content.size)
                )
            }
            .padding()
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("textLayerContentControls")
    }

    private var selectedFontBinding: Binding<CustomFont> {
        Binding(
            get: {
                content.selectedFont
            },
            set: { nextFont in
                content.selectedFont = nextFont
            }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                content.color.color
            },
            set: { nextColor in
                content.color = ThumbnailDocumentColor(color: nextColor)
            }
        )
    }
}

/// GAPS: auto-fit for the MAIN title, the same behaviour text layers offer.
struct OverlayAutoFitToggleRow: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label("Auto-fit title", systemImage: "arrow.down.right.and.arrow.up.left")
        }
        .accessibilityIdentifier("overlayAutoFitToggle")
        .accessibilityHint("Shrinks the title until it fits on the canvas. The size becomes a maximum.")
    }
}
