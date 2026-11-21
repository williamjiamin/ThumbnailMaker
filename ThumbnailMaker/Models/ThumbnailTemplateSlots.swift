//
//  ThumbnailTemplateSlots.swift
//  ThumbnailMaker
//
//  FEATURE-05: personal templates. Describes, per replaceable part of a
//  design, whether applying the template pulls the live project's asset in,
//  leaves the slot empty for the creator to fill, or ships the template's own
//  bytes (a brand logo, a channel name).
//

import Foundation

enum ThumbnailTemplateOrigin: String, Codable, Equatable {
    case builtIn
    case personal

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = ThumbnailTemplateOrigin(rawValue: rawValue) ?? .personal
    }
}

enum ThumbnailTemplateSlotPolicy: String, Codable, Equatable, CaseIterable, Identifiable {
    /// Pull the live project's asset / headline into the template.
    case replaceFromProject
    /// Intentionally empty; the creator fills it after applying.
    case placeholder
    /// Ship the template's own bytes / text.
    case retained

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = ThumbnailTemplateSlotPolicy(rawValue: rawValue) ?? .replaceFromProject
    }

    var displayName: String {
        switch self {
        case .replaceFromProject: "Use project's"
        case .placeholder: "Leave empty"
        case .retained: "Keep template's"
        }
    }
}

struct ThumbnailTemplateSlots: Codable, Equatable {
    static let currentVersion = 1

    var version: Int = currentVersion
    /// -> ThumbnailDocument.imageData (+ imageRecipe)
    var backgroundImage: ThumbnailTemplateSlotPolicy
    /// -> ThumbnailDocumentProfile.imageData
    var profileImage: ThumbnailTemplateSlotPolicy
    /// -> ThumbnailDocumentText.value. `.placeholder` behaves like
    /// `.replaceFromProject` (a headline is never left blank, because an empty
    /// headline removes the text overlay entirely).
    var title: ThumbnailTemplateSlotPolicy
    /// Template-local ids of image layers whose media ships with the template.
    var retainedLayerIDs: [String]
    /// Number of project image layers deliberately left out at capture time.
    var omittedImageLayerCount: Int

    init(
        backgroundImage: ThumbnailTemplateSlotPolicy,
        profileImage: ThumbnailTemplateSlotPolicy,
        title: ThumbnailTemplateSlotPolicy,
        retainedLayerIDs: [String] = [],
        omittedImageLayerCount: Int = 0
    ) {
        self.backgroundImage = backgroundImage
        self.profileImage = profileImage
        self.title = title
        self.retainedLayerIDs = retainedLayerIDs
        self.omittedImageLayerCount = omittedImageLayerCount
    }

    static let builtInDefaults = ThumbnailTemplateSlots(
        backgroundImage: .replaceFromProject,
        profileImage: .replaceFromProject,
        title: .retained
    )

    static let personalDefaults = ThumbnailTemplateSlots(
        backgroundImage: .replaceFromProject,
        profileImage: .replaceFromProject,
        title: .replaceFromProject
    )

    private enum CodingKeys: String, CodingKey {
        case version, backgroundImage, profileImage, title, retainedLayerIDs, omittedImageLayerCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.builtInDefaults
        version = max(try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion, Self.currentVersion)
        backgroundImage = try container.decodeIfPresent(ThumbnailTemplateSlotPolicy.self, forKey: .backgroundImage) ?? defaults.backgroundImage
        profileImage = try container.decodeIfPresent(ThumbnailTemplateSlotPolicy.self, forKey: .profileImage) ?? defaults.profileImage
        title = try container.decodeIfPresent(ThumbnailTemplateSlotPolicy.self, forKey: .title) ?? defaults.title
        retainedLayerIDs = try container.decodeIfPresent([String].self, forKey: .retainedLayerIDs) ?? []
        omittedImageLayerCount = try container.decodeIfPresent(Int.self, forKey: .omittedImageLayerCount) ?? 0
    }
}
