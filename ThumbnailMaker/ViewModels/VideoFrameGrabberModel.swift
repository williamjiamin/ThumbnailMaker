//
//  VideoFrameGrabberModel.swift
//  ThumbnailMaker
//
//  FRAME: state for the "Grab from Video" sheet, plus the editor intents that
//  place a grabbed frame. Heavy work (decode, Vision scoring) runs off the
//  main actor; every async result is tagged with a revision so a stale
//  preview, suggestion pass or video load can never overwrite a newer one.
//

import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// Where a grabbed frame goes.
enum VideoFrameDestination: String, CaseIterable, Identifiable {
    case background
    case imageLayer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .background: "Use as Background"
        case .imageLayer: "Add as Image Layer"
        }
    }
}

@MainActor
final class VideoFrameGrabberModel: ObservableObject {
    enum Phase: Equatable {
        case empty
        case loading
        case ready(VideoFrameSource)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .empty
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var previewImage: UIImage?
    @Published private(set) var isRenderingPreview = false
    @Published private(set) var suggestions: [VideoFrameSuggestion] = []
    @Published private(set) var isAnalyzing = false
    @Published private(set) var hasAnalyzed = false
    @Published private(set) var isExporting = false

    /// Bumped on every new video (and on reset): tags loads and suggestion passes.
    private(set) var sourceRevision = 0
    /// Bumped on every seek: tags preview renders.
    private(set) var previewRevision = 0

    private var loadTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    /// Temporary copies this model owns and deletes when replaced.
    private var ownedFileURL: URL?
    private let detectsFaces: Bool

    init(detectsFaces: Bool = true) {
        self.detectsFaces = detectsFaces
    }

    var source: VideoFrameSource? {
        if case .ready(let source) = phase { return source }
        return nil
    }

    // MARK: Loading

    /// Loads a video. `ownsFile` marks a temporary copy the model deletes
    /// when it is replaced or the sheet closes.
    func loadVideo(at url: URL, ownsFile: Bool) {
        cancelWork()
        removeOwnedFile()
        if ownsFile { ownedFileURL = url }
        sourceRevision += 1
        let revision = sourceRevision
        phase = .loading
        currentTime = 0
        previewImage = nil
        suggestions = []
        hasAnalyzed = false

        loadTask = Task { [weak self] in
            do {
                let source = try await VideoFrameGrabber.load(url: url)
                guard let self, revision == self.sourceRevision, !Task.isCancelled else { return }
                self.phase = .ready(source)
                self.seek(to: min(source.duration * 0.1, 1.0))
                self.analyzeSuggestions()
            } catch {
                guard let self, revision == self.sourceRevision, !Task.isCancelled else { return }
                self.phase = .failed(
                    (error as? LocalizedError)?.errorDescription ?? "This video could not be opened."
                )
            }
        }
    }

    func showLoadFailure(_ message: String) {
        cancelWork()
        sourceRevision += 1
        phase = .failed(message)
    }

    /// Marks the start of an external import (picker transfer) so the sheet
    /// shows progress and any earlier in-flight work becomes stale.
    func beginExternalImport() {
        cancelWork()
        sourceRevision += 1
        phase = .loading
    }

    // MARK: Scrubbing

    /// Moves the playhead and renders the exact full-resolution frame there.
    /// Only the newest request may publish its image.
    func seek(to time: Double) {
        guard let source else { return }
        let clamped = VideoFrameTimeline.clampedTime(time, duration: source.duration)
        currentTime = clamped
        previewRevision += 1
        let revision = previewRevision
        previewTask?.cancel()
        isRenderingPreview = true
        previewTask = Task { [weak self] in
            let image = await Self.runDetached(priority: .userInitiated) {
                try await VideoFrameGrabber.frame(at: clamped, url: source.url, duration: source.duration)
            }
            guard let self, revision == self.previewRevision, !Task.isCancelled else { return }
            if let image {
                self.previewImage = UIImage(cgImage: image)
            }
            self.isRenderingPreview = false
        }
    }

    func seek(toFraction fraction: Double) {
        guard let source else { return }
        seek(to: VideoFrameTimeline.time(forFraction: fraction, duration: source.duration))
    }

    func select(_ suggestion: VideoFrameSuggestion) {
        seek(to: suggestion.decodeTime)
    }

    // MARK: Suggestions

    /// Samples ~40 frames off the main actor and publishes the top 6 distinct.
    func analyzeSuggestions() {
        guard let source else { return }
        analysisTask?.cancel()
        let revision = sourceRevision
        let detectsFaces = detectsFaces
        isAnalyzing = true
        analysisTask = Task { [weak self] in
            let result = await Self.runDetached(priority: .utility) {
                try await VideoFrameGrabber.suggestions(for: source, detectsFaces: detectsFaces)
            }
            guard let self, revision == self.sourceRevision, !Task.isCancelled else { return }
            self.suggestions = result ?? []
            self.hasAnalyzed = true
            self.isAnalyzing = false
        }
    }

    // MARK: Export

    /// Lossless PNG of the exact full-resolution frame at the playhead.
    func currentFramePNG() async -> Data? {
        guard let source else { return nil }
        let time = currentTime
        let revision = sourceRevision
        isExporting = true
        defer { isExporting = false }
        let data = await Self.runDetached(priority: .userInitiated) {
            try await VideoFrameGrabber.pngData(at: time, url: source.url, duration: source.duration)
        }
        guard revision == sourceRevision else { return nil }
        return data
    }

    /// Runs `work` off the main actor; cancelling the caller cancels it.
    private static func runDetached<T: Sendable>(
        priority: TaskPriority,
        _ work: @escaping @Sendable () async throws -> T
    ) async -> T? {
        let task = Task.detached(priority: priority, operation: work)
        return await withTaskCancellationHandler {
            try? await task.value
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: Teardown

    func cancelWork() {
        loadTask?.cancel()
        previewTask?.cancel()
        analysisTask?.cancel()
        loadTask = nil
        previewTask = nil
        analysisTask = nil
        isAnalyzing = false
        isRenderingPreview = false
    }

    /// Cancels everything, invalidates in-flight results and deletes any
    /// temporary copy of the video.
    func reset() {
        cancelWork()
        sourceRevision += 1
        previewRevision += 1
        removeOwnedFile()
        phase = .empty
        previewImage = nil
        suggestions = []
        hasAnalyzed = false
    }

    private func removeOwnedFile() {
        guard let url = ownedFileURL else { return }
        ownedFileURL = nil
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// A fresh private directory for one imported video copy.
    nonisolated static func makeImportDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoFrameImports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Copies `url` into a private temporary directory (security scoped when
    /// it came from Files) and returns the copy.
    nonisolated static func copyToImportDirectory(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let directory = try makeImportDirectory()
        let name = url.lastPathComponent.isEmpty ? "video.mov" : url.lastPathComponent
        let destination = directory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }
}

// MARK: - Editor intents

/// The two view-model intents a grabbed frame needs, shared by both editors
/// without touching their private history state.
@MainActor
protocol VideoFrameEditing: ThumbnailQuickActionEditing {
    func beginImageImport() -> Int
    func applyImportedImageData(_ data: Data, revision: Int, preservingFrame: Bool) -> Bool
}

extension SimpleMakerViewModel: VideoFrameEditing {}
extension PremiumMakerViewModel: VideoFrameEditing {}

extension VideoFrameEditing {
    /// Places a grabbed frame (lossless PNG) as one undo step. The background
    /// path bumps the image-import revision, so an older in-flight photo pick
    /// cannot overwrite it, and starts from a fresh frame recipe since the
    /// video frame's aspect ratio differs from the previous photo's.
    /// Returns whether it applied and, for a layer, the new layer to select.
    @discardableResult
    func applyVideoFrame(
        _ pngData: Data,
        as destination: VideoFrameDestination
    ) -> (applied: Bool, selection: ThumbnailLayerSelection?) {
        guard UIImage(data: pngData) != nil else { return (false, nil) }
        switch destination {
        case .imageLayer:
            return (true, addImageLayer(imageData: pngData))
        case .background:
            commitEditorStateNow()
            let revision = beginImageImport()
            guard applyImportedImageData(pngData, revision: revision, preservingFrame: false) else {
                return (false, nil)
            }
            commitEditorStateNow()
            return (true, nil)
        }
    }
}
