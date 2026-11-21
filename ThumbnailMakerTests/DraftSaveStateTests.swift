//
//  DraftSaveStateTests.swift
//  ThumbnailMakerTests
//
//  Verifies that SimpleMakerViewModel / PremiumMakerViewModel publish
//  DraftSaveState transitions and preserve the last good document when
//  a save attempt fails.
//

import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct DraftSaveStateTests {
    @Test func simpleMakerTransitionsToSavedOnSuccess() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json"))
        let viewModel = SimpleMakerViewModel(draftStore: store, brandKitStore: brandStore(in: directory))
        viewModel.simpleMakerConfiguration.overlayText = "first version"

        viewModel.saveDraftNow()
        if case .saved = viewModel.draftSaveState {
            // expected
        } else {
            Issue.record("Expected .saved state, got \(viewModel.draftSaveState)")
        }
        #expect(viewModel.saveError == nil)
    }

    @Test func premiumMakerTransitionsToSavedOnSuccess() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium.json"))
        let viewModel = PremiumMakerViewModel(draftStore: store, brandKitStore: brandStore(in: directory))
        viewModel.premiumMakerConfiguration.overlayText = "premium draft"

        viewModel.saveDraftNow()
        if case .saved = viewModel.draftSaveState {
            // expected
        } else {
            Issue.record("Expected .saved state, got \(viewModel.draftSaveState)")
        }
        #expect(viewModel.saveError == nil)
    }

    @Test func lastGoodDraftSurvivesFailedSaveAndRetrySucceeds() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
            try? FileManager.default.removeItem(at: directory)
        }
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json"))
        let viewModel = SimpleMakerViewModel(draftStore: store, brandKitStore: brandStore(in: directory))

        viewModel.simpleMakerConfiguration.overlayText = "good draft"
        viewModel.saveDraftNow()
        if case .saved = viewModel.draftSaveState {
            // expected baseline
        } else {
            Issue.record("Expected .saved state for baseline, got \(viewModel.draftSaveState)")
        }
        let baselineBytes = try #require(try? Data(contentsOf: store.fileURL))
        #expect(!baselineBytes.isEmpty)

        // Force the next save to fail by making the containing directory
        // read-only. The store's atomic write needs to create a temporary file
        // beside the draft, so the write fails while the directory and the
        // already-saved bytes stay readable — which is what lets the
        // "last good draft survives" invariant actually be observed.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: directory.path
        )
        viewModel.simpleMakerConfiguration.overlayText = "doomed"
        viewModel.saveDraftNow()
        if case .failed = viewModel.draftSaveState {
            // expected failure surfaced
        } else {
            Issue.record("Expected .failed state after save into read-only dir, got \(viewModel.draftSaveState)")
        }
        #expect(viewModel.draftSaveState.failureMessage != nil)
        #expect(viewModel.saveError != nil)

        // The failed write must not have corrupted or replaced the last good
        // draft that was already on disk.
        #expect(try Data(contentsOf: store.fileURL) == baselineBytes)
        let survivor = try #require(try store.load())
        #expect(survivor.overlayText == "good draft")

        // Repair the directory and retry. The retry must succeed and must now
        // persist the current configuration, not the stale baseline.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        viewModel.retryDraftSave()
        if case .saved = viewModel.draftSaveState {
            // expected recovery
        } else {
            Issue.record("Expected .saved after retry, got \(viewModel.draftSaveState)")
        }
        let restored = try #require(try store.load())
        #expect(restored.overlayText == "doomed")
    }

    private func brandStore(in directory: URL) -> BrandKitStore {
        BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
    }
}
