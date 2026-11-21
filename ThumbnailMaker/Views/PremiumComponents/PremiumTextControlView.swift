import SwiftUI

struct PremiumTextControlView: View {
    @Binding var selectedLayer: ThumbnailLayerSelection
    @Binding var textTransform: ThumbnailOverlayTransform
    @Binding var profileTransform: ThumbnailOverlayTransform
    @Binding var textColor: Color
    @Binding var selectedFont: CustomFont
    @Binding var usesFallbackFont: Bool
    @Binding var previewText: String
    /// FEATURE-04
    @Binding var textStyle: ThumbnailTextStyle?
    /// GAPS: main-title auto-fit (hidden when nil).
    var autoFit: Binding<Bool>? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            if selectedLayer == .textOverlay {
                fontAndColorRow

                Divider()
                    .padding(.horizontal)

                if let autoFit { // GAPS
                    OverlayAutoFitToggleRow(isOn: autoFit)
                        .padding()
                    Divider()
                        .padding(.horizontal)
                }

                // FEATURE-04: text style presets + advanced controls.
                TextStyleControlView(style: $textStyle, role: .overlay)
                    .padding()

                Divider()
                    .padding(.horizontal)
            }

            VStack(alignment: .leading, spacing: 14) {
                if selectedLayer == .textOverlay {
                    OverlayTransformStatusView(
                        title: "Text Canvas",
                        transform: $textTransform
                    )
                } else if selectedLayer == .profileOverlay {
                    OverlayTransformStatusView(
                        title: "Profile Canvas",
                        transform: $profileTransform,
                        resetTransform: .profileDefault
                    )
                }
            }
            .padding()
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }

    private var fontAndColorRow: some View {
        HStack(spacing: 0) {
            FontPickerView(
                selectedFont: $selectedFont,
                usesFallbackFont: $usesFallbackFont,
                previewText: $previewText,
                isPremium: true
            )
            .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 40)
                .padding(.horizontal)

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
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
