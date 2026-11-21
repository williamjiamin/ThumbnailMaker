//
//  QuickCreateDraft.swift
//  ThumbnailMaker
//
//  SHELL (1.1.0 rebuild): the guided Quick Create wizard's state as a pure
//  value (Template -> Text -> Style -> Export). `makeDocument` turns the
//  choices into an ordinary ThumbnailDocument; the editor then adopts it as
//  a normal, undoable, saved project. Nothing here touches disk or UI.
//

import Foundation
import SwiftUI

enum QuickCreateStep: Int, CaseIterable, Identifiable, Equatable {
    case template
    case text
    case style
    case export

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .template: "Template"
        case .text: "Text"
        case .style: "Style"
        case .export: "Export"
        }
    }

    var prompt: String {
        switch self {
        case .template: "Pick a format and template to get started."
        case .text: "Add your title and subtitle text."
        case .style: "Choose a text style, background and brand kit."
        case .export: "Choose how this thumbnail will be exported."
        }
    }

    var next: QuickCreateStep? { QuickCreateStep(rawValue: rawValue + 1) }
    var previous: QuickCreateStep? { QuickCreateStep(rawValue: rawValue - 1) }
}

/// The five formats offered by 1.1.0, mapped onto the existing aspect
/// ratios and export presets (4:3 and 3:4 reuse the general Video Cover and
/// Portrait Cover presets, which have exactly those ratios).
enum QuickCreateFormat: String, CaseIterable, Identifiable, Equatable {
    case youtube
    case shorts
    case instagram
    case facebook
    case pinterest

    var id: String { rawValue }

    var aspectRatio: AspectRatio {
        switch self {
        case .youtube: .ratio16_9
        case .shorts: .ratio9_16
        case .instagram: .ratio1_1
        case .facebook: .ratio4_3
        case .pinterest: .ratio3_4
        }
    }

    var exportPreset: ThumbnailExportPreset {
        switch self {
        case .youtube: .youTubeThumbnail
        case .shorts: .shortFormCover
        case .instagram: .instagramSquare
        case .facebook: .videoCover
        case .pinterest: .portraitCover
        }
    }

    var ratioLabel: String { aspectRatio.rawValue }

    var platformLabel: String {
        switch self {
        case .youtube: "YouTube"
        case .shorts: "Shorts/TikTok"
        case .instagram: "Instagram"
        case .facebook: "Facebook"
        case .pinterest: "Pinterest"
        }
    }
}

/// Category chips: All plus the four 1.1.0 categories.
enum QuickCreateCategoryFilter: String, CaseIterable, Identifiable, Equatable {
    case all
    case gaming
    case vlog
    case tutorial
    case reaction

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .gaming: "Gaming"
        case .vlog: "Vlog"
        case .tutorial: "Tutorial"
        case .reaction: "Reaction"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .gaming: "gamecontroller"
        case .vlog: "video"
        case .tutorial: "book"
        case .reaction: "face.smiling"
        }
    }

    func includes(_ template: ThumbnailTemplate) -> Bool {
        switch self {
        case .all: true
        case .gaming: template.category == .gaming
        case .vlog: template.category == .vlog
        case .tutorial: template.category == .tutorial
        case .reaction: template.category == .reaction
        }
    }
}

enum QuickCreateBackgroundChoice: Equatable {
    /// Keep the layout's own background.
    case layout
    case solid(ThumbnailDocumentColor)
    case gradient(ThumbnailBackgroundFill)
}

struct QuickCreateDraft: Equatable {
    static let titleCharacterLimit = 80
    static let subtitleCharacterLimit = 80

    var step: QuickCreateStep = .template
    var format: QuickCreateFormat = .youtube
    var categoryFilter: QuickCreateCategoryFilter = .all
    var templateID: String = ThumbnailTemplate.quickCreateBlankID
    var title = ""
    var subtitle = ""
    var font: CustomFont?
    /// nil keeps the layout's title colour.
    var titleColor: ThumbnailDocumentColor?
    /// nil keeps the layout's own text style.
    var textStylePresetID: String?
    var background: QuickCreateBackgroundChoice = .layout
    var brandKitID: String?
    var exportFormat: ThumbnailExportFormat = .png

    static var layouts: [ThumbnailTemplate] { ThumbnailTemplate.quickCreateLayouts }

    var visibleLayouts: [ThumbnailTemplate] {
        Self.layouts.filter { categoryFilter.includes($0) || $0.isQuickCreateBlank }
    }

    var selectedLayout: ThumbnailTemplate {
        Self.layouts.first { $0.id == templateID } ?? Self.layouts[0]
    }

    /// The font the wizard will use: an explicit choice, else the layout's.
    var effectiveFont: CustomFont {
        font ?? CustomFont(rawValue: selectedLayout.document.text.selectedFontRawValue) ?? .goNoto
    }

    var effectiveTitleColor: ThumbnailDocumentColor {
        titleColor ?? selectedLayout.document.text.color
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedSubtitle: String { subtitle.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Name of the project the wizard creates.
    var projectName: String {
        let base = trimmedTitle.isEmpty ? "Quick Create" : trimmedTitle
        return String(base.prefix(60))
    }

    mutating func goForward() {
        if let next = step.next { step = next }
    }

    mutating func goBack() {
        if let previous = step.previous { step = previous }
    }

    mutating func selectCategory(_ filter: QuickCreateCategoryFilter) {
        categoryFilter = filter
        // Keep the selection visible: fall back to Blank when filtered out.
        if !visibleLayouts.contains(where: { $0.id == templateID }) {
            templateID = ThumbnailTemplate.quickCreateBlankID
        }
    }

    /// Builds the finished document. `brandKit` is the kit picked on the
    /// Style step (nil when none). `now` stamps `updatedAt`.
    func makeDocument(
        brandKit: BrandKit? = nil,
        now: Date = Date(),
        idProvider: () -> String = { UUID().uuidString }
    ) -> ThumbnailDocument {
        let layout = selectedLayout
        var document = layout.makeDocument(updatedAt: now)
        let font = effectiveFont

        // 1. Format: ratio + matching export preset + chosen file format.
        document.canvas.aspectRatioRawValue = format.aspectRatio.rawValue
        let preset = format.exportPreset
        document.export = ThumbnailDocumentExport(
            presetID: preset.id,
            formatRawValue: exportFormat.rawValue,
            usesCustomSize: false,
            customWidth: preset.size.width,
            customHeight: preset.size.height
        )

        // 2. Title. An empty title keeps the layout's placeholder so there
        // is something to edit (Blank stays empty).
        if !trimmedTitle.isEmpty {
            document.text.value = String(title.prefix(Self.titleCharacterLimit))
        }
        document.text.selectedFontRawValue = font.rawValue
        document.text.color = effectiveTitleColor

        // 3. Subtitle: fills the layout's subtitle line, or adds a second
        // text layer under (or above, for bottom titles) the title.
        let subtitleValue = String(trimmedSubtitle.prefix(Self.subtitleCharacterLimit))
        let subtitleIndex = document.layers.firstIndex { $0.id == ThumbnailTemplate.quickCreateSubtitleLayerID }
        var layers = document.layers
        if let subtitleIndex {
            var layer = layers[subtitleIndex]
            layer.id = idProvider() // fresh id per project
            if case .text(var content) = layer.content {
                if !subtitleValue.isEmpty { content.value = subtitleValue }
                content.selectedFontRawValue = font.rawValue
                content.color = effectiveTitleColor
                layer.content = .text(content)
            }
            layers[subtitleIndex] = layer
        } else if !subtitleValue.isEmpty {
            let titleY = document.text.value.isEmpty ? 0.5 : document.text.transform.y
            let subtitleY = titleY > 0.68 ? titleY - 0.18 : min(0.9, titleY + 0.18)
            layers.append(
                ThumbnailDocumentLayer.textLayer(
                    id: idProvider(),
                    value: subtitleValue,
                    color: effectiveTitleColor,
                    size: 0.08,
                    selectedFontRawValue: font.rawValue,
                    name: "Subtitle",
                    transform: ThumbnailOverlayTransform(
                        x: document.text.transform.x,
                        y: subtitleY,
                        rotationDegrees: 0
                    )
                )
            )
        }
        document.layers = layers.reconciledForCurrentOverlays(
            hasText: !document.text.value.isEmpty,
            hasProfile: false
        )

        // 4. Brand kit (Style step): recolours and re-fonts project-wide.
        if let brandKit {
            document = brandKit.applied(to: document, scope: .projectWide)
        }

        // 5. Text style preset (Style step) on the title and subtitle.
        if let textStylePresetID {
            let overlayStyle = ThumbnailTextStylePreset.all(for: .overlay)
                .first { $0.id == textStylePresetID }
            let layerStyle = ThumbnailTextStylePreset.all(for: .contentLayer)
                .first { $0.id == textStylePresetID }
            if let overlayStyle {
                document.text.style = overlayStyle.style
            }
            if let layerStyle {
                for index in document.layers.indices {
                    if case .text(var content) = document.layers[index].content {
                        content.style = layerStyle.style
                        document.layers[index].content = .text(content)
                    }
                }
            }
        }

        // 6. Background (Style step). Chosen last so it wins over the kit.
        switch background {
        case .layout:
            break
        case .solid(let color):
            document.canvas.backgroundColor = color
            document.canvas.backgroundFill = nil
        case .gradient(let fill):
            let normalized = fill.normalized()
            document.canvas.backgroundFill = normalized
            if let representative = normalized.representativeColor {
                document.canvas.backgroundColor = representative
            }
        }

        document.editorMode = .simple
        document.updatedAt = now
        return document
    }
}
