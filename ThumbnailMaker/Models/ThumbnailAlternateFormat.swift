//
//  ThumbnailAlternateFormat.swift
//  ThumbnailMaker
//
//  FEATURE-09: one design, several sizes. An alternate format stores only
//  what may differ from the original design: the canvas kind, its own image
//  frame recipe, per-layer geometry, per-size hidden layers and any text the
//  user explicitly unlinked. Everything else (image bytes, colours, fonts,
//  styles, adjustments) is read from the original at render time, so the
//  sizes stay linked. Stored inside `ThumbnailDocument.formats`, so history,
//  autosave, variants, projects and packages carry it with no extra code.
//

import CoreGraphics
import Foundation

enum ThumbnailFormatKind: String, Codable, CaseIterable, Identifiable, Equatable {
    case landscape
    case square
    case vertical

    var id: String { rawValue }

    var aspectRatio: AspectRatio {
        switch self {
        case .landscape: .ratio16_9
        case .square: .ratio1_1
        case .vertical: .ratio9_16
        }
    }

    var preset: ThumbnailExportPreset {
        switch self {
        case .landscape: .youTubeThumbnail
        case .square: .instagramSquare
        case .vertical: .shortFormCover
        }
    }

    var presetID: String { preset.id }

    var displayName: String {
        switch self {
        case .landscape: "Landscape 16:9"
        case .square: "Square 1:1"
        case .vertical: "Vertical 9:16"
        }
    }

    var shortName: String {
        switch self {
        case .landscape: "16:9"
        case .square: "1:1"
        case .vertical: "9:16"
        }
    }

    var systemImage: String {
        switch self {
        case .landscape: "rectangle"
        case .square: "square"
        case .vertical: "rectangle.portrait"
        }
    }

    /// The kind that matches an original canvas ratio. That kind is never
    /// offered as an alternate size because it would duplicate the original.
    static func kind(for ratio: AspectRatio) -> ThumbnailFormatKind? {
        allCases.first { $0.aspectRatio == ratio }
    }

    /// Reference canvas used by the pure reflow / clipping maths.
    var canvasSize: CGSize {
        let dimensions = aspectRatio.dimensions
        return CGSize(width: dimensions.width, height: dimensions.height)
    }
}

/// Size-dependent geometry of one layer. Which fields are used depends on the
/// layer: text/profile/image use `size`, shapes use `width`/`height`.
struct ThumbnailLayerGeometry: Codable, Equatable {
    static let profileSizeLimits: ClosedRange<CGFloat> = 0.1...0.3

    var transform: ThumbnailOverlayTransform
    var size: Double?
    var width: Double?
    var height: Double?

    init(
        transform: ThumbnailOverlayTransform,
        size: Double? = nil,
        width: Double? = nil,
        height: Double? = nil
    ) {
        self.transform = transform
        self.size = size
        self.width = width
        self.height = height
    }

    private enum CodingKeys: String, CodingKey {
        case transform, size, width, height
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transform = (try? container.decodeIfPresent(ThumbnailOverlayTransform.self, forKey: .transform)) ?? .centered
        size = try? container.decodeIfPresent(Double.self, forKey: .size)
        width = try? container.decodeIfPresent(Double.self, forKey: .width)
        height = try? container.decodeIfPresent(Double.self, forKey: .height)
    }

    /// Reads the geometry of `layerID` from `document`, or nil when the layer
    /// is not present (or has no geometry, like the background).
    static func extract(layerID: String, from document: ThumbnailDocument) -> ThumbnailLayerGeometry? {
        switch layerID {
        case ThumbnailDocumentLayer.backgroundID:
            return nil
        case ThumbnailDocumentLayer.textID:
            guard !document.text.value.isEmpty else { return nil }
            return ThumbnailLayerGeometry(transform: document.text.transform, size: document.text.size)
        case ThumbnailDocumentLayer.profileID:
            guard let profile = document.profile else { return nil }
            return ThumbnailLayerGeometry(transform: profile.transform, size: profile.size)
        default:
            switch document.layers.record(id: layerID)?.content {
            case .image(let content):
                return ThumbnailLayerGeometry(transform: content.transform, size: content.size)
            case .text(let content):
                return ThumbnailLayerGeometry(transform: content.transform, size: content.size)
            case .shape(let content):
                return ThumbnailLayerGeometry(transform: content.transform, width: content.width, height: content.height)
            case nil:
                return nil
            }
        }
    }

    /// Writes this geometry into `layerID`, clamped through the same limits
    /// the editor uses. Missing fields keep the document's current value.
    func apply(to document: inout ThumbnailDocument, layerID: String) {
        let transform = Self.sanitized(transform)
        switch layerID {
        case ThumbnailDocumentLayer.backgroundID:
            return
        case ThumbnailDocumentLayer.textID:
            document.text.transform = transform
            document.text.size = Self.clamped(size, fallback: document.text.size, limits: ContentLayerCanvasGeometry.textSizeLimits)
        case ThumbnailDocumentLayer.profileID:
            guard var profile = document.profile else { return }
            profile.transform = transform
            profile.size = Self.clamped(size, fallback: profile.size, limits: Self.profileSizeLimits)
            document.profile = profile
        default:
            guard let index = document.layers.firstIndex(where: { $0.id == layerID }) else { return }
            switch document.layers[index].content {
            case .image(var content):
                content.transform = transform
                content.size = Self.clamped(size, fallback: content.size, limits: ContentLayerCanvasGeometry.imageSizeLimits)
                document.layers[index].content = .image(content)
            case .text(var content):
                content.transform = transform
                content.size = Self.clamped(size, fallback: content.size, limits: ContentLayerCanvasGeometry.textSizeLimits)
                document.layers[index].content = .text(content)
            case .shape(var content):
                content.transform = transform
                content.width = Self.clamped(width, fallback: content.width, limits: ContentLayerCanvasGeometry.shapeWidthLimits)
                content.height = Self.clamped(height, fallback: content.height, limits: ContentLayerCanvasGeometry.shapeHeightLimits)
                document.layers[index].content = .shape(content)
            case nil:
                return
            }
        }
    }

    static func sanitized(_ transform: ThumbnailOverlayTransform) -> ThumbnailOverlayTransform {
        var result = transform
        result.x = clampedPosition(transform.x)
        result.y = clampedPosition(transform.y)
        result.rotationDegrees = transform.rotationDegrees.isFinite ? transform.rotationDegrees : 0
        return result
    }

    static func clampedPosition(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0.5 }
        return min(0.95, max(0.05, value))
    }

    static func clamped(_ value: Double?, fallback: Double, limits: ClosedRange<CGFloat>) -> Double {
        let candidate = (value?.isFinite == true ? value : nil) ?? fallback
        let safe = candidate.isFinite ? candidate : Double(limits.lowerBound)
        return min(Double(limits.upperBound), max(Double(limits.lowerBound), safe))
    }
}

struct ThumbnailAlternateFormat: Codable, Equatable, Identifiable {
    static let currentReflowVersion = 1

    var kind: ThumbnailFormatKind
    var createdAt: Date
    var reflowVersion: Int
    var imageRecipe: ThumbnailImageFrameRecipe
    /// Geometry per original layer id. Ids that no longer exist in the
    /// original are ignored; layers added later are reflowed on the fly.
    var layout: [String: ThumbnailLayerGeometry]
    /// Layers hidden in this size only (never in the original).
    var hiddenLayerIDs: [String]
    /// Text the user explicitly unlinked from the original, per layer id.
    var detachedText: [String: String]

    var id: String { kind.rawValue }

    init(
        kind: ThumbnailFormatKind,
        createdAt: Date = Date(),
        reflowVersion: Int = ThumbnailAlternateFormat.currentReflowVersion,
        imageRecipe: ThumbnailImageFrameRecipe = .identity,
        layout: [String: ThumbnailLayerGeometry] = [:],
        hiddenLayerIDs: [String] = [],
        detachedText: [String: String] = [:]
    ) {
        self.kind = kind
        self.createdAt = createdAt
        self.reflowVersion = reflowVersion
        self.imageRecipe = imageRecipe
        self.layout = layout
        self.hiddenLayerIDs = hiddenLayerIDs
        self.detachedText = detachedText
    }

    func isHidden(_ layerID: String) -> Bool {
        hiddenLayerIDs.contains(layerID)
    }

    func isTextDetached(_ layerID: String) -> Bool {
        detachedText[layerID] != nil
    }

    private enum CodingKeys: String, CodingKey {
        case kindRawValue, createdAt, reflowVersion, imageRecipe, layout, hiddenLayerIDs, detachedText
    }

    enum DecodingFailure: Error {
        case unknownKind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = try container.decodeIfPresent(String.self, forKey: .kindRawValue)
        guard let kind = rawKind.flatMap(ThumbnailFormatKind.init(rawValue:)) else {
            throw DecodingFailure.unknownKind
        }
        self.kind = kind
        createdAt = (try? container.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date(timeIntervalSince1970: 0)
        reflowVersion = (try? container.decodeIfPresent(Int.self, forKey: .reflowVersion)) ?? Self.currentReflowVersion
        imageRecipe = (try? container.decodeIfPresent(ThumbnailImageFrameRecipe.self, forKey: .imageRecipe)) ?? .identity
        layout = (try? container.decodeIfPresent([String: ThumbnailLayerGeometry].self, forKey: .layout)) ?? [:]
        hiddenLayerIDs = Array(Set((try? container.decodeIfPresent([String].self, forKey: .hiddenLayerIDs)) ?? [])).sorted()
        detachedText = (try? container.decodeIfPresent([String: String].self, forKey: .detachedText)) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind.rawValue, forKey: .kindRawValue)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(reflowVersion, forKey: .reflowVersion)
        try container.encode(imageRecipe, forKey: .imageRecipe)
        try container.encode(layout, forKey: .layout)
        try container.encode(hiddenLayerIDs, forKey: .hiddenLayerIDs)
        try container.encode(detachedText, forKey: .detachedText)
    }
}

struct ThumbnailFormatSet: Codable, Equatable {
    static let maximumCount = ThumbnailFormatKind.allCases.count

    private(set) var formats: [ThumbnailAlternateFormat]

    init(formats: [ThumbnailAlternateFormat] = []) {
        self.formats = formats
        self = normalized()
    }

    var isEmpty: Bool { formats.isEmpty }
    var nilIfEmpty: ThumbnailFormatSet? { formats.isEmpty ? nil : self }

    func format(id: String) -> ThumbnailAlternateFormat? {
        formats.first { $0.id == id }
    }

    func contains(_ kind: ThumbnailFormatKind) -> Bool {
        formats.contains { $0.kind == kind }
    }

    /// Deduplicates kinds (first wins), caps the count and sorts by kind.
    func normalized() -> ThumbnailFormatSet {
        var seen = Set<ThumbnailFormatKind>()
        var unique: [ThumbnailAlternateFormat] = []
        for format in formats where !seen.contains(format.kind) {
            seen.insert(format.kind)
            unique.append(format)
        }
        let order = ThumbnailFormatKind.allCases
        unique.sort { (order.firstIndex(of: $0.kind) ?? 0) < (order.firstIndex(of: $1.kind) ?? 0) }
        return ThumbnailFormatSet(uncheckedFormats: Array(unique.prefix(Self.maximumCount)))
    }

    @discardableResult
    mutating func insert(_ format: ThumbnailAlternateFormat) -> Bool {
        guard !contains(format.kind) else { return false }
        formats.append(format)
        self = normalized()
        return true
    }

    @discardableResult
    mutating func replace(_ format: ThumbnailAlternateFormat) -> Bool {
        guard let index = formats.firstIndex(where: { $0.id == format.id }) else { return false }
        formats[index] = format
        return true
    }

    @discardableResult
    mutating func remove(id: String) -> Bool {
        let before = formats.count
        formats.removeAll { $0.id == id }
        return formats.count != before
    }

    private init(uncheckedFormats: [ThumbnailAlternateFormat]) {
        self.formats = uncheckedFormats
    }

    // Codable: unknown / corrupt entries are dropped, never fatal.
    private enum CodingKeys: String, CodingKey {
        case formats
    }

    private struct LossyFormat: Decodable {
        let value: ThumbnailAlternateFormat?
        init(from decoder: Decoder) throws {
            value = try? ThumbnailAlternateFormat(from: decoder)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lossy = (try? container.decodeIfPresent([LossyFormat].self, forKey: .formats)) ?? []
        self.init(uncheckedFormats: lossy.compactMap(\.value))
        self = normalized()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formats, forKey: .formats)
    }
}

extension ThumbnailDocument {
    /// The design without its alternate sizes: what the original renders and
    /// what a personal template should capture.
    func removingFormats() -> ThumbnailDocument {
        var copy = self
        copy.formats = nil
        return copy
    }

    /// Ids of layers that carry size-dependent geometry, in z order.
    var formatGeometryLayerIDs: [String] {
        layers
            .filter { $0.kind != .background }
            .filter { ThumbnailLayerGeometry.extract(layerID: $0.id, from: self) != nil }
            .map(\.id)
    }

    var formatKindsAvailableToAdd: [ThumbnailFormatKind] {
        let own = AspectRatio(rawValue: canvas.aspectRatioRawValue).flatMap(ThumbnailFormatKind.kind(for:))
        return ThumbnailFormatKind.allCases.filter { kind in
            kind != own && !(formats?.contains(kind) ?? false)
        }
    }
}
