//
//  ImageImportErrorTests.swift
//  ThumbnailMakerTests
//
//  Verifies the image-import pipeline publishes an actionable ImageImportError
//  when transfer or decode fails, and that the current document is preserved.
//

import Foundation
import PhotosUI
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ImageImportErrorTests {
    @Test func simpleMakerPublishesDecodeErrorOnInvalidData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json"))
        let viewModel = SimpleMakerViewModel(draftStore: store, brandKitStore: brandStore(in: directory))

        let original = try #require(makeImage(label: "original", red: 100, green: 50, blue: 25))
        viewModel.simpleMakerConfiguration.selectedImage = original

        let revision = viewModel.beginImageImport()
        let applied = viewModel.applyImportedImageData(Data([0xDE, 0xAD, 0xBE, 0xEF]), revision: revision)
        #expect(!applied)
        #expect(viewModel.imageImportError == .decodeFailed)
        // The existing selection is preserved on failure.
        #expect(viewModel.simpleMakerConfiguration.selectedImage != nil)
        #expect(viewModel.simpleMakerConfiguration.selectedImage?.size == original.size)
    }

    @Test func premiumMakerPublishesDecodeErrorOnInvalidData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium.json"))
        let viewModel = PremiumMakerViewModel(draftStore: store, brandKitStore: brandStore(in: directory))

        let original = try #require(makeImage(label: "original", red: 12, green: 34, blue: 56))
        viewModel.premiumMakerConfiguration.selectedImage = original

        let revision = viewModel.beginImageImport()
        let applied = viewModel.applyImportedImageData(Data([0x00, 0x00, 0x00, 0x00]), revision: revision)
        #expect(!applied)
        #expect(viewModel.imageImportError == .decodeFailed)
        #expect(viewModel.premiumMakerConfiguration.selectedImage?.size == original.size)
    }

    @Test func simpleMakerPreservesDocumentOnStaleImport() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json"))
        let viewModel = SimpleMakerViewModel(draftStore: store, brandKitStore: brandStore(in: directory))

        let original = try #require(makeImage(label: "kept", red: 5, green: 10, blue: 15))
        viewModel.simpleMakerConfiguration.selectedImage = original
        viewModel.simpleMakerConfiguration.overlayText = "stays put"

        // A stale import must not mutate the document — and, because a newer
        // import already owns it, must not raise a user-facing error either.
        let staleRevision = viewModel.beginImageImport()
        _ = viewModel.beginImageImport()
        let applied = viewModel.applyImportedImageData(Data([0x01, 0x02]), revision: staleRevision)
        #expect(!applied)
        #expect(viewModel.imageImportError == nil)
        #expect(viewModel.simpleMakerConfiguration.selectedImage?.size == original.size)
        #expect(viewModel.simpleMakerConfiguration.overlayText == "stays put")
    }

    @Test func unsupportedImageBytesSurfaceAsDecodeError() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json"))
        let viewModel = SimpleMakerViewModel(draftStore: store, brandKitStore: brandStore(in: directory))

        let bogus = Data(repeating: 0xFF, count: 64)
        let revision = viewModel.beginImageImport()
        let applied = viewModel.applyImportedImageData(bogus, revision: revision)
        #expect(!applied)
        #expect(viewModel.imageImportError == .decodeFailed)
        #expect(viewModel.imageImportError?.message.contains("decode") == true)
    }

    private func makeImage(label: String, red: UInt8, green: UInt8, blue: UInt8) -> UIImage? {
        let size = CGSize(width: 8, height: 8)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor(red: CGFloat(red) / 255.0, green: CGFloat(green) / 255.0, blue: CGFloat(blue) / 255.0, alpha: 1).setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
        }
    }

    private func brandStore(in directory: URL) -> BrandKitStore {
        BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
    }
}
