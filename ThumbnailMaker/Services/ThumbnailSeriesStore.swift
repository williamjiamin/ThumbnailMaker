//
//  ThumbnailSeriesStore.swift
//  ThumbnailMaker
//
//  FEATURE-15: file-backed series storage.
//
//      <directory>/series.json        rows + name (small, saved on every edit)
//      <directory>/source.json        the immutable source (written on capture)
//      <directory>/assets/<sha256>    row images, content-addressed (stored once)
//
//  For a library project <directory> is `<project>/series/`, so trashing a
//  project keeps its series and purging removes it. Writes are atomic. An
//  unreadable file is moved to `quarantine/` (never deleted) and reported.
//

import Foundation
import UIKit

struct ThumbnailSeriesLoadResult {
    var series: ThumbnailSeries?
    var source: ThumbnailSeriesSource?
    /// Human-readable notes about files that could not be read.
    var recoveryNotices: [String] = []
}

enum ThumbnailSeriesStoreError: LocalizedError, Equatable {
    case imageUnreadable(fileName: String)
    case imageTooLarge(fileName: String, limit: Int)

    var errorDescription: String? {
        switch self {
        case .imageUnreadable(let fileName):
            return "\"\(fileName)\" isn't an image this app can read."
        case let .imageTooLarge(fileName, limit):
            let formatted = ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)
            return "\"\(fileName)\" is larger than \(formatted). Use a smaller image."
        }
    }
}

final class ThumbnailSeriesStore {
    static let seriesFileName = "series.json"
    static let sourceFileName = "source.json"
    static let assetsDirectoryName = "assets"
    static let quarantineDirectoryName = "quarantine"
    static let maximumImageBytes = 40 * 1024 * 1024

    let directory: URL
    private let fileManager = FileManager.default

    init(directory: URL) {
        self.directory = directory
    }

    /// `<project>/series/` for a library project.
    convenience init(projectDirectory: URL) {
        self.init(directory: projectDirectory.appendingPathComponent("series", isDirectory: true))
    }

    /// Used when the editor has no library project (e.g. project library off).
    static func defaultDirectory(for editorMode: ThumbnailDocumentEditorMode) -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("ThumbnailMaker", isDirectory: true)
            .appendingPathComponent("Series", isDirectory: true)
            .appendingPathComponent(editorMode.rawValue, isDirectory: true)
    }

    var seriesURL: URL { directory.appendingPathComponent(Self.seriesFileName) }
    var sourceURL: URL { directory.appendingPathComponent(Self.sourceFileName) }
    var assetsDirectory: URL { directory.appendingPathComponent(Self.assetsDirectoryName, isDirectory: true) }

    // MARK: Load

    func load() -> ThumbnailSeriesLoadResult {
        var result = ThumbnailSeriesLoadResult()
        if fileManager.fileExists(atPath: seriesURL.path) {
            do {
                result.series = try Self.decoder.decode(ThumbnailSeries.self, from: Data(contentsOf: seriesURL))
            } catch {
                result.recoveryNotices.append(quarantine(seriesURL, label: "series table"))
            }
        }
        if fileManager.fileExists(atPath: sourceURL.path) {
            do {
                result.source = try Self.decoder.decode(ThumbnailSeriesSource.self, from: Data(contentsOf: sourceURL))
            } catch {
                result.recoveryNotices.append(quarantine(sourceURL, label: "series source"))
            }
        }
        return result
    }

    // MARK: Save

    func save(_ series: ThumbnailSeries) throws {
        try ensureDirectory(directory)
        try Self.encoder.encode(series).write(to: seriesURL, options: .atomic)
    }

    func saveSource(_ source: ThumbnailSeriesSource) throws {
        try ensureDirectory(directory)
        try Self.encoder.encode(source).write(to: sourceURL, options: .atomic)
    }

    // MARK: Assets

    /// Stores an image once (by content) and returns its reference. Images
    /// with a non-up orientation are normalised to PNG exactly like the
    /// editor's document encoding; others keep their original bytes.
    func importImage(_ data: Data, originalFileName: String) throws -> ThumbnailSeriesImageRef {
        guard data.count <= Self.maximumImageBytes else {
            throw ThumbnailSeriesStoreError.imageTooLarge(fileName: originalFileName, limit: Self.maximumImageBytes)
        }
        guard let image = UIImage(data: data) else {
            throw ThumbnailSeriesStoreError.imageUnreadable(fileName: originalFileName)
        }
        var stored = data
        if image.imageOrientation != .up {
            let format = UIGraphicsImageRendererFormat()
            format.scale = image.scale
            format.opaque = false
            stored = UIGraphicsImageRenderer(size: image.size, format: format)
                .image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
                .pngData() ?? data
        }
        let digest = ThumbnailVariantAssetLibrary.digest(stored)
        let url = assetURL(digest)
        if !fileManager.fileExists(atPath: url.path) {
            try ensureDirectory(assetsDirectory)
            try stored.write(to: url, options: .atomic)
        }
        return ThumbnailSeriesImageRef(digest: digest, originalFileName: originalFileName)
    }

    func assetData(_ digest: String) -> Data? {
        try? Data(contentsOf: assetURL(digest))
    }

    func availableAssetDigests() -> Set<String> {
        let names = (try? fileManager.contentsOfDirectory(atPath: assetsDirectory.path)) ?? []
        return Set(names.filter { !$0.hasPrefix(".") })
    }

    /// Removes assets no row references (e.g. after rows were deleted and the
    /// deletion can no longer be undone).
    func removeUnreferencedAssets(keeping digests: Set<String>) {
        for name in availableAssetDigests() where !digests.contains(name) {
            try? fileManager.removeItem(at: assetURL(name))
        }
    }

    func deleteAll() throws {
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    // MARK: Plumbing

    private func assetURL(_ digest: String) -> URL {
        assetsDirectory.appendingPathComponent(digest)
    }

    private func ensureDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func quarantine(_ url: URL, label: String) -> String {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folder = directory.appendingPathComponent(Self.quarantineDirectoryName, isDirectory: true)
        let target = folder.appendingPathComponent("\(stamp)-\(url.lastPathComponent)")
        do {
            try ensureDirectory(folder)
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.moveItem(at: url, to: target)
            return "The saved \(label) couldn't be read and was set aside. Starting fresh."
        } catch {
            return "The saved \(label) couldn't be read."
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
