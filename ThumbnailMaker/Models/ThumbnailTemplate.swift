//
//  ThumbnailTemplate.swift
//  ThumbnailMaker
//

import Foundation
import SwiftUI

enum ThumbnailTemplateCategory: String, CaseIterable, Codable, Equatable {
    case youtube
    case shortForm
    case podcast
    case gaming
    case vlog
    // SHELL (1.1.0 Quick Create categories)
    case tutorial
    case reaction
    // TEMPLATES (curated library). Older builds decode these as `.youtube`.
    case beforeAfter
    case listicle
    case news
    case minimal

    // FEATURE-05: a library written by a newer build may carry a category this
    // build does not know; fall back instead of failing the whole library.
    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = ThumbnailTemplateCategory(rawValue: rawValue) ?? .youtube
    }
}

struct ThumbnailTemplate: Codable, Equatable, Identifiable {
    static let currentVersion = 2

    var version = currentVersion
    var id: String
    var name: String
    var category: ThumbnailTemplateCategory
    var document: ThumbnailDocument
    // FEATURE-05: personal-template metadata. Every field is optional on
    // decode so v1 template JSON still opens.
    var origin: ThumbnailTemplateOrigin = .builtIn
    var isFavorite = false
    var createdAt = Date(timeIntervalSince1970: 0)
    var updatedAt = Date(timeIntervalSince1970: 0)
    var deletedAt: Date?
    var slots: ThumbnailTemplateSlots = .builtInDefaults
    var sourceTemplateID: String?

    init(
        version: Int = ThumbnailTemplate.currentVersion,
        id: String,
        name: String,
        category: ThumbnailTemplateCategory,
        document: ThumbnailDocument,
        origin: ThumbnailTemplateOrigin = .builtIn,
        isFavorite: Bool = false,
        createdAt: Date = Date(timeIntervalSince1970: 0),
        updatedAt: Date = Date(timeIntervalSince1970: 0),
        deletedAt: Date? = nil,
        slots: ThumbnailTemplateSlots = .builtInDefaults,
        sourceTemplateID: String? = nil
    ) {
        self.version = version
        self.id = id
        self.name = name
        self.category = category
        self.document = document
        self.origin = origin
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.slots = slots
        self.sourceTemplateID = sourceTemplateID
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case id
        case name
        case category
        case document
        case origin
        case isFavorite
        case createdAt
        case updatedAt
        case deletedAt
        case slots
        case sourceTemplateID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion

        version = max(decodedVersion, Self.currentVersion)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decode(ThumbnailTemplateCategory.self, forKey: .category)
        document = try container.decode(ThumbnailDocument.self, forKey: .document)
        origin = (try? container.decodeIfPresent(ThumbnailTemplateOrigin.self, forKey: .origin)) ?? .builtIn
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        slots = try container.decodeIfPresent(ThumbnailTemplateSlots.self, forKey: .slots) ?? .builtInDefaults
        sourceTemplateID = try container.decodeIfPresent(String.self, forKey: .sourceTemplateID)
    }

    /// FEATURE-05: only templates the creator saved can be renamed, deleted, etc.
    var isEditable: Bool { origin == .personal }

    func makeDocument(updatedAt: Date = Date()) -> ThumbnailDocument {
        var document = document
        document.imageData = nil
        document.profile?.imageData = nil
        document.layers.removeAll { layer in
            if case .image = layer.content {
                return true
            }
            return false
        }
        document.updatedAt = updatedAt
        return document
    }

    func makeDocument(
        preservingImagesFrom existingDocument: ThumbnailDocument,
        updatedAt: Date = Date()
    ) -> ThumbnailDocument {
        var document = makeDocument(updatedAt: updatedAt)
        document.imageData = existingDocument.imageData
        document.imageRecipe = existingDocument.imageRecipe

        var layerRecords = document.layers
        // FEATURE-14: the base photo's adjustment recipe travels with the photo.
        if let carried = existingDocument.layers.record(id: ThumbnailDocumentLayer.backgroundID)?.adjustments,
           document.imageData != nil {
            layerRecords.setAdjustments(carried, forLayerID: ThumbnailDocumentLayer.backgroundID)
        }
        // FEATURE-11: so does its cutout recipe.
        if let carried = existingDocument.layers.cutout(forLayerID: ThumbnailDocumentLayer.backgroundID),
           document.imageData != nil {
            layerRecords.setCutout(carried, forLayerID: ThumbnailDocumentLayer.backgroundID)
        }
        if var profile = document.profile {
            profile.imageData = profile.imageData ?? existingDocument.profile?.imageData
            document.profile = profile
        } else if let existingProfile = existingDocument.profile,
                  existingProfile.imageData != nil {
            document.profile = existingProfile
            if let existingProfileLayer = existingDocument.layers.first(where: {
                $0.id == ThumbnailDocumentLayer.profileID
            }) {
                layerRecords.append(existingProfileLayer)
            }
        }

        // FEATURE-14: a preserved profile photo keeps its adjustment recipe.
        if let carried = existingDocument.layers.record(id: ThumbnailDocumentLayer.profileID)?.adjustments,
           let profileData = document.profile?.imageData,
           profileData == existingDocument.profile?.imageData {
            layerRecords.setAdjustments(carried, forLayerID: ThumbnailDocumentLayer.profileID)
        }

        for existingContentLayer in existingDocument.layers where existingContentLayer.content != nil {
            if let existingIndex = layerRecords.firstIndex(where: { $0.id == existingContentLayer.id }) {
                layerRecords[existingIndex] = existingContentLayer
            } else if Self.isBuiltInLayoutLayerID(existingContentLayer.id) {
                // TEMPLATES: another built-in layout's decoration; switching
                // layouts replaces it instead of stacking both.
                continue
            } else {
                layerRecords.append(existingContentLayer)
            }
        }

        document.layers = layerRecords.reconciledForCurrentOverlays(
            hasText: !document.text.value.isEmpty,
            hasProfile: document.profile?.imageData != nil
        )
        return document
    }
}

extension ThumbnailTemplate {
    static let builtIns: [ThumbnailTemplate] = [
        ThumbnailTemplate(
            id: "youtube-bold-launch",
            name: "Bold Launch",
            category: .youtube,
            document: makeDocument(
                editorMode: .premium,
                aspectRatio: .ratio16_9,
                backgroundColor: Color(red: 0.05, green: 0.06, blue: 0.08),
                text: "BIG REVEAL",
                textColor: .white,
                textSize: 0.23,
                font: .montserrat,
                transform: ThumbnailOverlayTransform(
                    x: 0.50,
                    y: 0.46,
                    rotationDegrees: -4
                )
            )
        ),
        ThumbnailTemplate(
            id: "short-form-hook",
            name: "Vertical Hook",
            category: .shortForm,
            document: makeDocument(
                editorMode: .premium,
                aspectRatio: .ratio9_16,
                backgroundColor: Color(red: 0.02, green: 0.10, blue: 0.14),
                text: "WAIT FOR IT",
                textColor: Color(red: 1.0, green: 0.92, blue: 0.26),
                textSize: 0.18,
                font: .oswald,
                transform: ThumbnailOverlayTransform(
                    x: 0.50,
                    y: 0.28,
                    rotationDegrees: 0
                )
            )
        ),
        ThumbnailTemplate(
            id: "podcast-clean-title",
            name: "Podcast Clean Title",
            category: .podcast,
            document: makeDocument(
                editorMode: .simple,
                aspectRatio: .ratio1_1,
                backgroundColor: Color(red: 0.94, green: 0.95, blue: 0.97),
                text: "NEW EPISODE",
                textColor: Color(red: 0.09, green: 0.10, blue: 0.13),
                textSize: 0.17,
                font: .poppins,
                transform: ThumbnailOverlayTransform(
                    x: 0.50,
                    y: 0.72,
                    rotationDegrees: 0
                ),
                exportPresetID: ThumbnailExportPreset.podcastCover.id
            )
        ),
        ThumbnailTemplate(
            id: "gaming-impact",
            name: "Gaming Impact",
            category: .gaming,
            document: makeDocument(
                editorMode: .premium,
                aspectRatio: .ratio16_9,
                backgroundColor: Color(red: 0.12, green: 0.01, blue: 0.08),
                text: "I WON",
                textColor: Color(red: 0.18, green: 1.0, blue: 0.62),
                textSize: 0.28,
                font: .cherryBombOne,
                transform: ThumbnailOverlayTransform(
                    x: 0.55,
                    y: 0.38,
                    rotationDegrees: 6
                )
            )
        ),
        ThumbnailTemplate(
            id: "vlog-story",
            name: "Vlog Story",
            category: .vlog,
            document: makeDocument(
                editorMode: .simple,
                aspectRatio: .ratio4_3,
                backgroundColor: Color(red: 0.11, green: 0.20, blue: 0.23),
                text: "DAY ONE",
                textColor: Color(red: 1.0, green: 0.76, blue: 0.48),
                textSize: 0.2,
                font: .openSans,
                transform: ThumbnailOverlayTransform(
                    x: 0.48,
                    y: 0.62,
                    rotationDegrees: -2
                )
            )
        )
    ]

    private static let builtInUpdatedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private static func makeDocument(
        editorMode: ThumbnailDocumentEditorMode,
        aspectRatio: AspectRatio,
        backgroundColor: Color,
        text: String,
        textColor: Color,
        textSize: Double,
        font: CustomFont,
        transform: ThumbnailOverlayTransform,
        exportPresetID: String? = nil
    ) -> ThumbnailDocument {
        ThumbnailDocument(
            updatedAt: builtInUpdatedAt,
            editorMode: editorMode,
            canvas: ThumbnailDocumentCanvas(
                aspectRatioRawValue: aspectRatio.rawValue,
                backgroundColor: ThumbnailDocumentColor(color: backgroundColor)
            ),
            text: ThumbnailDocumentText(
                value: text,
                color: ThumbnailDocumentColor(color: textColor),
                size: textSize,
                transform: transform,
                selectedFontRawValue: font.rawValue
            ),
            layers: ThumbnailDocumentLayer.defaultLayers(hasText: true, hasProfile: false),
            export: ThumbnailDocumentExport(presetID: exportPresetID ?? presetID(for: aspectRatio))
        )
    }

    private static func presetID(for aspectRatio: AspectRatio) -> String {
        switch aspectRatio {
        case .ratio16_9:
            return ThumbnailExportPreset.youTubeThumbnail.id
        case .ratio9_16:
            return ThumbnailExportPreset.shortFormCover.id
        case .ratioReelsCover:
            return ThumbnailExportPreset.instagramReelsCover.id
        case .ratio1_1:
            return ThumbnailExportPreset.instagramSquare.id
        case .ratio4_3:
            return ThumbnailExportPreset.videoCover.id
        case .ratio3_4:
            return ThumbnailExportPreset.portraitCover.id
        }
    }
}
