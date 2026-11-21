//
//  ThumbnailSeriesCSVTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-15: tolerant CSV parsing with per-record isolation.
//

import Foundation
import Testing
@testable import ThumbnailMaker

struct ThumbnailSeriesCSVTests {
    @Test func tenRowFixtureIsolatesThreeMalformedRecordsWithLineNumbers() {
        let result = ThumbnailSeriesCSVParser.parse(SeriesTestSupport.tenRowCSV)

        #expect(result.fileError == nil)
        #expect(result.records.count == 7)
        #expect(result.records.map(\.line) == [2, 3, 5, 6, 8, 9, 11])
        #expect(result.recordErrors.map(\.line) == [4, 7, 10])
        #expect(result.records.map { $0.fields[.title] ?? "" } == [
            "Morning Routine",
            "Lighting, Explained",
            "The \"Perfect\" Desk",
            "Editing Speedrun",
            "Camera Settings",
            "Audio Tips",
            "Channel Q&A"
        ])
        #expect(result.records[2].fields[.name] == "desk-special")
        #expect(result.records[3].fields[.image] == "EP5.JPG")
    }

    @Test func lineEndingsAndBOMGiveIdenticalResults() {
        let lf = ThumbnailSeriesCSVParser.parse(SeriesTestSupport.tenRowCSV)
        let crlf = ThumbnailSeriesCSVParser.parse(SeriesTestSupport.tenRowCSV.replacingOccurrences(of: "\n", with: "\r\n"))
        let cr = ThumbnailSeriesCSVParser.parse(SeriesTestSupport.tenRowCSV.replacingOccurrences(of: "\n", with: "\r"))
        let bom = ThumbnailSeriesCSVParser.parse(Data([0xEF, 0xBB, 0xBF]) + Data(SeriesTestSupport.tenRowCSV.utf8))

        #expect(crlf == lf)
        #expect(cr == lf)
        #expect(bom == lf)
    }

    @Test func headersIgnoreCaseSpacesOrderAndUnknownColumns() {
        let csv = " Episode ,Notes, TITLE \n12,skip me,Hello\n\n13,,World\n"
        let result = ThumbnailSeriesCSVParser.parse(csv)

        #expect(result.fileError == nil)
        #expect(result.ignoredColumns == ["Notes"])
        #expect(result.records.map { $0.fields[.title] } == ["Hello", "World"])
        #expect(result.records.map { $0.fields[.episode] } == ["12", "13"])
        #expect(result.records.map(\.line) == [2, 4])
    }

    @Test func quotedFieldsKeepCommasQuotesAndLineBreaks() {
        let csv = "title,episode\n\"Line one\nLine two, still\",\"say \"\"hi\"\"\"\nNext,2\n"
        let result = ThumbnailSeriesCSVParser.parse(csv)

        #expect(result.recordErrors.isEmpty)
        #expect(result.records.count == 2)
        #expect(result.records[0].fields[.title] == "Line one\nLine two, still")
        #expect(result.records[0].fields[.episode] == "say \"hi\"")
        #expect(result.records[1].line == 4)
    }

    @Test func fileLevelErrors() {
        #expect(ThumbnailSeriesCSVParser.parse("").fileError == .empty)
        #expect(ThumbnailSeriesCSVParser.parse("\n  \n").fileError == .empty)
        #expect(ThumbnailSeriesCSVParser.parse("episode,image\n1,a.jpg\n").fileError == .missingTitleColumn)
        #expect(ThumbnailSeriesCSVParser.parse("title,Title\na,b\n").fileError == .duplicateHeader("title"))
        #expect(ThumbnailSeriesCSVParser.parse(Data([0x74, 0xFF, 0xFE, 0x0A])).fileError == .notUTF8)

        let tooMany = (["title"] + (1...101).map { "Row \($0)" }).joined(separator: "\n")
        #expect(ThumbnailSeriesCSVParser.parse(tooMany).fileError == .tooManyRows(limit: ThumbnailSeries.rowLimit))
        let exactlyAtLimit = (["title"] + (1...100).map { "Row \($0)" }).joined(separator: "\n")
        #expect(ThumbnailSeriesCSVParser.parse(exactlyAtLimit).records.count == 100)
    }

    @Test func writerRoundTripsCommasQuotesUnicodeAndNewlines() {
        let rows = [
            ThumbnailSeriesRow(title: "Plain", episode: "1"),
            ThumbnailSeriesRow(title: "Comma, inside", episode: nil, requestedImageName: "a b.jpg", outputName: "custom"),
            ThumbnailSeriesRow(title: "Quote \"here\"", episode: "2"),
            ThumbnailSeriesRow(title: "日本語のタイトル 🎬", episode: "三"),
            ThumbnailSeriesRow(title: "Two\nlines", episode: " padded ")
        ]
        let csv = ThumbnailSeriesCSVWriter.csv(for: rows)
        let result = ThumbnailSeriesCSVParser.parse(csv)
        let imported = ThumbnailSeriesCSVImporter.rows(from: result)

        #expect(result.recordErrors.isEmpty)
        #expect(imported.rows.map(\.title) == rows.map(\.title))
        #expect(imported.rows.map(\.episode) == rows.map(\.episode))
        #expect(imported.rows.map(\.outputName) == rows.map(\.outputName))
        #expect(imported.rows.map(\.requestedImageName) == rows.map(\.requestedImageName))
    }

    @Test func importerKeepsMalformedRecordsAsFixableRowsInFileOrder() {
        let result = ThumbnailSeriesCSVParser.parse(SeriesTestSupport.tenRowCSV)
        let ref = ThumbnailSeriesImageRef(digest: "abc", originalFileName: "ep5.jpg")
        let imported = ThumbnailSeriesCSVImporter.rows(from: result, images: ["ep5.jpg": ref])

        #expect(imported.rows.count == 10)
        #expect(imported.validCount == 7)
        #expect(imported.errorCount == 3)
        #expect(imported.rows.map(\.sourceLine) == [2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
        #expect(imported.rows[2].importError != nil)
        #expect(imported.rows[5].importError != nil)
        #expect(imported.rows[8].importError != nil)
        // Image names match case-insensitively; unmatched names wait for an image.
        #expect(imported.rows[4].imageRef == ref)
        #expect(imported.rows[4].requestedImageName == nil)
        #expect(imported.rows[0].requestedImageName == "ep1.jpg")
        #expect(imported.summary == "Imported 10 rows · 3 need fixing")
    }
}
