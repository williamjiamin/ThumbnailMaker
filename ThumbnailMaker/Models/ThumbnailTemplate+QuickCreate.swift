//
//  ThumbnailTemplate+QuickCreate.swift
//  ThumbnailMaker
//
//  SHELL (1.1.0 rebuild): the eight Quick Create layouts recovered from the
//  1.1.0 App Store screenshots (Blank, Bold Center, Bottom Title, Top Corner,
//  Subtitle, Full Width, Minimal, EPIC GAMEPLAY). They extend the built-in
//  templates: the original five `builtIns` are untouched, the layouts are
//  added alongside them (`allBuiltIns`) so the editor's template gallery can
//  offer them too. Layouts are ratio-independent (normalized transforms); the
//  wizard re-targets them to the chosen format.
//

import Foundation
import SwiftUI

extension ThumbnailTemplate {
    static let quickCreateBlankID = "quick-blank"
    /// Layer id (template-local) of the Subtitle layout's second text line.
    static let quickCreateSubtitleLayerID = "tpl-subtitle"

    static let quickCreateLayouts: [ThumbnailTemplate] = [
        quickLayout(
            id: quickCreateBlankID,
            name: "Blank",
            category: .youtube,
            background: ThumbnailDocumentColor(red: 1, green: 1, blue: 1, alpha: 1),
            text: "",
            textColor: ThumbnailDocumentColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1),
            textSize: 0.15,
            font: .goNoto,
            transform: .centered
        ),
        quickLayout(
            id: "quick-bold-center",
            name: "Bold Center",
            category: .reaction,
            text: "YOUR TEXT",
            textSize: 0.2,
            font: .montserrat,
            transform: .centered
        ),
        quickLayout(
            id: "quick-bottom-title",
            name: "Bottom Title",
            category: .vlog,
            text: "TITLE HERE",
            textSize: 0.16,
            font: .montserrat,
            transform: ThumbnailOverlayTransform(x: 0.5, y: 0.8, rotationDegrees: 0)
        ),
        quickLayout(
            id: "quick-top-corner",
            name: "Top Corner",
            category: .tutorial,
            text: "HEADLINE",
            textColor: ThumbnailDocumentColor(red: 1.0, green: 0.8, blue: 0.1, alpha: 1),
            textSize: 0.14,
            font: .oswald,
            transform: ThumbnailOverlayTransform(x: 0.3, y: 0.18, rotationDegrees: 0)
        ),
        quickLayout(
            id: "quick-subtitle",
            name: "Subtitle",
            category: .tutorial,
            text: "YOUR TITLE",
            textSize: 0.16,
            font: .montserrat,
            transform: ThumbnailOverlayTransform(x: 0.5, y: 0.42, rotationDegrees: 0),
            subtitle: "Subtitle"
        ),
        quickLayout(
            id: "quick-full-width",
            name: "Full Width",
            category: .reaction,
            text: "BIG TEXT",
            textSize: 0.3,
            font: .oswald,
            transform: .centered
        ),
        quickLayout(
            id: "quick-minimal",
            name: "Minimal",
            category: .vlog,
            text: "minimal",
            textSize: 0.1,
            font: .poppins,
            transform: .centered
        ),
        quickLayout(
            id: "quick-epic-gameplay",
            name: "EPIC GAMEPLAY",
            category: .gaming,
            background: ThumbnailDocumentColor(red: 0.93, green: 0.16, blue: 0.16, alpha: 1),
            fill: .epicGameplay,
            text: "EPIC GAMEPLAY",
            textSize: 0.18,
            font: .cherryBombOne,
            transform: .centered,
            style: ThumbnailTextStylePreset.all(for: .overlay).first { $0.id == "outlineAndShadow" }?.style
        )
    ]

    /// Every built-in: the original five plus the Quick Create layouts
    /// (except Blank, which only makes sense as a wizard starting point),
    /// then the curated TEMPLATES library.
    static let allBuiltIns: [ThumbnailTemplate] = builtIns
        + quickCreateLayouts.filter { $0.id != quickCreateBlankID }
        + curatedLibrary

    var isQuickCreateBlank: Bool { id == Self.quickCreateBlankID }

    private static func quickLayout(
        id: String,
        name: String,
        category: ThumbnailTemplateCategory,
        background: ThumbnailDocumentColor = ThumbnailDocumentColor(red: 0, green: 0, blue: 0, alpha: 1),
        fill: ThumbnailBackgroundFill? = nil,
        text: String,
        textColor: ThumbnailDocumentColor = ThumbnailDocumentColor(red: 1, green: 1, blue: 1, alpha: 1),
        textSize: Double,
        font: CustomFont,
        transform: ThumbnailOverlayTransform,
        style: ThumbnailTextStyle? = nil,
        subtitle: String? = nil
    ) -> ThumbnailTemplate {
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: !text.isEmpty, hasProfile: false)
        if let subtitle {
            layers.append(
                ThumbnailDocumentLayer.textLayer(
                    id: quickCreateSubtitleLayerID,
                    value: subtitle,
                    color: textColor,
                    size: 0.08,
                    selectedFontRawValue: font.rawValue,
                    name: "Subtitle",
                    transform: ThumbnailOverlayTransform(x: 0.5, y: 0.62, rotationDegrees: 0)
                )
            )
        }
        let document = ThumbnailDocument(
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            editorMode: .simple,
            canvas: ThumbnailDocumentCanvas(
                aspectRatioRawValue: AspectRatio.ratio16_9.rawValue,
                backgroundColor: background,
                backgroundFill: fill
            ),
            text: ThumbnailDocumentText(
                value: text,
                color: textColor,
                size: textSize,
                transform: transform,
                selectedFontRawValue: font.rawValue,
                style: style
            ),
            layers: layers,
            export: ThumbnailDocumentExport(presetID: ThumbnailExportPreset.youTubeThumbnail.id)
        )
        return ThumbnailTemplate(id: id, name: name, category: category, document: document)
    }
}
