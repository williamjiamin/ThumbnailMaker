//
//  ThumbnailExportRecipe.swift
//  ThumbnailMaker
//
//  FEATURE-10: a saved, reusable batch-export recipe (which variants, which
//  sizes, one format/quality, an optional file-size budget and an overwrite
//  policy). Recipes are app-level, like brand kits, and never live inside a
//  ThumbnailDocument, so documents, templates and .thumbproj packages are
//  unaffected.
//
//  Every field except `id` and `name` decodes with a default, so recipes
//  written by older or newer builds still open. A recipe from a newer schema
//  version opens read-only.
//

import Foundation

struct ThumbnailExportRecipeSize: Codable, Equatable, Hashable, Identifiable {
    var presetID: String?
    var width: Int
    var height: Int

    static let allowedDimensionRange = 320...4096

    init(presetID: String? = nil, width: Int, height: Int) {
        self.presetID = presetID
        self.width = width
        self.height = height
    }

    init(preset: ThumbnailExportPreset) {
        self.init(presetID: preset.id, width: preset.size.width, height: preset.size.height)
    }

    var id: String { "\(width)x\(height)" }
    var token: String { "\(width)x\(height)" }
    var exportSize: ThumbnailExportSize { ThumbnailExportSize(width: width, height: height) }

    var aspectValue: Double {
        guard height > 0 else { return 0 }
        return Double(width) / Double(height)
    }

    var isWithinAllowedRange: Bool {
        Self.allowedDimensionRange.contains(width) && Self.allowedDimensionRange.contains(height)
    }

    var displayName: String {
        if let presetID, let preset = ThumbnailExportPreset.all.first(where: { $0.id == presetID }),
           preset.size == exportSize {
            return "\(preset.name) · \(width) x \(height)"
        }
        return "Custom · \(width) x \(height)"
    }
}

struct ThumbnailExportVariantSelection: Codable, Equatable, Hashable {
    enum Mode: String, Codable {
        case all
        case preferredOnly
        case slots
    }

    var mode: Mode
    /// Only read when `mode == .slots`.
    var slots: [ThumbnailVariantSlot]

    init(mode: Mode, slots: [ThumbnailVariantSlot] = []) {
        self.mode = mode
        self.slots = mode == .slots ? Array(Set(slots)).sorted() : []
    }

    static let all = ThumbnailExportVariantSelection(mode: .all)
    static let preferredOnly = ThumbnailExportVariantSelection(mode: .preferredOnly)
    static func only(_ slots: [ThumbnailVariantSlot]) -> ThumbnailExportVariantSelection {
        ThumbnailExportVariantSelection(mode: .slots, slots: slots)
    }

    private enum CodingKeys: String, CodingKey { case mode, slots }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawMode = try container.decodeIfPresent(String.self, forKey: .mode) ?? Mode.all.rawValue
        let slots = (try? container.decodeIfPresent([ThumbnailVariantSlot].self, forKey: .slots)) ?? []
        self.init(mode: Mode(rawValue: rawMode) ?? .all, slots: slots)
    }

    /// The slots of `set` this selection picks, in A-B-C order. `preferredOnly`
    /// with no preferred variant picks nothing (the plan explains why).
    func selectedSlots(in set: ThumbnailVariantSet) -> [ThumbnailVariantSlot] {
        let available = set.variants.map(\.slot).sorted()
        switch mode {
        case .all:
            return available
        case .preferredOnly:
            guard let preferred = set.preferredSlot, available.contains(preferred) else { return [] }
            return [preferred]
        case .slots:
            return available.filter { slots.contains($0) }
        }
    }
}

struct ThumbnailExportFileSizeBudget: Codable, Equatable, Hashable {
    static let minimumQualityFloor = 0.4
    static let defaultQualityFloor = 0.6

    var maxBytes: Int
    var qualityFloor: Double

    init(maxBytes: Int, qualityFloor: Double = ThumbnailExportFileSizeBudget.defaultQualityFloor) {
        self.maxBytes = max(1, maxBytes)
        self.qualityFloor = qualityFloor
    }

    /// The lowest quality the fitter may use: never below 0.4, never above
    /// the quality the user asked for.
    func effectiveFloor(requestedQuality: Double) -> Double {
        min(max(qualityFloor, Self.minimumQualityFloor), requestedQuality)
    }

    private enum CodingKeys: String, CodingKey { case maxBytes, qualityFloor }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            maxBytes: try container.decodeIfPresent(Int.self, forKey: .maxBytes) ?? 2_000_000,
            qualityFloor: try container.decodeIfPresent(Double.self, forKey: .qualityFloor) ?? Self.defaultQualityFloor
        )
    }
}

enum ThumbnailExportOverwritePolicy: String, Codable, CaseIterable, Identifiable {
    /// Adds `-2`, `-3`, ... instead of touching an existing file.
    case keepBoth
    case replace
    case skip

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .keepBoth: return "Keep Both"
        case .replace: return "Replace"
        case .skip: return "Skip"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ThumbnailExportOverwritePolicy(rawValue: raw) ?? .keepBoth
    }
}

struct ThumbnailExportRecipe: Codable, Equatable, Identifiable {
    static let currentVersion = 1
    static let qualityRange: ClosedRange<Double> = 0.4...1.0
    static let maxNameLength = 40

    var id: UUID
    var version: Int
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var variantSelection: ThumbnailExportVariantSelection
    var sizes: [ThumbnailExportRecipeSize]
    var formatRawValue: String
    var compressionQuality: Double
    var fileSizeBudget: ThumbnailExportFileSizeBudget?
    var overwritePolicy: ThumbnailExportOverwritePolicy
    var namingIncludesSizeToken: Bool

    init(
        id: UUID = UUID(),
        version: Int = ThumbnailExportRecipe.currentVersion,
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        variantSelection: ThumbnailExportVariantSelection = .all,
        sizes: [ThumbnailExportRecipeSize],
        format: ThumbnailExportFormat = .jpeg,
        compressionQuality: Double = 0.92,
        fileSizeBudget: ThumbnailExportFileSizeBudget? = nil,
        overwritePolicy: ThumbnailExportOverwritePolicy = .keepBoth,
        namingIncludesSizeToken: Bool = true
    ) {
        self.id = id
        self.version = version
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.variantSelection = variantSelection
        self.sizes = sizes
        self.formatRawValue = format.rawValue
        self.compressionQuality = Self.clampedQuality(compressionQuality)
        self.fileSizeBudget = fileSizeBudget
        self.overwritePolicy = overwritePolicy
        self.namingIncludesSizeToken = namingIncludesSizeToken
    }

    private enum CodingKeys: String, CodingKey {
        case id, version, name, createdAt, updatedAt, variantSelection, sizes
        case formatRawValue, compressionQuality, fileSizeBudget, overwritePolicy, namingIncludesSizeToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        let now = Date()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        variantSelection = (try? container.decodeIfPresent(ThumbnailExportVariantSelection.self, forKey: .variantSelection)) ?? .all
        sizes = (try? container.decodeIfPresent([ThumbnailExportRecipeSize].self, forKey: .sizes))
            ?? [ThumbnailExportRecipeSize(preset: .youTubeThumbnail)]
        formatRawValue = try container.decodeIfPresent(String.self, forKey: .formatRawValue) ?? ThumbnailExportFormat.jpeg.rawValue
        compressionQuality = Self.clampedQuality(
            try container.decodeIfPresent(Double.self, forKey: .compressionQuality) ?? 0.92
        )
        fileSizeBudget = try? container.decodeIfPresent(ThumbnailExportFileSizeBudget.self, forKey: .fileSizeBudget)
        overwritePolicy = (try? container.decodeIfPresent(ThumbnailExportOverwritePolicy.self, forKey: .overwritePolicy)) ?? .keepBoth
        namingIncludesSizeToken = try container.decodeIfPresent(Bool.self, forKey: .namingIncludesSizeToken) ?? true
    }

    // MARK: Derived

    /// nil when the stored format is unknown to this build (never silently swapped).
    var format: ThumbnailExportFormat? { ThumbnailExportFormat(rawValue: formatRawValue) }

    var isFromNewerVersion: Bool { version > Self.currentVersion }
    var isBuiltIn: Bool { id == Self.currentOptionsID || Self.builtIns.contains { $0.id == id } }
    var isReadOnly: Bool { isBuiltIn || isFromNewerVersion }

    static func clampedQuality(_ value: Double) -> Double {
        guard value.isFinite else { return 0.92 }
        return min(max(value, qualityRange.lowerBound), qualityRange.upperBound)
    }

    static func cleanedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untitled Recipe" }
        return String(trimmed.prefix(maxNameLength))
    }

    // MARK: Built-ins

    static let youTubeABCID = UUID(uuidString: "0F1E0A10-0000-4000-8000-000000000001")!
    /// Stable id of the transient "Current Export Settings" recipe.
    static let currentOptionsID = UUID(uuidString: "0F1E0A10-0000-4000-8000-000000000002")!

    /// Three 16:9 sizes as JPEG, fitted under YouTube's 2 MB mobile limit
    /// (the same limit `ThumbnailExportPreset.uploadLimits` warns about).
    static let youTubeABC = ThumbnailExportRecipe(
        id: youTubeABCID,
        name: "YouTube A/B/C",
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0),
        variantSelection: .all,
        sizes: [
            ThumbnailExportRecipeSize(presetID: ThumbnailExportPreset.youTubeThumbnail.id, width: 3840, height: 2160),
            ThumbnailExportRecipeSize(width: 1920, height: 1080),
            ThumbnailExportRecipeSize(width: 1280, height: 720)
        ],
        format: .jpeg,
        compressionQuality: 0.92,
        fileSizeBudget: ThumbnailExportFileSizeBudget(maxBytes: 2_000_000, qualityFloor: 0.6),
        overwritePolicy: .keepBoth,
        namingIncludesSizeToken: true
    )

    static let builtIns: [ThumbnailExportRecipe] = [youTubeABC]

    /// Today's single export expressed as a one-size recipe (all variants).
    static func fromCurrentOptions(_ options: ThumbnailExportOptions, now: Date = Date()) -> ThumbnailExportRecipe {
        let size = options.outputSize
        return ThumbnailExportRecipe(
            id: currentOptionsID,
            name: "Current Export Settings",
            createdAt: now,
            updatedAt: now,
            variantSelection: .all,
            sizes: [
                ThumbnailExportRecipeSize(
                    presetID: options.usesCustomSize ? nil : options.preset.id,
                    width: size.width,
                    height: size.height
                )
            ],
            format: options.format,
            compressionQuality: options.compressionQuality,
            fileSizeBudget: nil,
            overwritePolicy: .keepBoth,
            namingIncludesSizeToken: true
        )
    }
}
