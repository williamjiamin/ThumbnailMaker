//
//  ThumbnailCutoutMaskTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-11: the cutout recipe — persistence, back-compat, clamping,
//  immutability of the original bytes, undo/redo and duplication.
//

import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ThumbnailCutoutMaskTests {
    // MARK: Back-compat / persistence

    @Test func legacyDocumentWithoutCutoutDecodesToNil() throws {
        let data = try #require(CutoutFixtures.solidPNG(width: 20, height: 10))
        var document = ThumbnailDocument(imageData: data)
        _ = document.layers.addImageLayer(imageData: data)
        let json = try CutoutFixtures.encode(document)
        let text = try #require(String(data: json, encoding: .utf8))
        #expect(!text.contains("cutout"), "A document with no cutout must encode byte-compatibly with older builds.")

        let decoded = try CutoutFixtures.decode(json)
        #expect(decoded.layers.allSatisfy { $0.cutout == nil })
        #expect(decoded.version == ThumbnailDocument.currentVersion)
    }

    @Test func cutoutRoundTripsThroughThumbnailDraftStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("draft.json"))

        let data = try #require(CutoutFixtures.solidPNG(width: 40, height: 20))
        var document = ThumbnailDocument(imageData: data)
        let layerID = document.layers.addImageLayer(imageData: data)
        let base = try CutoutFixtures.uniformBase(value: 200, sourceWidth: 40, sourceHeight: 20)
        document.layers.setAutomaticCutoutBase(base, forLayerID: layerID)
        let stroke = ThumbnailCutoutStroke(
            mode: .restore,
            points: [ThumbnailCutoutPoint(x: 0.1, y: 0.2), ThumbnailCutoutPoint(x: 0.7, y: 0.9)],
            radius: 0.07,
            softness: 0.4,
            opacity: 0.8
        )
        let appended = document.layers.appendCutoutStroke(stroke, toLayerID: layerID)
        #expect(appended)
        document.layers.setCutoutFeather(0.03, forLayerID: layerID)

        try store.save(document)
        let loaded = try #require(try store.loadDocument())
        let mask = try #require(loaded.layers.cutout(forLayerID: layerID))
        #expect(mask.strokes == [stroke])
        #expect(mask.strokes.first?.mode == .restore)
        #expect(mask.automaticBase == base)
        #expect(mask.feather == 0.03)
        #expect(mask.sourcePixelWidth == 40 && mask.sourcePixelHeight == 20)
    }

    @Test func decodeClampsOutOfRangeRecipeValues() throws {
        let json = """
        {"isEnabled": true, "feather": -1,
         "strokes": [
           {"id": "a", "mode": "erase", "radius": 9.0, "softness": 5, "opacity": 3, "points": [{"x": 2, "y": -1}]},
           {"id": "b", "mode": "future-mode", "radius": -1, "points": [{"x": 0.5, "y": 0.5}]},
           {"id": "c", "mode": "erase", "radius": 0.1, "points": []}
         ]}
        """
        let mask = try JSONDecoder().decode(ThumbnailCutoutMask.self, from: Data(json.utf8))
        #expect(mask.feather == 0)
        #expect(mask.strokes.count == 2, "A stroke with no points is dropped.")
        #expect(mask.strokes[0].radius == 0.5)
        #expect(mask.strokes[0].softness == 1)
        #expect(mask.strokes[0].opacity == 1)
        #expect(mask.strokes[0].points == [ThumbnailCutoutPoint(x: 1, y: 0)])
        #expect(mask.strokes[1].radius == 0.002)
        #expect(mask.strokes[1].mode == .erase, "Unknown modes decode as erase.")
        #expect(mask.strokes[1].modeRawValue == "future-mode", "…but the raw value is preserved.")

        let nan = ThumbnailCutoutStroke(mode: .erase, points: [ThumbnailCutoutPoint(x: .nan, y: 0.5)], radius: .nan)
        let clamped = nan.clamped()
        #expect(clamped.radius.isFinite)
        #expect(clamped.points[0].x.isFinite)
    }

    @Test func corruptCutoutNeverMakesTheDocumentUnopenable() throws {
        let data = try #require(CutoutFixtures.solidPNG(width: 8, height: 8))
        var document = ThumbnailDocument(imageData: data)
        let layerID = document.layers.addImageLayer(imageData: data)
        document.layers.appendCutoutStroke(
            ThumbnailCutoutStroke(mode: .erase, points: [ThumbnailCutoutPoint(x: 0.5, y: 0.5)], radius: 0.1),
            toLayerID: layerID
        )
        let json = try CutoutFixtures.encode(document)
        var object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        var layers = try #require(object["layers"] as? [[String: Any]])
        let index = try #require(layers.firstIndex { ($0["id"] as? String) == layerID })
        layers[index]["cutout"] = "not a mask"
        object["layers"] = layers
        let corrupted = try JSONSerialization.data(withJSONObject: object)

        let decoded = try CutoutFixtures.decode(corrupted)
        #expect(decoded.layers.record(id: layerID) != nil)
        #expect(decoded.layers.cutout(forLayerID: layerID)?.isActive != true)
    }

    // MARK: Invariants

    @Test func imageDataIsNeverMutatedByAnyCutoutEdit() throws {
        let data = try #require(CutoutFixtures.solidPNG(width: 16, height: 16))
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: false, hasProfile: false)
        let layerID = layers.addImageLayer(imageData: data)
        func bytes() -> Data? {
            guard case .image(let content) = layers.record(id: layerID)?.content else { return nil }
            return content.imageData
        }

        let stroke = ThumbnailCutoutStroke(mode: .erase, points: [ThumbnailCutoutPoint(x: 0.5, y: 0.5)], radius: 0.2)
        layers.appendCutoutStroke(stroke, toLayerID: layerID)
        #expect(bytes() == data)
        layers.setCutoutFeather(0.04, forLayerID: layerID)
        #expect(bytes() == data)
        layers.setCutoutEnabled(false, forLayerID: layerID)
        #expect(bytes() == data)
        layers.setAutomaticCutoutBase(try CutoutFixtures.uniformBase(value: 0, sourceWidth: 16, sourceHeight: 16), forLayerID: layerID)
        #expect(bytes() == data)
        let removedStroke = layers.removeLastCutoutStroke(fromLayerID: layerID)
        #expect(removedStroke == stroke.clamped())
        #expect(bytes() == data)
        layers.resetCutout(forLayerID: layerID)
        #expect(bytes() == data)
        #expect(layers.cutout(forLayerID: layerID) == nil)
    }

    @Test func updateCutoutDropsAnIdentityMaskBackToNil() throws {
        let data = try #require(CutoutFixtures.solidPNG(width: 8, height: 8))
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: false, hasProfile: false)
        let layerID = layers.addImageLayer(imageData: data)
        let before = layers

        layers.updateCutout(id: layerID) { _ in }
        #expect(layers == before, "A no-op session must leave the layers exactly equal.")

        layers.appendCutoutStroke(
            ThumbnailCutoutStroke(mode: .erase, points: [ThumbnailCutoutPoint(x: 0.2, y: 0.2)], radius: 0.1),
            toLayerID: layerID
        )
        #expect(layers.cutout(forLayerID: layerID) != nil)
        layers.removeLastCutoutStroke(fromLayerID: layerID)
        #expect(layers.cutout(forLayerID: layerID) == nil)
        #expect(layers == before)

        // Unknown content ids are never appended; the base photo record is created on demand.
        var missing = [ThumbnailDocumentLayer]()
        missing.setCutoutFeather(0.02, forLayerID: "nope")
        #expect(missing.isEmpty)
        missing.setCutoutFeather(0.02, forLayerID: ThumbnailDocumentLayer.backgroundID)
        #expect(missing.cutout(forLayerID: ThumbnailDocumentLayer.backgroundID)?.feather == 0.02)
    }

    @Test func duplicateContentLayerProducesAnIndependentCutout() throws {
        let data = try #require(CutoutFixtures.solidPNG(width: 8, height: 8))
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: false, hasProfile: false)
        let layerID = layers.addImageLayer(imageData: data)
        layers.appendCutoutStroke(
            ThumbnailCutoutStroke(mode: .erase, points: [ThumbnailCutoutPoint(x: 0.2, y: 0.2)], radius: 0.1),
            toLayerID: layerID
        )
        let duplicatedID = layers.duplicateContentLayer(id: layerID)
        let copyID = try #require(duplicatedID)
        layers.appendCutoutStroke(
            ThumbnailCutoutStroke(mode: .erase, points: [ThumbnailCutoutPoint(x: 0.8, y: 0.8)], radius: 0.1),
            toLayerID: copyID
        )

        let original = try #require(layers.cutout(forLayerID: layerID))
        let copy = try #require(layers.cutout(forLayerID: copyID))
        #expect(original.strokes.count == 1)
        #expect(copy.strokes.count == 2)
        #expect(Set(original.strokes.map(\.id)).isDisjoint(with: copy.strokes.map(\.id)))
    }

    @Test func historyUndoRedoRestoresStrokesAndBase() throws {
        let data = try #require(CutoutFixtures.solidPNG(width: 8, height: 8))
        var document = ThumbnailDocument(imageData: data)
        let layerID = document.layers.addImageLayer(imageData: data)
        var history = ThumbnailDocumentHistory()

        let before = ThumbnailDocumentHistory.snapshot(document)
        history.record(before)
        document.layers.setAutomaticCutoutBase(try CutoutFixtures.uniformBase(value: 90, sourceWidth: 8, sourceHeight: 8), forLayerID: layerID)
        document.layers.appendCutoutStroke(
            ThumbnailCutoutStroke(mode: .restore, points: [ThumbnailCutoutPoint(x: 0.5, y: 0.5)], radius: 0.2),
            toLayerID: layerID
        )
        let after = ThumbnailDocumentHistory.snapshot(document)

        let undone = history.undo(current: after)
        let restored = try #require(undone)
        #expect(restored.layers.cutout(forLayerID: layerID) == nil)

        let redone = history.redo(current: restored)
        let reapplied = try #require(redone)
        #expect(reapplied.layers.cutout(forLayerID: layerID) == after.layers.cutout(forLayerID: layerID))
        #expect(reapplied.layers.cutout(forLayerID: layerID)?.strokes.count == 1)
    }

    @Test func reconciledLayersKeepTheBaseCutout() throws {
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: false, hasProfile: false)
        layers.setCutoutFeather(0.02, forLayerID: ThumbnailDocumentLayer.backgroundID)
        let reconciled = layers.reconciledForCurrentOverlays(hasText: true, hasProfile: false)
        #expect(reconciled.cutout(forLayerID: ThumbnailDocumentLayer.backgroundID)?.feather == 0.02)
    }

    @Test func builtInTemplateCarriesTheBasePhotoCutout() throws {
        let data = try #require(CutoutFixtures.solidPNG(width: 12, height: 12))
        var document = ThumbnailDocument(imageData: data)
        document.layers.setCutoutFeather(0.05, forLayerID: ThumbnailDocumentLayer.backgroundID)
        let template = try #require(ThumbnailTemplate.builtIns.first)
        let applied = template.makeDocument(preservingImagesFrom: document)
        #expect(applied.imageData == data)
        #expect(applied.layers.cutout(forLayerID: ThumbnailDocumentLayer.backgroundID)?.feather == 0.05)
    }

    @Test func fingerprintChangesWithEveryRecipeEditButNotWithImageBytes() throws {
        var mask = ThumbnailCutoutMask()
        let empty = mask.fingerprint
        mask.appendStroke(ThumbnailCutoutStroke(id: "s", mode: .erase, points: [ThumbnailCutoutPoint(x: 0.1, y: 0.1)], radius: 0.1))
        let one = mask.fingerprint
        #expect(one != empty)
        var moved = mask
        moved.strokes[0].points[0].x = 0.2
        #expect(moved.fingerprint != one)
        var feathered = mask
        feathered.feather = 0.01
        #expect(feathered.fingerprint != one)
        var disabled = mask
        disabled.isEnabled = false
        #expect(disabled.fingerprint != one)
        #expect(mask.fingerprint == one, "Stable for an unchanged recipe.")
    }
}

// MARK: - Fixtures shared by the cutout test files

enum CutoutFixtures {
    static func encode(_ document: ThumbnailDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(document)
    }

    static func decode(_ data: Data) throws -> ThumbnailDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ThumbnailDocument.self, from: data)
    }

    static func solidPNG(width: Int, height: Int, color: UIColor = .orange) -> Data? {
        solidImage(width: width, height: height, color: color).pngData()
    }

    static func solidImage(width: Int, height: Int, color: UIColor = .orange) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// An sRGB premultiplied RGBA image built from explicit bytes.
    static func image(width: Int, height: Int, pixel: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> UIImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b, a) = pixel(x, y)
                let offset = (y * width + x) * 4
                // Premultiplied storage.
                bytes[offset] = UInt8((Int(r) * Int(a) + 127) / 255)
                bytes[offset + 1] = UInt8((Int(g) * Int(a) + 127) / 255)
                bytes[offset + 2] = UInt8((Int(b) * Int(a) + 127) / 255)
                bytes[offset + 3] = a
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    /// Premultiplied RGBA bytes, row 0 = top.
    static func rgba(_ image: UIImage) -> (width: Int, height: Int, bytes: [UInt8]) {
        let cgImage = ThumbnailCutoutMaskRenderer.uprightCGImage(of: image)!
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.setBlendMode(.copy)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (width, height, bytes)
    }

    static func alpha(_ pixels: (width: Int, height: Int, bytes: [UInt8]), x: Int, y: Int) -> Int {
        Int(pixels.bytes[(y * pixels.width + x) * 4 + 3])
    }

    static func pixel(_ pixels: (width: Int, height: Int, bytes: [UInt8]), x: Int, y: Int) -> [UInt8] {
        let offset = (y * pixels.width + x) * 4
        return Array(pixels.bytes[offset..<(offset + 4)])
    }

    /// Gray bytes of a mask raster, row 0 = top.
    static func gray(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }

    static func uniformBase(value: UInt8, sourceWidth: Int, sourceHeight: Int) throws -> ThumbnailCutoutAutomaticBase {
        let width = max(1, min(sourceWidth, 64))
        let height = max(1, min(sourceHeight, 64))
        let bytes = [UInt8](repeating: value, count: width * height)
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let gray = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        return try ThumbnailCutoutMaskRenderer.makeAutomaticBase(
            fromGrayMask: gray,
            sourcePixelWidth: sourceWidth,
            sourcePixelHeight: sourceHeight
        )
    }
}
