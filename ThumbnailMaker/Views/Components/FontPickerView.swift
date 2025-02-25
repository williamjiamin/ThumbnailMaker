import SwiftUI

struct FontPickerView: View {
    @Binding var selectedFont: CustomFont
    @Binding var usesFallbackFont: Bool
    @Binding var previewText: String
    let isPremium: Bool
    @State private var showingFontPicker = false
    
    var body: some View {
        Button(action: {
            // If user is not premium and has a premium font selected,
            // reset to a basic font before showing picker
            if !isPremium && selectedFont.isPremium {
                selectedFont = .goNoto // or any other basic font
            }
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
                        Text("Using Go Noto for some text")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    .help("Some characters in your text are using Go Noto font because the selected font doesn't support them")
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
    @State private var showingPremiumHint = false
    @State private var showingPremiumSheet = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(CustomFont.basicFonts, id: \.self) { font in
                        FontRow(
                            font: font,
                            previewText: previewText,
                            selectedFont: $selectedFont,
                            isPremium: isPremium
                        )
                    }
                } header: {
                    Text("Basic Fonts")
                }
                
                Section {
                    ForEach(CustomFont.premiumFonts, id: \.self) { font in
                        FontRow(
                            font: font,
                            previewText: previewText,
                            selectedFont: $selectedFont,
                            isPremium: isPremium
                        )
                    }
                } header: {
                    Text("Premium Fonts")
                }
                
                if !isPremium {
                    Section {
                        Button(action: { showingPremiumSheet = true }) {
                            VStack(alignment: .leading, spacing: 12) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 16) {
                                        ForEach(Array(CustomFont.premiumFonts.prefix(3)), id: \.self) { font in
                                            VStack(alignment: .leading) {
                                                Text(previewText.isEmpty ? "Sample" : previewText)
                                                    .font(.custom(font.rawValue, size: 17))
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                                Text(font.displayName)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            .frame(width: 120)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                }
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Premium Features")
                                        .font(.headline)
                                    
                                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                                        GridRow {
                                            premiumFeatureItem(icon: "textformat", text: "20+ Creative Fonts")
                                            premiumFeatureItem(icon: "play.rectangle.fill", text: "YouTube Thumbnail Import")
                                        }
                                        GridRow {
                                            premiumFeatureItem(icon: "rectangle.stack", text: "Batch Generation")
                                            premiumFeatureItem(icon: "photo.circle", text: "Profile Overlay")
                                        }
                                    }
                                }
                                
                                Button(action: { showingPremiumSheet = true }) {
                                    Text("Unlock All Features")
                                        .fontWeight(.medium)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                                .padding(.top, 8)
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    } header: {
                        Text("Premium Features")
                    }
                }
            }
            .navigationTitle("Select Font")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showingPremiumSheet) {
            PremiumMakerView()
        }
    }
    
    private func premiumFeatureItem(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .font(.system(size: 14))
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

struct FontRow: View {
    let font: CustomFont
    let previewText: String
    @Binding var selectedFont: CustomFont
    let isPremium: Bool
    
    var body: some View {
        Button(action: {
            if !font.isPremium || isPremium {
                selectedFont = font
            }
        }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(previewText.isEmpty ? "Sample Text" : previewText)
                        .font(.custom(font.rawValue, size: 17))
                        .lineLimit(1)
                        .foregroundColor(font.isPremium && !isPremium ? .secondary : .primary)
                    
                    Spacer()
                    
                    if selectedFont == font {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
                
                HStack {
                    Text(font.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if font.isPremium && !isPremium {
                        Text("Premium")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .disabled(font.isPremium && !isPremium)
    }
}

// Add a new view for premium font teasers
struct PremiumFontTeaser: View {
    let font: CustomFont
    let previewText: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(previewText.isEmpty ? "Sample Text" : previewText)
                    .font(.custom(font.rawValue, size: 17))
                    .lineLimit(1)
                    .foregroundColor(.secondary)
                
                Text(font.displayName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "star.circle.fill")
                .foregroundStyle(.linearGradient(colors: [.blue, .purple], 
                                               startPoint: .leading,
                                               endPoint: .trailing))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Show premium upgrade sheet
            NotificationCenter.default.post(
                name: Notification.Name("ShowPremiumUpgrade"),
                object: nil
            )
        }
    }
} 