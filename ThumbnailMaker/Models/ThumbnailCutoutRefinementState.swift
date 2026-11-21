//
//  ThumbnailCutoutRefinementState.swift
//  ThumbnailMaker
//
//  FEATURE-11: the refinement sheet's LOCAL working state. Brush strokes land
//  here (with their own undo stack) and never touch the document until Done,
//  which commits once: one sheet session is one document undo step. Pure
//  value type, so every sheet behaviour is unit-testable without a view.
//

import CoreGraphics
import Foundation

struct ThumbnailCutoutRefinementState: Equatable {
    static let undoLimit = 60
    static let brushRadiusRange: ClosedRange<Double> = 0.005...0.2
    /// Points closer than this (normalized) to the previous one are dropped
    /// while dragging, so a slow drag does not store thousands of samples.
    static let minimumPointSpacing = 0.002

    enum Tool: String, CaseIterable, Identifiable {
        case erase
        case restore
        case move

        var id: String { rawValue }

        var title: String {
            switch self {
            case .erase: "Erase"
            case .restore: "Restore"
            case .move: "Move"
            }
        }

        var strokeMode: ThumbnailCutoutStroke.Mode? {
            switch self {
            case .erase: .erase
            case .restore: .restore
            case .move: nil
            }
        }
    }

    /// The recipe stored on the layer when the sheet opened (nil = none).
    let original: ThumbnailCutoutMask?
    private(set) var working: ThumbnailCutoutMask
    private(set) var undoStack: [ThumbnailCutoutMask] = []
    var tool: Tool = .erase
    var brushRadius: Double = 0.04
    var brushSoftness: Double = 0.35
    /// Before/after: shows the untouched original while true.
    var showsBefore = false
    /// Points of the stroke being drawn right now (normalized, top-left).
    private(set) var pendingPoints: [ThumbnailCutoutPoint] = []

    init(stored: ThumbnailCutoutMask?) {
        original = stored
        var start = stored ?? .empty
        start.isEnabled = true
        working = start
    }

    var canUndo: Bool { !undoStack.isEmpty }

    /// What Done writes: nil when the result is the untouched original.
    var result: ThumbnailCutoutMask? {
        let clamped = working.clamped()
        return clamped.isIdentity ? nil : clamped
    }

    var hasChanges: Bool {
        let before: ThumbnailCutoutMask? = {
            guard var original else { return nil }
            original.isEnabled = true
            let clamped = original.clamped()
            return clamped.isIdentity ? nil : clamped
        }()
        return result != before
    }

    /// The recipe to preview (nil = original).
    var previewMask: ThumbnailCutoutMask? {
        showsBefore ? nil : working
    }

    // MARK: Brush

    mutating func beginStroke(at point: ThumbnailCutoutPoint) {
        guard tool.strokeMode != nil else { return }
        pendingPoints = [point.clamped()]
    }

    mutating func continueStroke(to point: ThumbnailCutoutPoint) {
        guard tool.strokeMode != nil else { return }
        let next = point.clamped()
        guard let last = pendingPoints.last else {
            pendingPoints = [next]
            return
        }
        guard hypot(next.x - last.x, next.y - last.y) >= Self.minimumPointSpacing,
              pendingPoints.count < ThumbnailCutoutMask.maxPointsPerStroke else { return }
        pendingPoints.append(next)
    }

    /// Commits the pending stroke into the working recipe. Returns true when
    /// a stroke was added.
    @discardableResult
    mutating func endStroke() -> Bool {
        defer { pendingPoints = [] }
        guard let mode = tool.strokeMode, !pendingPoints.isEmpty else { return false }
        let stroke = ThumbnailCutoutStroke(
            mode: mode,
            points: pendingPoints,
            radius: brushRadius,
            softness: brushSoftness
        )
        return edit { $0.appendStroke(stroke) }
    }

    mutating func cancelStroke() {
        pendingPoints = []
    }

    // MARK: Recipe edits (each is one local undo step)

    @discardableResult
    mutating func setAutomaticBase(_ base: ThumbnailCutoutAutomaticBase?) -> Bool {
        edit { $0.automaticBase = base }
    }

    /// Continuous feather slider: call `beginFeatherEdit` once when the drag
    /// starts so the whole drag is one local undo step.
    mutating func beginFeatherEdit() {
        pushUndo(working)
    }

    mutating func setFeather(_ feather: Double) {
        working.feather = ThumbnailCutoutMask.clamp(feather, to: ThumbnailCutoutMask.featherLimits, fallback: 0)
    }

    mutating func setBrushRadius(_ radius: Double) {
        brushRadius = ThumbnailCutoutMask.clamp(radius, to: Self.brushRadiusRange, fallback: 0.04)
    }

    mutating func setBrushSoftness(_ softness: Double) {
        brushSoftness = ThumbnailCutoutMask.clamp(softness, to: ThumbnailCutoutMask.softnessLimits, fallback: 0.35)
    }

    /// Back to the untouched original (undoable inside the sheet).
    @discardableResult
    mutating func reset() -> Bool {
        edit { $0.reset() }
    }

    @discardableResult
    mutating func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        working = previous
        return true
    }

    // MARK: Private

    private mutating func edit(_ change: (inout ThumbnailCutoutMask) -> Void) -> Bool {
        var next = working
        change(&next)
        guard next != working else { return false }
        pushUndo(working)
        working = next
        return true
    }

    private mutating func pushUndo(_ mask: ThumbnailCutoutMask) {
        undoStack.append(mask)
        if undoStack.count > Self.undoLimit {
            undoStack.removeFirst(undoStack.count - Self.undoLimit)
        }
    }
}

/// Maps between the sheet's view space and normalized image space through
/// the aspect-fit rect and the current zoom/pan. Pure, unit-tested.
struct ThumbnailCutoutCanvasMapping: Equatable {
    static let zoomRange: ClosedRange<CGFloat> = 1...8

    var canvasSize: CGSize
    var imagePixelSize: CGSize
    var zoom: CGFloat = 1
    var offset: CGSize = .zero

    /// The image's aspect-fit rect before zoom/pan.
    var fittedRect: CGRect {
        guard canvasSize.width > 0, canvasSize.height > 0,
              imagePixelSize.width > 0, imagePixelSize.height > 0 else { return .zero }
        let scale = min(canvasSize.width / imagePixelSize.width, canvasSize.height / imagePixelSize.height)
        let size = CGSize(width: imagePixelSize.width * scale, height: imagePixelSize.height * scale)
        return CGRect(
            x: (canvasSize.width - size.width) / 2,
            y: (canvasSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// The image rect on screen after zoom (about the canvas centre) and pan.
    var displayedRect: CGRect {
        let fit = fittedRect
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        return CGRect(
            x: center.x + (fit.minX - center.x) * zoom + offset.width,
            y: center.y + (fit.minY - center.y) * zoom + offset.height,
            width: fit.width * zoom,
            height: fit.height * zoom
        )
    }

    /// nil when the point is outside the image (with a small margin so edge
    /// strokes still reach the border).
    func normalizedPoint(for viewPoint: CGPoint, margin: CGFloat = 0.08) -> ThumbnailCutoutPoint? {
        let rect = displayedRect
        guard rect.width > 0, rect.height > 0 else { return nil }
        let x = Double((viewPoint.x - rect.minX) / rect.width)
        let y = Double((viewPoint.y - rect.minY) / rect.height)
        let m = Double(margin)
        guard x >= -m, x <= 1 + m, y >= -m, y <= 1 + m else { return nil }
        return ThumbnailCutoutPoint(x: x, y: y).clamped()
    }

    func viewPoint(for point: ThumbnailCutoutPoint) -> CGPoint {
        let rect = displayedRect
        return CGPoint(x: rect.minX + CGFloat(point.x) * rect.width, y: rect.minY + CGFloat(point.y) * rect.height)
    }

    /// Brush radius in view points for a normalized (long-side) radius.
    func viewRadius(forNormalizedRadius radius: Double) -> CGFloat {
        let rect = displayedRect
        return CGFloat(radius) * max(rect.width, rect.height)
    }

    mutating func setZoom(_ value: CGFloat) {
        zoom = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, value.isFinite ? value : 1))
        if zoom == 1 { offset = .zero }
    }
}
