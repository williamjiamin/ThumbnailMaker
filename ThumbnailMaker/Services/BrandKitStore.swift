//
//  BrandKitStore.swift
//  ThumbnailMaker
//

import Foundation

/// FEATURE-08: persists a `BrandKitLibrary` (many kits, one active) at
/// `libraryFileURL`. The legacy single-kit file at `fileURL` is migrated on
/// read without being rewritten, so a downgraded build still finds its kit.
/// `save(_:)` / `load()` remain as active-kit shims.
final class BrandKitStore {
    let fileURL: URL
    let libraryFileURL: URL

    init(fileURL: URL = BrandKitStore.defaultFileURL, libraryFileURL: URL? = nil) {
        self.fileURL = fileURL
        self.libraryFileURL = libraryFileURL
            ?? fileURL.deletingLastPathComponent().appendingPathComponent("brand-kits.json")
    }

    static var defaultFileURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return applicationSupport
            .appendingPathComponent("ThumbnailMaker", isDirectory: true)
            .appendingPathComponent("BrandKits", isDirectory: true)
            .appendingPathComponent("brand-kit.json")
    }

    // MARK: Library

    func saveLibrary(_ library: BrandKitLibrary) throws {
        var library = library
        library.updatedAt = Date()

        try FileManager.default.createDirectory(
            at: libraryFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try JSONEncoder.brandKitEncoder
            .encode(library)
            .write(to: libraryFileURL, options: [.atomic])
    }

    /// Library file first; else the legacy single kit (not rewritten); else empty.
    func loadLibrary() throws -> BrandKitLibrary {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: libraryFileURL.path) {
            let data = try Data(contentsOf: libraryFileURL)
            do {
                return try JSONDecoder.brandKitDecoder.decode(BrandKitLibrary.self, from: data)
            } catch {
                // A hand-copied single kit under the library name still opens.
                if let kit = try? JSONDecoder.brandKitDecoder.decode(BrandKit.self, from: data) {
                    return BrandKitLibrary(kits: [kit], activeKitID: kit.id, updatedAt: kit.updatedAt)
                }
                throw error
            }
        }

        if fileManager.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            let legacy = try JSONDecoder.brandKitDecoder.decode(BrandKit.self, from: data)
            return BrandKitLibrary(kits: [legacy], activeKitID: legacy.id, updatedAt: legacy.updatedAt)
        }

        return .empty
    }

    // MARK: Active-kit shims (pre-library API)

    func save(_ brandKit: BrandKit) throws {
        var brandKit = brandKit
        brandKit.updatedAt = Date()
        var library = try loadLibrary()
        guard library.upsert(brandKit, activate: true) else {
            throw BrandKitStoreError.libraryFull
        }
        try saveLibrary(library)
    }

    func load() throws -> BrandKit? {
        try loadLibrary().activeKit
    }

    /// Removes the whole library and the legacy file.
    func delete() throws {
        for url in [libraryFileURL, fileURL] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

enum BrandKitStoreError: LocalizedError, Equatable {
    case libraryFull

    var errorDescription: String? {
        switch self {
        case .libraryFull:
            return "You can keep up to \(BrandKitLibrary.maximumKitCount) brand kits. Delete one to add another."
        }
    }
}

private extension JSONEncoder {
    static var brandKitEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var brandKitDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
