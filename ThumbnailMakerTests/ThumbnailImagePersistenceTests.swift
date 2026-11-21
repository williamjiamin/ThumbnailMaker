import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ThumbnailImagePersistenceTests {
    @Test func simpleDraftKeepsTransparentAndPartiallyTransparentPixels() throws {
        let image = try alphaFixture()
        let expected = try pixels(image)
        #expect(stride(from: 3, to: expected.count, by: 4).map { expected[$0] } == [0, 64, 128, 255])
        var configuration = SimpleMakerConfigurationModel()
        configuration.selectedImage = image
        configuration.overlayText = "Transparent subject"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json"))

        try store.save(configuration)
        let restored = try #require(try store.load())
        #expect(try pixels(#require(restored.selectedImage)) == expected)
        #expect(restored.overlayText == configuration.overlayText)
    }

    @Test func premiumDraftAndProfileKeepAlphaAcrossRepeatedRoundTrips() throws {
        let image = try alphaFixture()
        let expected = try pixels(image)
        var configuration = PremiumMakerConfigurationModel()
        configuration.selectedImage = image
        configuration.circularProfile = CircularProfileConfig(image: image, size: 0.28)

        for index in 0..<20 {
            configuration.overlayText = "Revision \(index)"
            let document = try roundTrip(ThumbnailDocument(configuration: configuration))
            configuration = document.makePremiumConfiguration()
            #expect(try pixels(#require(configuration.selectedImage)) == expected)
            #expect(try pixels(#require(configuration.circularProfile?.image)) == expected)
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium.json"))
        try store.save(configuration)
        let restored = try #require(try store.loadPremium())
        #expect(try pixels(#require(restored.selectedImage)) == expected)
        #expect(try pixels(#require(restored.circularProfile?.image)) == expected)
    }

    @Test func templateAndHistoryPreserveOriginalPixels() throws {
        let image = try alphaFixture()
        let expected = try pixels(image)
        var configuration = PremiumMakerConfigurationModel()
        configuration.selectedImage = image
        configuration.circularProfile = CircularProfileConfig(image: image, size: 0.28)
        configuration.overlayText = "Original"
        let original = ThumbnailDocument(configuration: configuration)
        let template = try #require(ThumbnailTemplate.builtIns.first)
        let applied = template.makeDocument(preservingImagesFrom: original)
        var history = ThumbnailDocumentHistory()
        history.record(original)
        // `undo`/`redo` are mutating, so they cannot be evaluated inside the
        // #require macro expansion (which rebinds the base as an immutable).
        let undoResult = history.undo(current: applied)
        let undone = try #require(undoResult)
        let redoResult = history.redo(current: undone)
        let redone = try #require(redoResult)

        for document in [try roundTrip(applied), undone, redone] {
            let restored = document.makePremiumConfiguration()
            #expect(try pixels(#require(restored.selectedImage)) == expected)
            #expect(try pixels(#require(restored.circularProfile?.image)) == expected)
        }
    }

    @Test func existingJPEGDocumentsStillOpenAndDoNotAccumulateLoss() throws {
        let jpeg = try #require(try alphaFixture().jpegData(compressionQuality: 0.82))
        let decodedJPEG = try #require(UIImage(data: jpeg))
        let expected = try pixels(decodedJPEG)
        var document = ThumbnailDocument(configuration: SimpleMakerConfigurationModel())
        document.imageData = jpeg
        for _ in 0..<20 {
            let configuration = try roundTrip(document).makeSimpleConfiguration()
            #expect(try pixels(#require(configuration.selectedImage)) == expected)
            document = ThumbnailDocument(configuration: configuration)
        }
    }

    @Test(arguments: [UIImage.Orientation.right, .down, .leftMirrored, .upMirrored])
    func orientedImportsRetainDisplayedComposition(orientation: UIImage.Orientation) throws {
        let cgImage = try #require(try alphaFixture().cgImage)
        let image = UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
        var configuration = SimpleMakerConfigurationModel()
        configuration.selectedImage = image
        let restored = try #require(try roundTrip(ThumbnailDocument(configuration: configuration))
            .makeSimpleConfiguration().selectedImage)
        #expect(restored.size == image.size)
        #expect(try displayedPixels(restored) == displayedPixels(image))
    }

    private func roundTrip(_ document: ThumbnailDocument) throws -> ThumbnailDocument {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ThumbnailDocument.self, from: encoder.encode(document))
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

    private func displayedPixels(_ image: UIImage) throws -> [UInt8] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return try pixels(rendered)
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
