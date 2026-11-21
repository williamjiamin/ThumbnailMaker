//
//  ShapeCalloutViewModelIntents.swift
//  ThumbnailMaker
//
//  FEATURE-12: history-safe intents for arrows, badges and callouts, shared
//  by both editors through a tiny protocol (no private view-model access).
//
//  - `addCalloutLayer` and `updateShapeLayer` are DISCRETE: each call settles
//    any pending debounced edit, mutates, then settles again, so one call is
//    exactly one undo step (or none when nothing changed).
//  - Continuous edits (sliders, label typing) write through the layer
//    binding and ride the editor's existing debounced autosave.
//

import Foundation

@MainActor
protocol ThumbnailShapeCalloutEditing: AnyObject {
    var shapeCalloutLayers: [ThumbnailDocumentLayer] { get set }
    var brandKit: BrandKit? { get }
    func commitEditorStateNow()
}

extension ThumbnailShapeCalloutEditing {
    /// The first brand palette color, used as the accent for new presets.
    var calloutBrandAccent: ThumbnailDocumentColor? {
        brandKit?.palette.first?.color
    }

    @discardableResult
    func addCalloutLayer(_ preset: ThumbnailCalloutPreset, useBrandAccent: Bool = true) -> ThumbnailLayerSelection {
        commitEditorStateNow()
        var layers = shapeCalloutLayers
        let layerID = layers.addShapeLayer(
            content: preset.content(accent: useBrandAccent ? calloutBrandAccent : nil)
        )
        shapeCalloutLayers = layers
        commitEditorStateNow()
        return .content(layerID)
    }

    /// Returns false (and records no history) when the layer is missing, is
    /// not a shape, or the edit changes nothing.
    @discardableResult
    func updateShapeLayer(_ id: String, _ mutate: (inout ThumbnailShapeLayerContent) -> Void) -> Bool {
        guard let layer = shapeCalloutLayers.first(where: { $0.id == id }),
              case .shape(let current) = layer.content else { return false }
        var next = current
        mutate(&next)
        guard next != current else { return false }
        commitEditorStateNow()
        var layers = shapeCalloutLayers
        layers.updateShapeContent(id: id) { $0 = next }
        shapeCalloutLayers = layers
        commitEditorStateNow()
        return true
    }

    @discardableResult
    func applyCalloutPreset(_ preset: ThumbnailCalloutPreset, to id: String) -> Bool {
        updateShapeLayer(id) { $0 = preset.restyle($0) }
    }

    /// Recolors the shape's main color with a brand color (the stroke for
    /// line arrows and transparent highlight circles).
    @discardableResult
    func applyBrandColor(_ color: ThumbnailDocumentColor, to id: String) -> Bool {
        updateShapeLayer(id) { content in
            if content.shapeKind == .line {
                content.fillColor = color
                content.strokeColor = nil
            } else if content.fillColor.alpha < 0.05, content.strokeColor != nil {
                content.strokeColor = color
            } else {
                content.fillColor = color
                if var label = content.label {
                    label.color = ThumbnailCalloutPreset.contrastingLabelColor(on: color)
                    content.label = label
                }
            }
        }
    }
}

extension SimpleMakerViewModel: ThumbnailShapeCalloutEditing {
    var shapeCalloutLayers: [ThumbnailDocumentLayer] {
        get { simpleMakerConfiguration.layers }
        set { simpleMakerConfiguration.layers = newValue }
    }
}

extension PremiumMakerViewModel: ThumbnailShapeCalloutEditing {
    var shapeCalloutLayers: [ThumbnailDocumentLayer] {
        get { premiumMakerConfiguration.layers }
        set { premiumMakerConfiguration.layers = newValue }
    }
}
