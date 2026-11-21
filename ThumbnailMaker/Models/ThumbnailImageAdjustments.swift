//
//  ThumbnailImageAdjustments.swift
//  ThumbnailMaker
//
//  FEATURE-14: non-destructive photo adjustments. An adjustment is a
//  five-number RECIPE stored on a layer record; image bytes are never
//  touched. Reset writes `nil` back to the layer, so the document returns to
//  a value equal (and byte-identical when encoded) to the unadjusted one.
//
//  Blur is stored as a FRACTION of the rendered layer's shorter side, not in
//  points, so the small on-screen canvas and the full-size export show the
//  same amount of blur.
//

import CoreGraphics
import Foundation

struct ThumbnailImageAdjustments: Codable, Equatable, Sendable {
    static let brightnessRange: ClosedRange<Double> = -0.35...0.35
    static let contrastRange: ClosedRange<Double> = 0.50...1.60
    static let saturationRange: ClosedRange<Double> = 0.00...2.00
    static let blurRange: ClosedRange<Double> = 0.00...0.06
    static let vignetteRange: ClosedRange<Double> = 0.00...1.00

    /// Values closer than this to the neutral value snap to neutral, so slider
    /// round-off can never keep a "reset" recipe alive.
    static let neutralSnapTolerance = 1e-6

    /// Additive, neutral 0.
    var brightness: Double
    /// Multiplier, neutral 1.
    var contrast: Double
    /// Multiplier, neutral 1 (0 = greyscale).
    var saturation: Double
    /// Fraction of the rendered shorter side, neutral 0.
    var blur: Double
    /// Strength, neutral 0.
    var vignette: Double

    static let neutral = ThumbnailImageAdjustments()

    init(
        brightness: Double = 0,
        contrast: Double = 1,
        saturation: Double = 1,
        blur: Double = 0,
        vignette: Double = 0
    ) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.blur = blur
        self.vignette = vignette
    }

    var isNeutral: Bool { self == .neutral }

    // MARK: Codable (hardened against partial / corrupt JSON)

    private enum CodingKeys: String, CodingKey {
        case brightness, contrast, saturation, blur, vignette
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            brightness: (try? container.decodeIfPresent(Double.self, forKey: .brightness)) ?? 0,
            contrast: (try? container.decodeIfPresent(Double.self, forKey: .contrast)) ?? 1,
            saturation: (try? container.decodeIfPresent(Double.self, forKey: .saturation)) ?? 1,
            blur: (try? container.decodeIfPresent(Double.self, forKey: .blur)) ?? 0,
            vignette: (try? container.decodeIfPresent(Double.self, forKey: .vignette)) ?? 0
        )
        self = clamped()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(brightness, forKey: .brightness)
        try container.encode(contrast, forKey: .contrast)
        try container.encode(saturation, forKey: .saturation)
        try container.encode(blur, forKey: .blur)
        try container.encode(vignette, forKey: .vignette)
    }

    // MARK: Normalisation

    /// Non-finite values become neutral, everything is clamped into its
    /// declared range, and near-neutral values snap to exactly neutral.
    func clamped() -> ThumbnailImageAdjustments {
        ThumbnailImageAdjustments(
            brightness: Self.normalize(brightness, range: Self.brightnessRange, neutral: 0),
            contrast: Self.normalize(contrast, range: Self.contrastRange, neutral: 1),
            saturation: Self.normalize(saturation, range: Self.saturationRange, neutral: 1),
            blur: Self.normalize(blur, range: Self.blurRange, neutral: 0),
            vignette: Self.normalize(vignette, range: Self.vignetteRange, neutral: 0)
        )
    }

    mutating func reset() {
        self = .neutral
    }

    private static func normalize(_ value: Double, range: ClosedRange<Double>, neutral: Double) -> Double {
        guard value.isFinite else { return neutral }
        let clampedValue = min(range.upperBound, max(range.lowerBound, value))
        return abs(clampedValue - neutral) < neutralSnapTolerance ? neutral : clampedValue
    }

    // MARK: Rendering helpers (pure, unit-tested)

    /// Blur radius in points for a layer rendered at `size`. This is the
    /// preview/export parity mechanism: the same recipe yields a radius
    /// proportional to the rendered size.
    func blurRadius(forRenderedSize size: CGSize) -> CGFloat {
        guard blur > 0 else { return 0 }
        return CGFloat(blur) * max(0, min(size.width, size.height))
    }

    /// Where the vignette starts darkening, as a fraction of the half-diagonal.
    var vignetteStartFraction: Double { 0.45 }
    /// Where the vignette reaches full strength, as a fraction of the half-diagonal.
    var vignetteEndFraction: Double { 1.0 }
    /// Opacity of black at the vignette's outer edge.
    var vignetteOpacity: Double { min(0.85, max(0, vignette) * 0.85) }

    // MARK: Accessibility

    var accessibilitySummary: String {
        guard !isNeutral else { return "No adjustments" }
        return [
            "Brightness \(Self.signedPercent(brightness))",
            "contrast \(Self.percent(contrast))",
            "saturation \(Self.percent(saturation))",
            blur > 0 ? "blur \(Self.percent(blur / Self.blurRange.upperBound))" : "blur off",
            vignette > 0 ? "vignette \(Self.percent(vignette))" : "vignette off"
        ].joined(separator: ", ")
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    static func signedPercent(_ value: Double) -> String {
        let rounded = Int((value * 100).rounded())
        return rounded > 0 ? "+\(rounded)%" : "\(rounded)%"
    }
}

/// Which image an adjustment applies to. A separate type is needed because
/// `ThumbnailLayerSelection` cannot address the base photo.
enum ThumbnailAdjustmentTarget: Hashable, Identifiable {
    case baseImage
    case profileImage
    case contentLayer(String)

    var id: String { layerID }

    var layerID: String {
        switch self {
        case .baseImage:
            ThumbnailDocumentLayer.backgroundID
        case .profileImage:
            ThumbnailDocumentLayer.profileID
        case .contentLayer(let id):
            id
        }
    }

    init(layerID: String) {
        switch layerID {
        case ThumbnailDocumentLayer.backgroundID:
            self = .baseImage
        case ThumbnailDocumentLayer.profileID:
            self = .profileImage
        default:
            self = .contentLayer(layerID)
        }
    }
}

struct ThumbnailAdjustableImage: Identifiable, Equatable {
    let target: ThumbnailAdjustmentTarget
    let title: String

    var id: String { target.layerID }
}

extension Array where Element == ThumbnailDocumentLayer {
    func adjustments(forLayerID id: String) -> ThumbnailImageAdjustments {
        record(id: id)?.adjustments ?? .neutral
    }

    func adjustments(for target: ThumbnailAdjustmentTarget) -> ThumbnailImageAdjustments {
        adjustments(forLayerID: target.layerID)
    }

    /// The recipe to render, or nil for "draw the original untouched".
    func renderAdjustments(forLayerID id: String) -> ThumbnailImageAdjustments? {
        guard let adjustments = record(id: id)?.adjustments, !adjustments.isNeutral else { return nil }
        return adjustments
    }

    /// Clamps, normalises neutral to nil, and creates the singleton record if
    /// it is missing. Content layers are only updated in place (never appended).
    mutating func setAdjustments(_ adjustments: ThumbnailImageAdjustments, forLayerID id: String) {
        let next = adjustments.clamped()
        let stored: ThumbnailImageAdjustments? = next.isNeutral ? nil : next

        if let index = firstIndex(where: { $0.id == id }) {
            guard self[index].adjustments != stored else { return }
            self[index].adjustments = stored
            return
        }

        guard stored != nil else { return }
        var layer: ThumbnailDocumentLayer
        switch id {
        case ThumbnailDocumentLayer.backgroundID:
            layer = .defaultBackgroundLayer
        case ThumbnailDocumentLayer.profileID:
            layer = .defaultProfileLayer
        default:
            return
        }
        layer.adjustments = stored
        append(layer)
        sort { $0.zIndex < $1.zIndex }
    }

    mutating func setAdjustments(_ adjustments: ThumbnailImageAdjustments, for target: ThumbnailAdjustmentTarget) {
        setAdjustments(adjustments, forLayerID: target.layerID)
    }

    mutating func resetAdjustments(forLayerID id: String) {
        setAdjustments(.neutral, forLayerID: id)
    }

    mutating func applyLook(_ look: ThumbnailLook, toLayerID id: String) {
        setAdjustments(look.adjustments, forLayerID: id)
    }

    func canAdjustLayer(id: String, hasBaseImage: Bool, hasProfileImage: Bool) -> Bool {
        switch id {
        case ThumbnailDocumentLayer.backgroundID:
            return hasBaseImage
        case ThumbnailDocumentLayer.profileID:
            return hasProfileImage
        case ThumbnailDocumentLayer.textID:
            return false
        default:
            guard let layer = record(id: id), case .image = layer.content else { return false }
            return true
        }
    }

    /// Every image the user can adjust, back to front.
    func adjustableImages(hasBaseImage: Bool, hasProfileImage: Bool) -> [ThumbnailAdjustableImage] {
        var result: [ThumbnailAdjustableImage] = []
        if hasBaseImage {
            result.append(ThumbnailAdjustableImage(target: .baseImage, title: "Photo"))
        }
        let others = filter { layer in
            layer.id != ThumbnailDocumentLayer.backgroundID
                && canAdjustLayer(id: layer.id, hasBaseImage: hasBaseImage, hasProfileImage: hasProfileImage)
        }
        .sorted { $0.zIndex < $1.zIndex }
        for layer in others {
            let target = ThumbnailAdjustmentTarget(layerID: layer.id)
            let fallback = target == .profileImage ? "Profile" : "Image"
            result.append(ThumbnailAdjustableImage(
                target: target,
                title: layer.name.isEmpty ? fallback : layer.name
            ))
        }
        if hasProfileImage, !result.contains(where: { $0.target == .profileImage }) {
            result.append(ThumbnailAdjustableImage(target: .profileImage, title: "Profile"))
        }
        return result
    }
}
