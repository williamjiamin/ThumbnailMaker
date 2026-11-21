//
//  ThumbnailSeries.swift
//  ThumbnailMaker
//
//  FEATURE-15: a thumbnail series. One IMMUTABLE source design (always a
//  FEATURE-05 personal template, frozen at capture time) plus a table of rows
//  (title, episode, image, output name). Every row's thumbnail is derived from
//  (source, row, image bytes) by `ThumbnailSeriesRecipe`; nothing about a row
//  is ever baked into the source, so rows stay reversible edits.
//
//  All fields added after v1 must decode with defaults so older series open.
//

import Foundation

struct ThumbnailSeriesImageRef: Codable, Equatable, Hashable {
    /// SHA-256 of the stored bytes (content-addressed, see ThumbnailSeriesStore).
    var digest: String
    var originalFileName: String
}

struct ThumbnailSeriesRow: Codable, Equatable, Identifiable {
    static let titleCharacterLimit = 100

    var id: UUID
    var title: String
    var episode: String?
    /// The image the row uses once imported.
    var imageRef: ThumbnailSeriesImageRef?
    /// The image file name a CSV asked for; cleared once `imageRef` is set.
    var requestedImageName: String?
    /// Explicit output file stem; nil means "<series>-<episode or row number>".
    var outputName: String?
    /// 1-based CSV line the row came from (diagnostics only).
    var sourceLine: Int?
    /// A CSV record that could not be parsed; the row is kept so the user can
    /// fix it in place. Cleared as soon as the user edits the row.
    var importError: String?

    init(
        id: UUID = UUID(),
        title: String,
        episode: String? = nil,
        imageRef: ThumbnailSeriesImageRef? = nil,
        requestedImageName: String? = nil,
        outputName: String? = nil,
        sourceLine: Int? = nil,
        importError: String? = nil
    ) {
        self.id = id
        self.title = title
        self.episode = episode
        self.imageRef = imageRef
        self.requestedImageName = requestedImageName
        self.outputName = outputName
        self.sourceLine = sourceLine
        self.importError = importError
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, episode, imageRef, requestedImageName, outputName, sourceLine, importError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        episode = try container.decodeIfPresent(String.self, forKey: .episode)
        imageRef = try? container.decodeIfPresent(ThumbnailSeriesImageRef.self, forKey: .imageRef)
        requestedImageName = try container.decodeIfPresent(String.self, forKey: .requestedImageName)
        outputName = try container.decodeIfPresent(String.self, forKey: .outputName)
        sourceLine = try container.decodeIfPresent(Int.self, forKey: .sourceLine)
        importError = try container.decodeIfPresent(String.self, forKey: .importError)
    }

    /// Trimmed episode, nil when blank.
    var episodeValue: String? {
        guard let trimmed = episode?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

/// Where a series' source came from. Decodes unknown kinds as `.unknown`.
enum ThumbnailSeriesSourceOrigin: Codable, Equatable {
    case currentDesign(projectName: String)
    case personalTemplate(id: String, name: String)
    case unknown

    private enum CodingKeys: String, CodingKey { case kind, id, name }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        let name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        switch kind {
        case "currentDesign":
            self = .currentDesign(projectName: name)
        case "personalTemplate":
            self = .personalTemplate(id: try container.decodeIfPresent(String.self, forKey: .id) ?? "", name: name)
        default:
            self = .unknown
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .currentDesign(let projectName):
            try container.encode("currentDesign", forKey: .kind)
            try container.encode(projectName, forKey: .name)
        case let .personalTemplate(id, name):
            try container.encode("personalTemplate", forKey: .kind)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
        case .unknown:
            try container.encode("unknown", forKey: .kind)
        }
    }

    var displayName: String {
        switch self {
        case .currentDesign(let projectName):
            let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Current design" : "Current design · \(trimmed)"
        case .personalTemplate(_, let name):
            return "Template · \(name)"
        case .unknown:
            return "Saved source"
        }
    }
}

/// The frozen design every row is rendered from. Only `let` properties: the
/// only way to change it is to capture a new one (an explicit user action).
struct ThumbnailSeriesSource: Codable, Equatable {
    let capturedAt: Date
    let origin: ThumbnailSeriesSourceOrigin
    /// A FEATURE-05 personal template. Rows are rendered with
    /// `ThumbnailTemplate.instantiate(over:)`, so the template's slot policies
    /// (use project's / leave empty / keep template's) apply to every row.
    let template: ThumbnailTemplate
    /// What a row without its own image gets for "use project's" slots: the
    /// design that was open when the source was captured.
    let fallbackImageData: Data?
    let fallbackImageRecipe: ThumbnailImageFrameRecipe
    let fallbackProfile: ThumbnailDocumentProfile?
    let digest: String

    private enum CodingKeys: String, CodingKey {
        case capturedAt, origin, template, fallbackImageData, fallbackImageRecipe, fallbackProfile, digest
    }

    private init(
        capturedAt: Date,
        origin: ThumbnailSeriesSourceOrigin,
        template: ThumbnailTemplate,
        fallbackImageData: Data?,
        fallbackImageRecipe: ThumbnailImageFrameRecipe,
        fallbackProfile: ThumbnailDocumentProfile?
    ) {
        self.capturedAt = capturedAt
        self.origin = origin
        self.template = template
        self.fallbackImageData = fallbackImageData
        self.fallbackImageRecipe = fallbackImageRecipe
        self.fallbackProfile = fallbackProfile
        self.digest = Self.computeDigest(
            template: template,
            fallbackImageData: fallbackImageData,
            fallbackImageRecipe: fallbackImageRecipe,
            fallbackProfile: fallbackProfile
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        capturedAt = try container.decodeIfPresent(Date.self, forKey: .capturedAt) ?? Date(timeIntervalSince1970: 0)
        origin = (try? container.decodeIfPresent(ThumbnailSeriesSourceOrigin.self, forKey: .origin)) ?? .unknown
        template = try container.decode(ThumbnailTemplate.self, forKey: .template)
        fallbackImageData = try container.decodeIfPresent(Data.self, forKey: .fallbackImageData)
        fallbackImageRecipe = (try? container.decodeIfPresent(ThumbnailImageFrameRecipe.self, forKey: .fallbackImageRecipe)) ?? .identity
        fallbackProfile = try? container.decodeIfPresent(ThumbnailDocumentProfile.self, forKey: .fallbackProfile)
        let computed = Self.computeDigest(
            template: template,
            fallbackImageData: fallbackImageData,
            fallbackImageRecipe: fallbackImageRecipe,
            fallbackProfile: fallbackProfile
        )
        digest = try container.decodeIfPresent(String.self, forKey: .digest) ?? computed
    }

    /// Freezes the design that is open in the editor. Every image layer and
    /// the profile photo are kept with the source; the background photo and
    /// the headline are the per-row slots.
    static func currentDesign(
        _ document: ThumbnailDocument,
        projectName: String,
        now: Date = Date()
    ) -> ThumbnailSeriesSource {
        let now = wholeSeconds(now)
        let imageLayerIDs = Set(document.layers.compactMap { layer -> String? in
            if case .image = layer.content { return layer.id }
            return nil
        })
        let template = ThumbnailTemplate.capture(
            from: document,
            id: "series-source",
            name: projectName.isEmpty ? "Series source" : projectName,
            category: .youtube,
            retainedLayerIDs: imageLayerIDs,
            backgroundPolicy: .replaceFromProject,
            profilePolicy: .retained,
            titlePolicy: .replaceFromProject,
            now: now
        )
        return ThumbnailSeriesSource(
            capturedAt: now,
            origin: .currentDesign(projectName: projectName),
            template: template,
            fallbackImageData: document.imageData,
            fallbackImageRecipe: document.imageRecipe,
            fallbackProfile: document.profile
        )
    }

    /// Uses a saved personal template. The open design only supplies what the
    /// template itself asks the project for (background / profile).
    static func personalTemplate(
        _ template: ThumbnailTemplate,
        currentDocument: ThumbnailDocument,
        now: Date = Date()
    ) -> ThumbnailSeriesSource {
        ThumbnailSeriesSource(
            capturedAt: wholeSeconds(now),
            origin: .personalTemplate(id: template.id, name: template.name),
            template: template,
            fallbackImageData: currentDocument.imageData,
            fallbackImageRecipe: currentDocument.imageRecipe,
            fallbackProfile: currentDocument.profile
        )
    }

    var editorMode: ThumbnailDocumentEditorMode { template.document.editorMode }

    /// Stored dates are ISO 8601 (whole seconds); capturing on a whole second
    /// keeps a source equal to itself after a save / load round trip.
    static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    private static func computeDigest(
        template: ThumbnailTemplate,
        fallbackImageData: Data?,
        fallbackImageRecipe: ThumbnailImageFrameRecipe,
        fallbackProfile: ThumbnailDocumentProfile?
    ) -> String {
        struct Payload: Encodable {
            let template: ThumbnailTemplate
            let fallbackImage: String?
            let fallbackImageRecipe: ThumbnailImageFrameRecipe
            let fallbackProfile: ThumbnailDocumentProfile?
        }
        var stableTemplate = template
        stableTemplate.createdAt = Date(timeIntervalSince1970: 0)
        stableTemplate.updatedAt = Date(timeIntervalSince1970: 0)
        stableTemplate.document.updatedAt = Date(timeIntervalSince1970: 0)
        let payload = Payload(
            template: stableTemplate,
            fallbackImage: fallbackImageData.map(ThumbnailVariantAssetLibrary.digest),
            fallbackImageRecipe: fallbackImageRecipe,
            fallbackProfile: fallbackProfile
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = (try? encoder.encode(payload)) ?? Data()
        return ThumbnailVariantAssetLibrary.digest(data)
    }
}

/// The editable part of a series (small; saved on every table edit). The
/// source lives in its own file and is written only when captured.
struct ThumbnailSeries: Codable, Equatable {
    static let currentVersion = 1
    static let rowLimit = 100
    static let nameCharacterLimit = 60

    var version = currentVersion
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    /// Digest of the source these rows were last paired with.
    var sourceDigest: String?
    var rows: [ThumbnailSeriesRow]
    /// FEATURE-10 recipe last used to render this series.
    var exportRecipeID: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sourceDigest: String? = nil,
        rows: [ThumbnailSeriesRow] = [],
        exportRecipeID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceDigest = sourceDigest
        self.rows = rows
        self.exportRecipeID = exportRecipeID
    }

    private enum CodingKeys: String, CodingKey {
        case version, id, name, createdAt, updatedAt, sourceDigest, rows, exportRecipeID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        version = max(decodedVersion, Self.currentVersion)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Series"
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        sourceDigest = try container.decodeIfPresent(String.self, forKey: .sourceDigest)
        rows = try container.decodeIfPresent([ThumbnailSeriesRow].self, forKey: .rows) ?? []
        exportRecipeID = try? container.decodeIfPresent(UUID.self, forKey: .exportRecipeID)
    }

    static func cleanedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Series" }
        return String(trimmed.prefix(nameCharacterLimit))
    }
}
