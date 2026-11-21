//
//  ThumbnailSeriesRecipeTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-15: rows render through the personal-template engine,
//  deterministically, without ever mutating the source.
//

import Foundation
import Testing
@testable import ThumbnailMaker

struct ThumbnailSeriesRecipeTests {
    private typealias Support = SeriesTestSupport

    private func textLayerValues(_ document: ThumbnailDocument) -> [String] {
        document.layers.compactMap { layer in
            if case .text(let content) = layer.content { return content.value }
            return nil
        }
    }

    @Test func titleReplacesHeadlineAndEpisodeFillsToken() {
        let source = Support.currentDesignSource()
        let row = ThumbnailSeriesRow(title: "New Video", episode: "7")

        let document = ThumbnailSeriesRecipe.document(for: row, in: source, imageData: nil)

        #expect(document.text.value == "New Video")
        #expect(textLayerValues(document) == ["EP 7"])
    }

    @Test func titleTokenIsFilledInsteadOfReplacingTheHeadline() {
        let source = Support.currentDesignSource(Support.sourceDocument(headline: "{title} | Part {episode}"))
        let row = ThumbnailSeriesRow(title: "Lighting", episode: "2")

        let document = ThumbnailSeriesRecipe.document(for: row, in: source, imageData: nil)

        #expect(document.text.value == "Lighting | Part 2")
    }

    @Test func missingEpisodeLeavesNoDanglingToken() {
        let source = Support.currentDesignSource()
        let document = ThumbnailSeriesRecipe.document(for: ThumbnailSeriesRow(title: "A"), in: source, imageData: nil)
        #expect(textLayerValues(document) == ["EP"])
    }

    @Test func sourceIsNeverMutatedAndOutputIsDeterministic() {
        let source = Support.currentDesignSource()
        let copy = source
        let rows = (1...10).map { ThumbnailSeriesRow(title: "Video \($0)", episode: "\($0)") }

        var digests: [String] = []
        for row in rows {
            let first = ThumbnailSeriesRecipe.document(for: row, in: source, imageData: Support.imageData())
            let second = ThumbnailSeriesRecipe.document(for: row, in: source, imageData: Support.imageData())
            #expect(first == second)
            #expect(first.updatedAt == source.capturedAt)
            digests.append(ThumbnailSeriesRecipe.documentDigest(first))
        }

        #expect(source == copy)
        #expect(source.digest == copy.digest)
        #expect(Set(digests).count == 10)
    }

    @Test func rowImageResetsFramingButKeepsFitMode() {
        let original = Support.sourceDocument()
        let source = Support.currentDesignSource(original)
        let photo = Support.imageData(color: .systemGreen)

        let withImage = ThumbnailSeriesRecipe.document(for: ThumbnailSeriesRow(title: "A"), in: source, imageData: photo)
        #expect(withImage.imageData == photo)
        #expect(withImage.imageRecipe == ThumbnailImageFrameRecipe(fit: .fill))

        let withoutImage = ThumbnailSeriesRecipe.document(for: ThumbnailSeriesRow(title: "A"), in: source, imageData: nil)
        #expect(withoutImage.imageData == original.imageData)
        #expect(withoutImage.imageRecipe == original.imageRecipe)
    }

    @Test func personalTemplateSlotPoliciesDecideWhatRowsFill() {
        let design = Support.sourceDocument(headline: "Template Headline")
        let keepsEverything = ThumbnailTemplate.capture(
            from: design,
            name: "Keeps",
            category: .youtube,
            backgroundPolicy: .retained,
            profilePolicy: .retained,
            titlePolicy: .retained
        )
        let source = ThumbnailSeriesSource.personalTemplate(
            keepsEverything,
            currentDocument: Support.sourceDocument(withImage: false),
            now: Support.captureDate
        )

        let document = ThumbnailSeriesRecipe.document(
            for: ThumbnailSeriesRow(title: "Ignored", episode: "3"),
            in: source,
            imageData: Support.imageData(color: .systemGreen)
        )

        #expect(document.text.value == "Template Headline")
        #expect(document.imageData == design.imageData)
        #expect(textLayerValues(document) == ["EP 3"])
        #expect(!ThumbnailSeriesRecipe.sourceShowsTitle(source))
        #expect(!ThumbnailSeriesRecipe.sourceUsesRowImage(source))
    }

    @Test func layerStructureIsPreserved() {
        let design = Support.sourceDocument()
        let source = Support.currentDesignSource(design)
        let document = ThumbnailSeriesRecipe.document(for: ThumbnailSeriesRow(title: "A"), in: source, imageData: nil)

        #expect(document.layers.map(\.zIndex) == design.layers.map(\.zIndex))
        #expect(document.layers.map(\.kind) == design.layers.map(\.kind))
        #expect(document.layers.map(\.isVisible) == design.layers.map(\.isVisible))
        #expect(document.layers.map(\.isLocked) == design.layers.map(\.isLocked))
        #expect(document.canvas == design.canvas)
        #expect(document.editorMode == design.editorMode)
    }

    @Test func sourceRoundTripsThroughJSONWithStableDigest() throws {
        let source = Support.currentDesignSource()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(ThumbnailSeriesSource.self, from: encoder.encode(source))

        #expect(decoded.digest == source.digest)
        #expect(decoded.capturedAt == source.capturedAt)
        let row = ThumbnailSeriesRow(title: "Same", episode: "1")
        #expect(
            ThumbnailSeriesRecipe.documentDigest(ThumbnailSeriesRecipe.document(for: row, in: decoded, imageData: nil))
                == ThumbnailSeriesRecipe.documentDigest(ThumbnailSeriesRecipe.document(for: row, in: source, imageData: nil))
        )
    }

    @Test func unknownOriginDecodesAsUnknown() throws {
        let json = #"{"kind":"fromTheFuture","name":"x"}"#
        let origin = try JSONDecoder().decode(ThumbnailSeriesSourceOrigin.self, from: Data(json.utf8))
        #expect(origin == .unknown)
    }

    @Test func seriesV1WithoutOptionalFieldsDecodes() throws {
        let id = UUID()
        let rowID = UUID()
        let json = #"{"id":"\#(id.uuidString)","rows":[{"id":"\#(rowID.uuidString)","title":"Hi"}]}"#
        let series = try JSONDecoder().decode(ThumbnailSeries.self, from: Data(json.utf8))

        #expect(series.id == id)
        #expect(series.name == "Series")
        #expect(series.rows.count == 1)
        #expect(series.rows[0].title == "Hi")
        #expect(series.rows[0].imageRef == nil)
        #expect(series.rows[0].sourceLine == nil)
        #expect(series.exportRecipeID == nil)
    }
}
