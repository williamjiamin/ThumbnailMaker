//
//  ThumbnailSeriesTestSupport.swift
//  ThumbnailMakerTests
//
//  FEATURE-15 shared fixtures.
//

import Foundation
import UIKit
@testable import ThumbnailMaker

enum SeriesTestSupport {
    static let captureDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// The acceptance fixture: 10 data rows, 3 of them malformed
    /// (line 4: too few fields, line 7: unterminated quote, line 10: too many
    /// fields). Line numbers are 1-based and include the header.
    static let tenRowCSV = """
    title,episode,image,name
    Morning Routine,1,ep1.jpg,
    "Lighting, Explained",2,ep2.jpg,
    Too Few Fields,3
    "The ""Perfect"" Desk",4,,desk-special
    Editing Speedrun,5,EP5.JPG,
    "Unclosed quote,6,,
    Camera Settings,7,,
    Audio Tips,8,,
    Way,Too,Many,Fields,Here
    Channel Q&A,10,,
    """

    static func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FEATURE15-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func imageData(color: UIColor = .systemOrange, size: CGSize = CGSize(width: 32, height: 18)) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }.pngData()!
    }

    /// A simple 16:9 design with a headline, a background photo and one text
    /// layer that uses the {episode} token.
    static func sourceDocument(
        headline: String = "Old Headline",
        episodeLayerText: String? = "EP {episode}",
        withImage: Bool = true
    ) -> ThumbnailDocument {
        var document = ThumbnailDocument(
            updatedAt: Date(timeIntervalSince1970: 5),
            editorMode: .simple,
            canvas: ThumbnailDocumentCanvas(
                aspectRatioRawValue: AspectRatio.ratio16_9.rawValue,
                backgroundColor: ThumbnailDocumentColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 1)
            ),
            imageData: withImage ? imageData(color: .systemBlue) : nil,
            imageRecipe: ThumbnailImageFrameRecipe(fit: .fill, focusX: 0.2, focusY: 0.8, zoom: 2),
            text: ThumbnailDocumentText(value: headline)
        )
        if let episodeLayerText {
            document.layers.addTextLayer(value: episodeLayerText, id: "episode-layer")
        }
        return document
    }

    static func currentDesignSource(
        _ document: ThumbnailDocument = sourceDocument(),
        projectName: String = "My Show"
    ) -> ThumbnailSeriesSource {
        ThumbnailSeriesSource.currentDesign(document, projectName: projectName, now: captureDate)
    }
}
