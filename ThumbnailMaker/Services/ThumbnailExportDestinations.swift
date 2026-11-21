//
//  ThumbnailExportDestinations.swift
//  ThumbnailMaker
//
//  FEATURE-10: where the export queue writes. A user-picked Files folder keeps
//  exact names and detects conflicts; Photos adds new assets (names are not
//  kept, nothing is overwritten) and the UI says so.
//

import Foundation
import UIKit

enum ThumbnailExportWriteResult: Equatable {
    case written(fileName: String, url: URL?)
    case skippedExisting(fileName: String)
}

enum ThumbnailExportQueueError: LocalizedError, Equatable {
    case destinationUnavailable(String)
    case writeFailed(fileName: String, reason: String)
    case overBudget(String)

    var errorDescription: String? {
        switch self {
        case .destinationUnavailable(let name):
            return "Can't open \"\(name)\". Choose the folder again."
        case let .writeFailed(fileName, reason):
            return "Couldn't write \(fileName): \(reason)"
        case .overBudget(let message):
            return message
        }
    }
}

@MainActor
protocol ThumbnailExportDestinationWriting: AnyObject {
    var displayName: String { get }
    func snapshot() throws -> ThumbnailExportDestinationSnapshot
    /// Applies `policy` against the destination as it is NOW (files may have
    /// appeared since the plan was reviewed).
    func write(
        _ data: Data,
        fileName: String,
        format: ThumbnailExportFormat,
        policy: ThumbnailExportOverwritePolicy
    ) async throws -> ThumbnailExportWriteResult
}

// MARK: - Files folder

@MainActor
final class FolderExportDestination: ThumbnailExportDestinationWriting {
    static let bookmarkDefaultsKey = "ThumbnailExportQueue.folderBookmark"

    let folderURL: URL
    private let usesSecurityScope: Bool

    init(folderURL: URL, usesSecurityScope: Bool = true) {
        self.folderURL = folderURL
        self.usesSecurityScope = usesSecurityScope
    }

    var displayName: String {
        let name = folderURL.lastPathComponent
        return name.isEmpty ? "Folder" : name
    }

    func snapshot() throws -> ThumbnailExportDestinationSnapshot {
        let names = try withAccess { try currentFileNames() }
        return ThumbnailExportDestinationSnapshot(
            displayName: displayName,
            existingFileNames: names,
            supportsFileNames: true
        )
    }

    func write(
        _ data: Data,
        fileName: String,
        format: ThumbnailExportFormat,
        policy: ThumbnailExportOverwritePolicy
    ) async throws -> ThumbnailExportWriteResult {
        try withAccess {
            let existing = try currentFileNames()
            let exists = existing.contains(fileName.lowercased())
            let targetName: String
            switch policy {
            case .skip where exists:
                return .skippedExisting(fileName: fileName)
            case .keepBoth where exists:
                targetName = ThumbnailVariantExportNaming.uniqueName(fileName, taken: existing)
            default:
                targetName = fileName
            }

            let url = folderURL.appendingPathComponent(targetName)
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                throw ThumbnailExportQueueError.writeFailed(fileName: targetName, reason: error.localizedDescription)
            }
            return .written(fileName: targetName, url: url)
        }
    }

    private func currentFileNames() throws -> Set<String> {
        do {
            let names = try FileManager.default.contentsOfDirectory(atPath: folderURL.path)
            return Set(names.map { $0.lowercased() })
        } catch {
            throw ThumbnailExportQueueError.destinationUnavailable(displayName)
        }
    }

    private func withAccess<T>(_ body: () throws -> T) throws -> T {
        let didAccess = usesSecurityScope && folderURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { folderURL.stopAccessingSecurityScopedResource() }
        }
        return try body()
    }

    // MARK: Remembered folder (per device, never inside recipes or projects)

    static func remember(_ url: URL, defaults: UserDefaults = .standard) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        if let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(bookmark, forKey: bookmarkDefaultsKey)
        }
    }

    static func rememberedFolder(defaults: UserDefaults = .standard) -> FolderExportDestination? {
        guard let bookmark = defaults.data(forKey: bookmarkDefaultsKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            defaults.removeObject(forKey: bookmarkDefaultsKey)
            return nil
        }
        if isStale {
            remember(url, defaults: defaults)
        }
        return FolderExportDestination(folderURL: url)
    }

    static func forgetRememberedFolder(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: bookmarkDefaultsKey)
    }
}

// MARK: - Photos

@MainActor
final class PhotosExportDestination: ThumbnailExportDestinationWriting {
    static let namesNotKeptNote = "Photos doesn't keep file names and always adds new photos."

    var displayName: String { "Photos" }

    func snapshot() throws -> ThumbnailExportDestinationSnapshot {
        ThumbnailExportDestinationSnapshot(displayName: displayName, supportsFileNames: false)
    }

    func write(
        _ data: Data,
        fileName: String,
        format: ThumbnailExportFormat,
        policy: ThumbnailExportOverwritePolicy
    ) async throws -> ThumbnailExportWriteResult {
        var options = ThumbnailExportOptions()
        options.format = format
        try await ThumbnailExporter.saveEncodedDataToPhotoLibrary(data, options: options)
        return .written(fileName: fileName, url: nil)
    }
}
