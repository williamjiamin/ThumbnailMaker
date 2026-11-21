//
//  ThumbnailCutoutMask.swift
//  ThumbnailMaker
//
//  FEATURE-11: non-destructive cutout. A cutout is a RECIPE stored on the
//  layer record (the same place FEATURE-14 keeps photo adjustments): an
//  optional automatic subject mask, a list of erase/restore brush strokes and
//  a feather amount. The layer's image bytes are NEVER rewritten; the mask is
//  composited at render time (ThumbnailCutoutMaskRenderer), so "Reset" always
//  returns the untouched original.
//
//  Coordinate conventions (load-bearing):
//  - Points are normalized IMAGE space with a TOP-LEFT origin, 0...1 on each
//    axis, in the image's DISPLAY orientation (EXIF orientation applied).
//    Vision's normalized rects are bottom-left; never mix the two.
//  - Radius and feather are fractions of the image's LONG side, so a brush
//    keeps its size relative to the photo at any resolution.
//
//  Foundation only (no UIKit), so the recipe is pure and fast to test.
//

import Foundation

struct ThumbnailCutoutPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    func clamped() -> ThumbnailCutoutPoint {
        ThumbnailCutoutPoint(
            x: ThumbnailCutoutMask.clamp(x, to: 0...1, fallback: 0.5),
            y: ThumbnailCutoutMask.clamp(y, to: 0...1, fallback: 0.5)
        )
    }
}

struct ThumbnailCutoutStroke: Codable, Equatable, Identifiable, Sendable {
    enum Mode: String, Codable, Sendable, CaseIterable {
        case erase
        case restore
    }

    var id: String
    /// Stored as a string so an unknown future mode decodes (as erase).
    var modeRawValue: String
    /// At least one point; a single point is a dab.
    var points: [ThumbnailCutoutPoint]
    /// Fraction of the image's long side.
    var radius: Double
    /// 0 = hard edge, 1 = fully feathered dab.
    var softness: Double
    /// Flow, 0...1.
    var opacity: Double

    init(
        id: String = UUID().uuidString,
        mode: Mode,
        points: [ThumbnailCutoutPoint],
        radius: Double,
        softness: Double = 0.35,
        opacity: Double = 1
    ) {
        self.id = id
        self.modeRawValue = mode.rawValue
        self.points = points
        self.radius = radius
        self.softness = softness
        self.opacity = opacity
    }

    var mode: Mode {
        get { Mode(rawValue: modeRawValue) ?? .erase }
        set { modeRawValue = newValue.rawValue }
    }

    func clamped() -> ThumbnailCutoutStroke {
        var copy = self
        copy.points = points.map { $0.clamped() }
        copy.radius = ThumbnailCutoutMask.clamp(
            radius,
            to: ThumbnailCutoutMask.radiusLimits,
            fallback: ThumbnailCutoutMask.defaultRadius
        )
        copy.softness = ThumbnailCutoutMask.clamp(softness, to: ThumbnailCutoutMask.softnessLimits, fallback: 0)
        copy.opacity = ThumbnailCutoutMask.clamp(opacity, to: 0...1, fallback: 1)
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case id, mode, points, radius, softness, opacity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        modeRawValue = (try? container.decodeIfPresent(String.self, forKey: .mode)) ?? Mode.erase.rawValue
        points = (try? container.decodeIfPresent([ThumbnailCutoutPoint].self, forKey: .points)) ?? []
        radius = (try? container.decodeIfPresent(Double.self, forKey: .radius)) ?? ThumbnailCutoutMask.defaultRadius
        softness = (try? container.decodeIfPresent(Double.self, forKey: .softness)) ?? 0
        opacity = (try? container.decodeIfPresent(Double.self, forKey: .opacity)) ?? 1
        self = clamped()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(modeRawValue, forKey: .mode)
        try container.encode(points, forKey: .points)
        try container.encode(radius, forKey: .radius)
        try container.encode(softness, forKey: .softness)
        try container.encode(opacity, forKey: .opacity)
    }
}

/// The automatic subject mask (Vision). Stored SEPARATELY from the image bytes.
struct ThumbnailCutoutAutomaticBase: Codable, Equatable, Sendable {
    /// Assigned at generation. Cheap identity for cache keys, so nothing ever
    /// hashes the PNG payload.
    var id: String
    /// 8-bit grayscale PNG, white = keep, black = drop.
    var maskPNGData: Data
    var pixelWidth: Int
    var pixelHeight: Int
    /// Display-space pixel size of the image the mask was generated from.
    var sourcePixelWidth: Int
    var sourcePixelHeight: Int

    init(
        id: String = UUID().uuidString,
        maskPNGData: Data,
        pixelWidth: Int,
        pixelHeight: Int,
        sourcePixelWidth: Int,
        sourcePixelHeight: Int
    ) {
        self.id = id
        self.maskPNGData = maskPNGData
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.sourcePixelWidth = sourcePixelWidth
        self.sourcePixelHeight = sourcePixelHeight
    }
}

struct ThumbnailCutoutMask: Codable, Equatable, Sendable {
    static let maxAutomaticMaskDimension: Double = 2048
    static let radiusLimits: ClosedRange<Double> = 0.002...0.5
    static let softnessLimits: ClosedRange<Double> = 0...1
    static let featherLimits: ClosedRange<Double> = 0...0.08
    static let defaultRadius = 0.05
    /// Hard cap so a corrupt or runaway draft can never make rasterizing unbounded.
    static let maxStrokeCount = 2_000
    static let maxPointsPerStroke = 4_000

    /// Before/after: false renders the untouched original.
    var isEnabled: Bool
    /// nil = fully opaque base, so brush-only cutouts work with no Vision.
    var automaticBase: ThumbnailCutoutAutomaticBase?
    var strokes: [ThumbnailCutoutStroke]
    /// Gaussian radius as a fraction of the long side, applied once, last.
    var feather: Double
    /// Display-space pixel size of the image this recipe was authored for.
    /// 0 = unknown (treated as compatible). A recipe whose size no longer
    /// matches the layer's image is inert: the original renders.
    var sourcePixelWidth: Int
    var sourcePixelHeight: Int

    init(
        isEnabled: Bool = true,
        automaticBase: ThumbnailCutoutAutomaticBase? = nil,
        strokes: [ThumbnailCutoutStroke] = [],
        feather: Double = 0,
        sourcePixelWidth: Int = 0,
        sourcePixelHeight: Int = 0
    ) {
        self.isEnabled = isEnabled
        self.automaticBase = automaticBase
        self.strokes = strokes
        self.feather = feather
        self.sourcePixelWidth = sourcePixelWidth
        self.sourcePixelHeight = sourcePixelHeight
    }

    static let empty = ThumbnailCutoutMask()

    /// No base, no strokes, no feather: renders exactly the original.
    var isIdentity: Bool {
        automaticBase == nil && strokes.isEmpty && feather == 0
    }

    /// True when the renderer must do work.
    var isActive: Bool {
        isEnabled && !isIdentity
    }

    /// O(strokes) cache identity. NEVER hashes image or mask bytes.
    var fingerprint: String {
        var parts: [String] = [
            isEnabled ? "on" : "off",
            automaticBase.map { "b:\($0.id):\($0.pixelWidth)x\($0.pixelHeight)" } ?? "b:none",
            "f:\(Self.rounded(feather))",
            "s:\(sourcePixelWidth)x\(sourcePixelHeight)"
        ]
        for stroke in strokes {
            var strokeHasher = Hasher()
            for point in stroke.points {
                strokeHasher.combine(Self.rounded(point.x))
                strokeHasher.combine(Self.rounded(point.y))
            }
            parts.append(
                "\(stroke.id):\(stroke.modeRawValue):\(Self.rounded(stroke.radius)):\(Self.rounded(stroke.softness)):\(Self.rounded(stroke.opacity)):\(stroke.points.count):\(strokeHasher.finalize())"
            )
        }
        return parts.joined(separator: "|")
    }

    func isCompatible(withSourcePixelWidth width: Int, height: Int) -> Bool {
        let recipeMatches = (sourcePixelWidth == 0 && sourcePixelHeight == 0)
            || (sourcePixelWidth == width && sourcePixelHeight == height)
        let baseMatches = automaticBase.map {
            $0.sourcePixelWidth == width && $0.sourcePixelHeight == height
        } ?? true
        return recipeMatches && baseMatches
    }

    func clamped() -> ThumbnailCutoutMask {
        var copy = self
        copy.feather = Self.clamp(feather, to: Self.featherLimits, fallback: 0)
        copy.strokes = strokes
            .prefix(Self.maxStrokeCount)
            .map { stroke -> ThumbnailCutoutStroke in
                var bounded = stroke.clamped()
                if bounded.points.count > Self.maxPointsPerStroke {
                    bounded.points = Array(bounded.points.prefix(Self.maxPointsPerStroke))
                }
                return bounded
            }
            .filter { !$0.points.isEmpty }
        copy.sourcePixelWidth = max(0, sourcePixelWidth)
        copy.sourcePixelHeight = max(0, sourcePixelHeight)
        if let base = automaticBase,
           base.pixelWidth <= 0 || base.pixelHeight <= 0 || base.maskPNGData.isEmpty {
            copy.automaticBase = nil
        }
        return copy
    }

    /// Value semantics already isolate copies; fresh stroke ids make a
    /// duplicated layer's strokes provably distinct too.
    func independentCopy() -> ThumbnailCutoutMask {
        var copy = self
        copy.strokes = strokes.map { stroke in
            var fresh = stroke
            fresh.id = UUID().uuidString
            return fresh
        }
        return copy
    }

    mutating func appendStroke(_ stroke: ThumbnailCutoutStroke) {
        let bounded = stroke.clamped()
        guard !bounded.points.isEmpty, strokes.count < Self.maxStrokeCount else { return }
        strokes.append(bounded)
    }

    @discardableResult
    mutating func removeLastStroke() -> ThumbnailCutoutStroke? {
        strokes.popLast()
    }

    mutating func clearStrokes() {
        strokes.removeAll()
    }

    /// Back to the untouched original (keeps the authoring size).
    mutating func reset() {
        automaticBase = nil
        strokes = []
        feather = 0
        isEnabled = true
    }

    // MARK: Codable (never throws on bad values; clamps at the end)

    private enum CodingKeys: String, CodingKey {
        case isEnabled, automaticBase, strokes, feather, sourcePixelWidth, sourcePixelHeight
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = .empty
            return
        }
        isEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? true
        automaticBase = (try? container.decodeIfPresent(ThumbnailCutoutAutomaticBase.self, forKey: .automaticBase)) ?? nil
        strokes = (try? container.decodeIfPresent([ThumbnailCutoutStroke].self, forKey: .strokes)) ?? []
        feather = (try? container.decodeIfPresent(Double.self, forKey: .feather)) ?? 0
        sourcePixelWidth = (try? container.decodeIfPresent(Int.self, forKey: .sourcePixelWidth)) ?? 0
        sourcePixelHeight = (try? container.decodeIfPresent(Int.self, forKey: .sourcePixelHeight)) ?? 0
        self = clamped()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(automaticBase, forKey: .automaticBase)
        try container.encode(strokes, forKey: .strokes)
        try container.encode(feather, forKey: .feather)
        try container.encode(sourcePixelWidth, forKey: .sourcePixelWidth)
        try container.encode(sourcePixelHeight, forKey: .sourcePixelHeight)
    }

    // MARK: Helpers

    static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    private static func rounded(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int((value * 10_000).rounded())
    }

    var accessibilitySummary: String {
        guard isActive else { return isIdentity ? "No cutout" : "Cutout hidden" }
        var parts: [String] = []
        if automaticBase != nil { parts.append("automatic subject") }
        let erased = strokes.filter { $0.mode == .erase }.count
        let restored = strokes.count - erased
        if erased > 0 { parts.append("\(erased) erase stroke\(erased == 1 ? "" : "s")") }
        if restored > 0 { parts.append("\(restored) restore stroke\(restored == 1 ? "" : "s")") }
        if feather > 0 { parts.append("feather \(Int((feather / Self.featherLimits.upperBound * 100).rounded()))%") }
        return "Cutout: " + parts.joined(separator: ", ")
    }
}

/// Which image a cutout applies to. Reuses FEATURE-14's target so the base
/// photo (which `ThumbnailLayerSelection` cannot address) is reachable.
typealias ThumbnailCutoutTarget = ThumbnailAdjustmentTarget

extension Array where Element == ThumbnailDocumentLayer {
    func cutout(forLayerID id: String) -> ThumbnailCutoutMask? {
        record(id: id)?.cutout
    }

    /// Mutates the layer's cutout recipe. Materializes an empty recipe when
    /// there is none, and drops an identity recipe back to nil so a no-op
    /// session leaves the document exactly equal. Creates the background
    /// record if it is missing; content layers are only updated in place.
    /// Never touches image bytes.
    mutating func updateCutout(id: String, mutate: (inout ThumbnailCutoutMask) -> Void) {
        let existing = firstIndex(where: { $0.id == id })
        var mask = existing.flatMap { self[$0].cutout } ?? .empty
        mutate(&mask)
        mask = mask.clamped()
        let stored: ThumbnailCutoutMask? = mask.isIdentity ? nil : mask

        if let index = existing {
            guard self[index].cutout != stored else { return }
            self[index].cutout = stored
            return
        }

        guard stored != nil, id == ThumbnailDocumentLayer.backgroundID else { return }
        var layer = ThumbnailDocumentLayer.defaultBackgroundLayer
        layer.cutout = stored
        append(layer)
        sort { $0.zIndex < $1.zIndex }
    }

    mutating func setCutout(_ mask: ThumbnailCutoutMask?, forLayerID id: String) {
        updateCutout(id: id) { current in
            current = mask ?? .empty
        }
    }

    @discardableResult
    mutating func appendCutoutStroke(_ stroke: ThumbnailCutoutStroke, toLayerID id: String) -> Bool {
        let before = cutout(forLayerID: id)?.strokes.count ?? 0
        updateCutout(id: id) { $0.appendStroke(stroke) }
        return (cutout(forLayerID: id)?.strokes.count ?? 0) > before
    }

    @discardableResult
    mutating func removeLastCutoutStroke(fromLayerID id: String) -> ThumbnailCutoutStroke? {
        guard cutout(forLayerID: id)?.strokes.isEmpty == false else { return nil }
        var removed: ThumbnailCutoutStroke?
        updateCutout(id: id) { removed = $0.removeLastStroke() }
        return removed
    }

    mutating func resetCutout(forLayerID id: String) {
        setCutout(nil, forLayerID: id)
    }

    mutating func setCutoutEnabled(_ isEnabled: Bool, forLayerID id: String) {
        guard cutout(forLayerID: id) != nil else { return }
        updateCutout(id: id) { $0.isEnabled = isEnabled }
    }

    mutating func setCutoutFeather(_ feather: Double, forLayerID id: String) {
        updateCutout(id: id) { $0.feather = feather }
    }

    mutating func setAutomaticCutoutBase(_ base: ThumbnailCutoutAutomaticBase?, forLayerID id: String) {
        updateCutout(id: id) { mask in
            mask.automaticBase = base
            if let base {
                mask.sourcePixelWidth = base.sourcePixelWidth
                mask.sourcePixelHeight = base.sourcePixelHeight
                mask.isEnabled = true
            }
        }
    }
}
