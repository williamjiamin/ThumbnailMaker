//
//  ThumbnailQuickActionEditing.swift
//  ThumbnailMaker
//
//  EDITOR (1.1.0 parity): the "Actions" row and quick-add strip shared by
//  both editors. Every quick action reuses an existing intent (duplicate /
//  delete from the view models, align from FEATURE-07's arrange engine) or is
//  written through `performArrangeMutation`, so each tap is exactly one undo
//  step and a tap that changes nothing records no history.
//

import CoreGraphics
import Foundation

enum ThumbnailQuickAction: String, CaseIterable, Identifiable {
    case duplicate
    case delete
    case centerHorizontally
    case centerVertically
    case bringToFront
    case sendToBack
    case flip
    case resetTransform

    var id: String { rawValue }

    var title: String {
        switch self {
        case .duplicate: "Duplicate"
        case .delete: "Delete"
        case .centerHorizontally: "Center Horizontally"
        case .centerVertically: "Center Vertically"
        case .bringToFront: "Bring to Front"
        case .sendToBack: "Send to Back"
        case .flip: "Flip"
        case .resetTransform: "Reset Transform"
        }
    }

    /// Short caption under the icon button.
    var shortTitle: String {
        switch self {
        case .duplicate: "Duplicate"
        case .delete: "Delete"
        case .centerHorizontally: "Center H"
        case .centerVertically: "Center V"
        case .bringToFront: "Front"
        case .sendToBack: "Back"
        case .flip: "Flip"
        case .resetTransform: "Reset"
        }
    }

    var systemImage: String {
        switch self {
        case .duplicate: "plus.square.on.square"
        case .delete: "trash"
        case .centerHorizontally: "align.horizontal.center"
        case .centerVertically: "align.vertical.center"
        case .bringToFront: "square.3.layers.3d.top.filled"
        case .sendToBack: "square.3.layers.3d.bottom.filled"
        case .flip: "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .resetTransform: "arrow.counterclockwise"
        }
    }

    var accessibilityIdentifier: String {
        "quickAction_\(rawValue)"
    }

    var isDestructive: Bool { self == .delete }
}

/// What the quick actions and the unified asset library need from an editor.
/// Both view models already provide every requirement.
@MainActor
protocol ThumbnailQuickActionEditing: ThumbnailArrangeEditing {
    var brandKitLibrary: BrandKitLibrary { get }
    func addTextLayer(value: String) -> ThumbnailLayerSelection
    func addImageLayer(imageData: Data) -> ThumbnailLayerSelection
    func addStickerLayer(imageData: Data) -> ThumbnailLayerSelection
    func duplicateLayer(_ selection: ThumbnailLayerSelection) -> ThumbnailLayerSelection?
    func deleteLayer(_ selection: ThumbnailLayerSelection) -> ThumbnailLayerSelection?
}

extension SimpleMakerViewModel: ThumbnailQuickActionEditing {}
extension PremiumMakerViewModel: ThumbnailQuickActionEditing {}

/// Outcome of one quick action: the layer to select afterwards and a short
/// VoiceOver announcement.
struct ThumbnailQuickActionOutcome: Equatable {
    var applied: Bool
    var selection: ThumbnailLayerSelection
    var announcement: String
}

extension ThumbnailQuickActionEditing {
    /// Whether `action` can do anything for `selection` right now.
    func canPerformQuickAction(_ action: ThumbnailQuickAction, on selection: ThumbnailLayerSelection) -> Bool {
        let configuration = arrangeConfiguration
        guard selectableLayerSelections.contains(selection),
              configuration.arrangeTransform(for: selection) != nil else {
            return false
        }
        let isLocked = configuration.layers.isLocked(selection)
        switch action {
        case .duplicate, .delete:
            if case .content = selection { return true }
            return false
        case .centerHorizontally, .centerVertically, .flip, .resetTransform:
            return !isLocked
        case .bringToFront:
            return configuration.layers.canMoveForward(selection, within: selectableLayerSelections)
        case .sendToBack:
            return configuration.layers.canMoveBackward(selection, within: selectableLayerSelections)
        }
    }

    @discardableResult
    func performQuickAction(
        _ action: ThumbnailQuickAction,
        on selection: ThumbnailLayerSelection
    ) -> ThumbnailQuickActionOutcome {
        guard canPerformQuickAction(action, on: selection) else {
            let reason = arrangeConfiguration.layers.isLocked(selection)
                ? "Layer is locked."
                : "\(action.title) is not available for this layer."
            return ThumbnailQuickActionOutcome(applied: false, selection: selection, announcement: reason)
        }

        switch action {
        case .duplicate:
            guard let copy = duplicateLayer(selection) else {
                return ThumbnailQuickActionOutcome(applied: false, selection: selection, announcement: "Could not duplicate.")
            }
            return ThumbnailQuickActionOutcome(applied: true, selection: copy, announcement: "Duplicated layer.")
        case .delete:
            let next = deleteLayer(selection) ?? selectableLayerSelections.last ?? .textOverlay
            return ThumbnailQuickActionOutcome(applied: true, selection: next, announcement: "Deleted layer.")
        case .centerHorizontally, .centerVertically:
            let result = alignSelection(
                [selection],
                edge: action == .centerHorizontally ? .horizontalCenter : .verticalCenter,
                reference: .canvas
            )
            return ThumbnailQuickActionOutcome(
                applied: result.applied,
                selection: selection,
                announcement: result.applied ? "\(action.title)." : "Already centered."
            )
        case .bringToFront, .sendToBack:
            let layers = selectableLayerSelections
            let toFront = action == .bringToFront
            let result = performArrangeMutation { configuration in
                var moved = false
                while toFront
                    ? configuration.layers.canMoveForward(selection, within: layers)
                    : configuration.layers.canMoveBackward(selection, within: layers) {
                    if toFront {
                        configuration.layers.moveForward(selection, within: layers)
                    } else {
                        configuration.layers.moveBackward(selection, within: layers)
                    }
                    moved = true
                }
                return ThumbnailArrangeResult(applied: moved, skippedCount: 0, announcement: action.title)
            }
            return ThumbnailQuickActionOutcome(applied: result.applied, selection: selection, announcement: "\(action.title).")
        case .flip:
            let result = performArrangeMutation { configuration in
                let applied = configuration.updateArrangeTransform(for: selection) { $0.flipHorizontally() }
                return ThumbnailArrangeResult(applied: applied, skippedCount: 0, announcement: "Flipped.")
            }
            return ThumbnailQuickActionOutcome(applied: result.applied, selection: selection, announcement: "Flipped.")
        case .resetTransform:
            let result = performArrangeMutation { configuration in
                let applied = configuration.updateArrangeTransform(for: selection) {
                    $0.reset(to: ThumbnailQuickActionDefaults.transform(for: selection))
                }
                return ThumbnailArrangeResult(applied: applied, skippedCount: 0, announcement: "Reset.")
            }
            return ThumbnailQuickActionOutcome(
                applied: result.applied,
                selection: selection,
                announcement: result.applied ? "Transform reset." : "Already at default position."
            )
        }
    }
}

enum ThumbnailQuickActionDefaults {
    static func transform(for selection: ThumbnailLayerSelection) -> ThumbnailOverlayTransform {
        switch selection {
        case .profileOverlay: .profileDefault
        case .textOverlay, .content: .centered
        }
    }
}

extension ThumbnailArrangeableConfiguration {
    /// Mutates one layer's transform (position, rotation, flip). Returns false
    /// when the layer has no transform.
    @discardableResult
    mutating func updateArrangeTransform(
        for selection: ThumbnailLayerSelection,
        _ body: (inout ThumbnailOverlayTransform) -> Void
    ) -> Bool {
        switch selection {
        case .textOverlay:
            guard !overlayText.isEmpty else { return false }
            body(&textTransform)
            return true
        case .profileOverlay:
            guard var transform = arrangeProfileTransform else { return false }
            body(&transform)
            arrangeProfileTransform = transform
            return true
        case .content(let id):
            guard let index = layers.firstIndex(where: { $0.id == id }) else { return false }
            switch layers[index].content {
            case .image(var content):
                body(&content.transform)
                layers[index].content = .image(content)
            case .text(var content):
                body(&content.transform)
                layers[index].content = .text(content)
            case .shape(var content):
                body(&content.transform)
                layers[index].content = .shape(content)
            case nil:
                return false
            }
            return true
        }
    }
}
