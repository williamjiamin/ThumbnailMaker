//
//  ThumbnailPerformanceBudget.swift
//  ThumbnailMaker
//
//  APP-09: explicit performance and memory budgets. The millisecond targets
//  describe a 12 MP (4032x3024) photo on an A15-class device and are reported
//  by the diagnostics panel; they are NOT gating in tests, which assert on
//  event counts (encodes, hashes) instead because timings are noisy on
//  simulators and CI.
//

import Foundation

enum ThumbnailPerformanceBudget {
    /// Snapshot + history + save of a text edit when the photo is unchanged.
    static let textCommitMainMs: Double = 16
    static let undoRedoMs: Double = 50
    static let variantSwitchMs: Double = 100
    /// Image encodes allowed while committing an edit that did not change a photo.
    static let imageEncodesPerUnchangedCommit = 0
    /// Peak process footprint while editing.
    static let editingFootprintBytes: UInt64 = 450 * 1024 * 1024
    /// Distinct image bytes kept alive by undo/redo stacks and baselines across
    /// every variant slot. Snapshots that share a photo buffer count it once.
    static let historyPayloadByteBudget = 256 * 1024 * 1024
}
