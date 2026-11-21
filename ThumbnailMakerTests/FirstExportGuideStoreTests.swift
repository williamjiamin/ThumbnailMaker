//
//  FirstExportGuideStoreTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-13: guide progress persistence, back-compat and launch policy.
//

import Foundation
import Testing
@testable import ThumbnailMaker

@MainActor
struct FirstExportGuideStoreTests {
    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FirstExportGuideStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func missingFileLoadsDefault() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FirstExportGuideStore(fileURL: directory.appendingPathComponent("guide.json"))
        let result = store.load()
        #expect(result.progress == FirstExportGuideProgress())
        #expect(result.isWritable)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FirstExportGuideStore(fileURL: directory.appendingPathComponent("nested/guide.json"))
        var progress = FirstExportGuideProgress(status: .paused, currentStep: .checkReadiness, completedSteps: [.addVisual, .writeTitle])
        progress.startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        progress.pausedAt = Date(timeIntervalSince1970: 1_700_000_100)
        progress.lastEditorMode = .premium
        try store.save(progress)
        #expect(store.load().progress == progress)
    }

    @Test func legacyMinimalJSONDecodesWithDefaults() throws {
        let data = Data(#"{"status":"active"}"#.utf8)
        let progress = try JSONDecoder.firstExportGuideDecoder.decode(FirstExportGuideProgress.self, from: data)
        #expect(progress.status == .active)
        #expect(progress.schemaVersion == 1)
        #expect(progress.completedSteps.isEmpty)
        #expect(progress.currentStep == nil)
        #expect(progress.completionAcknowledged == false)
    }

    @Test func unknownStepNamesAreDropped() throws {
        let data = Data(#"{"status":"active","completedSteps":["writeTitle","pickMusic","addVisual"],"currentStep":"pickMusic"}"#.utf8)
        let progress = try JSONDecoder.firstExportGuideDecoder.decode(FirstExportGuideProgress.self, from: data)
        #expect(progress.completedSteps == [.addVisual, .writeTitle])
        #expect(progress.currentStep == nil)
    }

    @Test func futureSchemaIsHiddenAndNeverOverwritten() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("guide.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = Data(#"{"schemaVersion":99,"status":"active","newField":true}"#.utf8)
        try original.write(to: fileURL)

        let store = FirstExportGuideStore(fileURL: fileURL)
        let result = store.load()
        #expect(result.progress.status == .skipped)
        #expect(!result.isWritable)

        let controller = FirstExportGuideController(store: store)
        #expect(controller.presentation == .hidden)
        controller.showFromSettings()
        controller.recordExport(ThumbnailExportEvent(kind: .photos, editorMode: .simple))
        #expect(try Data(contentsOf: fileURL) == original)
    }

    @Test func corruptFileLoadsAsSkippedWithoutThrowing() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("guide.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0xFF, 0x00, 0x13]).write(to: fileURL)

        let result = FirstExportGuideStore(fileURL: fileURL).load()
        #expect(result.progress.status == .skipped)
        #expect(result.isWritable)
    }

    @Test func launchPolicyForUITests() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("guide.json")

        let existingTests = FirstExportGuideStore.forLaunch(arguments: ["-DisableDraftPersistence"], fileURL: fileURL)
        #expect(existingTests.fileURL == nil)
        #expect(existingTests.load().progress.status == .skipped)

        let guideTests = FirstExportGuideStore.forLaunch(
            arguments: ["-DisableDraftPersistence", "-UITestFirstExportGuide"],
            fileURL: fileURL
        )
        #expect(guideTests.fileURL == nil)
        #expect(guideTests.load().progress.status == .active)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sibling = directory.appendingPathComponent("brand-kit.json")
        try Data("{}".utf8).write(to: sibling)
        try FirstExportGuideStore(fileURL: fileURL).save(FirstExportGuideProgress(status: .completed))
        let reset = FirstExportGuideStore.forLaunch(arguments: ["-UITestResetFirstExportGuide"], fileURL: fileURL)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(FileManager.default.fileExists(atPath: sibling.path))
        #expect(reset.fileURL == fileURL)
        #expect(reset.load().progress == FirstExportGuideProgress())
    }
}
