import SwiftUI

struct FontPickerView: View {
    @Binding var selectedFont: CustomFont
    @Binding var usesFallbackFont: Bool
    @Binding var previewText: String
    let isPremium: Bool
    @State private var showingFontPicker = false
    
    var body: some View {
        Button(action: {
            showingFontPicker = true
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Font")
                        .font(.headline)
                    Text(selectedFont.displayName)
                        .font(.custom(selectedFont.rawValue, size: 14))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if usesFallbackFont {
                    VStack(alignment: .leading, spacing: 2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 12))
                        Text("Some text using default font")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    .help("Some characters in your text cannot be displayed with this font and will use Go Noto instead")
                }
                
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(8)
        }
        .sheet(isPresented: $showingFontPicker) {
            FontPickerSheet(
                selectedFont: $selectedFont,
                previewText: previewText,
                isPremium: isPremium
            )
        }
    }
}

struct FontPickerSheet: View {
    @Binding var selectedFont: CustomFont
    let previewText: String
    let isPremium: Bool
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Default") {
                    FontRow(
                        font: .goNoto,
                        previewText: previewText,
                        selectedFont: $selectedFont
                    )
                }
                
                if isPremium {
                    Section("Style Fonts") {
                        ForEach(CustomFont.styleOnlyFonts, id: \.self) { font in
                            FontRow(
                                font: font,
                                previewText: previewText,
                                selectedFont: $selectedFont
                            )
                        }
                    }
                }
            }
            .navigationTitle("Select Font")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct FontRow: View {
    let font: CustomFont
    let previewText: String
    @Binding var selectedFont: CustomFont
    
    var body: some View {
        Button(action: {
            selectedFont = font
        }) {
            HStack {
                Text(previewText.isEmpty ? "Sample Text" : previewText)
                    .font(.custom(font.rawValue, size: 17))
                    .lineLimit(1)
                Spacer()
                if selectedFont == font {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
        .foregroundColor(.primary)
    }
} 