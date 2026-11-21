//
//  ThumbnailVariantSlot.swift
//  ThumbnailMaker
//
//  FEATURE-02: named A/B/C variants of one design.
//

import Foundation

/// One of the three variant slots of a design. YouTube Test & Compare accepts
/// exactly three thumbnails, so the cap is expressed in the type itself.
///
/// Slots are never re-lettered when a variant is removed: a set may legitimately
/// hold {A, C}. Re-lettering would silently rename a design the user has already
/// reasoned about (and possibly exported under that name).
enum ThumbnailVariantSlot: String, Codable, CaseIterable, Identifiable, Comparable {
    case a
    case b
    case c

    var id: String { rawValue }
    var displayLetter: String { rawValue.uppercased() }
    var defaultName: String { "Variant \(displayLetter)" }
    var exportToken: String { "variant-\(rawValue)" }

    var sortIndex: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.sortIndex < rhs.sortIndex
    }
}
