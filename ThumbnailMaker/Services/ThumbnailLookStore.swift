//
//  ThumbnailLookStore.swift
//  ThumbnailMaker
//
//  FEATURE-14: persists the user's saved looks (atomic JSON), shared by both
//  editors. Mirrors BrandKitStore.
//

import Combine
import Foundation

final class ThumbnailLookStore {
    let fileURL: URL

    init(fileURL: URL = ThumbnailLookStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    static var defaultFileURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return applicationSupport
            .appendingPathComponent("ThumbnailMaker", isDirectory: true)
            .appendingPathComponent("Looks", isDirectory: true)
            .appendingPathComponent("looks.json")
    }

    func save(_ library: ThumbnailLookLibrary) throws {
        var library = library
        library.updatedAt = Date()

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try JSONEncoder.lookEncoder
            .encode(library)
            .write(to: fileURL, options: [.atomic])
    }

    func load() throws -> ThumbnailLookLibrary? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.lookDecoder.decode(ThumbnailLookLibrary.self, from: data)
    }

    func delete() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: fileURL)
    }
}

/// Owns the look library for the adjustments panel: loads it once, applies
/// edits, and saves. A failed save rolls the edit back and reports why, so
/// the on-screen list always matches what is on disk.
@MainActor
final class ThumbnailLookLibraryController: ObservableObject {
    @Published private(set) var library: ThumbnailLookLibrary
    @Published var errorMessage: String?

    private let store: ThumbnailLookStore?

    /// `store == nil` keeps looks in memory only (UI tests / previews).
    init(store: ThumbnailLookStore? = ThumbnailLookLibraryController.defaultStore()) {
        self.store = store
        var loaded = ThumbnailLookLibrary()
        if let store {
            do {
                loaded = try store.load() ?? ThumbnailLookLibrary()
            } catch {
                errorMessage = "Could not load saved looks: \(error.localizedDescription)"
            }
        }
        library = loaded
    }

    nonisolated static func defaultStore() -> ThumbnailLookStore? {
        ProcessInfo.processInfo.arguments.contains("-DisableDraftPersistence") ? nil : ThumbnailLookStore()
    }

    var allLooks: [ThumbnailLook] { library.allLooks }

    @discardableResult
    func saveLook(named name: String, adjustments: ThumbnailImageAdjustments) -> ThumbnailLook? {
        var next = library
        do {
            let look = try next.upsert(name: name, adjustments: adjustments)
            try commit(next)
            return look
        } catch {
            errorMessage = "Could not save the look: \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    func deleteLook(id: String) -> Bool {
        var next = library
        do {
            try next.remove(id: id)
            try commit(next)
            return true
        } catch {
            errorMessage = "Could not delete the look: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func renameLook(id: String, to name: String) -> Bool {
        var next = library
        do {
            try next.rename(id: id, to: name)
            try commit(next)
            return true
        } catch {
            errorMessage = "Could not rename the look: \(error.localizedDescription)"
            return false
        }
    }

    private func commit(_ next: ThumbnailLookLibrary) throws {
        try store?.save(next)
        library = next
    }
}

private extension JSONEncoder {
    static var lookEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var lookDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
