//
//  ThumbnailDocument.swift
//  ThumbnailMaker
//

import Foundation
import SwiftUI
import UIKit

enum ContentLayerCanvasGeometry {
    static let imageSizeLimits: ClosedRange<CGFloat> = 0.08...0.72
    static let textSizeLimits: ClosedRange<CGFloat> = 0.08...0.34
    static let shapeWidthLimits: ClosedRange<CGFloat> = 0.08...0.92
    static let shapeHeightLimits: ClosedRange<CGFloat> = 0.08...0.92

    static func imageFrameSize(
        for image: UIImage,
        content: ThumbnailImageLayerContent,
        resizeTranslation: CGSize,
        canvasSize: CGSize
    ) -> CGSize {
        let size = ThumbnailOverlayTransform.adjustedOverlaySize(
            CGFloat(content.size),
            by: resizeTranslation,
            in: canvasSize,
            limits: imageSizeLimits
        )
        let maxSide = min(canvasSize.width, canvasSize.height) * size
        return imageFrameSize(for: image, maxSide: maxSide)
    }

    static func imageFrameSize(for image: UIImage, maxSide: CGFloat) -> CGSize {
        guard image.size.width > 0, image.size.height > 0 else {
            return CGSize(width: maxSide, height: maxSide)
        }

        let aspectRatio = image.size.width / image.size.height
        if aspectRatio >= 1 {
            return CGSize(width: maxSide, height: maxSide / aspectRatio)
        }

        return CGSize(width: maxSide * aspectRatio, height: maxSide)
    }

    static func adjustedImageSize(
        _ size: CGFloat,
        by translation: CGSize,
        in canvasSize: CGSize
    ) -> CGFloat {
        ThumbnailOverlayTransform.adjustedOverlaySize(
            size,
            by: translation,
            in: canvasSize,
            limits: imageSizeLimits
        )
    }

    static func textFrameSize(
        for content: ThumbnailTextLayerContent,
        resizeTranslation: CGSize,
        canvasSize: CGSize
    ) -> CGSize {
        let normalizedSize = adjustedTextSize(
            CGFloat(content.size),
            by: resizeTranslation,
            in: canvasSize
        )
        let fontSize = max(1, canvasSize.height * normalizedSize)
        let lineCount = min(3, max(1, content.value.components(separatedBy: .newlines).count))
        let estimatedCharacterWidth = fontSize * 0.56
        let estimatedTextWidth = CGFloat(max(content.value.count, 4)) * estimatedCharacterWidth
        let width = min(canvasSize.width * 0.9, max(canvasSize.width * 0.18, estimatedTextWidth))
        let height = min(canvasSize.height * 0.48, max(fontSize * 1.45, fontSize * CGFloat(lineCount) * 1.25))
        return CGSize(width: width, height: height)
    }

    static func adjustedTextSize(
        _ size: CGFloat,
        by translation: CGSize,
        in canvasSize: CGSize
    ) -> CGFloat {
        ThumbnailOverlayTransform.adjustedOverlaySize(
            size,
            by: translation,
            in: canvasSize,
            limits: textSizeLimits
        )
    }

    static func shapeFrameSize(
        for content: ThumbnailShapeLayerContent,
        resizeTranslation: CGSize,
        canvasSize: CGSize
    ) -> CGSize {
        let normalizedSize = normalizedShapeSize(
            for: content,
            by: resizeTranslation,
            in: canvasSize
        )
        return CGSize(
            width: canvasSize.width * CGFloat(normalizedSize.width),
            height: canvasSize.height * CGFloat(normalizedSize.height)
        )
    }

    static func normalizedShapeSize(
        for content: ThumbnailShapeLayerContent,
        by translation: CGSize,
        in canvasSize: CGSize
    ) -> (width: Double, height: Double) {
        let nextWidth = min(
            shapeWidthLimits.upperBound,
            max(shapeWidthLimits.lowerBound, CGFloat(content.width) + translation.width / max(canvasSize.width, 1))
        )
        let nextHeight = min(
            shapeHeightLimits.upperBound,
            max(shapeHeightLimits.lowerBound, CGFloat(content.height) + translation.height / max(canvasSize.height, 1))
        )
        return (Double(nextWidth), Double(nextHeight))
    }

    static func hitSize(for frameSize: CGSize) -> CGSize {
        CGSize(
            width: max(frameSize.width, 44),
            height: max(frameSize.height, 44)
        )
    }
}

struct ThumbnailDocument: Codable, Equatable {
    static let currentVersion = 4

    var version = currentVersion
    var updatedAt: Date
    var editorMode: ThumbnailDocumentEditorMode
    var canvas: ThumbnailDocumentCanvas
    var imageData: Data?
    var text: ThumbnailDocumentText
    var profile: ThumbnailDocumentProfile?
    var layers: [ThumbnailDocumentLayer]
    var macro: ThumbnailDocumentMacro
    var export: ThumbnailDocumentExport

    init(
        version: Int = ThumbnailDocument.currentVersion,
        updatedAt: Date = Date(),
        editorMode: ThumbnailDocumentEditorMode = .simple,
        canvas: ThumbnailDocumentCanvas = ThumbnailDocumentCanvas(),
        imageData: Data? = nil,
        text: ThumbnailDocumentText = ThumbnailDocumentText(),
        profile: ThumbnailDocumentProfile? = nil,
        layers: [ThumbnailDocumentLayer]? = nil,
        macro: ThumbnailDocumentMacro = ThumbnailDocumentMacro(),
        export: ThumbnailDocumentExport = ThumbnailDocumentExport()
    ) {
        self.version = version
        self.updatedAt = updatedAt
        self.editorMode = editorMode
        self.canvas = canvas
        self.imageData = imageData
        self.text = text
        self.profile = profile
        self.layers = layers ?? ThumbnailDocumentLayer.defaultLayers(
            hasText: !text.value.isEmpty,
            hasProfile: profile?.imageData != nil
        )
        self.macro = macro
        self.export = export
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case updatedAt
        case editorMode
        case canvas
        case imageData
        case text
        case profile
        case layers
        case macro
        case export
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion

        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        editorMode = try container.decode(
            ThumbnailDocumentEditorMode.self,
            forKey: .editorMode
        )
        canvas = try container.decode(ThumbnailDocumentCanvas.self, forKey: .canvas)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        text = try container.decode(ThumbnailDocumentText.self, forKey: .text)
        profile = try container.decodeIfPresent(ThumbnailDocumentProfile.self, forKey: .profile)
        macro = try container.decode(ThumbnailDocumentMacro.self, forKey: .macro)
        export = try container.decode(ThumbnailDocumentExport.self, forKey: .export)
        layers = try container.decodeIfPresent([ThumbnailDocumentLayer].self, forKey: .layers)
            ?? ThumbnailDocumentLayer.defaultLayers(
                hasText: !text.value.isEmpty,
                hasProfile: profile?.imageData != nil
            )
        version = max(decodedVersion, Self.currentVersion)
    }
}

enum ThumbnailDocumentEditorMode: String, Codable, Equatable {
    case simple
    case premium
}

struct ThumbnailDocumentCanvas: Codable, Equatable {
    var aspectRatioRawValue: String
    var backgroundColor: ThumbnailDocumentColor

    init(
        aspectRatioRawValue: String = AspectRatio.ratio16_9.rawValue,
        backgroundColor: ThumbnailDocumentColor = ThumbnailDocumentColor(
            color: Color(uiColor: .secondarySystemBackground)
        )
    ) {
        self.aspectRatioRawValue = aspectRatioRawValue
        self.backgroundColor = backgroundColor
    }
}

struct ThumbnailDocumentText: Codable, Equatable {
    var value: String
    var color: ThumbnailDocumentColor
    var size: Double
    var verticalAlignmentRawValue: String
    var horizontalAlignmentRawValue: String
    var transform: ThumbnailOverlayTransform
    var selectedFontRawValue: String

    init(
        value: String = "",
        color: ThumbnailDocumentColor = ThumbnailDocumentColor(color: .white),
        size: Double = 0.15,
        verticalAlignmentRawValue: String = VerticalAlignment.center.rawValue,
        horizontalAlignmentRawValue: String = HorizontalAlignment.center.rawValue,
        transform: ThumbnailOverlayTransform = .centered,
        selectedFontRawValue: String = CustomFont.goNoto.rawValue
    ) {
        self.value = value
        self.color = color
        self.size = size
        self.verticalAlignmentRawValue = verticalAlignmentRawValue
        self.horizontalAlignmentRawValue = horizontalAlignmentRawValue
        self.transform = transform
        self.selectedFontRawValue = selectedFontRawValue
    }
}

struct ThumbnailDocumentProfile: Codable, Equatable {
    var imageData: Data?
    var size: Double
    var transform: ThumbnailOverlayTransform

    init(
        imageData: Data? = nil,
        size: Double = 0.2,
        transform: ThumbnailOverlayTransform = .profileDefault
    ) {
        self.imageData = imageData
        self.size = size
        self.transform = transform
    }

    private enum CodingKeys: String, CodingKey {
        case imageData
        case positionRawValue
        case size
        case transform
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyPositionRawValue = try container.decodeIfPresent(
            String.self,
            forKey: .positionRawValue
        )

        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        size = try container.decodeIfPresent(Double.self, forKey: .size) ?? 0.2
        transform = try container.decodeIfPresent(
            ThumbnailOverlayTransform.self,
            forKey: .transform
        ) ?? Self.legacyTransform(for: legacyPositionRawValue)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encode(size, forKey: .size)
        try container.encode(transform, forKey: .transform)
    }

    private static func legacyTransform(for positionRawValue: String?) -> ThumbnailOverlayTransform {
        switch positionRawValue {
        case "topLeft":
            return ThumbnailOverlayTransform(x: 0.16, y: 0.18)
        case "topCenter":
            return ThumbnailOverlayTransform(x: 0.5, y: 0.18)
        case "topRight":
            return .profileDefault
        case "middleLeft":
            return ThumbnailOverlayTransform(x: 0.16, y: 0.5)
        case "middleCenter":
            return .centered
        case "middleRight":
            return ThumbnailOverlayTransform(x: 0.84, y: 0.5)
        case "bottomLeft":
            return ThumbnailOverlayTransform(x: 0.16, y: 0.82)
        case "bottomCenter":
            return ThumbnailOverlayTransform(x: 0.5, y: 0.82)
        case "bottomRight":
            return ThumbnailOverlayTransform(x: 0.84, y: 0.82)
        default:
            return .profileDefault
        }
    }
}

struct ThumbnailImageLayerContent: Codable, Equatable {
    var imageData: Data
    var transform: ThumbnailOverlayTransform
    var size: Double
    var isSticker: Bool

    private enum CodingKeys: String, CodingKey {
        case imageData
        case transform
        case size
        case isSticker
    }

    init(
        imageData: Data,
        transform: ThumbnailOverlayTransform = .centered,
        size: Double = 0.32,
        isSticker: Bool = false
    ) {
        self.imageData = imageData
        self.transform = transform
        self.size = size
        self.isSticker = isSticker
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        imageData = try container.decode(Data.self, forKey: .imageData)
        transform = try container.decodeIfPresent(ThumbnailOverlayTransform.self, forKey: .transform) ?? .centered
        size = try container.decodeIfPresent(Double.self, forKey: .size) ?? 0.32
        isSticker = try container.decodeIfPresent(Bool.self, forKey: .isSticker) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(imageData, forKey: .imageData)
        try container.encode(transform, forKey: .transform)
        try container.encode(size, forKey: .size)
        try container.encode(isSticker, forKey: .isSticker)
    }
}

struct ThumbnailTextLayerContent: Codable, Equatable {
    var value: String
    var color: ThumbnailDocumentColor
    var size: Double
    var transform: ThumbnailOverlayTransform
    var selectedFontRawValue: String

    init(
        value: String = "New text",
        color: ThumbnailDocumentColor = ThumbnailDocumentColor(color: .white),
        size: Double = 0.15,
        transform: ThumbnailOverlayTransform = .centered,
        selectedFontRawValue: String = CustomFont.goNoto.rawValue
    ) {
        self.value = value
        self.color = color
        self.size = size
        self.transform = transform
        self.selectedFontRawValue = selectedFontRawValue
    }

    var selectedFont: CustomFont {
        get { CustomFont(rawValue: selectedFontRawValue) ?? .goNoto }
        set { selectedFontRawValue = newValue.rawValue }
    }
}

enum ThumbnailShapeKind: String, Codable, CaseIterable, Equatable {
    case rectangle
    case ellipse

    var displayName: String {
        switch self {
        case .rectangle:
            "Rectangle"
        case .ellipse:
            "Ellipse"
        }
    }
}

struct ThumbnailShapeLayerContent: Codable, Equatable {
    var shapeRawValue: String
    var fillColor: ThumbnailDocumentColor
    var strokeColor: ThumbnailDocumentColor?
    var strokeWidth: Double
    var transform: ThumbnailOverlayTransform
    var width: Double
    var height: Double

    init(
        shapeKind: ThumbnailShapeKind = .rectangle,
        fillColor: ThumbnailDocumentColor = ThumbnailDocumentColor(red: 1, green: 0.82, blue: 0, alpha: 1),
        strokeColor: ThumbnailDocumentColor? = ThumbnailDocumentColor(red: 1, green: 1, blue: 1, alpha: 1),
        strokeWidth: Double = 0.01,
        transform: ThumbnailOverlayTransform = .centered,
        width: Double = 0.34,
        height: Double = 0.22
    ) {
        self.shapeRawValue = shapeKind.rawValue
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.transform = transform
        self.width = width
        self.height = height
    }

    var shapeKind: ThumbnailShapeKind {
        get { ThumbnailShapeKind(rawValue: shapeRawValue) ?? .rectangle }
        set { shapeRawValue = newValue.rawValue }
    }
}

enum ThumbnailLayerContent: Codable, Equatable {
    case image(ThumbnailImageLayerContent)
    case text(ThumbnailTextLayerContent)
    case shape(ThumbnailShapeLayerContent)
}

enum ThumbnailDocumentLayerKind: String, Codable, Equatable {
    case background
    case profile
    case text
    case image
    case shape
}

struct ThumbnailDocumentLayer: Codable, Equatable, Identifiable {
    static let backgroundID = "background"
    static let profileID = "profile"
    static let textID = "text"
    static let contentLayerZIndexStart = 30

    var id: String
    var kind: ThumbnailDocumentLayerKind
    var name: String
    var isVisible: Bool
    var isLocked: Bool
    var zIndex: Int
    var content: ThumbnailLayerContent?

    init(
        id: String,
        kind: ThumbnailDocumentLayerKind,
        name: String,
        isVisible: Bool = true,
        isLocked: Bool = false,
        zIndex: Int,
        content: ThumbnailLayerContent? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.zIndex = zIndex
        self.content = content
    }

    static func defaultLayers(hasText: Bool, hasProfile: Bool) -> [ThumbnailDocumentLayer] {
        var layers = [
            defaultBackgroundLayer
        ]

        if hasProfile {
            layers.append(defaultProfileLayer)
        }

        if hasText {
            layers.append(defaultTextLayer)
        }

        return layers
    }

    static var defaultBackgroundLayer: ThumbnailDocumentLayer {
        ThumbnailDocumentLayer(
            id: backgroundID,
            kind: .background,
            name: "Background",
            isLocked: true,
            zIndex: 0
        )
    }

    static var defaultProfileLayer: ThumbnailDocumentLayer {
        ThumbnailDocumentLayer(
            id: profileID,
            kind: .profile,
            name: "Profile",
            zIndex: 10
        )
    }

    static var defaultTextLayer: ThumbnailDocumentLayer {
        ThumbnailDocumentLayer(
            id: textID,
            kind: .text,
            name: "Text",
            zIndex: 20
        )
    }

    static func defaultLayer(for editorLayer: ThumbnailEditorLayer) -> ThumbnailDocumentLayer {
        switch editorLayer {
        case .text:
            defaultTextLayer
        case .profile:
            defaultProfileLayer
        }
    }

    static func imageLayer(
        id: String = UUID().uuidString,
        imageData: Data,
        name: String = "Image",
        transform: ThumbnailOverlayTransform = .centered,
        size: Double = 0.32,
        isSticker: Bool = false,
        zIndex: Int = contentLayerZIndexStart
    ) -> ThumbnailDocumentLayer {
        ThumbnailDocumentLayer(
            id: id,
            kind: .image,
            name: name,
            zIndex: zIndex,
            content: .image(
                ThumbnailImageLayerContent(
                    imageData: imageData,
                    transform: transform,
                    size: size,
                    isSticker: isSticker
                )
            )
        )
    }

    static func textLayer(
        id: String = UUID().uuidString,
        value: String = "New text",
        color: ThumbnailDocumentColor = ThumbnailDocumentColor(color: .white),
        size: Double = 0.15,
        selectedFontRawValue: String = CustomFont.goNoto.rawValue,
        name: String = "Text",
        transform: ThumbnailOverlayTransform = .centered,
        zIndex: Int = contentLayerZIndexStart
    ) -> ThumbnailDocumentLayer {
        ThumbnailDocumentLayer(
            id: id,
            kind: .text,
            name: name,
            zIndex: zIndex,
            content: .text(
                ThumbnailTextLayerContent(
                    value: value,
                    color: color,
                    size: size,
                    transform: transform,
                    selectedFontRawValue: selectedFontRawValue
                )
            )
        )
    }

    static func shapeLayer(
        id: String = UUID().uuidString,
        shapeKind: ThumbnailShapeKind = .rectangle,
        fillColor: ThumbnailDocumentColor = ThumbnailDocumentColor(red: 1, green: 0.82, blue: 0, alpha: 1),
        strokeColor: ThumbnailDocumentColor? = ThumbnailDocumentColor(red: 1, green: 1, blue: 1, alpha: 1),
        strokeWidth: Double = 0.01,
        name: String? = nil,
        transform: ThumbnailOverlayTransform = .centered,
        width: Double = 0.34,
        height: Double = 0.22,
        zIndex: Int = contentLayerZIndexStart
    ) -> ThumbnailDocumentLayer {
        ThumbnailDocumentLayer(
            id: id,
            kind: .shape,
            name: name ?? shapeKind.displayName,
            zIndex: zIndex,
            content: .shape(
                ThumbnailShapeLayerContent(
                    shapeKind: shapeKind,
                    fillColor: fillColor,
                    strokeColor: strokeColor,
                    strokeWidth: strokeWidth,
                    transform: transform,
                    width: width,
                    height: height
                )
            )
        )
    }

    static func reconciled(
        _ existingLayers: [ThumbnailDocumentLayer],
        hasText: Bool,
        hasProfile: Bool
    ) -> [ThumbnailDocumentLayer] {
        let existingByID = Dictionary(
            existingLayers.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let defaults = defaultLayers(hasText: hasText, hasProfile: hasProfile)

        let fixedLayerIDs = Set(defaults.map(\.id))
        let reconciledSingletons = defaults.map { defaultLayer in
            guard let existing = existingByID[defaultLayer.id] else {
                return defaultLayer
            }

            return ThumbnailDocumentLayer(
                id: defaultLayer.id,
                kind: defaultLayer.kind,
                name: existing.name.isEmpty ? defaultLayer.name : existing.name,
                isVisible: existing.isVisible,
                isLocked: defaultLayer.kind == .background ? true : existing.isLocked,
                zIndex: defaultLayer.kind == .background ? defaultLayer.zIndex : existing.zIndex,
                content: nil
            )
        }

        let contentLayers = existingLayers.filter { layer in
            !fixedLayerIDs.contains(layer.id) && layer.content != nil
        }

        return (reconciledSingletons + contentLayers)
            .sorted { $0.zIndex < $1.zIndex }
    }
}

extension Array where Element == ThumbnailDocumentLayer {
    func reconciledForCurrentOverlays(hasText: Bool, hasProfile: Bool) -> [ThumbnailDocumentLayer] {
        ThumbnailDocumentLayer.reconciled(self, hasText: hasText, hasProfile: hasProfile)
    }

    func record(for editorLayer: ThumbnailEditorLayer) -> ThumbnailDocumentLayer? {
        first { $0.id == editorLayer.documentLayerID }
    }

    func record(for selection: ThumbnailLayerSelection) -> ThumbnailDocumentLayer? {
        record(id: selection.documentLayerID)
    }

    func record(id: String) -> ThumbnailDocumentLayer? {
        first { $0.id == id }
    }

    func isVisible(_ editorLayer: ThumbnailEditorLayer) -> Bool {
        record(for: editorLayer)?.isVisible ?? true
    }

    func isLocked(_ editorLayer: ThumbnailEditorLayer) -> Bool {
        record(for: editorLayer)?.isLocked ?? false
    }

    func isVisible(_ selection: ThumbnailLayerSelection) -> Bool {
        record(for: selection)?.isVisible ?? true
    }

    func isLocked(_ selection: ThumbnailLayerSelection) -> Bool {
        record(for: selection)?.isLocked ?? false
    }

    var hasContentLayers: Bool {
        contains { $0.content != nil }
    }

    func sortedEditorLayers(_ editorLayers: [ThumbnailEditorLayer]) -> [ThumbnailEditorLayer] {
        editorLayers.sorted {
            zIndex(for: $0) < zIndex(for: $1)
        }
    }

    func sortedSelections(_ selections: [ThumbnailLayerSelection]) -> [ThumbnailLayerSelection] {
        selections.sorted {
            zIndex(forLayerID: $0.documentLayerID) < zIndex(forLayerID: $1.documentLayerID)
        }
    }

    func selectableLayerSelections(
        hasText: Bool,
        hasProfile: Bool,
        includeContentLayers: Bool = true
    ) -> [ThumbnailLayerSelection] {
        var selections: [ThumbnailLayerSelection] = []

        if hasText {
            selections.append(.textOverlay)
        }

        if hasProfile {
            selections.append(.profileOverlay)
        }

        selections.append(contentsOf: compactMap { layer in
            guard layer.id != ThumbnailDocumentLayer.backgroundID else { return nil }

            switch layer.id {
            case ThumbnailDocumentLayer.textID:
                return nil
            case ThumbnailDocumentLayer.profileID:
                return nil
            default:
                return includeContentLayers && layer.content != nil ? .content(layer.id) : nil
            }
        })

        return sortedSelections(selections)
    }

    func canMoveForward(_ editorLayer: ThumbnailEditorLayer, within editorLayers: [ThumbnailEditorLayer]) -> Bool {
        let orderedLayerIDs = orderedLayerIDs(within: editorLayers)
        return orderedLayerIDs.contains(editorLayer.documentLayerID)
            && orderedLayerIDs.last != editorLayer.documentLayerID
    }

    func canMoveBackward(_ editorLayer: ThumbnailEditorLayer, within editorLayers: [ThumbnailEditorLayer]) -> Bool {
        let orderedLayerIDs = orderedLayerIDs(within: editorLayers)
        return orderedLayerIDs.contains(editorLayer.documentLayerID)
            && orderedLayerIDs.first != editorLayer.documentLayerID
    }

    func canMoveForward(_ selection: ThumbnailLayerSelection, within selections: [ThumbnailLayerSelection]) -> Bool {
        canMoveForward(layerID: selection.documentLayerID, within: selections.map(\.documentLayerID))
    }

    func canMoveBackward(_ selection: ThumbnailLayerSelection, within selections: [ThumbnailLayerSelection]) -> Bool {
        canMoveBackward(layerID: selection.documentLayerID, within: selections.map(\.documentLayerID))
    }

    func canMoveForward(layerID: String, within layerIDs: [String]) -> Bool {
        let orderedLayerIDs = orderedLayerIDs(withinLayerIDs: layerIDs)
        return orderedLayerIDs.contains(layerID) && orderedLayerIDs.last != layerID
    }

    func canMoveBackward(layerID: String, within layerIDs: [String]) -> Bool {
        let orderedLayerIDs = orderedLayerIDs(withinLayerIDs: layerIDs)
        return orderedLayerIDs.contains(layerID) && orderedLayerIDs.first != layerID
    }

    mutating func setVisible(_ isVisible: Bool, for editorLayer: ThumbnailEditorLayer) {
        update(editorLayer) { layer in
            layer.isVisible = isVisible
        }
    }

    mutating func toggleVisibility(for editorLayer: ThumbnailEditorLayer) {
        update(editorLayer) { layer in
            layer.isVisible.toggle()
        }
    }

    mutating func toggleVisibility(for selection: ThumbnailLayerSelection) {
        update(selection) { layer in
            layer.isVisible.toggle()
        }
    }

    mutating func setLocked(_ isLocked: Bool, for editorLayer: ThumbnailEditorLayer) {
        update(editorLayer) { layer in
            layer.isLocked = isLocked
        }
    }

    mutating func toggleLock(for editorLayer: ThumbnailEditorLayer) {
        update(editorLayer) { layer in
            layer.isLocked.toggle()
        }
    }

    mutating func toggleLock(for selection: ThumbnailLayerSelection) {
        update(selection) { layer in
            guard layer.kind != .background else { return }
            layer.isLocked.toggle()
        }
    }

    mutating func moveForward(_ editorLayer: ThumbnailEditorLayer, within editorLayers: [ThumbnailEditorLayer]) {
        move(editorLayer, by: 1, within: editorLayers)
    }

    mutating func moveBackward(_ editorLayer: ThumbnailEditorLayer, within editorLayers: [ThumbnailEditorLayer]) {
        move(editorLayer, by: -1, within: editorLayers)
    }

    mutating func moveForward(_ selection: ThumbnailLayerSelection, within selections: [ThumbnailLayerSelection]) {
        move(layerID: selection.documentLayerID, by: 1, withinLayerIDs: selections.map(\.documentLayerID))
    }

    mutating func moveBackward(_ selection: ThumbnailLayerSelection, within selections: [ThumbnailLayerSelection]) {
        move(layerID: selection.documentLayerID, by: -1, withinLayerIDs: selections.map(\.documentLayerID))
    }

    @discardableResult
    mutating func addImageLayer(
        imageData: Data,
        id: String = UUID().uuidString,
        transform: ThumbnailOverlayTransform = .centered,
        size: Double = 0.32,
        isSticker: Bool = false
    ) -> String {
        let layerTitle = isSticker ? "Sticker" : "Image"
        let layerCount = filter { layer in
            guard case .image(let content) = layer.content else { return false }
            return content.isSticker == isSticker
        }.count + 1
        let zIndex = Swift.max(
            ThumbnailDocumentLayer.contentLayerZIndexStart,
            (map(\.zIndex).max() ?? ThumbnailDocumentLayer.contentLayerZIndexStart - 10) + 10
        )
        append(
            ThumbnailDocumentLayer.imageLayer(
                id: id,
                imageData: imageData,
                name: "\(layerTitle) \(layerCount)",
                transform: transform,
                size: size,
                isSticker: isSticker,
                zIndex: zIndex
            )
        )
        sort { $0.zIndex < $1.zIndex }
        return id
    }

    @discardableResult
    mutating func addStickerLayer(
        imageData: Data,
        id: String = UUID().uuidString,
        transform: ThumbnailOverlayTransform = .centered,
        size: Double = 0.24
    ) -> String {
        addImageLayer(
            imageData: imageData,
            id: id,
            transform: transform,
            size: size,
            isSticker: true
        )
    }

    @discardableResult
    mutating func addTextLayer(
        value: String = "New text",
        id: String = UUID().uuidString,
        color: ThumbnailDocumentColor = ThumbnailDocumentColor(color: .white),
        size: Double = 0.15,
        selectedFontRawValue: String = CustomFont.goNoto.rawValue,
        transform: ThumbnailOverlayTransform = .centered
    ) -> String {
        let layerCount = filter {
            if case .text = $0.content {
                return true
            }
            return false
        }.count + 1
        let zIndex = Swift.max(
            ThumbnailDocumentLayer.contentLayerZIndexStart,
            (map(\.zIndex).max() ?? ThumbnailDocumentLayer.contentLayerZIndexStart - 10) + 10
        )
        append(
            ThumbnailDocumentLayer.textLayer(
                id: id,
                value: value,
                color: color,
                size: size,
                selectedFontRawValue: selectedFontRawValue,
                name: "Text \(layerCount)",
                transform: transform,
                zIndex: zIndex
            )
        )
        sort { $0.zIndex < $1.zIndex }
        return id
    }

    @discardableResult
    mutating func addShapeLayer(
        shapeKind: ThumbnailShapeKind = .rectangle,
        id: String = UUID().uuidString,
        fillColor: ThumbnailDocumentColor = ThumbnailDocumentColor(red: 1, green: 0.82, blue: 0, alpha: 1),
        strokeColor: ThumbnailDocumentColor? = ThumbnailDocumentColor(red: 1, green: 1, blue: 1, alpha: 1),
        strokeWidth: Double = 0.01,
        transform: ThumbnailOverlayTransform = .centered,
        width: Double = 0.34,
        height: Double = 0.22
    ) -> String {
        let layerCount = filter { $0.kind == .shape }.count + 1
        let zIndex = Swift.max(
            ThumbnailDocumentLayer.contentLayerZIndexStart,
            (map(\.zIndex).max() ?? ThumbnailDocumentLayer.contentLayerZIndexStart - 10) + 10
        )
        append(
            ThumbnailDocumentLayer.shapeLayer(
                id: id,
                shapeKind: shapeKind,
                fillColor: fillColor,
                strokeColor: strokeColor,
                strokeWidth: strokeWidth,
                name: "\(shapeKind.displayName) \(layerCount)",
                transform: transform,
                width: width,
                height: height,
                zIndex: zIndex
            )
        )
        sort { $0.zIndex < $1.zIndex }
        return id
    }

    @discardableResult
    mutating func duplicateContentLayer(id sourceID: String, newID: String = UUID().uuidString) -> String? {
        guard let sourceIndex = firstIndex(where: { $0.id == sourceID }),
              self[sourceIndex].content != nil else {
            return nil
        }

        var duplicatedLayer = self[sourceIndex]
        duplicatedLayer.id = newID
        duplicatedLayer.name = Self.copyName(for: duplicatedLayer.name)
        duplicatedLayer.zIndex = (map(\.zIndex).max() ?? duplicatedLayer.zIndex) + 10
        duplicatedLayer.content = Self.nudgedContent(duplicatedLayer.content)
        append(duplicatedLayer)
        sort { $0.zIndex < $1.zIndex }
        return newID
    }

    mutating func deleteContentLayer(id: String) {
        removeAll { layer in
            layer.id == id && layer.content != nil
        }
    }

    mutating func updateImageContent(
        id: String,
        mutate: (inout ThumbnailImageLayerContent) -> Void
    ) {
        guard let index = firstIndex(where: { $0.id == id }),
              case .image(var content) = self[index].content else {
            return
        }

        mutate(&content)
        self[index].content = .image(content)
    }

    mutating func updateTextContent(
        id: String,
        mutate: (inout ThumbnailTextLayerContent) -> Void
    ) {
        guard let index = firstIndex(where: { $0.id == id }),
              case .text(var content) = self[index].content else {
            return
        }

        mutate(&content)
        self[index].content = .text(content)
    }

    mutating func updateShapeContent(
        id: String,
        mutate: (inout ThumbnailShapeLayerContent) -> Void
    ) {
        guard let index = firstIndex(where: { $0.id == id }),
              case .shape(var content) = self[index].content else {
            return
        }

        mutate(&content)
        self[index].content = .shape(content)
    }

    private mutating func update(
        _ editorLayer: ThumbnailEditorLayer,
        mutate: (inout ThumbnailDocumentLayer) -> Void
    ) {
        if let index = firstIndex(where: { $0.id == editorLayer.documentLayerID }) {
            mutate(&self[index])
        } else {
            var layer = ThumbnailDocumentLayer.defaultLayer(for: editorLayer)
            mutate(&layer)
            append(layer)
            sort { $0.zIndex < $1.zIndex }
        }
    }

    private mutating func update(
        _ selection: ThumbnailLayerSelection,
        mutate: (inout ThumbnailDocumentLayer) -> Void
    ) {
        switch selection {
        case .textOverlay, .profileOverlay:
            if let editorLayer = selection.editorLayer {
                update(editorLayer, mutate: mutate)
            }
        case .content(let id):
            guard let index = firstIndex(where: { $0.id == id }) else { return }
            mutate(&self[index])
        }
    }

    private func zIndex(for editorLayer: ThumbnailEditorLayer) -> Int {
        record(for: editorLayer)?.zIndex ?? ThumbnailDocumentLayer.defaultLayer(for: editorLayer).zIndex
    }

    private func zIndex(forLayerID layerID: String) -> Int {
        if layerID == ThumbnailDocumentLayer.textID {
            return record(id: layerID)?.zIndex ?? ThumbnailDocumentLayer.defaultTextLayer.zIndex
        }

        if layerID == ThumbnailDocumentLayer.profileID {
            return record(id: layerID)?.zIndex ?? ThumbnailDocumentLayer.defaultProfileLayer.zIndex
        }

        return record(id: layerID)?.zIndex ?? Int.max
    }

    private func orderedLayerIDs(within editorLayers: [ThumbnailEditorLayer]) -> [String] {
        sortedEditorLayers(editorLayers).map(\.documentLayerID)
    }

    private func orderedLayerIDs(withinLayerIDs layerIDs: [String]) -> [String] {
        layerIDs.sorted {
            zIndex(forLayerID: $0) < zIndex(forLayerID: $1)
        }
    }

    private mutating func move(
        _ editorLayer: ThumbnailEditorLayer,
        by offset: Int,
        within editorLayers: [ThumbnailEditorLayer]
    ) {
        let orderedLayers = sortedEditorLayers(editorLayers)
        guard let currentIndex = orderedLayers.firstIndex(of: editorLayer) else { return }

        let targetIndex = currentIndex + offset
        guard orderedLayers.indices.contains(targetIndex) else { return }

        let targetLayer = orderedLayers[targetIndex]
        ensureRecordExists(for: editorLayer)
        ensureRecordExists(for: targetLayer)

        guard
            let currentRecordIndex = firstIndex(where: { $0.id == editorLayer.documentLayerID }),
            let targetRecordIndex = firstIndex(where: { $0.id == targetLayer.documentLayerID })
        else {
            return
        }

        let currentZIndex = self[currentRecordIndex].zIndex
        self[currentRecordIndex].zIndex = self[targetRecordIndex].zIndex
        self[targetRecordIndex].zIndex = currentZIndex
        sort { $0.zIndex < $1.zIndex }
    }

    private mutating func move(
        layerID: String,
        by offset: Int,
        withinLayerIDs layerIDs: [String]
    ) {
        let orderedLayerIDs = orderedLayerIDs(withinLayerIDs: layerIDs)
        guard let currentIndex = orderedLayerIDs.firstIndex(of: layerID) else { return }

        let targetIndex = currentIndex + offset
        guard orderedLayerIDs.indices.contains(targetIndex) else { return }

        let targetLayerID = orderedLayerIDs[targetIndex]
        ensureRecordExists(forLayerID: layerID)
        ensureRecordExists(forLayerID: targetLayerID)

        guard
            let currentRecordIndex = firstIndex(where: { $0.id == layerID }),
            let targetRecordIndex = firstIndex(where: { $0.id == targetLayerID })
        else {
            return
        }

        let currentZIndex = self[currentRecordIndex].zIndex
        self[currentRecordIndex].zIndex = self[targetRecordIndex].zIndex
        self[targetRecordIndex].zIndex = currentZIndex
        sort { $0.zIndex < $1.zIndex }
    }

    private mutating func ensureRecordExists(for editorLayer: ThumbnailEditorLayer) {
        guard record(for: editorLayer) == nil else { return }

        append(ThumbnailDocumentLayer.defaultLayer(for: editorLayer))
        sort { $0.zIndex < $1.zIndex }
    }

    private mutating func ensureRecordExists(forLayerID layerID: String) {
        switch layerID {
        case ThumbnailDocumentLayer.textID:
            ensureRecordExists(for: .text)
        case ThumbnailDocumentLayer.profileID:
            ensureRecordExists(for: .profile)
        default:
            return
        }
    }

    private static func copyName(for name: String) -> String {
        name.hasSuffix(" Copy") ? name : "\(name) Copy"
    }

    private static func nudgedContent(_ content: ThumbnailLayerContent?) -> ThumbnailLayerContent? {
        switch content {
        case .image(var imageContent):
            imageContent.transform.x = Swift.min(0.95, Swift.max(0.05, imageContent.transform.x + 0.04))
            imageContent.transform.y = Swift.min(0.95, Swift.max(0.05, imageContent.transform.y + 0.04))
            return .image(imageContent)
        case .text(var textContent):
            textContent.transform.x = Swift.min(0.95, Swift.max(0.05, textContent.transform.x + 0.04))
            textContent.transform.y = Swift.min(0.95, Swift.max(0.05, textContent.transform.y + 0.04))
            return .text(textContent)
        case .shape(var shapeContent):
            shapeContent.transform.x = Swift.min(0.95, Swift.max(0.05, shapeContent.transform.x + 0.04))
            shapeContent.transform.y = Swift.min(0.95, Swift.max(0.05, shapeContent.transform.y + 0.04))
            return .shape(shapeContent)
        case nil:
            return content
        }
    }
}

struct ThumbnailDocumentMacro: Codable, Equatable {
    var isEnabled: Bool
    var startNumber: Int
    var endNumber: Int
    var appendPositionRawValue: String

    init(
        isEnabled: Bool = false,
        startNumber: Int = 1,
        endNumber: Int = 1,
        appendPositionRawValue: String = MacroConfig.AppendPosition.after.rawValue
    ) {
        self.isEnabled = isEnabled
        self.startNumber = startNumber
        self.endNumber = endNumber
        self.appendPositionRawValue = appendPositionRawValue
    }
}

struct ThumbnailDocumentExport: Codable, Equatable {
    var presetID: String
    var formatRawValue: String
    var compressionQuality: Double
    var usesCustomSize: Bool
    var customWidth: Int
    var customHeight: Int

    init(
        presetID: String = ThumbnailExportPreset.youTubeThumbnail.id,
        formatRawValue: String = ThumbnailExportFormat.png.rawValue,
        compressionQuality: Double = 0.9,
        usesCustomSize: Bool = false,
        customWidth: Int = 1920,
        customHeight: Int = 1080
    ) {
        self.presetID = presetID
        self.formatRawValue = formatRawValue
        self.compressionQuality = compressionQuality
        self.usesCustomSize = usesCustomSize
        self.customWidth = customWidth
        self.customHeight = customHeight
    }
}

struct ThumbnailDocumentColor: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(color: Color) {
        let resolvedColor = UIColor(color)
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        if resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            self.init(
                red: Double(red),
                green: Double(green),
                blue: Double(blue),
                alpha: Double(alpha)
            )
        } else {
            var white: CGFloat = 0
            resolvedColor.getWhite(&white, alpha: &alpha)
            self.init(
                red: Double(white),
                green: Double(white),
                blue: Double(white),
                alpha: Double(alpha)
            )
        }
    }

    var color: Color {
        Color(
            uiColor: UIColor(
                red: CGFloat(red),
                green: CGFloat(green),
                blue: CGFloat(blue),
                alpha: CGFloat(alpha)
            )
        )
    }
}

extension ThumbnailDocument {
    init(configuration: SimpleMakerConfigurationModel, updatedAt: Date = Date()) {
        self.init(
            updatedAt: updatedAt,
            editorMode: .simple,
            canvas: ThumbnailDocumentCanvas(
                aspectRatioRawValue: configuration.selectedRatio.rawValue,
                backgroundColor: ThumbnailDocumentColor(color: configuration.backgroundColor)
            ),
            imageData: Self.encodedImageData(from: configuration.selectedImage),
            text: ThumbnailDocumentText(
                value: configuration.overlayText,
                color: ThumbnailDocumentColor(color: configuration.textColor),
                size: Double(configuration.textSize),
                verticalAlignmentRawValue: configuration.verticalAlignment.rawValue,
                horizontalAlignmentRawValue: configuration.horizontalAlignment.rawValue,
                transform: configuration.textTransform,
                selectedFontRawValue: configuration.selectedFont.rawValue
            ),
            layers: configuration.layers.reconciledForCurrentOverlays(
                hasText: !configuration.overlayText.isEmpty,
                hasProfile: false
            ),
            export: ThumbnailDocumentExport(options: configuration.exportOptions)
        )
    }

    init(configuration: PremiumMakerConfigurationModel, updatedAt: Date = Date()) {
        self.init(
            updatedAt: updatedAt,
            editorMode: .premium,
            canvas: ThumbnailDocumentCanvas(
                aspectRatioRawValue: configuration.selectedRatio.rawValue,
                backgroundColor: ThumbnailDocumentColor(color: configuration.backgroundColor)
            ),
            imageData: Self.encodedImageData(from: configuration.selectedImage),
            text: ThumbnailDocumentText(
                value: configuration.overlayText,
                color: ThumbnailDocumentColor(color: configuration.textColor),
                size: Double(configuration.textSize),
                verticalAlignmentRawValue: configuration.verticalAlignment.rawValue,
                horizontalAlignmentRawValue: configuration.horizontalAlignment.rawValue,
                transform: configuration.textTransform,
                selectedFontRawValue: configuration.selectedFont.rawValue
            ),
            profile: configuration.circularProfile.map {
                ThumbnailDocumentProfile(
                    imageData: Self.encodedImageData(from: $0.image),
                    size: Double($0.size),
                    transform: configuration.profileTransform
                )
            },
            layers: configuration.layers.reconciledForCurrentOverlays(
                hasText: !configuration.overlayText.isEmpty,
                hasProfile: configuration.circularProfile?.image != nil
            ),
            macro: ThumbnailDocumentMacro(configuration.macroConfig),
            export: ThumbnailDocumentExport(options: configuration.exportOptions)
        )
    }

    func makeSimpleConfiguration() -> SimpleMakerConfigurationModel {
        var configuration = SimpleMakerConfigurationModel()
        applySharedState(to: &configuration)
        return configuration
    }

    func makePremiumConfiguration() -> PremiumMakerConfigurationModel {
        var configuration = PremiumMakerConfigurationModel()
        applySharedState(to: &configuration)
        configuration.circularProfile = profile.map {
            CircularProfileConfig(
                image: $0.imageData.flatMap(UIImage.init(data:)),
                size: CGFloat($0.size)
            )
        }
        configuration.profileTransform = profile?.transform ?? .profileDefault
        configuration.macroConfig = macro.makeConfiguration()
        return configuration
    }

    private func applySharedState(to configuration: inout SimpleMakerConfigurationModel) {
        configuration.selectedImage = imageData.flatMap(UIImage.init(data:))
        configuration.overlayText = text.value
        configuration.selectedRatio = AspectRatio(rawValue: canvas.aspectRatioRawValue) ?? .ratio16_9
        configuration.backgroundColor = canvas.backgroundColor.color
        configuration.textColor = text.color.color
        configuration.textSize = CGFloat(text.size)
        configuration.verticalAlignment = VerticalAlignment(rawValue: text.verticalAlignmentRawValue) ?? .center
        configuration.horizontalAlignment = HorizontalAlignment(rawValue: text.horizontalAlignmentRawValue) ?? .center
        configuration.textTransform = text.transform
        configuration.selectedFont = CustomFont(rawValue: text.selectedFontRawValue) ?? .goNoto
        configuration.layers = layers.reconciledForCurrentOverlays(
            hasText: !text.value.isEmpty,
            hasProfile: false
        )
        configuration.exportOptions = export.makeOptions()
    }

    private func applySharedState(to configuration: inout PremiumMakerConfigurationModel) {
        configuration.selectedImage = imageData.flatMap(UIImage.init(data:))
        configuration.overlayText = text.value
        configuration.selectedRatio = AspectRatio(rawValue: canvas.aspectRatioRawValue) ?? .ratio16_9
        configuration.backgroundColor = canvas.backgroundColor.color
        configuration.textColor = text.color.color
        configuration.textSize = CGFloat(text.size)
        configuration.verticalAlignment = VerticalAlignment(rawValue: text.verticalAlignmentRawValue) ?? .center
        configuration.horizontalAlignment = HorizontalAlignment(rawValue: text.horizontalAlignmentRawValue) ?? .center
        configuration.textTransform = text.transform
        configuration.selectedFont = CustomFont(rawValue: text.selectedFontRawValue) ?? .goNoto
        configuration.layers = layers.reconciledForCurrentOverlays(
            hasText: !text.value.isEmpty,
            hasProfile: profile?.imageData != nil
        )
        configuration.exportOptions = export.makeOptions()
    }

    private static func encodedImageData(from image: UIImage?) -> Data? {
        image?.jpegData(compressionQuality: 0.92) ?? image?.pngData()
    }
}

private extension ThumbnailDocumentExport {
    init(options: ThumbnailExportOptions) {
        self.init(
            presetID: options.preset.id,
            formatRawValue: options.format.rawValue,
            compressionQuality: options.compressionQuality,
            usesCustomSize: options.usesCustomSize,
            customWidth: options.customSize.width,
            customHeight: options.customSize.height
        )
    }

    func makeOptions() -> ThumbnailExportOptions {
        var options = ThumbnailExportOptions()
        if let preset = ThumbnailExportPreset.all.first(where: { $0.id == presetID }) {
            options.applyPreset(preset)
        }
        options.format = ThumbnailExportFormat(rawValue: formatRawValue) ?? .png
        options.compressionQuality = compressionQuality
        options.usesCustomSize = usesCustomSize
        options.customSize = ThumbnailExportSize(width: customWidth, height: customHeight)
        return options
    }
}

private extension ThumbnailDocumentMacro {
    init(_ configuration: MacroConfig) {
        self.init(
            isEnabled: configuration.isEnabled,
            startNumber: configuration.startNumber,
            endNumber: configuration.endNumber,
            appendPositionRawValue: configuration.appendPosition.rawValue
        )
    }

    func makeConfiguration() -> MacroConfig {
        MacroConfig(
            isEnabled: isEnabled,
            startNumber: startNumber,
            endNumber: endNumber,
            appendPosition: MacroConfig.AppendPosition(rawValue: appendPositionRawValue) ?? .after
        )
    }
}
