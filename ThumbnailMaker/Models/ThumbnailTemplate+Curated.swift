//
//  ThumbnailTemplate+Curated.swift
//  ThumbnailMaker
//
//  TEMPLATES: the curated built-in template library. Every entry is a
//  LAYOUT ONLY: gradient or solid background, one styled headline, and at
//  most a few arrows / badges / callouts built from the FEATURE-12 shape
//  model. No artwork or photos ship with a template; the creator's own photo
//  fills the background image slot (FEATURE-05 `builtInDefaults`) and each
//  layout keeps a focal region clear for their subject.
//
//  Design rules every entry follows (and ThumbnailTemplateLayoutAudit plus
//  the unit tests enforce):
//  - one focal subject region, kept free of text;
//  - two or three colour families;
//  - a headline of three to five words, large enough for the readiness
//    check's small mobile preview;
//  - all text inside the export preset's safe zone, never clipped.
//
//  Layer ids are `builtin-<template id>-<role>`, so they are stable and
//  unique across the library. When a creator switches from one built-in
//  layout to another, the previous layout's decorations are recognised by
//  that prefix and removed instead of piling up (see `makeDocument`).
//

import CoreGraphics
import Foundation
import SwiftUI

/// Library metadata that does not belong in the persisted template JSON.
struct ThumbnailCuratedTemplate: Equatable {
    let template: ThumbnailTemplate
    /// Normalized canvas rect (0...1) kept clear for the creator's subject.
    /// nil for layouts where the whole photo is the subject (split
    /// comparisons, centred title cards).
    let focalRegion: CGRect?
    /// One line describing the layout, shown as the gallery card's hint.
    let layoutNote: String
}

extension ThumbnailTemplate {
    /// 16:9 headline size: the smallest size the readiness check accepts in
    /// its 96 px mobile preview (12 pt), which is also ~15 px at 120 px wide.
    static let landscapeHeadlineSize = 0.225

    /// Prefix of every content-layer id a built-in layout ships.
    static let builtInLayerIDPrefix = "builtin-"

    static func builtInLayerID(templateID: String, role: String) -> String {
        "\(builtInLayerIDPrefix)\(templateID)-\(role)"
    }

    static func isBuiltInLayoutLayerID(_ id: String) -> Bool {
        id.hasPrefix(builtInLayerIDPrefix)
    }

    /// The curated library in gallery order.
    static let curatedLibrary: [ThumbnailTemplate] = curatedCatalog.map(\.template)

    static func curatedEntry(id: String) -> ThumbnailCuratedTemplate? {
        curatedCatalog.first { $0.template.id == id }
    }
}

// MARK: - Catalog

extension ThumbnailTemplate {
    static let curatedCatalog: [ThumbnailCuratedTemplate] = [
        // MARK: Gaming
        curated(
            id: "curated-gaming-final-victory",
            name: "Final Victory",
            category: .gaming,
            background: Palette.nightPurple,
            fill: .linearGradient([Palette.royalPurple, Palette.nightPurple], angleDegrees: 135),
            headline: "I FINALLY\nWON",
            headlineColor: Palette.victoryYellow,
            font: .oswald,
            anchor: .leading(x: 0.08, y: 0.46),
            maxWidth: 0.46,
            style: .outlineAndShadow,
            decorations: [
                .badge(role: "badge", text: "RANKED #1", fill: Palette.victoryYellow, labelColor: Palette.nightPurple,
                       x: 0.72, y: 0.13, width: 0.24)
            ],
            focalRegion: CGRect(x: 0.58, y: 0.22, width: 0.28, height: 0.64),
            note: "Headline left, winner on the right."
        ),
        curated(
            id: "curated-gaming-boss-fight",
            name: "Boss Fight",
            category: .gaming,
            background: Palette.bloodBlack,
            fill: .linearGradient([Palette.bossRed, Palette.bloodBlack], angleDegrees: 90),
            headline: "HARDEST\nBOSS EVER",
            headlineColor: Palette.white,
            font: .oswald,
            anchor: .trailing(x: 0.84, y: 0.46),
            maxWidth: 0.52,
            style: .glow(Palette.bossRed),
            decorations: [],
            focalRegion: CGRect(x: 0.06, y: 0.08, width: 0.24, height: 0.78),
            note: "Boss on the left, glowing headline right."
        ),

        // MARK: Vlog
        curated(
            id: "curated-vlog-golden-hour",
            name: "Golden Hour",
            category: .vlog,
            background: Palette.burntOrange,
            fill: .linearGradient([Palette.burntOrange, Palette.duskPlum], angleDegrees: 45),
            headline: "MY FIRST\nSOLO TRIP",
            headlineColor: Palette.white,
            font: .oswald,
            anchor: .leading(x: 0.07, y: 0.46),
            maxWidth: 0.5,
            style: .softShadow,
            decorations: [
                .badge(role: "badge", text: "DAY 1", fill: Palette.white, labelColor: Palette.duskPlum,
                       x: 0.73, y: 0.13, width: 0.15)
            ],
            focalRegion: CGRect(x: 0.6, y: 0.22, width: 0.26, height: 0.64),
            note: "Warm sunset wash, story title left."
        ),
        curated(
            id: "curated-vlog-week-in-life",
            name: "Week in My Life",
            category: .vlog,
            background: Palette.cream,
            headline: "A WEEK IN\nMY LIFE",
            headlineColor: Palette.espresso,
            font: .oswald,
            anchor: .leading(x: 0.07, y: 0.46),
            maxWidth: 0.5,
            style: .plain,
            decorations: [
                .badge(role: "badge", text: "NEW VLOG", fill: Palette.terracotta, labelColor: Palette.white,
                       x: 0.73, y: 0.13, width: 0.23)
            ],
            focalRegion: CGRect(x: 0.6, y: 0.22, width: 0.26, height: 0.64),
            note: "Clean cream card with a terracotta tag."
        ),

        // MARK: Tutorial
        curated(
            id: "curated-tutorial-step-by-step",
            name: "Step by Step",
            category: .tutorial,
            background: Palette.navy,
            headline: "EDIT IN\n5 STEPS",
            headlineColor: Palette.white,
            font: .oswald,
            anchor: .leading(x: 0.07, y: 0.46),
            maxWidth: 0.42,
            style: .plain,
            decorations: [
                .badge(role: "badge", text: "STEP 1", fill: Palette.signalYellow, labelColor: Palette.navy,
                       x: 0.73, y: 0.13, width: 0.17),
                .arrow(role: "arrow", fill: Palette.signalYellow, x: 0.53, y: 0.6, width: 0.1, height: 0.1,
                       pointsLeft: false)
            ],
            focalRegion: CGRect(x: 0.6, y: 0.22, width: 0.26, height: 0.64),
            note: "Numbered how-to with an arrow to the result."
        ),
        curated(
            id: "curated-tutorial-beginner-guide",
            name: "Beginner Guide",
            category: .tutorial,
            background: Palette.paper,
            headline: "LEARN IT\nIN 10 MIN",
            headlineColor: Palette.ink,
            font: .oswald,
            anchor: .trailing(x: 0.86, y: 0.46),
            maxWidth: 0.48,
            style: .plain,
            decorations: [
                .badge(role: "badge", text: "BEGINNER", fill: Palette.cobalt, labelColor: Palette.white,
                       x: 0.2, y: 0.13, width: 0.22)
            ],
            focalRegion: CGRect(x: 0.06, y: 0.22, width: 0.28, height: 0.64),
            note: "Bright, friendly guide with the lesson on the left."
        ),
        curated(
            id: "curated-tutorial-fix-mistake",
            name: "Fix the Mistake",
            category: .tutorial,
            background: Palette.charcoal,
            headline: "DON'T DO\nTHIS",
            headlineColor: Palette.white,
            font: .oswald,
            anchor: .leading(x: 0.07, y: 0.46),
            maxWidth: 0.5,
            style: .boldOutline,
            decorations: [
                .callout(role: "callout", text: "WRONG", fill: Palette.alarmRed, labelColor: Palette.white,
                         x: 0.74, y: 0.15, width: 0.2, height: 0.18, tail: .bottom)
            ],
            focalRegion: CGRect(x: 0.6, y: 0.28, width: 0.26, height: 0.58),
            note: "Warning callout over the mistake you show."
        ),

        // MARK: Reaction
        curated(
            id: "curated-reaction-shocked",
            name: "Shocked",
            category: .reaction,
            background: Palette.amber,
            fill: .linearGradient([Palette.lemon, Palette.amber], angleDegrees: 90),
            headline: "I CAN'T\nBELIEVE IT",
            headlineColor: Palette.ink,
            font: .oswald,
            anchor: .leading(x: 0.07, y: 0.46),
            maxWidth: 0.5,
            style: .outline(Palette.white),
            decorations: [
                .ring(role: "ring", stroke: Palette.alarmRed, x: 0.74, y: 0.47, width: 0.22, height: 0.56)
            ],
            focalRegion: CGRect(x: 0.6, y: 0.08, width: 0.26, height: 0.78),
            note: "Loud yellow with a circle around the reaction."
        ),
        curated(
            id: "curated-reaction-wait-for-it",
            name: "Wait For It",
            category: .reaction,
            background: Palette.midnight,
            fill: .linearGradient([Palette.deepBlue, Palette.midnight], angleDegrees: 135),
            headline: "WAIT FOR\nTHE END",
            headlineColor: Palette.white,
            font: .oswald,
            anchor: .leading(x: 0.08, y: 0.46),
            maxWidth: 0.48,
            style: .outlineAndShadow,
            decorations: [
                .callout(role: "bubble", text: "OMG", fill: Palette.white, labelColor: Palette.midnight,
                         x: 0.76, y: 0.15, width: 0.16, height: 0.18, tail: .bottomLeft)
            ],
            focalRegion: CGRect(x: 0.6, y: 0.28, width: 0.26, height: 0.58),
            note: "Speech bubble over the reaction shot."
        ),

        // MARK: Podcast
        curated(
            id: "curated-podcast-guest-episode",
            name: "Guest Episode",
            category: .podcast,
            aspectRatio: .ratio1_1,
            exportPresetID: ThumbnailExportPreset.podcastCover.id,
            background: Palette.deepTeal,
            headline: "THE GUEST\nEPISODE",
            headlineColor: Palette.butter,
            headlineSize: 0.13,
            font: .montserrat,
            anchor: .center(x: 0.5, y: 0.74),
            maxWidth: 0.84,
            style: .plain,
            decorations: [
                .badge(role: "badge", text: "EP 42", fill: Palette.butter, labelColor: Palette.deepTeal,
                       x: 0.2, y: 0.14, width: 0.2, height: 0.08)
            ],
            focalRegion: CGRect(x: 0.3, y: 0.08, width: 0.4, height: 0.46),
            note: "Square cover: guest on top, title below."
        ),
        curated(
            id: "curated-podcast-hard-truth",
            name: "Hard Truth",
            category: .podcast,
            background: Palette.plum,
            headline: "THE HARD\nTRUTH",
            headlineColor: Palette.white,
            font: .oswald,
            anchor: .leading(x: 0.07, y: 0.46),
            maxWidth: 0.5,
            style: .softShadow,
            decorations: [
                .badge(role: "badge", text: "FULL EPISODE", fill: Palette.magenta, labelColor: Palette.white,
                       x: 0.72, y: 0.13, width: 0.28)
            ],
            focalRegion: CGRect(x: 0.6, y: 0.22, width: 0.26, height: 0.64),
            note: "Clip thumbnail: quote left, speaker right."
        ),

        // MARK: Shorts (9:16)
        curated(
            id: "curated-shorts-top-hook",
            name: "Top Hook",
            category: .shortForm,
            aspectRatio: .ratio9_16,
            background: Palette.midnight,
            fill: .linearGradient([Palette.midnight, Palette.violet], angleDegrees: 90),
            headline: "WATCH\nTILL THE END",
            headlineColor: Palette.white,
            headlineSize: 0.075,
            font: .oswald,
            anchor: .center(x: 0.44, y: 0.26),
            maxWidth: 0.7,
            style: .outlineAndShadow,
            decorations: [
                .badge(role: "badge", text: "PART 1", fill: Palette.signalYellow, labelColor: Palette.midnight,
                       x: 0.44, y: 0.7, width: 0.3, height: 0.06)
            ],
            focalRegion: CGRect(x: 0.1, y: 0.4, width: 0.68, height: 0.24),
            note: "Hook above the subject, clear of the Shorts UI."
        ),
        curated(
            id: "curated-shorts-bottom-caption",
            name: "Bottom Caption",
            category: .shortForm,
            aspectRatio: .ratio9_16,
            background: Palette.peach,
            headline: "TRY THIS\nTODAY",
            headlineColor: Palette.ink,
            headlineSize: 0.08,
            font: .oswald,
            anchor: .center(x: 0.44, y: 0.6),
            maxWidth: 0.52,
            style: .panel(Palette.white.withAlpha(0.92)),
            decorations: [],
            focalRegion: CGRect(x: 0.1, y: 0.13, width: 0.68, height: 0.3),
            note: "Subject up top, caption on a white card."
        ),

        // MARK: Before / After
        curated(
            id: "curated-before-after-split",
            name: "Before / After Split",
            category: .beforeAfter,
            background: Palette.graphite,
            headline: "30 DAYS LATER",
            headlineColor: Palette.white,
            font: .oswald,
            anchor: .center(x: 0.46, y: 0.66),
            maxWidth: 0.72,
            style: .panel(Palette.graphite.withAlpha(0.88)),
            decorations: [
                .badge(role: "before", text: "BEFORE", fill: Palette.white, labelColor: Palette.graphite,
                       x: 0.17, y: 0.13, width: 0.18),
                .badge(role: "after", text: "AFTER", fill: Palette.mint, labelColor: Palette.graphite,
                       x: 0.75, y: 0.13, width: 0.18)
            ],
            focalRegion: nil,
            note: "Side-by-side photo, labels on top, result below."
        ),
        curated(
            id: "curated-before-after-makeover",
            name: "Makeover Reveal",
            category: .beforeAfter,
            background: Palette.linen,
            headline: "FULL ROOM\nMAKEOVER",
            headlineColor: Palette.espresso,
            font: .roboto,
            anchor: .center(x: 0.46, y: 0.38),
            maxWidth: 0.72,
            style: .outline(Palette.white),
            decorations: [
                .badge(role: "before", text: "BEFORE", fill: Palette.espresso, labelColor: Palette.white,
                       x: 0.17, y: 0.8, width: 0.18),
                .arrow(role: "arrow", fill: Palette.sage, x: 0.46, y: 0.8, width: 0.16, height: 0.1,
                       pointsLeft: false),
                .badge(role: "after", text: "AFTER", fill: Palette.sage, labelColor: Palette.white,
                       x: 0.75, y: 0.8, width: 0.18)
            ],
            focalRegion: nil,
            note: "Before and after tags along the bottom."
        ),

        // MARK: Listicle / Top-N
        curated(
            id: "curated-listicle-top-five",
            name: "Top 5 Countdown",
            category: .listicle,
            background: Palette.inkBlue,
            fill: .linearGradient([Palette.electricBlue, Palette.inkBlue], angleDegrees: 135),
            headline: "BEST APPS\nTHIS YEAR",
            headlineColor: Palette.white,
            font: .oswald,
            anchor: .leading(x: 0.07, y: 0.46),
            maxWidth: 0.52,
            style: .softShadow,
            decorations: [
                .burst(role: "burst", text: "TOP 5", fill: Palette.signalYellow, labelColor: Palette.inkBlue,
                       x: 0.73, y: 0.2, width: 0.2, height: 0.22)
            ],
            focalRegion: CGRect(x: 0.6, y: 0.36, width: 0.26, height: 0.5),
            note: "Countdown burst with the list topic."
        ),
        curated(
            id: "curated-listicle-tier-list",
            name: "Tier List",
            category: .listicle,
            background: Palette.charcoal,
            headline: "I RANKED\nEVERY ONE",
            headlineColor: Palette.white,
            font: .oswald,
            anchor: .trailing(x: 0.86, y: 0.46),
            maxWidth: 0.52,
            style: .plain,
            decorations: [
                .badge(role: "badge", text: "S TIER", fill: Palette.gold, labelColor: Palette.charcoal,
                       x: 0.19, y: 0.13, width: 0.16)
            ],
            focalRegion: CGRect(x: 0.06, y: 0.22, width: 0.26, height: 0.64),
            note: "Ranking title right, the pick on the left."
        ),

        // MARK: News / Announcement
        curated(
            id: "curated-news-breaking",
            name: "Breaking Update",
            category: .news,
            background: Palette.newsNavy,
            headline: "UPDATE\nIS HERE",
            headlineColor: Palette.white,
            font: .roboto,
            anchor: .leading(x: 0.07, y: 0.56),
            maxWidth: 0.5,
            style: .plain,
            decorations: [
                .badge(role: "badge", text: "BREAKING", fill: Palette.alarmRed, labelColor: Palette.white,
                       x: 0.18, y: 0.13, width: 0.22)
            ],
            focalRegion: CGRect(x: 0.6, y: 0.08, width: 0.26, height: 0.78),
            note: "Newsroom tag with the headline left."
        ),
        curated(
            id: "curated-news-announcement",
            name: "Announcement",
            category: .news,
            background: Palette.indigo,
            fill: .linearGradient([Palette.indigo, Palette.orchid], angleDegrees: 0),
            headline: "WE HAVE\nBIG NEWS",
            headlineColor: Palette.white,
            font: .roboto,
            anchor: .center(x: 0.46, y: 0.56),
            maxWidth: 0.64,
            style: .softShadow,
            decorations: [
                .badge(role: "badge", text: "ANNOUNCEMENT", fill: Palette.white, labelColor: Palette.indigo,
                       x: 0.46, y: 0.13, width: 0.34)
            ],
            focalRegion: nil,
            note: "Centred announcement card."
        ),

        // MARK: Minimal
        curated(
            id: "curated-minimal-less-better",
            name: "Less but Better",
            category: .minimal,
            background: Palette.linen,
            headline: "LESS BUT\nBETTER",
            headlineColor: Palette.rust,
            font: .oswald,
            anchor: .leading(x: 0.07, y: 0.46),
            maxWidth: 0.48,
            style: .plain,
            decorations: [],
            focalRegion: CGRect(x: 0.6, y: 0.08, width: 0.26, height: 0.78),
            note: "Quiet off-white card with one accent colour."
        ),
        curated(
            id: "curated-minimal-mono",
            name: "Mono Title",
            category: .minimal,
            background: Palette.pureBlack,
            headline: "SIMPLE DESK\nSETUP",
            headlineColor: Palette.white,
            font: .roboto,
            anchor: .center(x: 0.46, y: 0.42),
            maxWidth: 0.8,
            style: .plain,
            decorations: [
                .bar(role: "bar", fill: Palette.signalYellow, x: 0.46, y: 0.8, width: 0.12, height: 0.08)
            ],
            focalRegion: nil,
            note: "Black and white title with one accent bar."
        )
    ]
}

// MARK: - Palette

private extension ThumbnailDocumentColor {
    func withAlpha(_ alpha: Double) -> ThumbnailDocumentColor {
        ThumbnailDocumentColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

private enum Palette {
    static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> ThumbnailDocumentColor {
        ThumbnailDocumentColor(red: red, green: green, blue: blue, alpha: 1)
    }

    static let white = rgb(1, 1, 1)
    static let pureBlack = rgb(0.03, 0.03, 0.04)
    static let ink = rgb(0.07, 0.08, 0.1)
    static let charcoal = rgb(0.1, 0.1, 0.12)
    static let graphite = rgb(0.12, 0.13, 0.15)
    static let paper = rgb(0.98, 0.98, 0.99)
    static let linen = rgb(0.95, 0.94, 0.91)
    static let cream = rgb(0.97, 0.94, 0.88)
    static let espresso = rgb(0.16, 0.12, 0.1)

    static let royalPurple = rgb(0.3, 0.08, 0.55)
    static let nightPurple = rgb(0.07, 0.02, 0.15)
    static let victoryYellow = rgb(1, 0.84, 0.12)
    static let bossRed = rgb(0.62, 0.04, 0.07)
    static let bloodBlack = rgb(0.1, 0.01, 0.02)
    static let burntOrange = rgb(0.75, 0.25, 0.08)
    static let duskPlum = rgb(0.5, 0.08, 0.28)
    static let terracotta = rgb(0.72, 0.3, 0.18)
    static let navy = rgb(0.06, 0.1, 0.22)
    static let signalYellow = rgb(1, 0.82, 0.1)
    static let cobalt = rgb(0.1, 0.33, 0.85)
    static let alarmRed = rgb(0.85, 0.1, 0.12)
    static let lemon = rgb(1, 0.88, 0.25)
    static let amber = rgb(1, 0.66, 0.1)
    static let deepBlue = rgb(0.1, 0.18, 0.4)
    static let midnight = rgb(0.03, 0.04, 0.1)
    static let deepTeal = rgb(0.05, 0.22, 0.24)
    static let butter = rgb(0.99, 0.87, 0.55)
    static let plum = rgb(0.13, 0.08, 0.2)
    static let magenta = rgb(0.8, 0.15, 0.55)
    static let violet = rgb(0.3, 0.1, 0.5)
    static let peach = rgb(1, 0.72, 0.62)
    static let rust = rgb(0.6, 0.22, 0.12)
    static let mint = rgb(0.3, 0.85, 0.55)
    static let sage = rgb(0.3, 0.45, 0.32)
    static let inkBlue = rgb(0.04, 0.1, 0.35)
    static let electricBlue = rgb(0.1, 0.35, 0.95)
    static let gold = rgb(1, 0.76, 0.2)
    static let newsNavy = rgb(0.04, 0.07, 0.16)
    static let indigo = rgb(0.25, 0.18, 0.7)
    static let orchid = rgb(0.55, 0.2, 0.7)
}

// MARK: - Builders

extension ThumbnailTemplate {
    /// Where the headline's text frame sits. `leading`/`trailing` pin the
    /// frame's left/right edge (and align the text that way); `center`
    /// centres it.
    fileprivate enum HeadlineAnchor {
        case leading(x: Double, y: Double)
        case center(x: Double, y: Double)
        case trailing(x: Double, y: Double)
    }

    fileprivate enum HeadlineLook {
        case plain
        case softShadow
        case boldOutline
        case outline(ThumbnailDocumentColor)
        case outlineAndShadow
        case glow(ThumbnailDocumentColor)
        case panel(ThumbnailDocumentColor)
    }

    fileprivate enum Decoration {
        /// Pill tag with a one-line label; height is a fraction of the canvas height.
        case badge(role: String, text: String, fill: ThumbnailDocumentColor, labelColor: ThumbnailDocumentColor,
                   x: Double, y: Double, width: Double, height: Double = 0.1)
        case burst(role: String, text: String, fill: ThumbnailDocumentColor, labelColor: ThumbnailDocumentColor,
                   x: Double, y: Double, width: Double, height: Double)
        case callout(role: String, text: String, fill: ThumbnailDocumentColor, labelColor: ThumbnailDocumentColor,
                     x: Double, y: Double, width: Double, height: Double, tail: ThumbnailCalloutTailDirection)
        case arrow(role: String, fill: ThumbnailDocumentColor,
                   x: Double, y: Double, width: Double, height: Double, pointsLeft: Bool)
        case ring(role: String, stroke: ThumbnailDocumentColor, x: Double, y: Double, width: Double, height: Double)
        case bar(role: String, fill: ThumbnailDocumentColor, x: Double, y: Double, width: Double, height: Double)

        func layer(templateID: String, zIndex: Int) -> ThumbnailDocumentLayer {
            let (role, name, content) = resolved
            return ThumbnailDocumentLayer(
                id: ThumbnailTemplate.builtInLayerID(templateID: templateID, role: role),
                kind: .shape,
                name: name,
                zIndex: zIndex,
                content: .shape(content)
            )
        }

        private static func label(
            _ text: String,
            color: ThumbnailDocumentColor,
            sizeFraction: Double = 0.42
        ) -> ThumbnailShapeLabel {
            ThumbnailShapeLabel(text: text, color: color, fontRawValue: CustomFont.roboto.rawValue, sizeFraction: sizeFraction)
        }

        private var resolved: (String, String, ThumbnailShapeLayerContent) {
            switch self {
            case let .badge(role, text, fill, labelColor, x, y, width, height):
                return (role, "Badge", ThumbnailShapeLayerContent(
                    shapeKind: .pill,
                    fillColor: fill,
                    strokeColor: nil,
                    strokeWidth: 0,
                    transform: ThumbnailOverlayTransform(x: x, y: y),
                    width: width,
                    height: height,
                    geometry: ThumbnailShapeGeometryRecipe(cornerRadius: 0.5),
                    label: Self.label(text, color: labelColor)
                ))
            case let .burst(role, text, fill, labelColor, x, y, width, height):
                return (role, "Burst Badge", ThumbnailShapeLayerContent(
                    shapeKind: .burst,
                    fillColor: fill,
                    strokeColor: nil,
                    strokeWidth: 0,
                    transform: ThumbnailOverlayTransform(x: x, y: y, rotationDegrees: -8),
                    width: width,
                    height: height,
                    geometry: ThumbnailShapeGeometryRecipe(burstPoints: 14, burstInnerRatio: 0.82),
                    label: Self.label(text, color: labelColor, sizeFraction: 0.3)
                ))
            case let .callout(role, text, fill, labelColor, x, y, width, height, tail):
                return (role, "Callout", ThumbnailShapeLayerContent(
                    shapeKind: .callout,
                    fillColor: fill,
                    strokeColor: nil,
                    strokeWidth: 0,
                    transform: ThumbnailOverlayTransform(x: x, y: y),
                    width: width,
                    height: height,
                    geometry: ThumbnailShapeGeometryRecipe(cornerRadius: 0.3, tailDirection: tail, tailLength: 0.28),
                    label: Self.label(text, color: labelColor)
                ))
            case let .arrow(role, fill, x, y, width, height, pointsLeft):
                return (role, "Arrow", ThumbnailShapeLayerContent(
                    shapeKind: .arrow,
                    fillColor: fill,
                    strokeColor: nil,
                    strokeWidth: 0,
                    transform: ThumbnailOverlayTransform(x: x, y: y),
                    width: width,
                    height: height,
                    geometry: ThumbnailShapeGeometryRecipe(
                        startHead: pointsLeft ? .triangle : ThumbnailArrowheadStyle.none,
                        endHead: pointsLeft ? ThumbnailArrowheadStyle.none : .triangle
                    )
                ))
            case let .ring(role, stroke, x, y, width, height):
                return (role, "Highlight", ThumbnailShapeLayerContent(
                    shapeKind: .ellipse,
                    fillColor: ThumbnailDocumentColor(red: 1, green: 1, blue: 1, alpha: 0),
                    strokeColor: stroke,
                    strokeWidth: 0.014,
                    transform: ThumbnailOverlayTransform(x: x, y: y),
                    width: width,
                    height: height
                ))
            case let .bar(role, fill, x, y, width, height):
                return (role, "Accent Bar", ThumbnailShapeLayerContent(
                    shapeKind: .pill,
                    fillColor: fill,
                    strokeColor: nil,
                    strokeWidth: 0,
                    transform: ThumbnailOverlayTransform(x: x, y: y),
                    width: width,
                    height: height,
                    geometry: ThumbnailShapeGeometryRecipe(cornerRadius: 0.5)
                ))
            }
        }
    }

    fileprivate static func headlineStyle(
        _ look: HeadlineLook,
        alignment: ThumbnailTextAlignment,
        maxWidth: Double
    ) -> ThumbnailTextStyle {
        var style = ThumbnailTextStyle(
            alignment: alignment,
            maxWidthFraction: maxWidth,
            lineLimit: nil,
            minimumScaleFactor: 1
        )
        let shadowBlack = ThumbnailDocumentColor(red: 0, green: 0, blue: 0, alpha: 0.82)
        switch look {
        case .plain:
            style.presetID = "plain"
        case .softShadow:
            style.isShadowEnabled = true
            style.shadowColor = shadowBlack
            style.shadowRadius = 0.028
            style.shadowOffsetX = 0.009
            style.shadowOffsetY = 0.009
            style.presetID = "softShadow"
        case .boldOutline:
            style.outlineWidth = 0.06
            style.outlineColor = ThumbnailTextStyle.black
            style.presetID = "boldOutline"
        case .outline(let color):
            style.outlineWidth = 0.05
            style.outlineColor = color
            style.presetID = "boldOutline"
        case .outlineAndShadow:
            style.outlineWidth = 0.06
            style.outlineColor = ThumbnailTextStyle.black
            style.isShadowEnabled = true
            style.shadowColor = shadowBlack
            style.shadowRadius = 0.05
            style.shadowOffsetX = 0.03
            style.shadowOffsetY = 0.03
            style.presetID = "outlineAndShadow"
        case .glow(let color):
            style.isShadowEnabled = true
            style.shadowColor = color
            style.shadowRadius = 0.12
            style.presetID = "glow"
        case .panel(let color):
            style.panelColor = color
            style.panelCornerRadius = 0.25
            style.horizontalPadding = 0.3
            style.verticalPadding = 0.12
            style.presetID = "panelPill"
        }
        return style.normalized()
    }

    fileprivate static func curated(
        id: String,
        name: String,
        category: ThumbnailTemplateCategory,
        aspectRatio: AspectRatio = .ratio16_9,
        exportPresetID: String? = nil,
        background: ThumbnailDocumentColor,
        fill: ThumbnailBackgroundFill? = nil,
        headline: String,
        headlineColor: ThumbnailDocumentColor,
        headlineSize: Double = landscapeHeadlineSize,
        font: CustomFont,
        anchor: HeadlineAnchor,
        maxWidth: Double,
        style look: HeadlineLook,
        decorations: [Decoration],
        focalRegion: CGRect?,
        note: String
    ) -> ThumbnailCuratedTemplate {
        let alignment: ThumbnailTextAlignment
        let transform: ThumbnailOverlayTransform
        switch anchor {
        case let .leading(x, y):
            alignment = .leading
            transform = ThumbnailOverlayTransform(x: x + maxWidth / 2, y: y)
        case let .center(x, y):
            alignment = .center
            transform = ThumbnailOverlayTransform(x: x, y: y)
        case let .trailing(x, y):
            alignment = .trailing
            transform = ThumbnailOverlayTransform(x: x - maxWidth / 2, y: y)
        }

        var layers = [ThumbnailDocumentLayer.defaultBackgroundLayer]
        for (index, decoration) in decorations.enumerated() {
            layers.append(decoration.layer(
                templateID: id,
                zIndex: ThumbnailDocumentLayer.contentLayerZIndexStart + index
            ))
        }
        // The headline sits above its decorations so a badge can never hide it.
        var textLayer = ThumbnailDocumentLayer.defaultTextLayer
        textLayer.name = "Headline"
        textLayer.zIndex = ThumbnailDocumentLayer.contentLayerZIndexStart + decorations.count
        layers.append(textLayer)

        let presetID = exportPresetID ?? Self.curatedPresetID(for: aspectRatio)
        let document = ThumbnailDocument(
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            editorMode: .simple,
            canvas: ThumbnailDocumentCanvas(
                aspectRatioRawValue: aspectRatio.rawValue,
                backgroundColor: background,
                backgroundFill: fill
            ),
            text: ThumbnailDocumentText(
                value: headline,
                color: headlineColor,
                size: headlineSize,
                transform: transform,
                selectedFontRawValue: font.rawValue,
                style: headlineStyle(look, alignment: alignment, maxWidth: maxWidth)
            ),
            layers: layers.reconciledForCurrentOverlays(hasText: true, hasProfile: false),
            export: ThumbnailDocumentExport(presetID: presetID)
        )
        return ThumbnailCuratedTemplate(
            template: ThumbnailTemplate(id: id, name: name, category: category, document: document),
            focalRegion: focalRegion,
            layoutNote: note
        )
    }

    private static func curatedPresetID(for aspectRatio: AspectRatio) -> String {
        switch aspectRatio {
        case .ratio16_9: ThumbnailExportPreset.youTubeThumbnail.id
        case .ratio9_16: ThumbnailExportPreset.shortFormCover.id
        case .ratioReelsCover: ThumbnailExportPreset.instagramReelsCover.id
        case .ratio1_1: ThumbnailExportPreset.instagramSquare.id
        case .ratio4_3: ThumbnailExportPreset.videoCover.id
        case .ratio3_4: ThumbnailExportPreset.portraitCover.id
        }
    }
}
