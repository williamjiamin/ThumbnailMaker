//
//  ThumbnailSeriesStoreTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-15: series persistence, content-addressed images, quarantine.
//

import Foundation
import Testing
@testable import ThumbnailMaker

struct ThumbnailSeriesStoreTests {
    private typealias Support = SeriesTestSupport

    @Test func seriesAndSourceRoundTrip() throws {
        let directory = Support.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailSeriesStore(directory: directory)
        let source = Support.currentDesignSource()
        let series = ThumbnailSeries(
            name: "Show",
            createdAt: Support.captureDate,
            updatedAt: Support.captureDate,
            sourceDigest: source.digest,
            rows: [ThumbnailSeriesRow(title: "A", episode: "1", outputName: "a"), ThumbnailSeriesRow(title: "B")]
        )

        try store.save(series)
        try store.saveSource(source)
        let loaded = store.load()

        #expect(loaded.series == series)
        #expect(loaded.source == source)
        #expect(loaded.recoveryNotices.isEmpty)
    }

    @Test func imagesAreStoredOnceByContent() throws {
        let directory = Support.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailSeriesStore(directory: directory)
        let data = Support.imageData()

        let refs = try (1...10).map { try store.importImage(data, originalFileName: "ep\($0).png") }

        #expect(Set(refs.map(\.digest)).count == 1)
        #expect(store.availableAssetDigests() == [refs[0].digest])
        #expect(store.assetData(refs[0].digest) == data)
        #expect(refs[3].originalFileName == "ep4.png")
    }

    @Test func unreadableImageIsRejected() {
        let directory = Support.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailSeriesStore(directory: directory)

        #expect(throws: ThumbnailSeriesStoreError.imageUnreadable(fileName: "notes.txt")) {
            try store.importImage(Data("hello".utf8), originalFileName: "notes.txt")
        }
        #expect(store.availableAssetDigests().isEmpty)
    }

    @Test func corruptFilesAreQuarantinedNotDeleted() throws {
        let directory = Support.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailSeriesStore(directory: directory)
        try store.saveSource(Support.currentDesignSource())
        try Data("{ not json".utf8).write(to: store.seriesURL)

        let loaded = store.load()

        #expect(loaded.series == nil)
        #expect(loaded.source != nil)
        #expect(loaded.recoveryNotices.count == 1)
        #expect(!FileManager.default.fileExists(atPath: store.seriesURL.path))
        let quarantined = try FileManager.default.contentsOfDirectory(
            atPath: directory.appendingPathComponent(ThumbnailSeriesStore.quarantineDirectoryName).path
        )
        #expect(quarantined.count == 1)
    }

    @Test func projectSeriesLivesInsideTheProjectAndIsPurgedWithIt() throws {
        let root = Support.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = ThumbnailProjectStore(rootDirectory: root)
        let id = UUID()
        let store = ThumbnailSeriesStore(projectDirectory: projects.projectDirectory(id: id))
        try store.save(ThumbnailSeries(name: "S"))

        #expect(store.seriesURL.path.hasPrefix(projects.projectDirectory(id: id).path))
        try projects.purgeDirectory(id: id)
        #expect(!FileManager.default.fileExists(atPath: store.seriesURL.path))
    }
}
