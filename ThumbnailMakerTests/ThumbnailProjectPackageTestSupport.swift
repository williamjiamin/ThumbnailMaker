//
//  ThumbnailProjectPackageTestSupport.swift
//  ThumbnailMakerTests
//
//  FEATURE-06 shared fixtures.
//

import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

enum PackageFixtures {
    static let date = Date(timeIntervalSince1970: 1_780_000_000)

    /// 4x1 PNG with fully transparent and partially transparent pixels.
    static func alphaPNG() throws -> Data {
        let rgba = Data([0, 0, 0, 0, 64, 0, 0, 64, 0, 128, 0, 128, 0, 0, 255, 255])
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

    static func solidPNG(_ color: UIColor, size: CGSize = CGSize(width: 6, height: 4)) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return try #require(image.pngData())
    }

    static func jpeg() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { context in
            UIColor.systemPurple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        return try #require(image.jpegData(compressionQuality: 0.7))
    }

    /// A premium document exercising every persisted surface: background with
    /// a frame recipe, profile, two image layers sharing identical bytes, a
    /// sticker, a styled text layer, a shape, non-default canvas/export/macro.
    static func premiumDocument() throws -> ThumbnailDocument {
        let background = try alphaPNG()
        let profile = try solidPNG(.systemRed)
        let shared = try solidPNG(.systemGreen)
        let sticker = try jpeg()

        var style = ThumbnailTextStyle.legacyApproximation(for: .contentLayer)
        style.outlineWidth = 0.08
        style.panelColor = ThumbnailDocumentColor(red: 0, green: 0, blue: 0, alpha: 0.5)

        let layers: [ThumbnailDocumentLayer] = [
            ThumbnailDocumentLayer.defaultBackgroundLayer,
            ThumbnailDocumentLayer.defaultProfileLayer,
            ThumbnailDocumentLayer(id: ThumbnailDocumentLayer.textID, kind: .text, name: "Headline", isLocked: true, zIndex: 20),
            .imageLayer(id: "img-1", imageData: shared, name: "Photo 1",
                        transform: ThumbnailOverlayTransform(x: 0.2, y: 0.3, rotationDegrees: 12), size: 0.4, zIndex: 30),
            .imageLayer(id: "img-2", imageData: shared, name: "Photo 2", zIndex: 40),
            .imageLayer(id: "sticker-1", imageData: sticker, name: "Sticker", isSticker: true, zIndex: 50),
            .textLayer(id: "text-1", value: "Styled", color: ThumbnailDocumentColor(red: 1, green: 0.5, blue: 0, alpha: 1),
                       size: 0.12, selectedFontRawValue: CustomFont.goNoto.rawValue, name: "Callout",
                       transform: ThumbnailOverlayTransform(x: 0.7, y: 0.8), zIndex: 60, style: style),
            .shapeLayer(id: "shape-1", shapeKind: .rectangle, strokeWidth: 0.03, width: 0.5, height: 0.1, zIndex: 70)
        ]

        return ThumbnailDocument(
            updatedAt: date,
            editorMode: .premium,
            canvas: ThumbnailDocumentCanvas(
                aspectRatioRawValue: AspectRatio.ratio4_3.rawValue,
                backgroundColor: ThumbnailDocumentColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
            ),
            imageData: background,
            imageRecipe: .fillCentered,
            text: ThumbnailDocumentText(value: "Launch Day", size: 0.2, style: style),
            profile: ThumbnailDocumentProfile(imageData: profile, size: 0.25),
            layers: layers,
            macro: ThumbnailDocumentMacro(isEnabled: true, startNumber: 3, endNumber: 9),
            export: ThumbnailDocumentExport(
                formatRawValue: ThumbnailExportFormat.jpeg.rawValue,
                compressionQuality: 0.6,
                usesCustomSize: true,
                customWidth: 1600,
                customHeight: 1200
            )
        )
    }

    static func contents(
        document: ThumbnailDocument,
        name: String = "Launch Art",
        variantSet: ThumbnailVariantSet? = nil,
        preview: Data? = nil
    ) -> ThumbnailProjectPackageContents {
        ThumbnailProjectPackageContents(
            projectID: UUID().uuidString,
            name: name,
            createdAt: date,
            updatedAt: date,
            editorMode: document.editorMode,
            document: document,
            variantSet: variantSet,
            previewPNGData: preview
        )
    }

    static func makeDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FEATURE06-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes a package to `<directory>/<name>.thumbproj` and returns the URL.
    @discardableResult
    static func writePackage(
        _ contents: ThumbnailProjectPackageContents,
        in directory: URL,
        fileName: String = "Fixture"
    ) throws -> URL {
        let encoded = try ThumbnailProjectPackageWriter.encode(contents)
        let url = directory.appendingPathComponent("\(fileName).\(ThumbnailProjectPackageLayout.fileExtension)")
        try ThumbnailProjectPackageWriter.write(encoded, to: url)
        return url
    }

    static func readManifestJSON(_ packageURL: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: packageURL.appendingPathComponent("manifest.json"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func writeManifestJSON(_ object: [String: Any], to packageURL: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: packageURL.appendingPathComponent("manifest.json"))
    }
}
