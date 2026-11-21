//
//  ThumbnailVariantStoreTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-02: variant persistence, dedup, lossless images, damage tolerance.
//

import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ThumbnailVariantStoreTests {
    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func alphaPNG(seed: UInt8 = 0) throws -> Data {
        let rgba = Data([seed, 0, 0, 0, 64, seed, 0, 64, 0, 128, seed, 128, 0, 0, 255, 255])
        let provider = try #require(CGDataProvider(data: rgba as CFData))
        let image = try #require(CGImage(
            width: 4, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                .union(.byteOrder32Big),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        return try #require(UIImage(cgImage: image).pngData())
    }

    private func pixels(_ data: Data) throws -> [UInt8] {
        let cgImage = try #require(UIImage(data: data)?.cgImage)
        let context = try #require(CGContext(
            data: nil, width: cgImage.width, height: cgImage.height, bitsPerComponent: 8,
            bytesPerRow: cgImage.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        let raw = try #require(context.data)
        return Array(UnsafeBufferPointer(start: raw.assumingMemoryBound(to: UInt8.self),
                                         count: cgImage.width * cgImage.height * 4))
    }

    /// A premium-style document with a background, a profile image and an
    /// image layer, so every payload location is exercised.
    private func richDocument(text: String, background: Data, layerImage: Data) -> ThumbnailDocument {
        var document = ThumbnailDocument(
            editorMode: .premium,
            imageData: background,
            text: ThumbnailDocumentText(value: text),
            profile: ThumbnailDocumentProfile(imageData: background, size: 0.2)
        )
        _ = document.layers.addImageLayer(imageData: layerImage, id: "layer-\(text)")
        return document
    }

    private func threeVariantSet(background: Data, layerImage: Data) -> ThumbnailVariantSet {
        var set = ThumbnailVariantSet(
            seedDocument: richDocument(text: "A", background: background, layerImage: layerImage),
            editorMode: .premium,
            projectName: "Ep 1"
        )
        set.duplicateVariant(from: .a)
        set.updateDocument(richDocument(text: "B", background: background, layerImage: layerImage), for: .b)
        set.duplicateVariant(from: .b)
        set.updateDocument(richDocument(text: "C", background: background, layerImage: layerImage), for: .c)
        set.setPreferred(.c)
        set.activate(.b)
        return set
    }

    /// ISO-8601 persistence drops sub-second precision; compare content only.
    private func expectSameContent(_ lhs: ThumbnailVariantSet, _ rhs: ThumbnailVariantSet) {
        #expect(lhs.slots == rhs.slots)
        #expect(lhs.activeSlot == rhs.activeSlot)
        #expect(lhs.preferredSlot == rhs.preferredSlot)
        #expect(lhs.projectName == rhs.projectName)
        #expect(lhs.editorMode == rhs.editorMode)
        #expect(lhs.variants.map(\.name) == rhs.variants.map(\.name))
        for slot in lhs.slots {
            let left = lhs.document(for: slot).map(ThumbnailDocumentHistory.snapshot)
            let right = rhs.document(for: slot).map(ThumbnailDocumentHistory.snapshot)
            #expect(left == right, "Variant \(slot.displayLetter) differs after round trip")
        }
    }

    @Test func saveLoadRoundTripPreservesEveryVariant() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailVariantStore(fileURL: directory.appendingPathComponent("nested/variants.json"))
        let set = threeVariantSet(background: try alphaPNG(), layerImage: try alphaPNG(seed: 9))

        try store.save(set)
        let loaded = try #require(try store.load())
        #expect(loaded.missingAssetDigests.isEmpty)
        expectSameContent(loaded.set, set)
    }

    @Test func imagePayloadsSurviveTwentyRoundTrips() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let background = try alphaPNG()
        let layerImage = try alphaPNG(seed: 200)
        let expectedBackground = try pixels(background)
        let expectedLayer = try pixels(layerImage)
        #expect(stride(from: 3, to: expectedBackground.count, by: 4).map { expectedBackground[$0] } == [0, 64, 128, 255])

        var set = threeVariantSet(background: background, layerImage: layerImage)
        for index in 0..<20 {
            let store = ThumbnailVariantStore(fileURL: directory.appendingPathComponent("variants.json"))
            set.rename(slot: .a, to: "Round \(index)")
            try store.save(set)
            set = try #require(try ThumbnailVariantStore(fileURL: store.fileURL).load()).set
        }

        for variant in set.variants {
            let document = variant.document
            #expect(try pixels(#require(document.imageData)) == expectedBackground)
            #expect(try pixels(#require(document.profile?.imageData)) == expectedBackground)
            let layer = try #require(document.layers.first { $0.kind == .image })
            guard case .image(let content) = layer.content else {
                Issue.record("Image layer lost its content")
                continue
            }
            #expect(content.imageData == layerImage)
            #expect(try pixels(content.imageData) == expectedLayer)
        }
    }

    @Test func sharedImageBytesAreStoredOnce() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // A large-ish, incompressible payload so dedup dominates file size.
        var generator = SystemRandomNumberGenerator()
        let background = Data((0..<200_000).map { _ in UInt8.random(in: 0...255, using: &generator) })
        let layerImage = try alphaPNG()

        let single = ThumbnailVariantSet(
            seedDocument: richDocument(text: "A", background: background, layerImage: layerImage),
            editorMode: .premium
        )
        let singleStore = ThumbnailVariantStore(fileURL: directory.appendingPathComponent("single.json"))
        try singleStore.save(single)

        let tripleStore = ThumbnailVariantStore(fileURL: directory.appendingPathComponent("triple.json"))
        try tripleStore.save(threeVariantSet(background: background, layerImage: layerImage))

        let singleSize = try Data(contentsOf: singleStore.fileURL).count
        let tripleSize = try Data(contentsOf: tripleStore.fileURL).count
        #expect(Double(tripleSize) < Double(singleSize) * 1.6)

        let stored = try ThumbnailVariantStore.decoder.decode(
            ThumbnailVariantStore.StoredFile.self,
            from: Data(contentsOf: tripleStore.fileURL)
        )
        let digest = ThumbnailVariantAssetLibrary.digest(background)
        #expect(stored.assets[digest] == background)
        #expect(stored.assets.values.filter { $0 == background }.count == 1)
    }

    @Test func missingAssetsDegradeGracefullyInsteadOfThrowing() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let background = try alphaPNG()
        let layerImage = try alphaPNG(seed: 77)
        let fileURL = directory.appendingPathComponent("variants.json")
        try ThumbnailVariantStore(fileURL: fileURL).save(threeVariantSet(background: background, layerImage: layerImage))

        var stored = try ThumbnailVariantStore.decoder.decode(
            ThumbnailVariantStore.StoredFile.self,
            from: Data(contentsOf: fileURL)
        )
        let droppedDigest = ThumbnailVariantAssetLibrary.digest(layerImage)
        let removed = stored.assets.removeValue(forKey: droppedDigest)
        #expect(removed != nil)
        try ThumbnailVariantStore.encoder.encode(stored).write(to: fileURL)

        let loaded = try #require(try ThumbnailVariantStore(fileURL: fileURL).load())
        #expect(loaded.missingAssetDigests == [droppedDigest])
        #expect(loaded.set.slots == [.a, .b, .c])
        for variant in loaded.set.variants {
            #expect(variant.document.imageData == background)
            #expect(variant.document.text.value == variant.slot.displayLetter)
        }

        let restore = try #require(
            ThumbnailVariantStore(fileURL: fileURL).restoreSet(legacyDraft: nil, editorMode: .premium)
        )
        #expect(restore.warning == ThumbnailVariantStore.missingImagesWarning)
    }

    @Test func corruptFileFallsBackToTheLegacyDraft() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("variants.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: fileURL)

        let legacy = ThumbnailDocument(text: ThumbnailDocumentText(value: "Legacy"))
        let restore = try #require(
            ThumbnailVariantStore(fileURL: fileURL).restoreSet(legacyDraft: legacy, editorMode: .simple)
        )
        #expect(restore.set.slots == [.a])
        #expect(restore.set.activeDocument.text.value == "Legacy")
        #expect(restore.warning == ThumbnailVariantStore.unreadableVariantsWarning)
    }

    @Test func legacyDraftWinsForTheActiveSlotWhenItIsNewer() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailVariantStore(fileURL: directory.appendingPathComponent("variants.json"))
        var set = ThumbnailVariantSet(
            seedDocument: ThumbnailDocument(text: ThumbnailDocumentText(value: "A")),
            editorMode: .simple
        )
        set.duplicateVariant(from: .a)
        try store.save(set)

        let newer = ThumbnailDocument(text: ThumbnailDocumentText(value: "B edited"))
        let restore = try #require(store.restoreSet(legacyDraft: newer, editorMode: .simple))
        #expect(restore.set.activeSlot == .b)
        #expect(restore.set.document(for: .b)?.text.value == "B edited")
        #expect(restore.set.document(for: .a)?.text.value == "A")
        #expect(restore.migratedFromLegacyDraft == false)
    }

    @Test func loadReturnsNilWhenNoFileExistsAndDeleteRemovesTheFile() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailVariantStore(fileURL: directory.appendingPathComponent("a/b/variants.json"))
        #expect(try store.load() == nil)
        #expect(store.restoreSet(legacyDraft: nil, editorMode: .simple) == nil)

        try store.save(ThumbnailVariantSet(seedDocument: ThumbnailDocument(), editorMode: .simple))
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
        try store.delete()
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(try store.load() == nil)
    }

    @Test func variantFileSitsBesideTheDraft() {
        let draftURL = URL(fileURLWithPath: "/tmp/x/simple.json")
        #expect(ThumbnailVariantStore.siblingURL(of: draftURL, kind: .simple).path == "/tmp/x/simple-maker-variants.json")
        #expect(ThumbnailVariantStore.siblingURL(of: draftURL, kind: .premium).lastPathComponent == "premium-maker-variants.json")
        #expect(
            ThumbnailVariantStore.defaultFileURL(for: .simple).deletingLastPathComponent()
                == ThumbnailDraftStore.defaultFileURL(for: .simple).deletingLastPathComponent()
        )
    }

    @Test func oversizedSetThrowsSetTooLarge() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailVariantStore(
            fileURL: directory.appendingPathComponent("variants.json"),
            maximumByteCount: 1_000
        )
        let big = ThumbnailDocument(imageData: Data(repeating: 7, count: 10_000))
        do {
            try store.save(ThumbnailVariantSet(seedDocument: big, editorMode: .simple))
            Issue.record("Expected setTooLarge")
        } catch let error as ThumbnailVariantStoreError {
            guard case .setTooLarge = error else {
                Issue.record("Unexpected error \(error)")
                return
            }
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(ThumbnailVariantStore.maximumByteCount == 120 * 1024 * 1024)
    }

    @Test func redundantSaveSkipsRewrite() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailVariantStore(fileURL: directory.appendingPathComponent("variants.json"))
        var set = ThumbnailVariantSet(seedDocument: ThumbnailDocument(), editorMode: .simple)
        try store.save(set)
        let marker = Date(timeIntervalSince1970: 1_000)
        try FileManager.default.setAttributes([.modificationDate: marker], ofItemAtPath: store.fileURL.path)

        try store.save(set)
        let unchanged = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.modificationDate] as? Date
        #expect(unchanged == marker)

        set.rename(slot: .a, to: "Changed")
        try store.save(set)
        let changed = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.modificationDate] as? Date
        #expect(changed != marker)
    }
}
