//
//  ThumbnailImageFrameRecipePersistenceTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-03: the framing recipe is persisted, back-compatible with v4
//  documents, reversible through history, and never touches image pixels.
//

import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ThumbnailImageFrameRecipePersistenceTests {
    private let customRecipe = ThumbnailImageFrameRecipe(fit: .fill, focusX: 0.2, focusY: 0.8, zoom: 3)

    @Test func documentsWithoutRecipeDecodeAsIdentityAndUpgrade() throws {
        var configuration = PremiumMakerConfigurationModel()
        configuration.selectedImage = try alphaFixture()
        configuration.overlayText = "Legacy title"
        configuration.imageRecipe = customRecipe
        let encoded = try encoder().encode(ThumbnailDocument(configuration: configuration))

        var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["imageRecipe"] != nil)
        object.removeValue(forKey: "imageRecipe")
        object["version"] = 4
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let legacy = try decoder().decode(ThumbnailDocument.self, from: legacyData)
        #expect(legacy.imageRecipe == .identity)
        #expect(legacy.version == ThumbnailDocument.currentVersion)
        #expect(ThumbnailDocument.currentVersion == 5)
        #expect(legacy.text.value == "Legacy title")
        #expect(legacy.imageData != nil)
        #expect(legacy.makePremiumConfiguration().imageRecipe == .identity)
        #expect(legacy.makeSimpleConfiguration().imageRecipe == .identity)
    }

    @Test func corruptRecipeValuesAreSanitizedOnDecode() throws {
        let json = #"{"fitRawValue":"bogus","focusX":7,"focusY":-2,"zoom":1000}"#
        let recipe = try decoder().decode(ThumbnailImageFrameRecipe.self, from: Data(json.utf8))
        #expect(recipe.fit == .fit)
        #expect(recipe.focusX == 1)
        #expect(recipe.focusY == 0)
        #expect(recipe.zoom == 8)

        let empty = try decoder().decode(ThumbnailImageFrameRecipe.self, from: Data("{}".utf8))
        #expect(empty == .identity)
    }

    @Test func recipeRoundTripsThroughBothEditorsAndDraftStore() throws {
        var simple = SimpleMakerConfigurationModel()
        simple.selectedImage = try alphaFixture()
        simple.imageRecipe = customRecipe
        #expect(try roundTrip(simple.document).makeSimpleConfiguration().imageRecipe == customRecipe)

        var premium = PremiumMakerConfigurationModel()
        premium.selectedImage = try alphaFixture()
        premium.imageRecipe = customRecipe
        #expect(try roundTrip(premium.document).makePremiumConfiguration().imageRecipe == customRecipe)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let simpleStore = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json"))
        try simpleStore.save(simple)
        #expect(try #require(try simpleStore.load()).imageRecipe == customRecipe)

        let premiumStore = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium.json"))
        try premiumStore.save(premium)
        #expect(try #require(try premiumStore.loadPremium()).imageRecipe == customRecipe)
    }

    @Test func framingNeverTouchesOriginalPixels() throws {
        let image = try alphaFixture()
        let expected = try pixels(image)
        var configuration = SimpleMakerConfigurationModel()
        configuration.selectedImage = image
        configuration.imageRecipe = customRecipe

        for _ in 0..<20 {
            configuration = try roundTrip(ThumbnailDocument(configuration: configuration)).makeSimpleConfiguration()
            let restored = try #require(configuration.selectedImage)
            #expect(try pixels(restored) == expected)
            #expect(restored.size == image.size)
            #expect(configuration.imageRecipe == customRecipe)
        }
        #expect(stride(from: 3, to: expected.count, by: 4).map { expected[$0] } == [0, 64, 128, 255])
    }

    @Test func historyUndoesAndRedoesRecipe() throws {
        var configuration = SimpleMakerConfigurationModel()
        configuration.selectedImage = try alphaFixture()
        let before = ThumbnailDocument(configuration: configuration)
        configuration.imageRecipe = customRecipe
        let after = ThumbnailDocument(configuration: configuration)

        var history = ThumbnailDocumentHistory()
        history.record(before)
        let undoResult = history.undo(current: after)
        let undone = try #require(undoResult)
        #expect(undone.imageRecipe == .identity)
        let redoResult = history.redo(current: undone)
        let redone = try #require(redoResult)
        #expect(redone.imageRecipe == customRecipe)
    }

    @Test func applyingTemplateKeepsImageFrame() throws {
        var configuration = PremiumMakerConfigurationModel()
        configuration.selectedImage = try alphaFixture()
        configuration.imageRecipe = customRecipe
        let template = try #require(ThumbnailTemplate.builtIns.first)
        let applied = template.makeDocument(preservingImagesFrom: configuration.document)
        #expect(applied.imageRecipe == customRecipe)
        #expect(applied.imageData != nil)

        // Without an image to preserve, a template starts from the default frame.
        #expect(template.makeDocument().imageRecipe == .identity)
    }

    // MARK: Helpers

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func roundTrip(_ document: ThumbnailDocument) throws -> ThumbnailDocument {
        try decoder().decode(ThumbnailDocument.self, from: encoder().encode(document))
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
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self),
                                         count: cgImage.width * cgImage.height * 4))
    }
}
