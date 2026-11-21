//
//  ThumbnailProjectPackageRoundTripTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-06: a project exported to a .thumbproj and read back from an
//  unrelated directory comes back identical, with original bytes intact.
//

import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ThumbnailProjectPackageRoundTripTests {
    @Test func packageRoundTripsThroughAFreshDataDirectory() throws {
        let source = PackageFixtures.makeDirectory()
        let destination = PackageFixtures.makeDirectory()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }
        let original = try PackageFixtures.premiumDocument()
        let packageURL = try PackageFixtures.writePackage(PackageFixtures.contents(document: original), in: source)

        // Simulates AirDrop/Files: copy to an unrelated location, delete the source.
        let copiedURL = destination.appendingPathComponent("Received.thumbproj")
        try FileManager.default.copyItem(at: packageURL, to: copiedURL)
        try FileManager.default.removeItem(at: source)

        let package = try ThumbnailProjectPackageReader.readPackage(at: copiedURL)
        #expect(ThumbnailDocumentHistory.snapshot(package.contents.document)
            == ThumbnailDocumentHistory.snapshot(original))
        #expect(package.contents.name == "Launch Art")
        #expect(package.contents.editorMode == .premium)

        let plan = ThumbnailProjectImporter.importPlan(for: package, into: .premium, now: PackageFixtures.date)
        let imported = plan.document
        #expect(imported.layers == original.layers)
        #expect(imported.text == original.text)
        #expect(imported.canvas == original.canvas)
        #expect(imported.export == original.export)
        #expect(imported.macro == original.macro)
        #expect(imported.imageRecipe == original.imageRecipe)
        #expect(imported.profile == original.profile)
        #expect(plan.isCrossEditorImport == false)
        #expect(plan.didRenameForCollision == false)
    }

    @Test func roundTripPreservesExactOriginalBytes() throws {
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try PackageFixtures.premiumDocument()
        let url = try PackageFixtures.writePackage(PackageFixtures.contents(document: original), in: directory)

        let restored = try ThumbnailProjectPackageReader.readPackage(at: url).contents.document
        #expect(restored.imageData == original.imageData)
        #expect(restored.profile?.imageData == original.profile?.imageData)
        for layer in original.layers {
            guard case .image(let originalContent) = layer.content else { continue }
            let restoredLayer = try #require(restored.layers.record(id: layer.id))
            guard case .image(let restoredContent) = restoredLayer.content else {
                Issue.record("layer \(layer.id) lost its image content")
                continue
            }
            #expect(restoredContent.imageData == originalContent.imageData)
        }

        // Alpha survives because bytes are copied, never re-encoded.
        let background = try #require(restored.makePremiumConfiguration().selectedImage)
        #expect(background.cgImage?.alphaInfo != CGImageAlphaInfo.none)
    }

    @Test func identicalImagesAreStoredOnce() throws {
        let original = try PackageFixtures.premiumDocument()
        let encoded = try ThumbnailProjectPackageWriter.encode(PackageFixtures.contents(document: original))

        // background, profile, shared (x2), sticker -> 4 distinct assets.
        #expect(encoded.manifest.assets.count == 4)
        let refs = encoded.manifest.documentAssets
        #expect(refs.contentLayers.count == 3)
        #expect(refs.contentLayers["img-1"] == refs.contentLayers["img-2"])
        let assetFiles = encoded.files.keys.filter { $0.hasPrefix("assets/") }
        #expect(assetFiles.count == 4)
    }

    @Test func packageLayoutIsStableAndSelfDescribing() throws {
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let preview = try PackageFixtures.solidPNG(.systemBlue)
        let url = try PackageFixtures.writePackage(
            PackageFixtures.contents(document: try PackageFixtures.premiumDocument(), preview: preview),
            in: directory
        )

        let topLevel = Set(try FileManager.default.contentsOfDirectory(atPath: url.path))
        #expect(topLevel == ["manifest.json", "document.json", "assets", "preview.png"])

        let assetNames = try FileManager.default.contentsOfDirectory(atPath: url.appendingPathComponent("assets").path)
        #expect(assetNames.count == 4)
        for name in assetNames {
            let parts = name.split(separator: ".").map(String.init)
            #expect(parts.count == 2)
            #expect(ThumbnailProjectPackageReader.isSHA256Hex(parts[0]))
            #expect(ThumbnailProjectPackageLayout.allowedAssetExtensions.contains(parts[1]))
        }
        #expect(assetNames.contains { $0.hasSuffix(".jpg") }, "the JPEG sticker keeps its format")

        let manifestText = try String(contentsOf: url.appendingPathComponent("manifest.json"), encoding: .utf8)
        #expect(!manifestText.contains("/Users"))
        #expect(!manifestText.contains("/private"))
        #expect(!manifestText.contains("file://"))

        let manifest = try ThumbnailProjectPackageReader.readPackage(at: url).manifest
        #expect(manifest.formatIdentifier == ThumbnailProjectPackageLayout.formatIdentifier)
        #expect(manifest.schemaVersion == 1)
        #expect(manifest.minimumReaderVersion == 1)
        #expect(manifest.documentVersion == ThumbnailDocument.currentVersion)
        #expect(manifest.previewPath == "preview.png")
    }

    @Test func documentJSONCarriesNoPixelBlobs() throws {
        let bigImage = try PackageFixtures.solidPNG(.systemOrange, size: CGSize(width: 600, height: 600))
        var document = try PackageFixtures.premiumDocument()
        document.imageData = bigImage
        let encoded = try ThumbnailProjectPackageWriter.encode(PackageFixtures.contents(document: document))
        let documentData = try #require(encoded.files["document.json"])

        #expect(documentData.count < 64 * 1024)
        let standalone = try ThumbnailProjectPackageCoding.decoder.decode(ThumbnailDocument.self, from: documentData)
        #expect(standalone.imageData == nil)
        #expect(standalone.profile?.imageData == nil)
        for layer in standalone.layers {
            if case .image(let content) = layer.content {
                #expect(content.imageData.isEmpty)
            }
        }
    }

    @Test func previewIsOptionalAndACorruptPreviewIsDropped() throws {
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = try PackageFixtures.premiumDocument()

        let withoutPreview = try PackageFixtures.writePackage(
            PackageFixtures.contents(document: document),
            in: directory,
            fileName: "NoPreview"
        )
        #expect(!FileManager.default.fileExists(atPath: withoutPreview.appendingPathComponent("preview.png").path))
        #expect(try ThumbnailProjectPackageReader.readPackage(at: withoutPreview).contents.previewPNGData == nil)

        let withPreview = try PackageFixtures.writePackage(
            PackageFixtures.contents(document: document, preview: try PackageFixtures.solidPNG(.systemBlue)),
            in: directory,
            fileName: "Preview"
        )
        try Data("not a png".utf8).write(to: withPreview.appendingPathComponent("preview.png"))
        let package = try ThumbnailProjectPackageReader.readPackage(at: withPreview)
        #expect(package.contents.previewPNGData == nil)
        #expect(ThumbnailDocumentHistory.snapshot(package.contents.document) == ThumbnailDocumentHistory.snapshot(document))
    }

    @Test func emptyDocumentRoundTrips() throws {
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = ThumbnailDocument(updatedAt: PackageFixtures.date)
        let url = try PackageFixtures.writePackage(PackageFixtures.contents(document: document), in: directory)

        let package = try ThumbnailProjectPackageReader.readPackage(at: url)
        #expect(package.manifest.assets.isEmpty)
        #expect(ThumbnailDocumentHistory.snapshot(package.contents.document) == ThumbnailDocumentHistory.snapshot(document))
    }

    @Test func variantsRoundTripWithSharedAssets() throws {
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = try PackageFixtures.premiumDocument()
        var set = ThumbnailVariantSet(seedDocument: document, editorMode: .premium, projectName: "launch", now: PackageFixtures.date)
        set.duplicateVariant(from: .a, now: PackageFixtures.date)
        var variantB = document
        variantB.text.value = "Variant B title"
        set.updateDocument(variantB, for: .b, now: PackageFixtures.date)
        set.rename(slot: .b, to: "Bold", now: PackageFixtures.date)
        set.setPreferred(.b, now: PackageFixtures.date)
        set.activate(.a)

        let encoded = try ThumbnailProjectPackageWriter.encode(
            PackageFixtures.contents(document: document, variantSet: set)
        )
        #expect(encoded.manifest.assets.count == 4, "variants reuse the document's images")
        #expect(encoded.files["variants/a.json"] != nil)
        #expect(encoded.files["variants/b.json"] != nil)

        let url = directory.appendingPathComponent("Variants.thumbproj")
        try ThumbnailProjectPackageWriter.write(encoded, to: url)
        let restored = try #require(try ThumbnailProjectPackageReader.readPackage(at: url).contents.variantSet)
        #expect(restored.slots == [.a, .b])
        #expect(restored.activeSlot == .a)
        #expect(restored.preferredSlot == .b)
        #expect(restored.projectName == "launch")
        #expect(restored.variant(for: .b)?.name == "Bold")
        #expect(restored.document(for: .b)?.text.value == "Variant B title")
        #expect(restored.document(for: .b)?.imageData == document.imageData)
    }

    @Test func fileDocumentWrapperMatchesWriterOutput() throws {
        let encoded = try ThumbnailProjectPackageWriter.encode(
            PackageFixtures.contents(document: try PackageFixtures.premiumDocument(), name: "My / Project: 2")
        )
        let document = ThumbnailProjectFileDocument(package: encoded)
        #expect(document.suggestedFileName == "My - Project- 2")

        let wrapper = ThumbnailProjectPackageWriter.fileWrapper(for: encoded)
        let package = try ThumbnailProjectPackageReader.package(from: wrapper)
        #expect(package.manifest == encoded.manifest)
    }
}
