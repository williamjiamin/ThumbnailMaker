//
//  ThumbnailProjectPackageValidationTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-06: every damaged, hostile or future package is rejected with a
//  specific error, and the reader never modifies what it rejects.
//

import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ThumbnailProjectPackageValidationTests {
    private func makeGoodPackage(in directory: URL) throws -> URL {
        try PackageFixtures.writePackage(
            PackageFixtures.contents(document: try PackageFixtures.premiumDocument()),
            in: directory
        )
    }

    private func expectReadError(
        _ expected: ThumbnailProjectPackageError,
        at url: URL,
        limits: ThumbnailProjectPackageLimits = .standard,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        do {
            _ = try ThumbnailProjectPackageReader.readPackage(at: url, limits: limits)
            Issue.record("expected \(expected), but the package was accepted", sourceLocation: sourceLocation)
        } catch let error as ThumbnailProjectPackageError {
            #expect(error == expected, sourceLocation: sourceLocation)
        } catch {
            Issue.record("unexpected error \(error)", sourceLocation: sourceLocation)
        }
    }

    private func firstAssetRecord(_ url: URL) throws -> [String: Any] {
        let manifest = try PackageFixtures.readManifestJSON(url)
        let assets = try #require(manifest["assets"] as? [[String: Any]])
        return try #require(assets.first)
    }

    private func mutateFirstAsset(_ url: URL, _ change: (inout [String: Any]) -> Void) throws {
        var manifest = try PackageFixtures.readManifestJSON(url)
        var assets = try #require(manifest["assets"] as? [[String: Any]])
        change(&assets[0])
        manifest["assets"] = assets
        try PackageFixtures.writeManifestJSON(manifest, to: url)
    }

    @Test func rejectsUnsupportedFutureVersionWithoutTouchingTheFile() throws {
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeGoodPackage(in: directory)
        var manifest = try PackageFixtures.readManifestJSON(url)
        manifest["minimumReaderVersion"] = 2
        manifest["schemaVersion"] = 2
        try PackageFixtures.writeManifestJSON(manifest, to: url)
        let manifestBefore = try Data(contentsOf: url.appendingPathComponent("manifest.json"))
        let documentBefore = try Data(contentsOf: url.appendingPathComponent("document.json"))

        expectReadError(.unsupportedFutureVersion(found: 2, supported: 1), at: url)

        #expect(try Data(contentsOf: url.appendingPathComponent("manifest.json")) == manifestBefore)
        #expect(try Data(contentsOf: url.appendingPathComponent("document.json")) == documentBefore)
    }

    @Test func rejectsADocumentFromANewerApp() throws {
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeGoodPackage(in: directory)
        let documentURL = url.appendingPathComponent("document.json")
        var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: documentURL)) as? [String: Any])
        object["version"] = ThumbnailDocument.currentVersion + 1
        try JSONSerialization.data(withJSONObject: object).write(to: documentURL)

        expectReadError(
            .unsupportedFutureVersion(found: ThumbnailDocument.currentVersion + 1, supported: ThumbnailDocument.currentVersion),
            at: url
        )
    }

    @Test func acceptsForwardCompatibleManifestWithUnknownFields() throws {
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeGoodPackage(in: directory)
        var manifest = try PackageFixtures.readManifestJSON(url)
        manifest["schemaVersion"] = 2
        manifest["minimumReaderVersion"] = 1
        manifest["futureField"] = ["nested": [1, 2, 3]]
        try PackageFixtures.writeManifestJSON(manifest, to: url)

        let package = try ThumbnailProjectPackageReader.readPackage(at: url)
        #expect(package.manifest.schemaVersion == 2)
        #expect(package.contents.name == "Launch Art")
        #expect(package.manifest.assets.count == 4)
    }

    @Test func rejectsWrongFormatIdentifier() throws {
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeGoodPackage(in: directory)
        var manifest = try PackageFixtures.readManifestJSON(url)
        manifest["formatIdentifier"] = "com.example.other"
        try PackageFixtures.writeManifestJSON(manifest, to: url)

        expectReadError(.unsupportedFormatIdentifier("com.example.other"), at: url)
    }

    @Test func rejectsMissingManifestAndMissingDocument() throws {
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let noManifest = try PackageFixtures.writePackage(
            PackageFixtures.contents(document: try PackageFixtures.premiumDocument()), in: directory, fileName: "A")
        try FileManager.default.removeItem(at: noManifest.appendingPathComponent("manifest.json"))
        expectReadError(.manifestMissing, at: noManifest)

        let noDocument = try PackageFixtures.writePackage(
            PackageFixtures.contents(document: try PackageFixtures.premiumDocument()), in: directory, fileName: "B")
        try FileManager.default.removeItem(at: noDocument.appendingPathComponent("document.json"))
        expectReadError(.documentMissing, at: noDocument)
    }

    @Test func rejectsMalformedManifestJSON() throws {
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeGoodPackage(in: directory)
        let manifestURL = url.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        try data.prefix(data.count / 2).write(to: manifestURL)

        do {
            _ = try ThumbnailProjectPackageReader.readPackage(at: url)
            Issue.record("truncated manifest was accepted")
        } catch ThumbnailProjectPackageError.manifestUnreadable {
            // expected
        }
    }

    @Test func rejectsMalformedDocumentJSON() throws {
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeGoodPackage(in: directory)
        try Data("{\"version\": 5, \"layers\": [".utf8).write(to: url.appendingPathComponent("document.json"))

        do {
            _ = try ThumbnailProjectPackageReader.readPackage(at: url)
            Issue.record("malformed document was accepted")
        } catch ThumbnailProjectPackageError.documentUnreadable {
            // expected
        }
    }

    @Test func rejectsMissingAsset() throws {
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeGoodPackage(in: directory)
        let record = try firstAssetRecord(url)
        let id = try #require(record["id"] as? String)
        let path = try #require(record["path"] as? String)
        try FileManager.default.removeItem(at: url.appendingPathComponent(path))

        expectReadError(.assetMissing(id: id), at: url)
    }

    @Test func rejectsTamperedAssetBytes() throws {
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeGoodPackage(in: directory)
        let record = try firstAssetRecord(url)
        let id = try #require(record["id"] as? String)
        let assetURL = url.appendingPathComponent(try #require(record["path"] as? String))
        var bytes = try Data(contentsOf: assetURL)
        bytes[bytes.count - 1] ^= 0xFF
        try bytes.write(to: assetURL)

        expectReadError(.assetChecksumMismatch(id: id), at: url)
    }

    @Test func rejectsNonImageAssetEvenWithAMatchingChecksum() throws {
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeGoodPackage(in: directory)
        let record = try firstAssetRecord(url)
        let oldPath = try #require(record["path"] as? String)
        let oldID = try #require(record["id"] as? String)

        let junk = Data((0..<256).map { UInt8($0) })
        let newID = ThumbnailVariantAssetLibrary.digest(junk)
        try FileManager.default.removeItem(at: url.appendingPathComponent(oldPath))
        try junk.write(to: url.appendingPathComponent("assets/\(newID).png"))
        try mutateFirstAsset(url) { asset in
            asset["id"] = newID
            asset["sha256"] = newID
            asset["path"] = "assets/\(newID).png"
            asset["byteCount"] = junk.count
        }
        // Re-point every binding that used the old id.
        var manifest = try PackageFixtures.readManifestJSON(url)
        let refsData = try JSONSerialization.data(withJSONObject: try #require(manifest["documentAssets"]))
        let refsText = try #require(String(data: refsData, encoding: .utf8)).replacingOccurrences(of: oldID, with: newID)
        manifest["documentAssets"] = try JSONSerialization.jsonObject(with: Data(refsText.utf8))
        try PackageFixtures.writeManifestJSON(manifest, to: url)

        expectReadError(.assetUndecodable(id: newID), at: url)
    }

    @Test(arguments: [
        "../../../etc/passwd",
        "/etc/passwd",
        "assets/../../secret.png",
        "assets/sub/dir/x.png",
        "x.png",
        "assets/other.png",
        "assets\\x.png",
        "file:///etc/passwd"
    ])
    func rejectsPathTraversal(path: String) throws {
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeGoodPackage(in: directory)
        try mutateFirstAsset(url) { $0["path"] = path }

        expectReadError(.assetPathRejected(path), at: url)
    }

    @Test func rejectsTooManyAssets() throws {
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeGoodPackage(in: directory)
        var manifest = try PackageFixtures.readManifestJSON(url)
        let assets = try #require(manifest["assets"] as? [[String: Any]])
        manifest["assets"] = Array(repeating: assets[0], count: 65)
        try PackageFixtures.writeManifestJSON(manifest, to: url)

        expectReadError(.assetCountExceeded(found: 65, limit: 64), at: url)
    }

    @Test func rejectsOversizedAssetAndOversizedPackage() throws {
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeGoodPackage(in: directory)
        let record = try firstAssetRecord(url)
        let id = try #require(record["id"] as? String)
        let size = try #require(record["byteCount"] as? Int)

        var tinyAssets = ThumbnailProjectPackageLimits.standard
        tinyAssets.maximumAssetByteCount = size - 1
        expectReadError(.assetTooLarge(id: id, byteCount: size, limit: size - 1), at: url, limits: tinyAssets)

        var tinyPackage = ThumbnailProjectPackageLimits.standard
        tinyPackage.maximumTotalByteCount = 2048
        do {
            _ = try ThumbnailProjectPackageReader.readPackage(at: url, limits: tinyPackage)
            Issue.record("oversized package was accepted")
        } catch ThumbnailProjectPackageError.packageTooLarge(_, let limit) {
            #expect(limit == 2048)
        }

        // The writer enforces the same ceilings, so it never emits such a package.
        #expect(throws: ThumbnailProjectPackageError.self) {
            try ThumbnailProjectPackageWriter.encode(
                PackageFixtures.contents(document: try PackageFixtures.premiumDocument()),
                limits: tinyPackage
            )
        }
    }

    @Test func rejectsRegularFileAsPackage() throws {
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("NotAPackage.thumbproj")
        try Data("{}".utf8).write(to: file)

        expectReadError(.notAPackage, at: file)
    }

    @Test func rejectsUnresolvableBinding() throws {
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeGoodPackage(in: directory)
        var manifest = try PackageFixtures.readManifestJSON(url)
        var refs = try #require(manifest["documentAssets"] as? [String: Any])
        refs["backgroundImage"] = String(repeating: "0", count: 64)
        manifest["documentAssets"] = refs
        try PackageFixtures.writeManifestJSON(manifest, to: url)

        expectReadError(.bindingUnresolved(slot: "background"), at: url)
    }

    @Test func rejectsBindingToALayerThatDoesNotExist() throws {
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeGoodPackage(in: directory)
        var manifest = try PackageFixtures.readManifestJSON(url)
        var refs = try #require(manifest["documentAssets"] as? [String: Any])
        var layers = try #require(refs["contentLayers"] as? [String: String])
        layers["ghost"] = layers["img-1"]
        refs["contentLayers"] = layers
        manifest["documentAssets"] = refs
        try PackageFixtures.writeManifestJSON(manifest, to: url)

        expectReadError(.bindingUnresolved(slot: "layer:ghost"), at: url)
    }

    @Test func rejectsImageLayerWhoseBindingWasRemoved() throws {
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeGoodPackage(in: directory)
        var manifest = try PackageFixtures.readManifestJSON(url)
        var refs = try #require(manifest["documentAssets"] as? [String: Any])
        var layers = try #require(refs["contentLayers"] as? [String: String])
        layers.removeValue(forKey: "sticker-1")
        refs["contentLayers"] = layers
        manifest["documentAssets"] = refs
        try PackageFixtures.writeManifestJSON(manifest, to: url)

        expectReadError(.bindingUnresolved(slot: "layer:sticker-1"), at: url)
    }

    @Test func rejectsAssetSizeMismatch() throws {
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeGoodPackage(in: directory)
        let record = try firstAssetRecord(url)
        let id = try #require(record["id"] as? String)
        let size = try #require(record["byteCount"] as? Int)
        try mutateFirstAsset(url) { $0["byteCount"] = size + 10 }

        expectReadError(.assetSizeMismatch(id: id), at: url)
    }

    @Test func rejectsDamagedVariants() throws {
        let directory = PackageFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = try PackageFixtures.premiumDocument()
        var set = ThumbnailVariantSet(seedDocument: document, editorMode: .premium, now: PackageFixtures.date)
        set.duplicateVariant(from: .a, now: PackageFixtures.date)
        let url = try PackageFixtures.writePackage(
            PackageFixtures.contents(document: document, variantSet: set),
            in: directory
        )
        try FileManager.default.removeItem(at: url.appendingPathComponent("variants/b.json"))

        expectReadError(.variantInvalid("variant B is missing"), at: url)
    }

    @Test func errorsExplainThatNothingChanged() {
        let error = ThumbnailProjectPackageError.unsupportedFutureVersion(found: 2, supported: 1)
        #expect(error.userMessage.contains("newer version"))
        #expect(error.userMessage.contains("has not been changed"))
        #expect(ThumbnailProjectPackageError.assetMissing(id: "x").userMessage.contains("unchanged"))
    }
}
