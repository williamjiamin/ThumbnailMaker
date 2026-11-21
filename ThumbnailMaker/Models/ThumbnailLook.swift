//
//  ThumbnailLook.swift
//  ThumbnailMaker
//
//  FEATURE-14: named, reusable adjustment recipes. Built-in looks ship with
//  the app and are never persisted; user looks live in `ThumbnailLookLibrary`
//  and are saved by `ThumbnailLookStore`.
//

import Foundation

struct ThumbnailLook: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var adjustments: ThumbnailImageAdjustments
    var isBuiltIn: Bool
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        adjustments: ThumbnailImageAdjustments,
        isBuiltIn: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.adjustments = adjustments
        self.isBuiltIn = isBuiltIn
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, adjustments, isBuiltIn, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        adjustments = (try container.decodeIfPresent(ThumbnailImageAdjustments.self, forKey: .adjustments) ?? .neutral)
            .clamped()
        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
    }
}

enum ThumbnailLookError: LocalizedError, Equatable {
    case invalidName
    case reservedName(String)
    case builtInLook

    var errorDescription: String? {
        switch self {
        case .invalidName:
            "Enter a name for the look."
        case .reservedName(let name):
            "\u{201C}\(name)\u{201D} is a built-in look. Choose another name."
        case .builtInLook:
            "Built-in looks can't be changed."
        }
    }
}

struct ThumbnailLookLibrary: Codable, Equatable {
    static let currentVersion = 1
    static let maxUserLooks = 24
    static let nameCharacterLimit = 40

    var version: Int
    /// User looks only; built-ins are never persisted.
    private(set) var looks: [ThumbnailLook]
    var updatedAt: Date

    init(looks: [ThumbnailLook] = [], updatedAt: Date = Date()) {
        self.version = Self.currentVersion
        self.looks = looks.filter { !$0.isBuiltIn && !Self.isBuiltInID($0.id) }
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case version, looks, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        let decodedLooks = try container.decodeIfPresent([ThumbnailLook].self, forKey: .looks) ?? []
        version = max(decodedVersion, Self.currentVersion)
        looks = decodedLooks.filter { !$0.isBuiltIn && !Self.isBuiltInID($0.id) }
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(looks, forKey: .looks)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    // MARK: Built-ins

    static let builtIns: [ThumbnailLook] = [
        builtIn("look-punchy", "Punchy", ThumbnailImageAdjustments(brightness: 0.04, contrast: 1.22, saturation: 1.18, vignette: 0.18)),
        builtIn("look-soft", "Soft", ThumbnailImageAdjustments(brightness: 0.06, contrast: 0.92, saturation: 0.94, blur: 0.006)),
        builtIn("look-mono", "Mono", ThumbnailImageAdjustments(contrast: 1.10, saturation: 0, vignette: 0.22)),
        builtIn("look-moody", "Moody", ThumbnailImageAdjustments(brightness: -0.08, contrast: 1.15, saturation: 0.85, vignette: 0.45)),
        builtIn("look-clean", "Clean", ThumbnailImageAdjustments(brightness: 0.02, contrast: 1.05, saturation: 1.05))
    ]

    private static func builtIn(_ id: String, _ name: String, _ adjustments: ThumbnailImageAdjustments) -> ThumbnailLook {
        ThumbnailLook(id: id, name: name, adjustments: adjustments, isBuiltIn: true, updatedAt: Date(timeIntervalSince1970: 0))
    }

    static func isBuiltInID(_ id: String) -> Bool {
        builtIns.contains { $0.id == id }
    }

    var allLooks: [ThumbnailLook] { Self.builtIns + looks }

    func look(id: String) -> ThumbnailLook? {
        allLooks.first { $0.id == id }
    }

    // MARK: Editing

    static func normalizedName(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(nameCharacterLimit))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Adds a user look, or replaces the user look with the same name
    /// (case-insensitive). The oldest look is dropped past `maxUserLooks`.
    @discardableResult
    mutating func upsert(
        name rawName: String,
        adjustments: ThumbnailImageAdjustments,
        now: Date = Date()
    ) throws -> ThumbnailLook {
        let name = Self.normalizedName(rawName)
        guard !name.isEmpty else { throw ThumbnailLookError.invalidName }
        if let builtIn = Self.builtIns.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            throw ThumbnailLookError.reservedName(builtIn.name)
        }

        let recipe = adjustments.clamped()
        let look: ThumbnailLook
        if let index = looks.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            looks[index].name = name
            looks[index].adjustments = recipe
            looks[index].updatedAt = now
            look = looks[index]
        } else {
            look = ThumbnailLook(name: name, adjustments: recipe, updatedAt: now)
            looks.append(look)
            while looks.count > Self.maxUserLooks,
                  let oldest = looks.enumerated().min(by: { $0.element.updatedAt < $1.element.updatedAt }) {
                looks.remove(at: oldest.offset)
            }
        }
        updatedAt = now
        return look
    }

    mutating func remove(id: String) throws {
        guard !Self.isBuiltInID(id) else { throw ThumbnailLookError.builtInLook }
        looks.removeAll { $0.id == id }
    }

    mutating func rename(id: String, to rawName: String, now: Date = Date()) throws {
        guard !Self.isBuiltInID(id) else { throw ThumbnailLookError.builtInLook }
        let name = Self.normalizedName(rawName)
        guard !name.isEmpty else { throw ThumbnailLookError.invalidName }
        if let builtIn = Self.builtIns.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            throw ThumbnailLookError.reservedName(builtIn.name)
        }
        guard looks.contains(where: { $0.id == id }) else { return }
        // Renaming onto another user look's name replaces that look.
        looks.removeAll { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }
        if let renamed = looks.firstIndex(where: { $0.id == id }) {
            looks[renamed].name = name
            looks[renamed].updatedAt = now
        }
        updatedAt = now
    }
}
