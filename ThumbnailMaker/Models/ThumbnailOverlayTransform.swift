//
//  ThumbnailOverlayTransform.swift
//  ThumbnailMaker
//

import CoreGraphics
import Foundation

struct CenterSnapGuide: OptionSet, Equatable {
    let rawValue: Int

    static let xCentered = CenterSnapGuide(rawValue: 1 << 0)
    static let yCentered = CenterSnapGuide(rawValue: 1 << 1)
}

struct ThumbnailOverlayTransform: Codable, Equatable {
    static let snapThreshold: CGFloat = 0.03
    /// Allowed range for a normalized centre (FEATURE-07 exposes it for arrange).
    static let centerRange: ClosedRange<CGFloat> = 0.05...0.95

    var x: CGFloat
    var y: CGFloat
    var rotationDegrees: Double
    var isFlippedHorizontally: Bool

    init(
        x: CGFloat = 0.5,
        y: CGFloat = 0.5,
        rotationDegrees: Double = 0,
        isFlippedHorizontally: Bool = false
    ) {
        self.x = x
        self.y = y
        self.rotationDegrees = rotationDegrees
        self.isFlippedHorizontally = isFlippedHorizontally
    }

    static let centered = ThumbnailOverlayTransform()
    static let profileDefault = ThumbnailOverlayTransform(x: 0.84, y: 0.18)

    mutating func move(by translation: CGSize, in canvasSize: CGSize) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }

        x = Self.clamped(x + translation.width / canvasSize.width)
        y = Self.clamped(y + translation.height / canvasSize.height)
    }

    mutating func moveWithSnap(by translation: CGSize, in canvasSize: CGSize) {
        let position = Self.normalizedPosition(
            x: x,
            y: y,
            translation: translation,
            in: canvasSize,
            snapping: true
        )
        x = position.x
        y = position.y
    }

    mutating func rotate(by degrees: Double) {
        rotationDegrees = Self.normalizedRotation(rotationDegrees + degrees)
    }

    mutating func flipHorizontally() {
        isFlippedHorizontally.toggle()
    }

    mutating func reset(to transform: ThumbnailOverlayTransform = .centered) {
        self = transform
    }

    static func adjustedOverlaySize(
        _ size: CGFloat,
        by translation: CGSize,
        in canvasSize: CGSize,
        limits: ClosedRange<CGFloat>
    ) -> CGFloat {
        let shortestSide = min(canvasSize.width, canvasSize.height)
        guard shortestSide > 0 else { return clamped(size, in: limits) }

        let delta = ((translation.width + translation.height) / shortestSide) * 0.05
        return clamped(size + delta, in: limits)
    }

    static func snapped(_ value: CGFloat, threshold: CGFloat = snapThreshold) -> CGFloat {
        isWithinSnapThreshold(value, threshold: threshold) ? 0.5 : value
    }

    static func centerSnapGuide(
        forNormalized x: CGFloat,
        y: CGFloat,
        threshold: CGFloat = snapThreshold
    ) -> CenterSnapGuide {
        var guide: CenterSnapGuide = []
        if isWithinSnapThreshold(x, threshold: threshold) {
            guide.insert(.xCentered)
        }
        if isWithinSnapThreshold(y, threshold: threshold) {
            guide.insert(.yCentered)
        }
        return guide
    }

    static func centerSnapGuide(
        for transform: ThumbnailOverlayTransform,
        translation: CGSize,
        in canvasSize: CGSize
    ) -> CenterSnapGuide {
        let position = normalizedPosition(
            x: transform.x,
            y: transform.y,
            translation: translation,
            in: canvasSize,
            snapping: false
        )
        return centerSnapGuide(forNormalized: position.x, y: position.y)
    }

    static func normalizedPosition(
        x: CGFloat,
        y: CGFloat,
        translation: CGSize,
        in canvasSize: CGSize,
        snapping: Bool
    ) -> CGPoint {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return CGPoint(x: clamped(x), y: clamped(y))
        }

        let rawX = clamped(x + translation.width / canvasSize.width)
        let rawY = clamped(y + translation.height / canvasSize.height)
        return CGPoint(
            x: clamped(snapping ? snapped(rawX) : rawX),
            y: clamped(snapping ? snapped(rawY) : rawY)
        )
    }

    static func rotationDelta(
        from startLocation: CGPoint,
        to currentLocation: CGPoint,
        around center: CGPoint
    ) -> Double {
        let startAngle = atan2(
            startLocation.y - center.y,
            startLocation.x - center.x
        )
        let currentAngle = atan2(
            currentLocation.y - center.y,
            currentLocation.x - center.x
        )
        return normalizedRotation((currentAngle - startAngle) * 180 / .pi)
    }

    var positionDescription: String {
        "\(Int(round(x * 100)))%, \(Int(round(y * 100)))%"
    }

    func canvasStateDescription(size: CGFloat? = nil) -> String {
        var components = [
            positionDescription,
            "\(Int(round(rotationDegrees))) degrees",
            isFlippedHorizontally ? "flipped" : "not flipped"
        ]

        if let size {
            components.append("size \(Int(round(size * 100))) percent")
        }

        return components.joined(separator: ", ")
    }

    func canvasStateDescription(width: CGFloat, height: CGFloat) -> String {
        var components = [
            positionDescription,
            "\(Int(round(rotationDegrees))) degrees",
            isFlippedHorizontally ? "flipped" : "not flipped"
        ]
        components.append("width \(Int(round(width * 100))) percent")
        components.append("height \(Int(round(height * 100))) percent")
        return components.joined(separator: ", ")
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        min(centerRange.upperBound, max(centerRange.lowerBound, value))
    }

    private static func clamped(_ value: CGFloat, in limits: ClosedRange<CGFloat>) -> CGFloat {
        min(limits.upperBound, max(limits.lowerBound, value))
    }

    private static func isWithinSnapThreshold(_ value: CGFloat, threshold: CGFloat) -> Bool {
        abs(value - 0.5) <= threshold + 0.000_001
    }

    private static func normalizedRotation(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 {
            value -= 360
        } else if value < -180 {
            value += 360
        }
        return value
    }
}
