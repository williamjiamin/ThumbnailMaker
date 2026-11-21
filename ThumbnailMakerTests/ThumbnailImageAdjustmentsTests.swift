//
//  ThumbnailImageAdjustmentsTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-14: the adjustment recipe model - normalisation, persistence,
//  reconciliation, back-compat, undo, templates and pixel safety.
//

import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ThumbnailImageAdjustmentsTests {
    private let heavy = ThumbnailImageAdjustments(brightness: 0.3, contrast: 1.5, saturation: 0, blur: 0.05, vignette: 1)
    private let warm = ThumbnailImageAdjustments(brightness: 0.1, contrast: 1.2, saturation: 1.3)

    @Test func neutralRecipeNormalizesToNilAndEncodesIdentically() throws {
        var document = try makeDocument()
        let original = try encode(document)

        document.layers.setAdjustments(ThumbnailImageAdjustments(brightness: 0.2), forLayerID: ThumbnailDocumentLayer.backgroundID)
        #expect(document.layers.record(id: ThumbnailDocumentLayer.backgroundID)?.adjustments?.brightness == 0.2)
        #expect(try encode(document) != original)

        document.layers.resetAdjustments(forLayerID: ThumbnailDocumentLayer.backgroundID)
        #expect(document.layers.record(id: ThumbnailDocumentLayer.backgroundID)?.adjustments == nil)
        #expect(try encode(document) == original, "Reset must leave no JSON residue.")

        // A slider left a hair off neutral still counts as neutral.
        document.layers.setAdjustments(
            ThumbnailImageAdjustments(contrast: 1.000_000_000_1),
            forLayerID: ThumbnailDocumentLayer.backgroundID
        )
        #expect(document.layers.record(id: ThumbnailDocumentLayer.backgroundID)?.adjustments == nil)
    }

    @Test func documentsWithoutAdjustmentsHaveNoAdjustmentsKey() throws {
        let json = try #require(String(data: encode(try makeDocument()), encoding: .utf8))
        #expect(!json.contains("adjustments"))
    }

    @Test func originalPixelsAndAlphaSurviveAdjustAndReset() throws {
        let image = try alphaFixture()
        let expected = try pixels(image)
        var configuration = SimpleMakerConfigurationModel()
        configuration.selectedImage = image
        configuration.overlayText = "Cutout"
        let layerData = try #require(image.pngData())
        let layerID = configuration.layers.addImageLayer(imageData: layerData)

        configuration.layers.setAdjustments(heavy, forLayerID: ThumbnailDocumentLayer.backgroundID)
        configuration.layers.setAdjustments(heavy, forLayerID: layerID)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json"))
        try store.save(configuration.document.makeSimpleConfiguration())
        var restored = try #require(try store.load())

        // Adjusted (not reset): the recipe never writes pixels.
        #expect(restored.layers.adjustments(forLayerID: ThumbnailDocumentLayer.backgroundID) == heavy)
        #expect(restored.layers.adjustments(forLayerID: layerID) == heavy)
        #expect(try pixels(#require(restored.selectedImage)) == expected)
        #expect(try imageData(of: layerID, in: restored.layers) == layerData)

        restored.layers.resetAdjustments(forLayerID: ThumbnailDocumentLayer.backgroundID)
        restored.layers.resetAdjustments(forLayerID: layerID)
        try store.save(restored)
        let reset = try #require(try store.load())
        #expect(reset.layers.allSatisfy { $0.adjustments == nil })
        #expect(try pixels(#require(reset.selectedImage)) == expected)
        #expect(try imageData(of: layerID, in: reset.layers) == layerData)
    }

    @Test func singletonLayerAdjustmentsSurviveReconciliation() throws {
        let image = try alphaFixture()
        var configuration = PremiumMakerConfigurationModel()
        configuration.selectedImage = image
        configuration.overlayText = "Title"
        configuration.circularProfile = CircularProfileConfig(image: image, size: 0.2)
        configuration.layers = configuration.layers.reconciledForCurrentOverlays(hasText: true, hasProfile: true)
        let layerID = configuration.layers.addImageLayer(imageData: try #require(image.pngData()))

        configuration.layers.setAdjustments(heavy, forLayerID: ThumbnailDocumentLayer.backgroundID)
        configuration.layers.setAdjustments(warm, forLayerID: ThumbnailDocumentLayer.profileID)
        configuration.layers.setAdjustments(warm, forLayerID: ThumbnailDocumentLayer.textID)
        configuration.layers.setAdjustments(heavy, forLayerID: layerID)

        let reconciled = configuration.layers.reconciledForCurrentOverlays(hasText: true, hasProfile: true)
        #expect(reconciled.adjustments(forLayerID: ThumbnailDocumentLayer.backgroundID) == heavy)
        #expect(reconciled.adjustments(forLayerID: ThumbnailDocumentLayer.profileID) == warm)
        #expect(reconciled.adjustments(forLayerID: ThumbnailDocumentLayer.textID) == warm)
        #expect(reconciled.adjustments(forLayerID: layerID) == heavy)

        let twice = configuration.document.makePremiumConfiguration().document.makePremiumConfiguration()
        #expect(twice.layers.adjustments(forLayerID: ThumbnailDocumentLayer.backgroundID) == heavy)
        #expect(twice.layers.adjustments(forLayerID: ThumbnailDocumentLayer.profileID) == warm)
        #expect(twice.layers.adjustments(forLayerID: layerID) == heavy)

        let decoded = try roundTrip(twice.document)
        #expect(decoded.layers.adjustments(forLayerID: ThumbnailDocumentLayer.profileID) == warm)
    }

    @Test func legacyDocumentsWithoutAdjustmentsStillOpen() throws {
        // A v4 document (pre image-frame recipe, pre adjustments).
        let data = try encode(try makeDocument())
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["version"] = 4
        object.removeValue(forKey: "imageRecipe")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let legacy = try decoder().decode(ThumbnailDocument.self, from: legacyData)
        #expect(legacy.layers.allSatisfy { $0.adjustments == nil })
        #expect(legacy.version == ThumbnailDocument.currentVersion)
        let again = try roundTrip(legacy)
        #expect(again == legacy)
        let configuration = legacy.makeSimpleConfiguration()
        #expect(configuration.layers.adjustments(forLayerID: ThumbnailDocumentLayer.backgroundID).isNeutral)
    }

    @Test func undoAndRedoRestoreAdjustments() throws {
        let before = try makeDocument()
        var after = before
        after.layers.setAdjustments(warm, forLayerID: ThumbnailDocumentLayer.backgroundID)

        var history = ThumbnailDocumentHistory()
        history.record(before)
        let undoResult = history.undo(current: after)
        let undone = try #require(undoResult)
        #expect(undone.layers.record(id: ThumbnailDocumentLayer.backgroundID)?.adjustments == nil)
        let redoResult = history.redo(current: undone)
        let redone = try #require(redoResult)
        #expect(redone.layers.adjustments(forLayerID: ThumbnailDocumentLayer.backgroundID) == warm)
    }

    @Test func clampingRejectsOutOfRangeAndNonFiniteValues() throws {
        let json = #"{"brightness": -50, "contrast": 99, "blur": "garbage", "vignette": 0.4}"#
        let decoded = try JSONDecoder().decode(ThumbnailImageAdjustments.self, from: Data(json.utf8))
        #expect(decoded.brightness == ThumbnailImageAdjustments.brightnessRange.lowerBound)
        #expect(decoded.contrast == ThumbnailImageAdjustments.contrastRange.upperBound)
        #expect(decoded.saturation == 1)
        #expect(decoded.blur == 0)
        #expect(decoded.vignette == 0.4)
        #expect(!decoded.isNeutral)

        let empty = try JSONDecoder().decode(ThumbnailImageAdjustments.self, from: Data("{}".utf8))
        #expect(empty.isNeutral)

        let nonFinite = ThumbnailImageAdjustments(brightness: .nan, contrast: .infinity, saturation: -.infinity, blur: .nan, vignette: 7).clamped()
        #expect(nonFinite.brightness == 0)
        #expect(nonFinite.contrast == 1)
        #expect(nonFinite.saturation == 1)
        #expect(nonFinite.blur == 0)
        #expect(nonFinite.vignette == 1)

        // Setting an out-of-range recipe stores the clamped value.
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: false, hasProfile: false)
        layers.setAdjustments(ThumbnailImageAdjustments(blur: 5), forLayerID: ThumbnailDocumentLayer.backgroundID)
        #expect(layers.adjustments(forLayerID: ThumbnailDocumentLayer.backgroundID).blur == ThumbnailImageAdjustments.blurRange.upperBound)
    }

    @Test func blurRadiusScalesLinearlyWithRenderedSize() {
        let recipe = ThumbnailImageAdjustments(blur: 0.04)
        let large = recipe.blurRadius(forRenderedSize: CGSize(width: 1280, height: 720))
        let small = recipe.blurRadius(forRenderedSize: CGSize(width: 320, height: 180))
        #expect(abs(large - 720 * 0.04) < 1e-9)
        #expect(abs(large / small - 4) < 1e-9)
        #expect(ThumbnailImageAdjustments(blur: 0).blurRadius(forRenderedSize: CGSize(width: 1280, height: 720)) == 0)
    }

    @Test func builtInLooksAreInsideDeclaredRangesAndDistinct() {
        let looks = ThumbnailLookLibrary.builtIns
        #expect(looks.count == 5)
        #expect(Set(looks.map(\.id)).count == looks.count)
        for look in looks {
            #expect(look.adjustments == look.adjustments.clamped(), "\(look.name) is out of range")
            #expect(!look.adjustments.isNeutral, "\(look.name) does nothing")
            #expect(look.isBuiltIn)
        }
    }

    @Test func applyingLookSetsExactRecipeAndNeutralLookClearsIt() throws {
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: true, hasProfile: false)
        let look = try #require(ThumbnailLookLibrary.builtIns.first { $0.id == "look-moody" })
        layers.applyLook(look, toLayerID: ThumbnailDocumentLayer.backgroundID)
        #expect(layers.adjustments(forLayerID: ThumbnailDocumentLayer.backgroundID) == look.adjustments)

        let neutralLook = ThumbnailLook(name: "Nothing", adjustments: .neutral)
        layers.applyLook(neutralLook, toLayerID: ThumbnailDocumentLayer.backgroundID)
        #expect(layers.record(id: ThumbnailDocumentLayer.backgroundID)?.adjustments == nil)
    }

    @Test func settingAdjustmentsCreatesMissingSingletonButNeverAppendsUnknownContent() {
        var layers: [ThumbnailDocumentLayer] = []
        layers.setAdjustments(warm, forLayerID: ThumbnailDocumentLayer.profileID)
        #expect(layers.count == 1)
        #expect(layers.first?.kind == .profile)
        layers.setAdjustments(warm, forLayerID: "missing-layer")
        #expect(layers.count == 1)
        layers.setAdjustments(.neutral, forLayerID: ThumbnailDocumentLayer.backgroundID)
        #expect(layers.count == 1, "A neutral recipe must not create a record.")
    }

    @Test func templatePreservesAdjustmentsWithThePreservedImages() throws {
        let image = try alphaFixture()
        var configuration = PremiumMakerConfigurationModel()
        configuration.selectedImage = image
        configuration.overlayText = "Before"
        configuration.circularProfile = CircularProfileConfig(image: image, size: 0.2)
        configuration.layers = configuration.layers.reconciledForCurrentOverlays(hasText: true, hasProfile: true)
        let layerID = configuration.layers.addImageLayer(imageData: try #require(image.pngData()))
        configuration.layers.setAdjustments(heavy, forLayerID: ThumbnailDocumentLayer.backgroundID)
        configuration.layers.setAdjustments(warm, forLayerID: ThumbnailDocumentLayer.profileID)
        configuration.layers.setAdjustments(warm, forLayerID: layerID)
        let existing = configuration.document

        for template in ThumbnailTemplate.builtIns {
            let applied = template.makeDocument(preservingImagesFrom: existing)
            #expect(applied.imageData == existing.imageData)
            #expect(applied.layers.adjustments(forLayerID: ThumbnailDocumentLayer.backgroundID) == heavy, "\(template.name) lost the photo recipe")
            #expect(applied.layers.adjustments(forLayerID: layerID) == warm)
            if applied.profile?.imageData == existing.profile?.imageData {
                #expect(applied.layers.adjustments(forLayerID: ThumbnailDocumentLayer.profileID) == warm, "\(template.name) lost the profile recipe")
            }
            let reopened = applied.makePremiumConfiguration()
            #expect(reopened.layers.adjustments(forLayerID: ThumbnailDocumentLayer.backgroundID) == heavy)
        }
    }

    @Test func canAdjustLayerRejectsTextAndShapeAndMissingImages() throws {
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: true, hasProfile: true)
        let imageID = layers.addImageLayer(imageData: try #require(try alphaFixture().pngData()))
        let textID = layers.addTextLayer(value: "Hi")
        let shapeID = layers.addShapeLayer()

        #expect(!layers.canAdjustLayer(id: ThumbnailDocumentLayer.backgroundID, hasBaseImage: false, hasProfileImage: false))
        #expect(layers.canAdjustLayer(id: ThumbnailDocumentLayer.backgroundID, hasBaseImage: true, hasProfileImage: false))
        #expect(!layers.canAdjustLayer(id: ThumbnailDocumentLayer.profileID, hasBaseImage: true, hasProfileImage: false))
        #expect(layers.canAdjustLayer(id: ThumbnailDocumentLayer.profileID, hasBaseImage: true, hasProfileImage: true))
        #expect(!layers.canAdjustLayer(id: ThumbnailDocumentLayer.textID, hasBaseImage: true, hasProfileImage: true))
        #expect(!layers.canAdjustLayer(id: textID, hasBaseImage: true, hasProfileImage: true))
        #expect(!layers.canAdjustLayer(id: shapeID, hasBaseImage: true, hasProfileImage: true))
        #expect(layers.canAdjustLayer(id: imageID, hasBaseImage: false, hasProfileImage: false))

        let targets = layers.adjustableImages(hasBaseImage: true, hasProfileImage: true).map(\.target)
        #expect(targets == [.baseImage, .profileImage, .contentLayer(imageID)])
        #expect(layers.adjustableImages(hasBaseImage: false, hasProfileImage: false).map(\.target) == [.contentLayer(imageID)])
    }

    @Test func accessibilitySummaryDescribesTheRecipe() {
        #expect(ThumbnailImageAdjustments.neutral.accessibilitySummary == "No adjustments")
        let summary = ThumbnailImageAdjustments(brightness: 0.12, contrast: 1.1, saturation: 1.2, vignette: 0.3).accessibilitySummary
        #expect(summary == "Brightness +12%, contrast 110%, saturation 120%, blur off, vignette 30%")
    }

    // MARK: Helpers

    private func makeDocument() throws -> ThumbnailDocument {
        var configuration = SimpleMakerConfigurationModel()
        configuration.selectedImage = try alphaFixture()
        configuration.overlayText = "Title"
        var document = configuration.document
        document.updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        return document
    }

    private func encode(_ document: ThumbnailDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func roundTrip(_ document: ThumbnailDocument) throws -> ThumbnailDocument {
        try decoder().decode(ThumbnailDocument.self, from: encode(document))
    }

    private func imageData(of layerID: String, in layers: [ThumbnailDocumentLayer]) throws -> Data {
        let layer = try #require(layers.record(id: layerID))
        guard case .image(let content) = layer.content else {
            Issue.record("Layer \(layerID) is not an image layer")
            return Data()
        }
        return content.imageData
    }

    private func alphaFixture() throws -> UIImage {
        let rgba = Data([0, 0, 0, 0, 64, 0, 0, 64, 0, 128, 0, 128, 0, 0, 255, 255])
        let provider = try #require(CGDataProvider(data: rgba as CFData))
        let image = try #require(CGImage(
            width: 4, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                .union(.byteOrder32Big),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        return UIImage(cgImage: image)
    }

    private func pixels(_ image: UIImage) throws -> [UInt8] {
        let cgImage = try #require(image.cgImage)
        let context = try #require(CGContext(
            data: nil, width: cgImage.width, height: cgImage.height, bitsPerComponent: 8,
            bytesPerRow: cgImage.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        let data = try #require(context.data)
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: cgImage.width * cgImage.height * 4))
    }
}
