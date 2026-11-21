//
//  ThumbnailFormatResolver.swift
//  ThumbnailMaker
//
//  FEATURE-09: builds the renderable document of one alternate size from the
//  original design plus the size's stored overrides, and folds an edited
//  size back into its overrides. Both are pure. Neither can change the
//  original: `resolvedDocument` returns a copy, and `foldBack` only returns a
//  new `ThumbnailFormatSet`.
//

import CoreGraphics
import Foundation

enum ThumbnailFormatResolver {
    static func resolvedDocument(
        master: ThumbnailDocument,
        formatID: String,
        layerImageSizes: [String: CGSize] = [:]
    ) -> ThumbnailDocument? {
        guard let format = master.formats?.format(id: formatID) else { return nil }
        return resolvedDocument(master: master, format: format, layerImageSizes: layerImageSizes)
    }

    static func resolvedDocument(
        master: ThumbnailDocument,
        format: ThumbnailAlternateFormat,
        layerImageSizes: [String: CGSize] = [:]
    ) -> ThumbnailDocument {
        var document = master.removingFormats()

        for id in master.formatGeometryLayerIDs {
            // Layers added to the original after the size was created are
            // reflowed on the fly; stale layout ids are simply never read.
            let geometry = format.layout[id]
                ?? ThumbnailFormatReflow.geometry(for: id, master: master, kind: format.kind, layerImageSizes: layerImageSizes)
            geometry?.apply(to: &document, layerID: id)
        }

        for (id, value) in format.detachedText {
            if id == ThumbnailDocumentLayer.textID {
                if !master.text.value.isEmpty {
                    document.text.value = value
                }
            } else {
                document.layers.updateTextContent(id: id) { $0.value = value }
            }
        }

        for index in document.layers.indices
        where document.layers[index].kind != .background && format.isHidden(document.layers[index].id) {
            document.layers[index].isVisible = false
        }

        document.canvas.aspectRatioRawValue = format.kind.aspectRatio.rawValue
        document.imageRecipe = format.imageRecipe
        let preset = format.kind.preset
        document.export.presetID = preset.id
        document.export.usesCustomSize = false
        document.export.customWidth = preset.size.width
        document.export.customHeight = preset.size.height
        return document
    }
}

enum ThumbnailFormatLinker {
    /// Writes an edited size back into its overrides only.
    /// - `detachedTextLayerIDs`: text layers that should be unlinked after the
    ///   edit (nil keeps the current set). Linked text edits are ignored, so
    ///   the original's text always wins for linked layers.
    /// - Layers that exist only in `edited` are ignored.
    static func foldBack(
        master: ThumbnailDocument,
        formatID: String,
        edited: ThumbnailDocument,
        detachedTextLayerIDs: Set<String>? = nil
    ) -> ThumbnailFormatSet? {
        guard var set = master.formats, var format = set.format(id: formatID) else { return nil }
        let masterIDs = master.formatGeometryLayerIDs
        let detachedIDs = detachedTextLayerIDs ?? Set(format.detachedText.keys)

        var detached: [String: String] = [:]
        for id in masterIDs where detachedIDs.contains(id) && isTextLayer(id, in: master) {
            let value = textValue(id, in: edited) ?? format.detachedText[id] ?? textValue(id, in: master) ?? ""
            // Clearing unlinked text relinks it rather than deleting the layer.
            if !value.isEmpty {
                detached[id] = value
            }
        }

        var layout: [String: ThumbnailLayerGeometry] = [:]
        var hidden = Set<String>()
        for id in masterIDs {
            let masterVisible = master.layers.record(id: id)?.isVisible ?? true
            if let geometry = ThumbnailLayerGeometry.extract(layerID: id, from: edited) {
                layout[id] = geometry
                if masterVisible {
                    if edited.layers.record(id: id)?.isVisible == false {
                        hidden.insert(id)
                    }
                } else if format.isHidden(id) {
                    hidden.insert(id) // cannot be observed while the original hides it
                }
            } else {
                layout[id] = format.layout[id]
                let wasRelinkedByClearing = id == ThumbnailDocumentLayer.textID && detached[id] == nil
                if !wasRelinkedByClearing {
                    hidden.insert(id)
                }
            }
        }

        format.layout = layout.compactMapValues { $0 }
        format.hiddenLayerIDs = hidden.sorted()
        format.detachedText = detached
        format.imageRecipe = edited.imageRecipe
        set.replace(format)
        return set
    }

    static func isTextLayer(_ id: String, in document: ThumbnailDocument) -> Bool {
        if case .text = ThumbnailFormatReflow.layerKind(id, in: document) { return true }
        return false
    }

    static func textValue(_ id: String, in document: ThumbnailDocument) -> String? {
        if id == ThumbnailDocumentLayer.textID {
            return document.text.value
        }
        if case .text(let content) = document.layers.record(id: id)?.content {
            return content.value
        }
        return nil
    }
}
