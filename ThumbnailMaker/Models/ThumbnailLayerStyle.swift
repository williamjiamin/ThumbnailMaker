//
//  ThumbnailLayerStyle.swift
//  ThumbnailMaker
//
//  FEATURE-08: named, reusable layer styles owned by a brand kit, the scope
//  a style (or a whole kit) is applied with, and the provenance a document
//  keeps about what was applied.
//
//  DELETION-SAFETY RULE: applying a style or kit RESOLVES concrete values into
//  the document (canvas, text, layer content). The ids stored in
//  `ThumbnailDocumentBranding` are provenance for the UI badge only and are
//  never looked up at render time, so deleting a kit or style can never
//  change a pixel of an already-styled project.
//

import Foundation

enum ThumbnailLayerStyleTarget: String, Codable, Equatable, CaseIterable {
    /// The singleton text overlay and `.text` content layers.
    case text
    /// `.shape` content layers.
    case shape

    var displayName: String {
        switch self {
        case .text: "Text"
        case .shape: "Shape"
        }
    }
}

/// Where a styling operation lands. A raw document layer id (not a view
/// selection) so the singleton ids work and the model needs no view types.
enum ThumbnailStyleApplicationScope: Equatable {
    case projectWide
    case layer(String)
}

/// Provenance only. Never read by the renderer or exporter.
struct ThumbnailDocumentBranding: Codable, Equatable {
    var appliedBrandKitID: String?
    /// Snapshot so the badge still has a name after the kit is deleted.
    var appliedBrandKitName: String?
    var styleIDsByLayerID: [String: String]
    /// Snapshot so the badge still has a name after the style is deleted.
    var styleNamesByLayerID: [String: String]

    init(
        appliedBrandKitID: String? = nil,
        appliedBrandKitName: String? = nil,
        styleIDsByLayerID: [String: String] = [:],
        styleNamesByLayerID: [String: String] = [:]
    ) {
        self.appliedBrandKitID = appliedBrandKitID
        self.appliedBrandKitName = appliedBrandKitName
        self.styleIDsByLayerID = styleIDsByLayerID
        self.styleNamesByLayerID = styleNamesByLayerID
    }

    private enum CodingKeys: String, CodingKey {
        case appliedBrandKitID
        case appliedBrandKitName
        case styleIDsByLayerID
        case styleNamesByLayerID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appliedBrandKitID = try container.decodeIfPresent(String.self, forKey: .appliedBrandKitID)
        appliedBrandKitName = try container.decodeIfPresent(String.self, forKey: .appliedBrandKitName)
        styleIDsByLayerID = try container.decodeIfPresent([String: String].self, forKey: .styleIDsByLayerID) ?? [:]
        styleNamesByLayerID = try container.decodeIfPresent([String: String].self, forKey: .styleNamesByLayerID) ?? [:]
    }

    /// Drops entries for layers that no longer exist. O(n) over a small map;
    /// runs on the autosave path.
    func pruned(keepingLayerIDs layerIDs: Set<String>) -> ThumbnailDocumentBranding {
        guard !styleIDsByLayerID.isEmpty || !styleNamesByLayerID.isEmpty else { return self }
        var copy = self
        copy.styleIDsByLayerID = styleIDsByLayerID.filter { layerIDs.contains($0.key) }
        copy.styleNamesByLayerID = styleNamesByLayerID.filter { layerIDs.contains($0.key) }
        return copy
    }

    mutating func recordStyle(id: String, name: String, forLayerID layerID: String) {
        styleIDsByLayerID[layerID] = id
        styleNamesByLayerID[layerID] = name
    }
}

/// A reversible recipe: every attribute is optional and nil leaves the target
/// untouched. Never stores pixels.
struct ThumbnailLayerStyle: Codable, Equatable, Identifiable {
    static let currentVersion = 1

    var version = currentVersion
    var id: String
    var name: String
    var targetRawValue: String
    // Text attributes.
    var textColor: ThumbnailDocumentColor?
    var fontRawValue: String?
    var textSize: Double?
    /// FEATURE-04 integration: outline/shadow/panel/spacing preset.
    var textStyle: ThumbnailTextStyle?
    // Shape attributes.
    var fillColor: ThumbnailDocumentColor?
    var strokeColor: ThumbnailDocumentColor?
    var strokeWidth: Double?
    var updatedAt: Date

    init(
        version: Int = ThumbnailLayerStyle.currentVersion,
        id: String = UUID().uuidString,
        name: String,
        target: ThumbnailLayerStyleTarget,
        textColor: ThumbnailDocumentColor? = nil,
        fontRawValue: String? = nil,
        textSize: Double? = nil,
        textStyle: ThumbnailTextStyle? = nil,
        fillColor: ThumbnailDocumentColor? = nil,
        strokeColor: ThumbnailDocumentColor? = nil,
        strokeWidth: Double? = nil,
        updatedAt: Date = Date()
    ) {
        self.version = version
        self.id = id
        self.name = name
        self.targetRawValue = target.rawValue
        self.textColor = textColor
        self.fontRawValue = fontRawValue
        self.textSize = textSize
        self.textStyle = textStyle
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case version, id, name, targetRawValue
        case textColor, fontRawValue, textSize, textStyle
        case fillColor, strokeColor, strokeWidth, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        version = max(decodedVersion, Self.currentVersion)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Style"
        targetRawValue = try container.decodeIfPresent(String.self, forKey: .targetRawValue)
            ?? ThumbnailLayerStyleTarget.text.rawValue
        textColor = try container.decodeIfPresent(ThumbnailDocumentColor.self, forKey: .textColor)
        fontRawValue = try container.decodeIfPresent(String.self, forKey: .fontRawValue)
        textSize = try container.decodeIfPresent(Double.self, forKey: .textSize)
        textStyle = try container.decodeIfPresent(ThumbnailTextStyle.self, forKey: .textStyle)
        fillColor = try container.decodeIfPresent(ThumbnailDocumentColor.self, forKey: .fillColor)
        strokeColor = try container.decodeIfPresent(ThumbnailDocumentColor.self, forKey: .strokeColor)
        strokeWidth = try container.decodeIfPresent(Double.self, forKey: .strokeWidth)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
    }

    var target: ThumbnailLayerStyleTarget {
        ThumbnailLayerStyleTarget(rawValue: targetRawValue) ?? .text
    }

    // MARK: Applying

    private func clampedTextSize(_ size: Double) -> Double {
        let limits = ContentLayerCanvasGeometry.textSizeLimits
        guard size.isFinite else { return Double(limits.lowerBound) }
        return Swift.min(Double(limits.upperBound), Swift.max(Double(limits.lowerBound), size))
    }

    func applied(to content: ThumbnailTextLayerContent) -> ThumbnailTextLayerContent {
        var content = content
        if let textColor { content.color = textColor }
        if let fontRawValue { content.selectedFontRawValue = fontRawValue }
        if let textSize { content.size = clampedTextSize(textSize) }
        if let textStyle { content.style = textStyle }
        return content
    }

    func applied(to content: ThumbnailShapeLayerContent) -> ThumbnailShapeLayerContent {
        var content = content
        if let fillColor { content.fillColor = fillColor }
        if let strokeWidth, strokeWidth.isFinite { content.strokeWidth = Swift.max(0, strokeWidth) }
        // A stroke-less shape stays stroke-less (recipe hygiene).
        if let strokeColor, content.strokeColor != nil { content.strokeColor = strokeColor }
        return content
    }

    /// Singleton overlay text (target `.text` only).
    func applied(to text: ThumbnailDocumentText) -> ThumbnailDocumentText {
        guard target == .text else { return text }
        var text = text
        if let textColor { text.color = textColor }
        if let fontRawValue { text.selectedFontRawValue = fontRawValue }
        if let textSize { text.size = clampedTextSize(textSize) }
        if let textStyle { text.style = textStyle }
        return text
    }

    /// Unchanged when locked, when the kind does not match the target, or for
    /// image content.
    func applied(to layer: ThumbnailDocumentLayer) -> ThumbnailDocumentLayer {
        guard !layer.isLocked else { return layer }
        var layer = layer
        switch (layer.content, target) {
        case (.text(let content), .text):
            layer.content = .text(applied(to: content))
        case (.shape(let content), .shape):
            layer.content = .shape(applied(to: content))
        default:
            break
        }
        return layer
    }

    func applied(to document: ThumbnailDocument, scope: ThumbnailStyleApplicationScope) -> ThumbnailDocument {
        var document = document
        switch scope {
        case .layer(let layerID):
            applyToLayer(id: layerID, in: &document)
        case .projectWide:
            if target == .text {
                applyToLayer(id: ThumbnailDocumentLayer.textID, in: &document)
            }
            for layer in document.layers where layer.content != nil {
                applyToLayer(id: layer.id, in: &document)
            }
        }
        return document
    }

    private func applyToLayer(id layerID: String, in document: inout ThumbnailDocument) {
        if layerID == ThumbnailDocumentLayer.textID {
            guard target == .text,
                  document.layers.first(where: { $0.id == layerID })?.isLocked != true else { return }
            let styled = applied(to: document.text)
            guard styled != document.text else { return }
            document.text = styled
            document.branding.recordStyle(id: id, name: name, forLayerID: layerID)
            return
        }

        guard let index = document.layers.firstIndex(where: { $0.id == layerID }),
              document.layers[index].content != nil else { return }
        let styled = applied(to: document.layers[index])
        guard styled != document.layers[index] else { return }
        document.layers[index] = styled
        document.branding.recordStyle(id: id, name: name, forLayerID: layerID)
    }

    // MARK: Capturing

    /// "Save this layer's look as a reusable style". Nil for layers with no
    /// stylable attributes (background, profile, images, unknown ids).
    static func capturing(
        layerID: String,
        in document: ThumbnailDocument,
        id: String = UUID().uuidString,
        name: String
    ) -> ThumbnailLayerStyle? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let styleName = trimmed.isEmpty ? "Style" : trimmed

        if layerID == ThumbnailDocumentLayer.textID {
            let text = document.text
            return ThumbnailLayerStyle(
                id: id,
                name: styleName,
                target: .text,
                textColor: text.color,
                fontRawValue: text.selectedFontRawValue,
                textSize: text.size,
                textStyle: text.style
            )
        }

        guard let layer = document.layers.first(where: { $0.id == layerID }) else { return nil }
        switch layer.content {
        case .text(let content):
            return ThumbnailLayerStyle(
                id: id,
                name: styleName,
                target: .text,
                textColor: content.color,
                fontRawValue: content.selectedFontRawValue,
                textSize: content.size,
                textStyle: content.style
            )
        case .shape(let content):
            return ThumbnailLayerStyle(
                id: id,
                name: styleName,
                target: .shape,
                fillColor: content.fillColor,
                strokeColor: content.strokeColor,
                strokeWidth: content.strokeWidth
            )
        case .image, nil:
            return nil
        }
    }

    /// Which target (if any) a layer id can receive in `document`.
    static func target(forLayerID layerID: String, in document: ThumbnailDocument) -> ThumbnailLayerStyleTarget? {
        if layerID == ThumbnailDocumentLayer.textID { return .text }
        switch document.layers.first(where: { $0.id == layerID })?.content {
        case .text: return .text
        case .shape: return .shape
        default: return nil
        }
    }
}
