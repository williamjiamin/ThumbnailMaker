//
//  BrandKitEditorView.swift
//  ThumbnailMaker
//

import SwiftUI

struct BrandKitEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var workingKit: BrandKit

    let allowsPremiumFonts: Bool
    let saveBrandKit: (BrandKit?) -> Void
    let applyBrandKit: (BrandKit) -> Void
    /// FEATURE-08: deletes only this kit. When nil, Delete falls back to
    /// `saveBrandKit(nil)` (the pre-library behaviour).
    let deleteBrandKit: ((BrandKit) -> Void)?

    init(
        brandKit: BrandKit?,
        allowsPremiumFonts: Bool,
        saveBrandKit: @escaping (BrandKit?) -> Void,
        applyBrandKit: @escaping (BrandKit) -> Void,
        deleteBrandKit: ((BrandKit) -> Void)? = nil
    ) {
        _workingKit = State(initialValue: brandKit ?? BrandKit.defaultCreatorKit())
        self.allowsPremiumFonts = allowsPremiumFonts
        self.saveBrandKit = saveBrandKit
        self.applyBrandKit = applyBrandKit
        self.deleteBrandKit = deleteBrandKit
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Brand name", text: $workingKit.name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("brandKitNameField")

                    Picker("Primary font", selection: primaryFontBinding) {
                        ForEach(availableFonts) { font in
                            Text(font.displayName)
                                .tag(font)
                        }
                    }
                    .accessibilityIdentifier("brandKitPrimaryFontPicker")
                }

                Section("Palette") {
                    ColorPicker("Text color", selection: paletteColorBinding(index: 0, name: "Text"))
                        .accessibilityIdentifier("brandKitTextColorPicker")

                    ColorPicker("Background color", selection: paletteColorBinding(index: 1, name: "Background"))
                        .accessibilityIdentifier("brandKitBackgroundColorPicker")

                    // FEATURE-08: accent drives shape fills when applying the kit.
                    ColorPicker("Accent color (shapes)", selection: paletteColorBinding(index: 2, name: "Accent"))
                        .accessibilityIdentifier("brandKitAccentColorPicker")
                }

                Section {
                    HStack(spacing: 16) {
                        Circle()
                            .fill(paletteColor(at: 0, fallback: .white))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(previewTitle)
                                .font(.custom(workingKit.primaryFont.postScriptName, size: 18))
                                .foregroundStyle(paletteColor(at: 0, fallback: .white))
                                .lineLimit(1)
                            Text("Brand kit preview")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(paletteColor(at: 1, fallback: Color(uiColor: .secondarySystemBackground)))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Brand kit preview")
                }

                Section {
                    Button {
                        let kit = normalizedKit()
                        saveBrandKit(kit)
                        applyBrandKit(kit)
                        dismiss()
                    } label: {
                        Label("Save and Apply", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("brandKitSaveApplyButton")

                    Button(role: .destructive) {
                        if let deleteBrandKit {
                            deleteBrandKit(workingKit)
                        } else {
                            saveBrandKit(nil)
                        }
                        dismiss()
                    } label: {
                        Label(deleteBrandKit == nil ? "Delete Brand Kit" : "Delete This Kit", systemImage: "trash")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("brandKitDeleteButton")
                }
            }
            .navigationTitle("Brand Kit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SheetToolbarButton(.cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    SheetToolbarButton(.save) {
                        saveBrandKit(normalizedKit())
                        dismiss()
                    }
                    .accessibilityIdentifier("brandKitSaveButton")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var availableFonts: [CustomFont] {
        allowsPremiumFonts ? CustomFont.allCases : CustomFont.basicFonts
    }

    private var primaryFontBinding: Binding<CustomFont> {
        Binding(
            get: {
                let font = workingKit.primaryFont
                if allowsPremiumFonts || !font.isPremium {
                    return font
                }
                return .goNoto
            },
            set: { font in
                workingKit.primaryFontRawValue = font.rawValue
            }
        )
    }

    private var previewTitle: String {
        let trimmedName = workingKit.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Creator Brand" : trimmedName
    }

    private func paletteColorBinding(index: Int, name: String) -> Binding<Color> {
        Binding(
            get: {
                paletteColor(at: index, fallback: fallbackColor(at: index))
            },
            set: { color in
                updatePaletteColor(at: index, name: name, color: color)
            }
        )
    }

    private func paletteColor(at index: Int, fallback: Color) -> Color {
        guard workingKit.palette.indices.contains(index) else {
            return fallback
        }

        return workingKit.palette[index].color.color
    }

    private func updatePaletteColor(at index: Int, name: String, color: Color) {
        while workingKit.palette.count <= index {
            let nextIndex = workingKit.palette.count
            workingKit.palette.append(
                BrandColor(
                    id: "\(workingKit.id)-color-\(nextIndex)",
                    name: defaultPaletteName(at: nextIndex),
                    color: ThumbnailDocumentColor(color: fallbackColor(at: nextIndex))
                )
            )
        }

        let existing = workingKit.palette[index]
        workingKit.palette[index] = BrandColor(
            id: existing.id,
            name: name,
            color: ThumbnailDocumentColor(color: color)
        )
    }

    private func normalizedKit() -> BrandKit {
        var kit = workingKit
        let trimmedName = kit.name.trimmingCharacters(in: .whitespacesAndNewlines)
        kit.name = trimmedName.isEmpty ? "Creator Brand" : trimmedName

        kit.palette = [
            normalizedBrandColor(at: 0, name: "Text", fallback: .white),
            normalizedBrandColor(
                at: 1,
                name: "Background",
                fallback: Color(uiColor: .secondarySystemBackground)
            )
        ] + workingKit.palette.dropFirst(2) // FEATURE-08: keep accent and extras
        kit.updatedAt = Date()
        return kit
    }

    private func normalizedBrandColor(at index: Int, name: String, fallback: Color) -> BrandColor {
        if workingKit.palette.indices.contains(index) {
            let existing = workingKit.palette[index]
            return BrandColor(
                id: existing.id,
                name: name,
                color: existing.color
            )
        }

        return BrandColor(
            id: "\(workingKit.id)-color-\(index)",
            name: name,
            color: ThumbnailDocumentColor(color: fallback)
        )
    }

    private func fallbackColor(at index: Int) -> Color {
        switch index {
        case 0: .white
        case 1: Color(uiColor: .secondarySystemBackground)
        default: paletteColor(at: 0, fallback: .white) // accent defaults to text
        }
    }

    private func defaultPaletteName(at index: Int) -> String {
        switch index {
        case 0:
            return "Text"
        case 1:
            return "Background"
        case 2:
            return "Accent"
        default:
            return "Color \(index + 1)"
        }
    }
}

#Preview {
    BrandKitEditorView(
        brandKit: .defaultCreatorKit(id: "preview-kit"),
        allowsPremiumFonts: true,
        saveBrandKit: { _ in },
        applyBrandKit: { _ in }
    )
}
