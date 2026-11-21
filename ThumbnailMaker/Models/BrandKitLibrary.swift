//
//  BrandKitLibrary.swift
//  ThumbnailMaker
//
//  FEATURE-08: many named brand kits, one active. Pure value type; every
//  mutator keeps `activeKitID` pointing at an existing kit (or nil when the
//  library is empty). Persisted by BrandKitStore.
//
//  Library management is NOT part of document undo: deleting a kit is undone
//  with `restore(_:at:)` (the UI offers an Undo toast), never with Cmd-Z.
//

import Foundation

struct BrandKitLibrary: Codable, Equatable {
    static let currentVersion = 1
    /// Kits can carry logo data; bound the single JSON file.
    static let maximumKitCount = 12

    var version = currentVersion
    var kits: [BrandKit]
    var activeKitID: String?
    var updatedAt: Date

    static let empty = BrandKitLibrary(kits: [], activeKitID: nil, updatedAt: Date(timeIntervalSince1970: 0))

    init(
        version: Int = BrandKitLibrary.currentVersion,
        kits: [BrandKit],
        activeKitID: String?,
        updatedAt: Date = Date()
    ) {
        self.version = version
        self.kits = kits
        self.activeKitID = activeKitID
        self.updatedAt = updatedAt
        normalizeActiveKit()
    }

    private enum CodingKeys: String, CodingKey {
        case version, kits, activeKitID, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        version = max(decodedVersion, Self.currentVersion)
        // Non-optional on purpose: a legacy single-kit file must NOT decode as
        // a library, which is how the store detects it for migration.
        kits = try container.decode([BrandKit].self, forKey: .kits)
        activeKitID = try container.decodeIfPresent(String.self, forKey: .activeKitID)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
        normalizeActiveKit()
    }

    // MARK: Queries

    var activeKit: BrandKit? {
        guard let activeKitID else { return nil }
        return kit(id: activeKitID)
    }

    var isFull: Bool { kits.count >= Self.maximumKitCount }

    func kit(id: String) -> BrandKit? {
        kits.first { $0.id == id }
    }

    /// Searches every kit so a document's provenance id resolves regardless
    /// of which kit owns the style.
    func style(id: String) -> ThumbnailLayerStyle? {
        for kit in kits {
            if let style = kit.styles.first(where: { $0.id == id }) {
                return style
            }
        }
        return nil
    }

    // MARK: Kit mutators

    /// Replaces by id, else appends. Returns false (unchanged) when appending
    /// would exceed `maximumKitCount`.
    @discardableResult
    mutating func upsert(_ kit: BrandKit, activate: Bool = true) -> Bool {
        if let index = kits.firstIndex(where: { $0.id == kit.id }) {
            kits[index] = kit
        } else {
            guard !isFull else { return false }
            kits.append(kit)
        }
        if activate || activeKitID == nil {
            activeKitID = kit.id
        }
        touch()
        return true
    }

    /// Deep copy (styles get fresh ids so later edits never alias), unique
    /// name, appended and activated. Nil when the source is missing or full.
    @discardableResult
    mutating func duplicate(id: String, newID: String = UUID().uuidString) -> BrandKit? {
        guard let source = kit(id: id), !isFull else { return nil }
        var copy = source
        copy.id = newID
        copy.name = Self.uniqueName(basedOn: "\(source.name) Copy", existing: kits.map(\.name))
        copy.palette = source.palette.enumerated().map { index, color in
            BrandColor(id: "\(newID)-color-\(index)", name: color.name, color: color.color)
        }
        copy.styles = source.styles.map { style in
            var style = style
            style.id = UUID().uuidString
            return style
        }
        copy.updatedAt = Date()
        kits.append(copy)
        activeKitID = copy.id
        touch()
        return copy
    }

    /// Trims; empty keeps the current name; clashes get a numeric suffix.
    mutating func rename(id: String, to name: String) {
        guard let index = kits.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != kits[index].name else { return }
        let others = kits.enumerated().filter { $0.offset != index }.map(\.element.name)
        kits[index].name = Self.uniqueName(basedOn: trimmed, existing: others)
        kits[index].updatedAt = Date()
        touch()
    }

    /// Returns what was removed so the caller can offer an Undo. When the
    /// active kit is removed the kit now at that index (else the last) becomes
    /// active.
    @discardableResult
    mutating func remove(id: String) -> (kit: BrandKit, index: Int)? {
        guard let index = kits.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = kits.remove(at: index)
        if activeKitID == id {
            if kits.indices.contains(index) {
                activeKitID = kits[index].id
            } else {
                activeKitID = kits.last?.id
            }
        }
        touch()
        return (removed, index)
    }

    /// Inverse of `remove`. Ignored when a kit with that id already exists or
    /// the library is full.
    mutating func restore(_ kit: BrandKit, at index: Int, activate: Bool = true) {
        guard self.kit(id: kit.id) == nil, !isFull else { return }
        kits.insert(kit, at: Swift.min(Swift.max(0, index), kits.count))
        if activate || activeKitID == nil {
            activeKitID = kit.id
        }
        touch()
    }

    /// Ignores ids that are not in the library.
    mutating func setActive(id: String) {
        guard kit(id: id) != nil, activeKitID != id else { return }
        activeKitID = id
        touch()
    }

    // MARK: Style mutators

    /// Replaces by id or appends. Returns false when the kit is missing.
    @discardableResult
    mutating func upsertStyle(_ style: ThumbnailLayerStyle, inKit kitID: String) -> Bool {
        guard let kitIndex = kits.firstIndex(where: { $0.id == kitID }) else { return false }
        var style = style
        let others = kits[kitIndex].styles.filter { $0.id != style.id }.map(\.name)
        style.name = Self.uniqueName(basedOn: style.name, existing: others)
        if let styleIndex = kits[kitIndex].styles.firstIndex(where: { $0.id == style.id }) {
            kits[kitIndex].styles[styleIndex] = style
        } else {
            kits[kitIndex].styles.append(style)
        }
        kits[kitIndex].updatedAt = Date()
        touch()
        return true
    }

    mutating func removeStyle(id: String, fromKit kitID: String) {
        guard let kitIndex = kits.firstIndex(where: { $0.id == kitID }) else { return }
        let before = kits[kitIndex].styles.count
        kits[kitIndex].styles.removeAll { $0.id == id }
        guard kits[kitIndex].styles.count != before else { return }
        kits[kitIndex].updatedAt = Date()
        touch()
    }

    // MARK: Naming

    /// "Brand" -> "Brand" if free, else "Brand 2", "Brand 3", ...
    /// ("Brand Copy" -> "Brand Copy 2" ...), mirroring layer copy naming.
    static func uniqueName(basedOn name: String, existing: [String]) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = Set(existing)
        guard taken.contains(base) else { return base }
        var counter = 2
        while taken.contains("\(base) \(counter)") {
            counter += 1
        }
        return "\(base) \(counter)"
    }

    // MARK: Private

    private mutating func touch() {
        updatedAt = Date()
    }

    private mutating func normalizeActiveKit() {
        if let activeKitID, kit(id: activeKitID) != nil { return }
        activeKitID = kits.first?.id
    }
}
