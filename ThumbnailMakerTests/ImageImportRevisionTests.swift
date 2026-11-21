//
//  ImageImportRevisionTests.swift
//  ThumbnailMakerTests
//
//  Verifies that a stale async image import (started before a newer pick)
//  cannot overwrite the newer pick's result.
//

import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ImageImportRevisionTests {
    @Test func simpleMakerRejectsStaleImageImport() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json"))
        let viewModel = SimpleMakerViewModel(draftStore: store, brandKitStore: brandStore(in: directory))

        let first = try #require(makeImage(label: "first", red: 255, green: 0, blue: 0))
        let second = try #require(makeImage(label: "second", red: 0, green: 0, blue: 255))

        // A slow first import claims a revision...
        let staleRevision = viewModel.beginImageImport()
        // ...then the user picks again before it completes, which advances the
        // counter and makes the first call's tag stale.
        let currentRevision = viewModel.beginImageImport()

        let firstApplied = viewModel.applyImportedImageData(first.pngData() ?? Data(), revision: staleRevision)
        #expect(!firstApplied, "Stale revision must not be applied.")
        #expect(viewModel.simpleMakerConfiguration.selectedImage == nil)

        let secondApplied = viewModel.applyImportedImageData(second.pngData() ?? Data(), revision: currentRevision)
        #expect(secondApplied, "Current revision must be applied.")
        let applied = try #require(viewModel.simpleMakerConfiguration.selectedImage)
        #expect(applied.size == second.size)
    }

    @Test func premiumMakerRejectsStaleImageImport() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium.json"))
        let viewModel = PremiumMakerViewModel(draftStore: store, brandKitStore: brandStore(in: directory))

        let first = try #require(makeImage(label: "first", red: 10, green: 20, blue: 30))
        let second = try #require(makeImage(label: "second", red: 200, green: 150, blue: 50))

        let staleRevision = viewModel.beginImageImport()
        let currentRevision = viewModel.beginImageImport()

        #expect(!viewModel.applyImportedImageData(first.pngData() ?? Data(), revision: staleRevision))
        #expect(viewModel.premiumMakerConfiguration.selectedImage == nil)
        #expect(viewModel.applyImportedImageData(second.pngData() ?? Data(), revision: currentRevision))
        let applied = try #require(viewModel.premiumMakerConfiguration.selectedImage)
        #expect(applied.size == second.size)
    }

    @Test func currentRevisionAlwaysWins() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json"))
        let viewModel = SimpleMakerViewModel(draftStore: store, brandKitStore: brandStore(in: directory))
        let payload = try #require(makeImage(label: "payload", red: 1, green: 2, blue: 3))

        let revision = viewModel.beginImageImport()
        #expect(viewModel.applyImportedImageData(payload.pngData() ?? Data(), revision: revision))
        #expect(viewModel.simpleMakerConfiguration.selectedImage?.size == payload.size)
    }

    private func makeImage(label: String, red: UInt8, green: UInt8, blue: UInt8) -> UIImage? {
        let size = CGSize(width: 8, height: 8)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(red: CGFloat(red) / 255.0, green: CGFloat(green) / 255.0, blue: CGFloat(blue) / 255.0, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func brandStore(in directory: URL) -> BrandKitStore {
        BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
    }
}
