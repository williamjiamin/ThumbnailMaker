//
//  ThumbnailIdea.swift
//  ThumbnailMaker
//

import Foundation
import SwiftUI

enum ThumbnailIdeaKind: String, Equatable {
    case layout
    case style
    case color
}

struct ThumbnailIdea: Identifiable, Equatable {
    let id: String
    let kind: ThumbnailIdeaKind
    let headline: String
    let rationale: String
    let template: ThumbnailTemplate
}

protocol ThumbnailIdeaProviding {
    func ideas(
        forTitle title: String,
        ratio: AspectRatio,
        brandKit: BrandKit?,
        templates: [ThumbnailTemplate]
    ) -> [ThumbnailIdea]
}

struct LocalThumbnailIdeaProvider: ThumbnailIdeaProviding {
    private let maximumIdeaCount = 5

    func ideas(
        forTitle title: String,
        ratio: AspectRatio,
        brandKit: BrandKit? = nil,
        templates: [ThumbnailTemplate] = ThumbnailTemplate.builtIns
    ) -> [ThumbnailIdea] {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return [] }

        let rankedTemplates = rankedTemplates(
            forTitle: normalizedTitle,
            ratio: ratio,
            templates: templates
        )
        guard let firstTemplate = rankedTemplates.first else { return [] }

        var ideas: [ThumbnailIdea] = rankedTemplates
            .prefix(3)
            .map { template in
                makeIdea(
                    kind: .layout,
                    title: normalizedTitle,
                    template: template,
                    headline: layoutHeadline(for: template),
                    rationale: layoutRationale(for: template)
                )
            }

        ideas.append(
            makeIdea(
                kind: .style,
                title: normalizedTitle,
                template: styleTemplate(from: firstTemplate, title: normalizedTitle, brandKit: brandKit),
                headline: "Typography punch",
                rationale: "Try a high-clarity font and bigger hook treatment before export."
            )
        )

        ideas.append(
            makeIdea(
                kind: .color,
                title: normalizedTitle,
                template: colorTemplate(from: firstTemplate, title: normalizedTitle, brandKit: brandKit),
                headline: brandKit?.palette.isEmpty == false ? "On-brand colorway" : "High-contrast colorway",
                rationale: brandKit?.palette.isEmpty == false
                    ? "Use your saved brand colors so variants stay consistent."
                    : "Use a bright text color against a dark creator-friendly background."
            )
        )

        return Array(ideas.uniqueByID().prefix(maximumIdeaCount))
    }

    private func rankedTemplates(
        forTitle title: String,
        ratio: AspectRatio,
        templates: [ThumbnailTemplate]
    ) -> [ThumbnailTemplate] {
        templates
            .map { template in
                (template: template, score: score(template, title: title, ratio: ratio))
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.template.id < rhs.template.id
                }
                return lhs.score > rhs.score
            }
            .map(\.template)
    }

    private func score(
        _ template: ThumbnailTemplate,
        title: String,
        ratio: AspectRatio
    ) -> Int {
        let lowercasedTitle = title.lowercased()
        var score = template.document.canvas.aspectRatioRawValue == ratio.rawValue ? 100 : 0

        switch template.category {
        case .gaming:
            score += containsAny(
                ["win", "lost", "boss", "game", "gaming", "vs", "rank", "speedrun"],
                in: lowercasedTitle
            ) ? 45 : 0
        case .podcast:
            score += containsAny(
                ["podcast", "episode", "interview", "talk", "guest", "story"],
                in: lowercasedTitle
            ) ? 45 : 0
        case .shortForm:
            score += containsAny(
                ["short", "tiktok", "reels", "wait", "secret", "hack", "watch"],
                in: lowercasedTitle
            ) ? 45 : 0
            score += lowercasedTitle.contains("?") ? 16 : 0
        case .youtube:
            score += containsAny(
                ["launch", "reveal", "how", "tutorial", "review", "youtube", "thumbnail"],
                in: lowercasedTitle
            ) ? 40 : 0
        case .vlog:
            score += containsAny(
                ["day", "travel", "vlog", "life", "behind", "story"],
                in: lowercasedTitle
            ) ? 36 : 0
        case .tutorial:
            score += containsAny(
                ["how", "tutorial", "guide", "learn", "step", "tips"],
                in: lowercasedTitle
            ) ? 40 : 0
        case .reaction:
            score += containsAny(
                ["react", "reaction", "omg", "insane", "shocked", "wow"],
                in: lowercasedTitle
            ) ? 40 : 0
        case .beforeAfter:
            score += containsAny(
                ["before", "after", "makeover", "transformation", "glow up", "results"],
                in: lowercasedTitle
            ) ? 40 : 0
        case .listicle:
            score += containsAny(
                ["top", "best", "ranked", "ranking", "tier", "things"],
                in: lowercasedTitle
            ) ? 40 : 0
        case .news:
            score += containsAny(
                ["news", "update", "breaking", "announcement", "announce"],
                in: lowercasedTitle
            ) ? 40 : 0
        case .minimal:
            score += containsAny(
                ["minimal", "simple", "clean", "setup", "aesthetic"],
                in: lowercasedTitle
            ) ? 36 : 0
        }

        return score
    }

    private func makeIdea(
        kind: ThumbnailIdeaKind,
        title: String,
        template: ThumbnailTemplate,
        headline: String,
        rationale: String
    ) -> ThumbnailIdea {
        let slug = titleSlug(for: title)
        var template = template
        template.id = "idea-\(kind.rawValue)-\(template.id)-\(slug)"
        template.name = headline
        template.document.text.value = title
        template.document.layers = template.document.layers.reconciledForCurrentOverlays(
            hasText: true,
            hasProfile: template.document.profile?.imageData != nil
        )

        return ThumbnailIdea(
            id: template.id,
            kind: kind,
            headline: headline,
            rationale: rationale,
            template: template
        )
    }

    private func styleTemplate(
        from template: ThumbnailTemplate,
        title: String,
        brandKit: BrandKit?
    ) -> ThumbnailTemplate {
        var template = template
        template.document.text.value = title
        template.document.text.size = min(0.3, max(template.document.text.size, 0.2))
        template.document.text.selectedFontRawValue = styleFont(for: brandKit).rawValue
        template.document.text.transform.rotationDegrees = 0
        return template
    }

    private func colorTemplate(
        from template: ThumbnailTemplate,
        title: String,
        brandKit: BrandKit?
    ) -> ThumbnailTemplate {
        var template = template
        template.document.text.value = title

        if let textColor = brandKit?.palette.first?.color,
           let backgroundColor = brandKit?.palette.dropFirst().first?.color {
            template.document.text.color = textColor
            template.document.canvas.backgroundColor = backgroundColor
        } else {
            let fallbackPalette = fallbackPalette(for: template.category)
            template.document.text.color = fallbackPalette.text
            template.document.canvas.backgroundColor = fallbackPalette.background
        }

        return template
    }

    private func styleFont(for brandKit: BrandKit?) -> CustomFont {
        if let brandFont = brandKit?.primaryFont, !brandFont.isPremium {
            return brandFont
        }

        return .montserrat
    }

    private func fallbackPalette(
        for category: ThumbnailTemplateCategory
    ) -> (text: ThumbnailDocumentColor, background: ThumbnailDocumentColor) {
        switch category {
        case .gaming:
            return (
                ThumbnailDocumentColor(red: 0.18, green: 1.0, blue: 0.62, alpha: 1),
                ThumbnailDocumentColor(red: 0.08, green: 0.01, blue: 0.10, alpha: 1)
            )
        case .shortForm:
            return (
                ThumbnailDocumentColor(red: 1.0, green: 0.92, blue: 0.18, alpha: 1),
                ThumbnailDocumentColor(red: 0.03, green: 0.09, blue: 0.13, alpha: 1)
            )
        case .podcast:
            return (
                ThumbnailDocumentColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1),
                ThumbnailDocumentColor(red: 0.92, green: 0.94, blue: 0.98, alpha: 1)
            )
        case .vlog:
            return (
                ThumbnailDocumentColor(red: 1.0, green: 0.77, blue: 0.42, alpha: 1),
                ThumbnailDocumentColor(red: 0.08, green: 0.18, blue: 0.20, alpha: 1)
            )
        case .youtube, .tutorial, .news, .listicle:
            return (
                ThumbnailDocumentColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1),
                ThumbnailDocumentColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1)
            )
        case .reaction:
            return (
                ThumbnailDocumentColor(red: 1.0, green: 0.92, blue: 0.18, alpha: 1),
                ThumbnailDocumentColor(red: 0.55, green: 0.05, blue: 0.10, alpha: 1)
            )
        case .beforeAfter, .minimal:
            return (
                ThumbnailDocumentColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1),
                ThumbnailDocumentColor(red: 0.95, green: 0.94, blue: 0.91, alpha: 1)
            )
        }
    }

    private func layoutHeadline(for template: ThumbnailTemplate) -> String {
        switch template.category {
        case .youtube:
            return "Bold centered hook"
        case .shortForm:
            return "Vertical swipe stopper"
        case .podcast:
            return "Clean episode card"
        case .gaming:
            return "High-impact gaming"
        case .vlog:
            return "Story-first layout"
        case .tutorial:
            return "Clear how-to title"
        case .reaction:
            return "Big-emotion reaction"
        case .beforeAfter:
            return "Before and after split"
        case .listicle:
            return "Countdown list"
        case .news:
            return "Announcement card"
        case .minimal:
            return "Minimal title"
        }
    }

    private func layoutRationale(for template: ThumbnailTemplate) -> String {
        switch template.category {
        case .youtube:
            return "Use a big, simple title that stays readable in small YouTube previews."
        case .shortForm:
            return "Place the hook high for Shorts, TikTok, and Reels cover crops."
        case .podcast:
            return "Give the title room so episode art works in square podcast grids."
        case .gaming:
            return "Lean into contrast and motion for competitive or reaction-driven titles."
        case .vlog:
            return "Keep the title warm and narrative for lifestyle or behind-the-scenes content."
        case .tutorial:
            return "Lead with the outcome so viewers know exactly what they will learn."
        case .reaction:
            return "Pair a short, loud caption with high contrast so the emotion reads instantly."
        case .beforeAfter:
            return "Label each side so the change reads at a glance."
        case .listicle:
            return "Lead with the number so the list promise is obvious."
        case .news:
            return "Tag the update so returning viewers spot it immediately."
        case .minimal:
            return "Let one short line and plenty of space carry the design."
        }
    }

    private func containsAny(_ keywords: [String], in title: String) -> Bool {
        keywords.contains { title.contains($0) }
    }

    private func titleSlug(for title: String) -> String {
        let characters = title
            .lowercased()
            .map { character -> Character in
                character.isLetter || character.isNumber ? character : "-"
            }
        let slug = String(characters)
            .split(separator: "-")
            .prefix(4)
            .joined(separator: "-")
        return slug.isEmpty ? "untitled" : slug
    }
}

private extension Array where Element == ThumbnailIdea {
    func uniqueByID() -> [ThumbnailIdea] {
        var seenIDs: Set<String> = []
        return filter { idea in
            seenIDs.insert(idea.id).inserted
        }
    }
}
