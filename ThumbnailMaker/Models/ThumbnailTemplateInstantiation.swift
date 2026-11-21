//
//  ThumbnailTemplateInstantiation.swift
//  ThumbnailMaker
//
//  FEATURE-05: capture a project as a reusable personal template, and apply a
//  template to a project either as a whole layout (composition) or as a look
//  only (style). Built-in templates keep their exact legacy application path
//  (`makeDocument(preservingImagesFrom:)`) so nothing about them changes.
//

import Foundation

enum ThumbnailTemplateApplicationMode: String, CaseIterable, Equatable, Identifiable {
    /// Replace the layout with the template's (slots decide which assets come along).
    case composition
    /// Keep layout, layers, images and headline; adopt only colours and typography.
    case styleOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .composition: "Replace layout"
        case .styleOnly: "Style only"
        }
    }
}

enum ThumbnailTemplateWarning: Equatable, Identifiable, Hashable {
    case missingBackgroundImage
    case missingProfileImage
    case unsupportedFont(rawValue: String)

    var id: String { message }

    var message: String {
        switch self {
        case .missingBackgroundImage:
            "This template has an empty background slot. Add a background image to finish the design."
        case .missingProfileImage:
            "This template has an empty profile slot. Add a profile photo to finish the design."
        case .unsupportedFont(let rawValue):
            "The font \"\(rawValue)\" is not available in this version, so a fallback font is used."
        }
    }
}

struct ThumbnailTemplateApplication: Equatable {
    var document: ThumbnailDocument
    /// Fresh content-layer ids in z order (empty for built-in / style-only application).
    var newContentLayerIDs: [String] = []
    /// Template-local id -> fresh id.
    var idMap: [String: String] = [:]
    var warnings: [ThumbnailTemplateWarning] = []
}

extension Array where Element == ThumbnailDocumentLayer {
    /// Rewrites every content-layer id; singleton ids (background/profile/text)
    /// are structural and are never touched.
    func withFreshContentLayerIDs(
        _ idProvider: () -> String
    ) -> (layers: [ThumbnailDocumentLayer], idMap: [String: String], orderedNewIDs: [String]) {
        var idMap: [String: String] = [:]
        var layers = self
        let contentIndices = layers.indices
            .filter { layers[$0].content != nil }
            .sorted { layers[$0].zIndex < layers[$1].zIndex }
        var orderedNewIDs: [String] = []
        for index in contentIndices {
            let newID = idProvider()
            idMap[layers[index].id] = newID
            layers[index].id = newID
            orderedNewIDs.append(newID)
        }
        return (layers, idMap, orderedNewIDs)
    }
}

extension ThumbnailTemplate {
    static let templateLayerIDPrefix = "tpl-"

    /// Builds a personal template from a project document. Only media the
    /// creator explicitly retains is copied; project UUIDs never survive.
    static func capture(
        from source: ThumbnailDocument,
        id: String = UUID().uuidString,
        name: String,
        category: ThumbnailTemplateCategory,
        retainedLayerIDs: Set<String> = [],
        backgroundPolicy: ThumbnailTemplateSlotPolicy = .replaceFromProject,
        profilePolicy: ThumbnailTemplateSlotPolicy = .replaceFromProject,
        titlePolicy: ThumbnailTemplateSlotPolicy = .replaceFromProject,
        isFavorite: Bool = false,
        now: Date = Date()
    ) -> ThumbnailTemplate {
        var document = source
        var omittedImageLayers = 0
        var templateRetainedIDs: [String] = []

        let singletons = document.layers.filter { $0.content == nil }
        let contentLayers = document.layers
            .filter { $0.content != nil }
            .sorted { $0.zIndex < $1.zIndex }

        var keptContentLayers: [ThumbnailDocumentLayer] = []
        for layer in contentLayers {
            let isImage: Bool
            if case .image = layer.content { isImage = true } else { isImage = false }
            if isImage && !retainedLayerIDs.contains(layer.id) {
                omittedImageLayers += 1
                continue
            }
            var kept = layer
            kept.id = "\(templateLayerIDPrefix)\(keptContentLayers.count)"
            if isImage {
                templateRetainedIDs.append(kept.id)
            }
            keptContentLayers.append(kept)
        }

        if backgroundPolicy != .retained {
            document.imageData = nil
            document.imageRecipe = .identity
        }
        if profilePolicy != .retained {
            document.profile?.imageData = nil
        }
        document.macro.isEnabled = false
        document.formats = nil // FEATURE-09: templates never carry sizes
        document.updatedAt = Date(timeIntervalSince1970: 0)
        document.layers = (singletons + keptContentLayers).reconciledForCurrentOverlays(
            hasText: !document.text.value.isEmpty,
            hasProfile: document.profile != nil
        )

        return ThumbnailTemplate(
            id: id,
            name: name,
            category: category,
            document: document,
            origin: .personal,
            isFavorite: isFavorite,
            createdAt: now,
            updatedAt: now,
            slots: ThumbnailTemplateSlots(
                backgroundImage: backgroundPolicy,
                profileImage: profilePolicy,
                title: titlePolicy == .retained ? .retained : .replaceFromProject,
                retainedLayerIDs: templateRetainedIDs,
                omittedImageLayerCount: omittedImageLayers
            )
        )
    }

    /// The single entry point the editors use.
    /// - Built-in (and idea-derived) templates in `.composition` mode use the
    ///   unchanged legacy path.
    /// - Personal templates in `.composition` mode are instantiated with fresh
    ///   layer ids and slot resolution.
    /// - `.styleOnly` adopts colours and typography only.
    func application(
        over existingDocument: ThumbnailDocument,
        mode: ThumbnailTemplateApplicationMode = .composition,
        updatedAt: Date = Date(),
        idProvider: () -> String = { UUID().uuidString }
    ) -> ThumbnailTemplateApplication {
        switch mode {
        case .styleOnly:
            return styleApplication(over: existingDocument, updatedAt: updatedAt)
        case .composition where origin == .builtIn:
            return ThumbnailTemplateApplication(
                document: makeDocument(preservingImagesFrom: existingDocument, updatedAt: updatedAt)
            )
        case .composition:
            return instantiate(over: existingDocument, updatedAt: updatedAt, idProvider: idProvider)
        }
    }

    func instantiate(
        over existingDocument: ThumbnailDocument,
        updatedAt: Date = Date(),
        idProvider: () -> String = { UUID().uuidString }
    ) -> ThumbnailTemplateApplication {
        var document = self.document
        var warnings: [ThumbnailTemplateWarning] = []

        let fresh = document.layers.withFreshContentLayerIDs(idProvider)
        var layers = fresh.layers.remappingGroupIDs() // FEATURE-07

        switch slots.backgroundImage {
        case .replaceFromProject:
            document.imageData = existingDocument.imageData
            document.imageRecipe = existingDocument.imageRecipe
            // FEATURE-11: a cutout belongs to the photo it was drawn on.
            layers.setCutout(
                existingDocument.layers.cutout(forLayerID: ThumbnailDocumentLayer.backgroundID),
                forLayerID: ThumbnailDocumentLayer.backgroundID
            )
        case .placeholder:
            document.imageData = nil
            document.imageRecipe = .identity
            layers.resetCutout(forLayerID: ThumbnailDocumentLayer.backgroundID) // FEATURE-11
        case .retained:
            break
        }
        // Only a deliberately empty slot is reported; a project that simply has
        // no image of its own is not a template problem.
        if slots.backgroundImage == .placeholder {
            warnings.append(.missingBackgroundImage)
        }

        switch slots.profileImage {
        case .replaceFromProject:
            if document.profile != nil {
                document.profile?.imageData = existingDocument.profile?.imageData
            } else if let existingProfile = existingDocument.profile, existingProfile.imageData != nil {
                document.profile = existingProfile
                let existingProfileLayer = existingDocument.layers.first { $0.id == ThumbnailDocumentLayer.profileID }
                layers.append(existingProfileLayer ?? ThumbnailDocumentLayer.defaultProfileLayer)
            }
        case .placeholder:
            document.profile?.imageData = nil
        case .retained:
            break
        }
        if document.profile != nil, slots.profileImage == .placeholder {
            warnings.append(.missingProfileImage)
        }

        if slots.title != .retained {
            let projectTitle = existingDocument.text.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !projectTitle.isEmpty {
                document.text.value = existingDocument.text.value
            }
        }

        if CustomFont(rawValue: document.text.selectedFontRawValue) == nil {
            warnings.append(.unsupportedFont(rawValue: document.text.selectedFontRawValue))
        }

        document.layers = layers.reconciledForCurrentOverlays(
            hasText: !document.text.value.isEmpty,
            hasProfile: document.profile?.imageData != nil
        )
        document.updatedAt = updatedAt

        return ThumbnailTemplateApplication(
            document: document,
            newContentLayerIDs: fresh.orderedNewIDs,
            idMap: fresh.idMap,
            warnings: warnings
        )
    }

    func styleApplication(
        over existingDocument: ThumbnailDocument,
        updatedAt: Date = Date()
    ) -> ThumbnailTemplateApplication {
        var document = existingDocument
        let style = self.document
        document.canvas.backgroundColor = style.canvas.backgroundColor
        document.canvas.backgroundFill = style.canvas.backgroundFill // SHELL
        document.text.color = style.text.color
        document.text.size = style.text.size
        document.text.selectedFontRawValue = style.text.selectedFontRawValue
        document.text.verticalAlignmentRawValue = style.text.verticalAlignmentRawValue
        document.text.horizontalAlignmentRawValue = style.text.horizontalAlignmentRawValue
        document.text.style = style.text.style
        document.updatedAt = updatedAt

        var warnings: [ThumbnailTemplateWarning] = []
        if CustomFont(rawValue: document.text.selectedFontRawValue) == nil {
            warnings.append(.unsupportedFont(rawValue: document.text.selectedFontRawValue))
        }
        return ThumbnailTemplateApplication(document: document, warnings: warnings)
    }

    /// Rough encoded size of the media a template carries, used for caps.
    var retainedMediaByteCount: Int {
        var total = document.imageData?.count ?? 0
        total += document.profile?.imageData?.count ?? 0
        for layer in document.layers {
            if case .image(let content) = layer.content {
                total += content.imageData.count
            }
        }
        return total
    }
}
