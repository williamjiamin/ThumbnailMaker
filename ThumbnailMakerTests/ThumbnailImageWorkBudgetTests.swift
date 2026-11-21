//
//  ThumbnailImageWorkBudgetTests.swift
//  ThumbnailMakerTests
//
//  APP-09: editing that does not change the photo does no photo work.
//  These assert on event counts, which are deterministic; timings are only
//  recorded (see ThumbnailPerformanceBudget).
//

import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ThumbnailImageWorkBudgetTests {
    private typealias Support = ThumbnailPerformanceTestSupport

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @Test func simpleEditorTextEditsUndoAndVariantsNeverReencodeThePhoto() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        let photo = try #require(Support.makePhoto(width: 320, height: 180).pngData())
        #expect(viewModel.applyImportedImageData(photo, revision: viewModel.beginImageImport()))
        viewModel.commitEditorStateNow()

        let recorder = Support.recording {
            for index in 0..<30 {
                viewModel.simpleMakerConfiguration.overlayText = "Title \(index)"
                viewModel.commitEditorStateNow()
            }
            for _ in 0..<5 { viewModel.undo() }
            for _ in 0..<5 { viewModel.redo() }
            _ = viewModel.duplicateActiveVariant()
            viewModel.simpleMakerConfiguration.overlayText = "Variant B"
            viewModel.commitEditorStateNow()
            viewModel.selectVariant(.a)
            viewModel.selectVariant(.b)
        }

        #expect(recorder.count(of: .imageEncode) == ThumbnailPerformanceBudget.imageEncodesPerUnchangedCommit)
        #expect(recorder.count(of: .historyCommit) >= 30)
        #expect(recorder.count(of: .undoRedo) == 10)
        #expect(recorder.count(of: .variantSwitch) == 2)
        #expect(recorder.count(of: .draftSave) > 0)
        #expect(recorder.lastSample(of: .historyCommit)?.footprintBytes != nil)

        let current = try #require(viewModel.simpleMakerConfiguration.document.imageData)
        let undoStack = viewModel.variantWorkspace.activeHistory.undoStack
        #expect(!undoStack.isEmpty)
        for snapshot in undoStack {
            #expect(ThumbnailDocumentPayloads.sharesBuffer(try #require(snapshot.imageData), current))
        }
        let payload = viewModel.variantWorkspace.historyBook.totalPayloadBytes()
        #expect(payload == current.count, "Every snapshot in every variant shares one photo buffer.")
    }

    @Test func premiumEditorTextEditsNeverReencodeThePhoto() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = PremiumMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        let photo = try #require(Support.makePhoto(width: 320, height: 180, seed: 0.4).pngData())
        #expect(viewModel.applyImportedImageData(photo, revision: viewModel.beginImageImport()))
        viewModel.commitEditorStateNow()

        let recorder = Support.recording {
            for index in 0..<20 {
                viewModel.premiumMakerConfiguration.overlayText = "Premium \(index)"
                viewModel.commitEditorStateNow()
            }
            for _ in 0..<3 { viewModel.undo() }
            for _ in 0..<3 { viewModel.redo() }
        }

        #expect(recorder.count(of: .imageEncode) == 0)
        #expect(recorder.count(of: .undoRedo) == 6)
        #expect(viewModel.premiumMakerConfiguration.overlayText == "Premium 19")
    }

    @Test func changingThePhotoIsStillEncodedAndUndoable() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json")),
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        let first = try #require(Support.makePhoto(seed: 0.1).pngData())
        let second = try #require(Support.makePhoto(seed: 0.7).pngData())
        #expect(viewModel.applyImportedImageData(first, revision: viewModel.beginImageImport()))
        viewModel.commitEditorStateNow()
        let firstDocumentData = try #require(viewModel.simpleMakerConfiguration.document.imageData)

        let recorder = Support.recording {
            _ = viewModel.applyImportedImageData(second, revision: viewModel.beginImageImport())
            viewModel.commitEditorStateNow()
        }
        #expect(recorder.count(of: .imageEncode) == 1)
        let secondDocumentData = try #require(viewModel.simpleMakerConfiguration.document.imageData)
        #expect(secondDocumentData != firstDocumentData)

        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.document.imageData == firstDocumentData)
    }

    @Test func diagnosticsSnapshotReportsCountsAndBudgets() {
        let recorder = ThumbnailPerformanceRecorder(capacity: 3)
        let now = Date()
        recorder.record(.init(op: .historyCommit, durationMs: 4, footprintBytes: 100, recordedAt: now))
        recorder.record(.init(op: .historyCommit, durationMs: 40, footprintBytes: 300, recordedAt: now))
        recorder.record(.init(op: .imageEncode, durationMs: 90, footprintBytes: nil, recordedAt: now))
        recorder.record(.init(op: .undoRedo, durationMs: 10, footprintBytes: 200, recordedAt: now))
        recorder.setHistoryPayloadBytes(ThumbnailPerformanceBudget.historyPayloadByteBudget + 1)

        let snapshot = PerformanceDiagnosticsSnapshot.make(recorder: recorder, currentFootprint: 1_048_576)
        #expect(recorder.recentSamples.count == 3, "Ring buffer keeps the newest samples.")
        #expect(snapshot.row(for: .historyCommit)?.count == 2, "Counts are not limited by capacity.")
        #expect(snapshot.row(for: .historyCommit)?.lastMs == 40)
        #expect(snapshot.row(for: .historyCommit)?.isOverBudget == true)
        #expect(snapshot.row(for: .undoRedo)?.isOverBudget == false)
        #expect(snapshot.row(for: .imageEncode)?.count == 1)
        #expect(snapshot.peakFootprintBytes == 300)
        #expect(snapshot.isHistoryPayloadOverBudget)
        #expect(!snapshot.isFootprintOverBudget)
        #expect(PerformanceDiagnosticsSnapshot.megabytes(snapshot.footprintBytes) == "1.0 MB")

        recorder.reset()
        #expect(recorder.count(of: .historyCommit) == 0)
        #expect(ThumbnailMemoryFootprint.currentBytes() ?? 0 > 0)
    }
}
