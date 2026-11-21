//
//  ThumbnailSeriesValidationTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-15: per-row errors block only that row; warnings never block.
//

import Foundation
import Testing
@testable import ThumbnailMaker

struct ThumbnailSeriesValidationTests {
    private typealias Support = SeriesTestSupport

    private func validate(
        _ rows: [ThumbnailSeriesRow],
        source: ThumbnailSeriesSource = SeriesTestSupport.currentDesignSource(),
        digests: Set<String> = []
    ) -> ThumbnailSeriesValidationReport {
        ThumbnailSeriesValidator.validate(
            series: ThumbnailSeries(name: "My Show", rows: rows),
            source: source,
            availableImageDigests: digests
        )
    }

    private func errors(_ report: ThumbnailSeriesValidationReport, _ row: ThumbnailSeriesRow) -> [String] {
        report.issues(for: row.id).filter { $0.severity == .error }.map(\.message)
    }

    @Test func blockingErrors() {
        let empty = ThumbnailSeriesRow(title: "   ")
        let long = ThumbnailSeriesRow(title: String(repeating: "a", count: 101))
        let waiting = ThumbnailSeriesRow(title: "Waiting", requestedImageName: "ep9.jpg")
        let missing = ThumbnailSeriesRow(title: "Missing", imageRef: ThumbnailSeriesImageRef(digest: "gone", originalFileName: "x.png"))
        let broken = ThumbnailSeriesRow(title: "", sourceLine: 4, importError: "expected 4 fields but found 2")
        let good = ThumbnailSeriesRow(title: "Fine")

        let report = validate([empty, long, waiting, missing, broken, good])

        #expect(errors(report, empty) == [ThumbnailSeriesRowError.emptyTitle.errorDescription!])
        #expect(errors(report, long) == [ThumbnailSeriesRowError.titleTooLong(max: 100).errorDescription!])
        #expect(errors(report, waiting) == [ThumbnailSeriesRowError.imageNotImported(fileName: "ep9.jpg").errorDescription!])
        #expect(errors(report, missing) == [ThumbnailSeriesRowError.imageUnreadable(fileName: "x.png").errorDescription!])
        #expect(errors(report, broken).first == "CSV line 4: expected 4 fields but found 2")
        #expect(report.renderableRowIDs == [good.id])
        #expect(report.errorRowCount == 5)
    }

    @Test func duplicateOutputNamesFlagOnlyLaterRows() {
        let first = ThumbnailSeriesRow(title: "One", episode: "1")
        let clash = ThumbnailSeriesRow(title: "Two", outputName: "My Show 1")
        let third = ThumbnailSeriesRow(title: "Three", episode: "1")
        let unique = ThumbnailSeriesRow(title: "Four")

        let report = validate([first, clash, third, unique])

        #expect(report.outputStems[first.id] == "my-show-1")
        #expect(report.outputStems[unique.id] == "my-show-004")
        #expect(errors(report, first).isEmpty)
        #expect(errors(report, clash) == [ThumbnailSeriesRowError.duplicateOutputName("my-show-1").errorDescription!])
        #expect(errors(report, third) == [ThumbnailSeriesRowError.duplicateOutputName("my-show-1").errorDescription!])
        #expect(report.renderableRowIDs == [first.id, unique.id])
    }

    @Test func warningsDoNotBlock() {
        let noEpisodeToken = Support.currentDesignSource(Support.sourceDocument(episodeLayerText: nil))
        let episodeRow = ThumbnailSeriesRow(title: "Has episode", episode: "3")
        let longRow = ThumbnailSeriesRow(title: String(repeating: "word ", count: 14).trimmingCharacters(in: .whitespaces))

        let report = validate([episodeRow, longRow], source: noEpisodeToken)

        #expect(report.renderableRowIDs == [episodeRow.id, longRow.id])
        #expect(report.issues(for: episodeRow.id).map(\.severity) == [.warning])
        #expect(report.issues(for: episodeRow.id).first?.message.contains("{episode}") == true)
        #expect(report.issues(for: longRow.id).map(\.severity) == [.warning])
    }

    @Test func importedImageClearsTheError() {
        let ref = ThumbnailSeriesImageRef(digest: "d1", originalFileName: "a.png")
        let row = ThumbnailSeriesRow(title: "Img", imageRef: ref)
        #expect(validate([row], digests: ["d1"]).renderableRowIDs == [row.id])
    }
}
