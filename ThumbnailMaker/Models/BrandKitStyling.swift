//
//  BrandKitStyling.swift
//  ThumbnailMaker
//
//  FEATURE-08: document-level, scoped brand kit application.
//
//  Palette role convention (positional, same as the original editor):
//    palette[0] = text, palette[1] = background, palette[2] = accent
//    (accent falls back to the text color).
//
//  Project-wide rules (locked content/text layers and image content are
//  never touched; the background is always recolored, as before):
//    1. canvas background   <- background color
//    2. overlay text        <- text color + primary font
//    3. `.text` layers      <- text color + (secondary ?? primary) font
//    4. `.shape` layers     <- accent fill; stroke <- text color only when the
//                              shape already has a stroke
//    5. branding.appliedBrandKitID / Name are stamped
//  Selection scope applies the single matching rule and does NOT stamp the
//  project-wide badge (the project is not wholly on-brand).
//

import Foundation

extension BrandKit {
    var textBrandColor: ThumbnailDocumentColor? { palette.first?.color }
    var backgroundBrandColor: ThumbnailDocumentColor? { palette.dropFirst().first?.color }
    var accentBrandColor: ThumbnailDocumentColor? { palette.dropFirst(2).first?.color ?? textBrandColor }

    /// The recipe "apply this kit" uses for one kind of layer. `forOverlay`
    /// picks the primary font; added text layers use the secondary font.
    func defaultStyle(for target: ThumbnailLayerStyleTarget, forOverlay: Bool = false) -> ThumbnailLayerStyle {
        switch target {
        case .text:
            let font = forOverlay ? primaryFont : (secondaryFont ?? primaryFont)
            return ThumbnailLayerStyle(
                id: "\(id)-text",
                name: "\(name) Text",
                target: .text,
                textColor: textBrandColor,
                fontRawValue: font.rawValue,
                updatedAt: updatedAt
            )
        case .shape:
            return ThumbnailLayerStyle(
                id: "\(id)-shape",
                name: "\(name) Shape",
                target: .shape,
                fillColor: accentBrandColor,
                strokeColor: textBrandColor,
                updatedAt: updatedAt
            )
        }
    }

    func applied(to document: ThumbnailDocument, scope: ThumbnailStyleApplicationScope) -> ThumbnailDocument {
        var document = document
        switch scope {
        case .projectWide:
            applyBackground(to: &document)
            applyOverlayText(to: &document)
            for layer in document.layers where layer.content != nil {
                applyContentLayer(id: layer.id, to: &document)
            }
            document.branding.appliedBrandKitID = id
            document.branding.appliedBrandKitName = name
        case .layer(let layerID):
            switch layerID {
            case ThumbnailDocumentLayer.backgroundID:
                applyBackground(to: &document)
            case ThumbnailDocumentLayer.textID:
                applyOverlayText(to: &document)
            default:
                applyContentLayer(id: layerID, to: &document)
            }
        }
        return document
    }

    private func isLocked(_ layerID: String, in document: ThumbnailDocument) -> Bool {
        document.layers.first(where: { $0.id == layerID })?.isLocked == true
    }

    private func applyBackground(to document: inout ThumbnailDocument) {
        // The background record is locked by default (it cannot be dragged),
        // so its lock does not block recoloring, exactly as before FEATURE-08.
        guard let backgroundBrandColor else { return }
        document.canvas.backgroundColor = backgroundBrandColor
        document.canvas.backgroundFill = nil // SHELL: a brand background is solid
    }

    private func applyOverlayText(to document: inout ThumbnailDocument) {
        let layerID = ThumbnailDocumentLayer.textID
        guard !isLocked(layerID, in: document) else { return }
        let styled = defaultStyle(for: .text, forOverlay: true).applied(to: document.text)
        guard styled != document.text else { return }
        document.text = styled
        clearStyleProvenance(for: layerID, in: &document)
    }

    private func applyContentLayer(id layerID: String, to document: inout ThumbnailDocument) {
        guard let index = document.layers.firstIndex(where: { $0.id == layerID }),
              !document.layers[index].isLocked else { return }
        let layer = document.layers[index]
        let styled: ThumbnailDocumentLayer
        switch layer.content {
        case .text:
            styled = defaultStyle(for: .text).applied(to: layer)
        case .shape:
            styled = defaultStyle(for: .shape).applied(to: layer)
        case .image, nil:
            return
        }
        guard styled != layer else { return }
        document.layers[index] = styled
        clearStyleProvenance(for: layerID, in: &document)
    }

    /// A kit restyle supersedes a named style previously applied to the layer.
    private func clearStyleProvenance(for layerID: String, in document: inout ThumbnailDocument) {
        document.branding.styleIDsByLayerID[layerID] = nil
        document.branding.styleNamesByLayerID[layerID] = nil
    }
}

extension ThumbnailDocument {
    /// Prefers the live kit's current name, falls back to the snapshot.
    func appliedBrandKitDisplayName(in library: BrandKitLibrary) -> String? {
        guard let kitID = branding.appliedBrandKitID else { return nil }
        return library.kit(id: kitID)?.name ?? branding.appliedBrandKitName
    }

    func appliedBrandKitIsMissing(in library: BrandKitLibrary) -> Bool {
        guard let kitID = branding.appliedBrandKitID else { return false }
        return library.kit(id: kitID) == nil
    }
}

// MARK: - Writing styled values back into an editor configuration

/// Copies only the style-bearing fields from a styled document into the
/// configuration, so the (expensive, lossy-to-reencode) image is untouched.
private enum StylingAdoption {
    static func adoptedLayers(
        _ current: [ThumbnailDocumentLayer],
        from styled: [ThumbnailDocumentLayer]
    ) -> [ThumbnailDocumentLayer] {
        let styledByID = Dictionary(styled.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return current.map { layer in
            guard layer.content != nil, let replacement = styledByID[layer.id] else { return layer }
            var layer = layer
            layer.content = replacement.content
            return layer
        }
    }
}

extension SimpleMakerConfigurationModel {
    mutating func adoptStyling(from document: ThumbnailDocument) {
        if ThumbnailDocumentColor(color: backgroundColor) != document.canvas.backgroundColor {
            backgroundColor = document.canvas.backgroundColor.color
        }
        backgroundFill = document.canvas.backgroundFill // SHELL
        if ThumbnailDocumentColor(color: textColor) != document.text.color {
            textColor = document.text.color.color
        }
        selectedFont = CustomFont(rawValue: document.text.selectedFontRawValue) ?? selectedFont
        if Double(textSize) != document.text.size {
            textSize = CGFloat(document.text.size)
        }
        textStyle = document.text.style
        layers = StylingAdoption.adoptedLayers(layers, from: document.layers)
        branding = document.branding
    }
}

extension PremiumMakerConfigurationModel {
    mutating func adoptStyling(from document: ThumbnailDocument) {
        if ThumbnailDocumentColor(color: backgroundColor) != document.canvas.backgroundColor {
            backgroundColor = document.canvas.backgroundColor.color
        }
        backgroundFill = document.canvas.backgroundFill // SHELL
        if ThumbnailDocumentColor(color: textColor) != document.text.color {
            textColor = document.text.color.color
        }
        selectedFont = CustomFont(rawValue: document.text.selectedFontRawValue) ?? selectedFont
        if Double(textSize) != document.text.size {
            textSize = CGFloat(document.text.size)
        }
        textStyle = document.text.style
        layers = StylingAdoption.adoptedLayers(layers, from: document.layers)
        branding = document.branding
    }
}
