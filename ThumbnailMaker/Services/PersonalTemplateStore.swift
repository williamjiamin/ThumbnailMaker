//
//  PersonalTemplateStore.swift
//  ThumbnailMaker
//
//  FEATURE-05: persists PersonalTemplateLibrary as one atomic JSON file,
//  mirroring BrandKitStore. Size caps are checked before any write, so a
//  rejected save never touches the good file on disk.
//

import Foundation

final class PersonalTemplateStore {
    static let maximumTemplateBytes = 2 * 1024 * 1024
    static let maximumLibraryBytes = 25 * 1024 * 1024

    let fileURL: URL

    init(fileURL: URL = PersonalTemplateStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    static var defaultFileURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return applicationSupport
            .appendingPathComponent("ThumbnailMaker", isDirectory: true)
            .appendingPathComponent("Templates", isDirectory: true)
            .appendingPathComponent("personal-templates.json")
    }

    /// Missing file -> empty library. Expired trash is swept and re-saved.
    func load(now: Date = Date()) throws -> PersonalTemplateLibrary {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return PersonalTemplateLibrary()
        }
        let data = try Data(contentsOf: fileURL)
        var library = try Self.decoder.decode(PersonalTemplateLibrary.self, from: data)
        if !library.purgeExpired(now: now).isEmpty {
            try? save(library)
        }
        return library
    }

    /// Never throws. An unreadable library is moved aside (never deleted) and
    /// an empty library is returned together with where the old file went.
    func loadRecoveringFromCorruption(now: Date = Date()) -> (library: PersonalTemplateLibrary, quarantined: URL?) {
        do {
            return (try load(now: now), nil)
        } catch {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return (PersonalTemplateLibrary(), nil)
            }
            let stamp = ISO8601DateFormatter().string(from: now)
                .replacingOccurrences(of: ":", with: "-")
            let quarantineURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent("personal-templates-corrupt-\(stamp).json")
            do {
                if FileManager.default.fileExists(atPath: quarantineURL.path) {
                    try FileManager.default.removeItem(at: quarantineURL)
                }
                try FileManager.default.moveItem(at: fileURL, to: quarantineURL)
                return (PersonalTemplateLibrary(), quarantineURL)
            } catch {
                return (PersonalTemplateLibrary(), nil)
            }
        }
    }

    func save(_ library: PersonalTemplateLibrary) throws {
        try Self.validateSize(of: library)
        let data = try Self.encoder.encode(library)
        guard data.count <= Self.maximumLibraryBytes else {
            throw PersonalTemplateLibrary.LibraryError.payloadTooLarge(
                bytes: data.count,
                limit: Self.maximumLibraryBytes
            )
        }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic])
    }

    func delete() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    static func validateSize(of template: ThumbnailTemplate) throws {
        // Base64 inflates media by ~4/3 inside JSON; the cap is on encoded size.
        let encodedEstimate = (template.retainedMediaByteCount * 4) / 3
        guard encodedEstimate <= maximumTemplateBytes else {
            throw PersonalTemplateLibrary.LibraryError.payloadTooLarge(
                bytes: encodedEstimate,
                limit: maximumTemplateBytes
            )
        }
    }

    static func validateSize(of library: PersonalTemplateLibrary) throws {
        for template in library.templates {
            try validateSize(of: template)
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
