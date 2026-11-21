//
//  ThumbnailShapePathBuilder.swift
//  ThumbnailMaker
//
//  FEATURE-12: pure geometry for arrows, badges and callouts. No views and no
//  UIKit, so every kind is unit-testable. Paths are drawn pointing right in
//  the layer's own box; rotation and flip stay on the layer transform.
//

import CoreGraphics
import SwiftUI

struct ThumbnailShapePaths {
    /// Filled (and optionally outlined) body. For `.line` this is the
    /// centerline, which is stroked with `lineWidth` instead of filled.
    var body: Path
    /// Line-arrow heads drawn as solid shapes (triangle, dot).
    var filledHeads: Path
    /// Line-arrow heads drawn as open chevrons.
    var strokedHeads: Path
}

enum ThumbnailShapePathBuilder {
    /// All geometry of the shape combined — used for hit/bounds reasoning and tests.
    static func path(
        for content: ThumbnailShapeLayerContent,
        in rect: CGRect,
        lineWidth: CGFloat = 1
    ) -> Path {
        let parts = paths(for: content, in: rect, lineWidth: lineWidth)
        var combined = parts.body
        combined.addPath(parts.filledHeads)
        combined.addPath(parts.strokedHeads)
        return combined
    }

    static func paths(
        for content: ThumbnailShapeLayerContent,
        in rect: CGRect,
        lineWidth: CGFloat = 1
    ) -> ThumbnailShapePaths {
        let rect = sanitized(rect)
        let geometry = content.resolvedGeometry
        switch content.shapeKind {
        case .rectangle:
            return ThumbnailShapePaths(
                body: Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.08, style: .continuous),
                filledHeads: Path(),
                strokedHeads: Path()
            )
        case .ellipse:
            return ThumbnailShapePaths(body: Path(ellipseIn: rect), filledHeads: Path(), strokedHeads: Path())
        case .arrow:
            return ThumbnailShapePaths(body: blockArrow(geometry, in: rect), filledHeads: Path(), strokedHeads: Path())
        case .line:
            return lineArrow(geometry, in: rect, lineWidth: sanitizedLength(lineWidth))
        case .pill:
            let radius = min(rect.width, rect.height) * CGFloat(geometry.cornerRadius)
            return ThumbnailShapePaths(
                body: Path(roundedRect: rect, cornerRadius: radius, style: .continuous),
                filledHeads: Path(),
                strokedHeads: Path()
            )
        case .burst:
            return ThumbnailShapePaths(body: burst(geometry, in: rect), filledHeads: Path(), strokedHeads: Path())
        case .callout:
            return ThumbnailShapePaths(body: callout(geometry, in: rect), filledHeads: Path(), strokedHeads: Path())
        }
    }

    // MARK: Body / label rectangles

    /// The part of the box that is "body" (a callout without its tail).
    static func bodyRect(for content: ThumbnailShapeLayerContent, in rect: CGRect) -> CGRect {
        let rect = sanitized(rect)
        guard content.shapeKind == .callout else { return rect }
        return calloutBodyRect(content.resolvedGeometry, in: rect)
    }

    /// Where a label is laid out: the body, inset so text clears corners/points.
    static func labelRect(for content: ThumbnailShapeLayerContent, in rect: CGRect) -> CGRect {
        let rect = sanitized(rect)
        let geometry = content.resolvedGeometry
        switch content.shapeKind {
        case .rectangle:
            return rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.08)
        case .ellipse:
            // Largest axis-aligned rect inside an ellipse is at 1/sqrt(2).
            return rect.insetBy(dx: rect.width * 0.146, dy: rect.height * 0.146)
        case .arrow:
            let headLength = arrowHeadLength(geometry, in: rect)
            let shaftHalf = rect.height * CGFloat(geometry.shaftThickness) / 2
            var shaft = CGRect(
                x: rect.minX + (geometry.startHead == .none ? 0 : headLength),
                y: rect.midY - shaftHalf,
                width: rect.width - headLength * (geometry.startHead == .none ? 1 : 2),
                height: shaftHalf * 2
            )
            shaft = shaft.insetBy(dx: min(shaft.width * 0.05, 4), dy: 0)
            return sanitized(shaft)
        case .line:
            return rect
        case .pill:
            let radius = min(rect.width, rect.height) * CGFloat(geometry.cornerRadius)
            return sanitized(rect.insetBy(dx: radius * 0.6, dy: rect.height * 0.08))
        case .burst:
            let ratio = CGFloat(geometry.burstInnerRatio) * 0.7071
            return sanitized(rect.insetBy(dx: rect.width * (1 - ratio) / 2, dy: rect.height * (1 - ratio) / 2))
        case .callout:
            let body = calloutBodyRect(geometry, in: rect)
            let radius = min(body.width, body.height) * CGFloat(geometry.cornerRadius)
            return sanitized(body.insetBy(dx: max(radius * 0.4, body.width * 0.06), dy: body.height * 0.1))
        }
    }

    /// The tip of a callout tail, or nil when the callout has no tail.
    static func calloutTailTip(for content: ThumbnailShapeLayerContent, in rect: CGRect) -> CGPoint? {
        let rect = sanitized(rect)
        let geometry = content.resolvedGeometry
        guard content.shapeKind == .callout,
              geometry.tailDirection != .none,
              geometry.tailLength > 0 else { return nil }
        return tailTip(geometry.tailDirection, in: rect)
    }

    // MARK: Block arrow

    private static func arrowHeadLength(_ geometry: ThumbnailResolvedShapeGeometry, in rect: CGRect) -> CGFloat {
        let isDouble = geometry.startHead != .none
        let maxFraction: CGFloat = isDouble ? 0.45 : 0.9
        return min(rect.width * CGFloat(geometry.headLength), rect.width * maxFraction)
    }

    private static func blockArrow(_ geometry: ThumbnailResolvedShapeGeometry, in rect: CGRect) -> Path {
        let shaftHalf = rect.height * CGFloat(geometry.shaftThickness) / 2
        let headHalf = max(shaftHalf, rect.height * CGFloat(geometry.headWidth) / 2)
        let headLength = arrowHeadLength(geometry, in: rect)
        let hasStart = geometry.startHead != .none
        let hasEnd = geometry.endHead != .none
        let midY = rect.midY

        var points: [CGPoint] = []
        // Top edge, left to right.
        if hasStart {
            points.append(CGPoint(x: rect.minX, y: midY))
            points.append(CGPoint(x: rect.minX + headLength, y: midY - headHalf))
            points.append(CGPoint(x: rect.minX + headLength, y: midY - shaftHalf))
        } else {
            points.append(CGPoint(x: rect.minX, y: midY - shaftHalf))
        }
        if hasEnd {
            points.append(CGPoint(x: rect.maxX - headLength, y: midY - shaftHalf))
            points.append(CGPoint(x: rect.maxX - headLength, y: midY - headHalf))
            points.append(CGPoint(x: rect.maxX, y: midY))
            points.append(CGPoint(x: rect.maxX - headLength, y: midY + headHalf))
            points.append(CGPoint(x: rect.maxX - headLength, y: midY + shaftHalf))
        } else {
            points.append(CGPoint(x: rect.maxX, y: midY - shaftHalf))
            points.append(CGPoint(x: rect.maxX, y: midY + shaftHalf))
        }
        // Bottom edge, right to left.
        if hasStart {
            points.append(CGPoint(x: rect.minX + headLength, y: midY + shaftHalf))
            points.append(CGPoint(x: rect.minX + headLength, y: midY + headHalf))
        } else {
            points.append(CGPoint(x: rect.minX, y: midY + shaftHalf))
        }
        return polygon(points.map { clamped($0, to: rect) })
    }

    // MARK: Line arrow

    private static func lineArrow(
        _ geometry: ThumbnailResolvedShapeGeometry,
        in rect: CGRect,
        lineWidth: CGFloat
    ) -> ThumbnailShapePaths {
        let halfHeight = rect.height / 2
        let headLength = min(
            rect.width * 0.45,
            max(lineWidth * 2.5, CGFloat(geometry.headLength) * max(rect.height, lineWidth * 4))
        )
        let headHalf = min(halfHeight, max(lineWidth * 1.2, headLength * CGFloat(geometry.headWidth) * 0.6))
        let inset = min(rect.width / 2, lineWidth / 2)
        let start = CGPoint(x: rect.minX + inset, y: rect.midY)
        let end = CGPoint(x: rect.maxX - inset, y: rect.midY)
        // Quadratic midpoint offset = (control - chord) / 2, so this puts the
        // curve's midpoint at 45% of the box height for curvature 1.
        let control = CGPoint(x: rect.midX, y: rect.midY - CGFloat(geometry.curvature) * rect.height * 0.9)

        var shaft = Path()
        shaft.move(to: start)
        if geometry.curvature == 0 {
            shaft.addLine(to: end)
        } else {
            shaft.addQuadCurve(to: end, control: control)
        }

        // Shorten the shaft under solid heads so round caps never poke past a tip.
        let approximateLength = quadraticLength(start, control, end)
        let startTrim = trimAmount(for: geometry.startHead, headLength: headLength)
        let endTrim = trimAmount(for: geometry.endHead, headLength: headLength)
        if approximateLength > 0, startTrim + endTrim > 0, startTrim + endTrim < approximateLength {
            shaft = shaft.trimmedPath(
                from: startTrim / approximateLength,
                to: 1 - endTrim / approximateLength
            )
        }

        var filled = Path()
        var stroked = Path()
        let startDirection = unit(CGPoint(x: start.x - control.x, y: start.y - control.y), fallback: CGPoint(x: -1, y: 0))
        let endDirection = unit(CGPoint(x: end.x - control.x, y: end.y - control.y), fallback: CGPoint(x: 1, y: 0))
        addHead(geometry.startHead, tip: start, direction: startDirection, length: headLength,
                halfWidth: headHalf, lineWidth: lineWidth, rect: rect, filled: &filled, stroked: &stroked)
        addHead(geometry.endHead, tip: end, direction: endDirection, length: headLength,
                halfWidth: headHalf, lineWidth: lineWidth, rect: rect, filled: &filled, stroked: &stroked)
        return ThumbnailShapePaths(body: shaft, filledHeads: filled, strokedHeads: stroked)
    }

    private static func trimAmount(for style: ThumbnailArrowheadStyle, headLength: CGFloat) -> CGFloat {
        switch style {
        case .triangle: headLength * 0.6
        case .none, .open, .dot: 0
        }
    }

    private static func addHead(
        _ style: ThumbnailArrowheadStyle,
        tip: CGPoint,
        direction: CGPoint,
        length: CGFloat,
        halfWidth: CGFloat,
        lineWidth: CGFloat,
        rect: CGRect,
        filled: inout Path,
        stroked: inout Path
    ) {
        let normal = CGPoint(x: -direction.y, y: direction.x)
        let base = CGPoint(x: tip.x - direction.x * length, y: tip.y - direction.y * length)
        let left = CGPoint(x: base.x + normal.x * halfWidth, y: base.y + normal.y * halfWidth)
        let right = CGPoint(x: base.x - normal.x * halfWidth, y: base.y - normal.y * halfWidth)
        switch style {
        case .none:
            break
        case .triangle:
            filled.addPath(polygon([tip, left, right].map { clamped($0, to: rect) }))
        case .open:
            var chevron = Path()
            chevron.move(to: clamped(left, to: rect))
            chevron.addLine(to: clamped(tip, to: rect))
            chevron.addLine(to: clamped(right, to: rect))
            stroked.addPath(chevron)
        case .dot:
            let radius = min(max(lineWidth * 1.4, halfWidth * 0.6), rect.height / 2, rect.width / 4)
            let center = clamped(tip, to: rect.insetBy(dx: min(radius, rect.width / 2), dy: min(radius, rect.height / 2)))
            filled.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
    }

    private static func quadraticLength(_ p0: CGPoint, _ c: CGPoint, _ p2: CGPoint) -> CGFloat {
        var length: CGFloat = 0
        var previous = p0
        let steps = 16
        for index in 1...steps {
            let t = CGFloat(index) / CGFloat(steps)
            let u = 1 - t
            let point = CGPoint(
                x: u * u * p0.x + 2 * u * t * c.x + t * t * p2.x,
                y: u * u * p0.y + 2 * u * t * c.y + t * t * p2.y
            )
            length += hypot(point.x - previous.x, point.y - previous.y)
            previous = point
        }
        return length
    }

    // MARK: Burst

    private static func burst(_ geometry: ThumbnailResolvedShapeGeometry, in rect: CGRect) -> Path {
        let count = geometry.burstPoints
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = CGSize(width: rect.width / 2, height: rect.height / 2)
        let ratio = CGFloat(geometry.burstInnerRatio)
        var points: [CGPoint] = []
        for index in 0..<(count * 2) {
            let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / CGFloat(count)
            let scale: CGFloat = index.isMultiple(of: 2) ? 1 : ratio
            points.append(CGPoint(
                x: center.x + cos(angle) * outer.width * scale,
                y: center.y + sin(angle) * outer.height * scale
            ))
        }
        return polygon(points.map { clamped($0, to: rect) })
    }

    // MARK: Callout

    private static func calloutBodyRect(_ geometry: ThumbnailResolvedShapeGeometry, in rect: CGRect) -> CGRect {
        let vector = geometry.tailDirection.vector
        let insetX = rect.width * CGFloat(geometry.tailLength)
        let insetY = rect.height * CGFloat(geometry.tailLength)
        var body = rect
        if vector.dx < 0 { body.origin.x += insetX; body.size.width -= insetX }
        if vector.dx > 0 { body.size.width -= insetX }
        if vector.dy < 0 { body.origin.y += insetY; body.size.height -= insetY }
        if vector.dy > 0 { body.size.height -= insetY }
        // Diagonal tails only need room on the vertical axis.
        if vector.dx != 0 && vector.dy != 0 {
            body.origin.x = rect.minX
            body.size.width = rect.width
        }
        return sanitized(body)
    }

    private static func tailTip(_ direction: ThumbnailCalloutTailDirection, in rect: CGRect) -> CGPoint {
        let vector = direction.vector
        let x: CGFloat = vector.dx < 0 ? rect.minX : (vector.dx > 0 ? rect.maxX : rect.midX)
        let y: CGFloat = vector.dy < 0 ? rect.minY : (vector.dy > 0 ? rect.maxY : rect.midY)
        return CGPoint(x: x, y: y)
    }

    private static func callout(_ geometry: ThumbnailResolvedShapeGeometry, in rect: CGRect) -> Path {
        let body = calloutBodyRect(geometry, in: rect)
        let radius = min(body.width, body.height) * CGFloat(geometry.cornerRadius)
        let bodyPath = Path(roundedRect: body, cornerRadius: radius, style: .continuous)
        guard geometry.tailDirection != .none, geometry.tailLength > 0 else { return bodyPath }

        let vector = geometry.tailDirection.vector
        let tip = tailTip(geometry.tailDirection, in: rect)
        let overlap = min(body.width, body.height) * 0.25
        var baseA: CGPoint
        var baseB: CGPoint
        if vector.dy != 0 {
            // Tail leaves through the top/bottom edge.
            let edgeY = vector.dy > 0 ? body.maxY - overlap : body.minY + overlap
            let baseWidth = body.width * CGFloat(geometry.tailWidth)
            let startX: CGFloat
            switch vector.dx {
            case ..<0: startX = body.minX + max(radius, body.width * 0.12)
            case 1...: startX = body.maxX - max(radius, body.width * 0.12) - baseWidth
            default: startX = body.midX - baseWidth / 2
            }
            baseA = CGPoint(x: startX, y: edgeY)
            baseB = CGPoint(x: startX + baseWidth, y: edgeY)
        } else {
            let edgeX = vector.dx > 0 ? body.maxX - overlap : body.minX + overlap
            let baseHeight = body.height * CGFloat(geometry.tailWidth)
            baseA = CGPoint(x: edgeX, y: body.midY - baseHeight / 2)
            baseB = CGPoint(x: edgeX, y: body.midY + baseHeight / 2)
        }
        baseA = clamped(baseA, to: body)
        baseB = clamped(baseB, to: body)
        let tail = polygon([baseA, tip, baseB])
        let merged = bodyPath.union(tail)
        if merged.isEmpty {
            var fallback = bodyPath
            fallback.addPath(tail)
            return fallback
        }
        return merged
    }

    // MARK: Helpers

    private static func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    private static func clamped(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(rect.maxX, max(rect.minX, point.x.isFinite ? point.x : rect.midX)),
            y: min(rect.maxY, max(rect.minY, point.y.isFinite ? point.y : rect.midY))
        )
    }

    private static func unit(_ vector: CGPoint, fallback: CGPoint) -> CGPoint {
        let length = hypot(vector.x, vector.y)
        guard length > 0.0001, length.isFinite else { return fallback }
        return CGPoint(x: vector.x / length, y: vector.y / length)
    }

    private static func sanitizedLength(_ value: CGFloat) -> CGFloat {
        guard value.isFinite, value > 0 else { return 1 }
        return value
    }

    private static func sanitized(_ rect: CGRect) -> CGRect {
        let standardized = rect.standardized
        guard standardized.origin.x.isFinite, standardized.origin.y.isFinite,
              standardized.width.isFinite, standardized.height.isFinite else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return CGRect(
            x: standardized.origin.x,
            y: standardized.origin.y,
            width: max(standardized.width, 0.5),
            height: max(standardized.height, 0.5)
        )
    }
}
