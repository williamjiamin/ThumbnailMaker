//
//  FirstExportGuideStore.swift
//  ThumbnailMaker
//
//  FEATURE-13: persists FirstExportGuideProgress as a small JSON file next to
//  the other app-level stores (BrandKitStore pattern). Never part of a project.
//

import Foundation

final class FirstExportGuideStore {
    struct LoadResult: Equatable {
        var progress: FirstExportGuideProgress
        /// False when the file on disk came from a newer build: we show nothing
        /// and never overwrite it.
        var isWritable: Bool
    }

    /// nil means in-memory (UI tests, previews, unit tests).
    let fileURL: URL?
    private var memory: FirstExportGuideProgress?

    init(fileURL: URL? = FirstExportGuideStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    static func inMemory(_ initial: FirstExportGuideProgress? = nil) -> FirstExportGuideStore {
        let store = FirstExportGuideStore(fileURL: nil)
        store.memory = initial
        return store
    }

    static var defaultFileURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return applicationSupport
            .appendingPathComponent("ThumbnailMaker", isDirectory: true)
            .appendingPathComponent("Guide", isDirectory: true)
            .appendingPathComponent("first-export-guide.json")
    }

    /// Launch policy:
    /// - `-DisableDraftPersistence` (every existing UI test): in-memory and
    ///   already skipped, so no card shifts existing layouts.
    /// - plus `-UITestFirstExportGuide`: in-memory and running.
    /// - `-UITestResetFirstExportGuide`: deletes only the guide file.
    static func forLaunch(
        arguments: [String],
        fileURL: URL = FirstExportGuideStore.defaultFileURL
    ) -> FirstExportGuideStore {
        if arguments.contains("-UITestResetFirstExportGuide") {
            try? FileManager.default.removeItem(at: fileURL)
        }
        if arguments.contains("-UITestFirstExportGuide") {
            return .inMemory(FirstExportGuideProgress(status: .active, currentStep: .addVisual))
        }
        if arguments.contains("-DisableDraftPersistence") {
            return .inMemory(FirstExportGuideProgress(status: .skipped))
        }
        return FirstExportGuideStore(fileURL: fileURL)
    }

    /// Never throws. Missing file -> fresh progress. Unreadable file -> skipped
    /// (the user can restart from Settings, which overwrites it). File from a
    /// newer schema -> skipped and read-only.
    func load() -> LoadResult {
        guard let fileURL else {
            return LoadResult(progress: memory ?? FirstExportGuideProgress(), isWritable: true)
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LoadResult(progress: FirstExportGuideProgress(), isWritable: true)
        }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder.firstExportGuideDecoder.decode(
                FirstExportGuideProgress.self,
                from: data
              ) else {
            return LoadResult(progress: FirstExportGuideProgress(status: .skipped), isWritable: true)
        }
        guard decoded.isSupported else {
            return LoadResult(progress: FirstExportGuideProgress(status: .skipped), isWritable: false)
        }
        return LoadResult(progress: decoded, isWritable: true)
    }

    func save(_ progress: FirstExportGuideProgress) throws {
        guard let fileURL else {
            memory = progress
            return
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder.firstExportGuideEncoder
            .encode(progress)
            .write(to: fileURL, options: [.atomic])
    }
}

extension JSONEncoder {
    static var firstExportGuideEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var firstExportGuideDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
