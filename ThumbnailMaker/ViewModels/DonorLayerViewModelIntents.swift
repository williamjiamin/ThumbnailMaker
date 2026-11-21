//
//  DonorLayerViewModelIntents.swift
//  ThumbnailMaker
//
//  DONOR (Simple Meme Maker ports): emoji stickers and freehand drawings,
//  both added as ordinary image layers. Each intent settles pending edits,
//  mutates, then settles again, so one call is exactly one undo step.
//

import Foundation

extension Array where Element == ThumbnailDocumentLayer {
    /// Adds an emoji sticker layer. Returns the layer id, or nil when the
    /// text is empty or could not be rendered.
    @discardableResult
    mutating func addEmojiStickerLayer(_ text: String, id: String = UUID().uuidString) -> String? {
        guard let emoji = ThumbnailEmojiSticker.sanitized(text),
              let data = ThumbnailEmojiSticker.pngData(for: emoji) else { return nil }
        let layerID = addStickerLayer(imageData: data, id: id)
        if let index = firstIndex(where: { $0.id == layerID }) {
            self[index].name = ThumbnailEmojiSticker.layerName(for: emoji)
        }
        return layerID
    }

    /// Adds a finished drawing as an image layer where it was drawn.
    @discardableResult
    mutating func addDrawingLayer(_ result: ThumbnailDrawingResult, id: String = UUID().uuidString) -> String {
        let layerID = addImageLayer(
            imageData: result.pngData,
            id: id,
            transform: result.placement.transform,
            size: result.placement.size
        )
        if let index = firstIndex(where: { $0.id == layerID }) {
            let drawingCount = filter { $0.name.hasPrefix("Drawing") }.count + 1
            self[index].name = "Drawing \(drawingCount)"
        }
        return layerID
    }
}

extension SimpleMakerViewModel {
    @discardableResult
    func addEmojiSticker(_ text: String) -> ThumbnailLayerSelection? {
        commitEditorStateNow()
        guard let layerID = simpleMakerConfiguration.layers.addEmojiStickerLayer(text) else { return nil }
        commitEditorStateNow()
        return .content(layerID)
    }

    @discardableResult
    func addDrawing(_ result: ThumbnailDrawingResult) -> ThumbnailLayerSelection {
        commitEditorStateNow()
        let layerID = simpleMakerConfiguration.layers.addDrawingLayer(result)
        commitEditorStateNow()
        return .content(layerID)
    }
}

extension PremiumMakerViewModel {
    @discardableResult
    func addEmojiSticker(_ text: String) -> ThumbnailLayerSelection? {
        commitEditorStateNow()
        guard let layerID = premiumMakerConfiguration.layers.addEmojiStickerLayer(text) else { return nil }
        commitEditorStateNow()
        return .content(layerID)
    }

    @discardableResult
    func addDrawing(_ result: ThumbnailDrawingResult) -> ThumbnailLayerSelection {
        commitEditorStateNow()
        let layerID = premiumMakerConfiguration.layers.addDrawingLayer(result)
        commitEditorStateNow()
        return .content(layerID)
    }
}
