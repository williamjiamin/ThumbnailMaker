//
//  ThumbnailBackgroundFill.swift
//  ThumbnailMaker
//
//  SHELL (1.1.0 rebuild): canvas background fill recipe. A document without
//  a fill (every document written before this build) keeps drawing its
//  solid `canvas.backgroundColor`. A fill is a pure recipe: the canvas, the
//  small previews, template cards and every exporter draw it through the
//  same `ThumbnailBackgroundFillView`, so canvas and export always match.
//

import Foundation
import SwiftUI

struct ThumbnailGradientStop: Codable, Equatable {
    var color: ThumbnailDocumentColor
    /// 0...1 along the gradient axis.
    var location: Double

    init(color: ThumbnailDocumentColor, location: Double) {
        self.color = color
        self.location = location
    }
}

struct ThumbnailBackgroundFill: Codable, Equatable {
    enum Kind: String, Codable, Equatable {
        /// Draw `canvas.backgroundColor` (same as having no fill).
        case solid
        case linearGradient

        // A newer build may add fill kinds; never fail the document.
        init(from decoder: Decoder) throws {
            let rawValue = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: rawValue) ?? .solid
        }
    }

    static let stopCountRange: ClosedRange<Int> = 2...3

    var kind: Kind
    var stops: [ThumbnailGradientStop]
    /// 0 = left to right, 90 = top to bottom (clockwise, screen space).
    var angleDegrees: Double

    init(kind: Kind = .linearGradient, stops: [ThumbnailGradientStop], angleDegrees: Double = 0) {
        self.kind = kind
        self.stops = stops
        self.angleDegrees = angleDegrees
    }

    /// Evenly spaced stops from 2-3 colours.
    static func linearGradient(
        _ colors: [ThumbnailDocumentColor],
        angleDegrees: Double = 0
    ) -> ThumbnailBackgroundFill {
        let count = max(1, colors.count - 1)
        let stops = colors.enumerated().map { index, color in
            ThumbnailGradientStop(color: color, location: Double(index) / Double(count))
        }
        return ThumbnailBackgroundFill(kind: .linearGradient, stops: stops, angleDegrees: angleDegrees)
            .normalized()
    }

    /// Clamps to 2-3 stops with sorted 0...1 locations and a 0..<360 angle.
    /// A gradient that cannot be drawn (fewer than two stops) becomes solid.
    func normalized() -> ThumbnailBackgroundFill {
        var copy = self
        copy.angleDegrees = Self.normalizedAngle(angleDegrees)
        copy.stops = stops
            .prefix(Self.stopCountRange.upperBound)
            .map { stop in
                var stop = stop
                stop.location = stop.location.isFinite ? min(1, max(0, stop.location)) : 0
                return stop
            }
            .sorted { $0.location < $1.location }
        if copy.kind == .linearGradient, copy.stops.count < Self.stopCountRange.lowerBound {
            copy.kind = .solid
        }
        return copy
    }

    /// True when this fill draws a gradient rather than the solid colour.
    var drawsGradient: Bool {
        kind == .linearGradient && stops.count >= Self.stopCountRange.lowerBound
    }

    var startPoint: UnitPoint {
        let vector = Self.unitVector(angleDegrees)
        return UnitPoint(x: 0.5 - vector.dx / 2, y: 0.5 - vector.dy / 2)
    }

    var endPoint: UnitPoint {
        let vector = Self.unitVector(angleDegrees)
        return UnitPoint(x: 0.5 + vector.dx / 2, y: 0.5 + vector.dy / 2)
    }

    var gradient: Gradient {
        Gradient(stops: stops.map { Gradient.Stop(color: $0.color.color, location: $0.location) })
    }

    /// A single representative colour (used where one colour is needed,
    /// such as contrast checks): the stop nearest the middle.
    var representativeColor: ThumbnailDocumentColor? {
        guard drawsGradient else { return nil }
        return stops.min { abs($0.location - 0.5) < abs($1.location - 0.5) }?.color
    }

    static func normalizedAngle(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }

    private static func unitVector(_ degrees: Double) -> CGVector {
        let radians = normalizedAngle(degrees) * .pi / 180
        return CGVector(dx: cos(radians), dy: sin(radians))
    }
}

extension ThumbnailBackgroundFill {
    /// Ready-made gradients offered in the editor and the Quick Create wizard.
    struct Preset: Identifiable, Equatable {
        let id: String
        let name: String
        let fill: ThumbnailBackgroundFill
    }

    static let epicGameplay = ThumbnailBackgroundFill.linearGradient(
        [
            ThumbnailDocumentColor(red: 1.0, green: 0.55, blue: 0.10, alpha: 1),
            ThumbnailDocumentColor(red: 0.93, green: 0.16, blue: 0.16, alpha: 1)
        ],
        angleDegrees: 180
    )

    static let presets: [Preset] = [
        Preset(id: "sunset", name: "Sunset", fill: epicGameplay),
        Preset(id: "violet", name: "Violet", fill: .linearGradient(
            [
                ThumbnailDocumentColor(red: 0.40, green: 0.42, blue: 0.91, alpha: 1),
                ThumbnailDocumentColor(red: 0.69, green: 0.44, blue: 0.86, alpha: 1)
            ],
            angleDegrees: 0
        )),
        Preset(id: "ocean", name: "Ocean", fill: .linearGradient(
            [
                ThumbnailDocumentColor(red: 0.02, green: 0.10, blue: 0.24, alpha: 1),
                ThumbnailDocumentColor(red: 0.05, green: 0.45, blue: 0.75, alpha: 1),
                ThumbnailDocumentColor(red: 0.20, green: 0.85, blue: 0.85, alpha: 1)
            ],
            angleDegrees: 45
        )),
        Preset(id: "neon", name: "Neon", fill: .linearGradient(
            [
                ThumbnailDocumentColor(red: 0.95, green: 0.10, blue: 0.60, alpha: 1),
                ThumbnailDocumentColor(red: 0.20, green: 0.10, blue: 0.55, alpha: 1)
            ],
            angleDegrees: 135
        )),
        Preset(id: "forest", name: "Forest", fill: .linearGradient(
            [
                ThumbnailDocumentColor(red: 0.05, green: 0.25, blue: 0.15, alpha: 1),
                ThumbnailDocumentColor(red: 0.45, green: 0.75, blue: 0.30, alpha: 1)
            ],
            angleDegrees: 90
        ))
    ]
}

/// Draws a canvas background: the fill's gradient when it has one,
/// otherwise the solid colour. Shared by the canvas and every exporter.
struct ThumbnailBackgroundFillView: View {
    let fill: ThumbnailBackgroundFill?
    let color: Color

    var body: some View {
        if let fill, fill.drawsGradient {
            Rectangle()
                .fill(LinearGradient(gradient: fill.gradient, startPoint: fill.startPoint, endPoint: fill.endPoint))
        } else {
            Rectangle()
                .fill(color)
        }
    }
}
