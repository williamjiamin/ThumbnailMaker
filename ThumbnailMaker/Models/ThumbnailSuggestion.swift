//
//  ThumbnailSuggestion.swift
//  ThumbnailMaker
//

import Foundation

enum BrandColorRole: String, Equatable {
    case text
    case background
}

enum ThumbnailSuggestionKind: String, Equatable {
    case text
    case contrast
    case crop
    case template
    case brand
}

enum ThumbnailSuggestionAction: Equatable {
    case shortenText
    case applyTemplate(id: String)
    case applyBrandColor(role: BrandColorRole)
    case cropToDetectedFace
    case none
}

struct ThumbnailSuggestion: Identifiable, Equatable {
    let id: String
    let kind: ThumbnailSuggestionKind
    let title: String
    let detail: String
    let action: ThumbnailSuggestionAction

    init(
        id: String,
        kind: ThumbnailSuggestionKind,
        title: String,
        detail: String,
        action: ThumbnailSuggestionAction
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.action = action
    }
}

extension ThumbnailSuggestion {
    var isCurrentlyActionableInEditor: Bool {
        switch action {
        case .shortenText, .applyTemplate, .cropToDetectedFace:
            return true
        case .applyBrandColor:
            return true
        case .none:
            return false
        }
    }
}

enum ThumbnailSuggestionTextShortener {
    static let maximumCharacterCount = 64
    static let maximumWordCount = 10

    static func shortened(_ text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return text }

        let words = trimmedText.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        var candidate = words.prefix(maximumWordCount).joined(separator: " ")
        candidate = limitedToMobileDensity(candidate)

        guard !candidate.isEmpty, candidate != trimmedText else {
            return text
        }

        return candidate
    }

    private static func limitedToMobileDensity(_ text: String) -> String {
        guard text.count > maximumCharacterCount else { return text }

        let limitedPrefix = String(text.prefix(maximumCharacterCount))
        if let lastWhitespaceIndex = limitedPrefix.lastIndex(where: { $0.isWhitespace || $0.isNewline }) {
            let wordBoundaryText = limitedPrefix[..<lastWhitespaceIndex]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !wordBoundaryText.isEmpty {
                return String(wordBoundaryText)
            }
        }

        return limitedPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

protocol ThumbnailSuggestionProviding {
    func suggestions<Configuration: ThumbnailReadinessConfiguration>(
        for configuration: Configuration,
        brandKit: BrandKit?,
        templates: [ThumbnailTemplate]
    ) -> [ThumbnailSuggestion]
}

struct LocalThumbnailSuggestionProvider: ThumbnailSuggestionProviding {
    func suggestions<Configuration: ThumbnailReadinessConfiguration>(
        for configuration: Configuration,
        brandKit: BrandKit? = nil,
        templates: [ThumbnailTemplate] = ThumbnailTemplate.builtIns
    ) -> [ThumbnailSuggestion] {
        let report = ThumbnailReadinessAnalyzer.analyze(configuration)
        var suggestions: [ThumbnailSuggestion] = []

        for finding in report.findings where finding.severity == .warning {
            if finding.message.localizedCaseInsensitiveContains("dense") {
                suggestions.appendUnique(
                    ThumbnailSuggestion(
                        id: "text-shorten-dense-title",
                        kind: .text,
                        title: "Shorten the title",
                        detail: "Dense thumbnail text is hard to read in mobile previews.",
                        action: .shortenText
                    )
                )
            }

            if finding.message.localizedCaseInsensitiveContains("contrast"), brandKit?.palette.isEmpty == false {
                suggestions.appendUnique(
                    ThumbnailSuggestion(
                        id: "contrast-apply-brand-text-color",
                        kind: .contrast,
                        title: "Use a brand color for text",
                        detail: "Apply the first brand color to improve contrast and keep the design on brand.",
                        action: .applyBrandColor(role: .text)
                    )
                )
            }

            if finding.message.localizedCaseInsensitiveContains("add an image") {
                appendTemplateSuggestion(
                    for: configuration,
                    templates: templates,
                    to: &suggestions
                )
            }
        }

        if configuration.selectedImage != nil {
            suggestions.appendUnique(
                ThumbnailSuggestion(
                    id: "crop-detected-face",
                    kind: .crop,
                    title: "Crop around detected faces",
                    detail: "Use on-device face detection to place people safely inside the creator-platform safe zone.",
                    action: .cropToDetectedFace
                )
            )
        }

        if let brandKit, !brandKit.palette.isEmpty {
            suggestions.appendUnique(
                ThumbnailSuggestion(
                    id: "brand-apply-kit",
                    kind: .brand,
                    title: "Apply brand kit",
                    detail: "Use saved colors and typography for a consistent creator identity.",
                    action: .applyBrandColor(role: .text)
                )
            )
        }

        return suggestions
    }

    private func appendTemplateSuggestion<Configuration: ThumbnailReadinessConfiguration>(
        for configuration: Configuration,
        templates: [ThumbnailTemplate],
        to suggestions: inout [ThumbnailSuggestion]
    ) {
        guard let template = templates.first(where: {
            $0.document.canvas.aspectRatioRawValue == configuration.selectedRatio.rawValue
        }) ?? templates.first else {
            return
        }

        suggestions.appendUnique(
            ThumbnailSuggestion(
                id: "template-\(template.id)",
                kind: .template,
                title: "Start from \(template.name)",
                detail: "Use a layout variant that matches the selected export ratio.",
                action: .applyTemplate(id: template.id)
            )
        )
    }
}

private extension Array where Element == ThumbnailSuggestion {
    mutating func appendUnique(_ suggestion: ThumbnailSuggestion) {
        guard !contains(where: { $0.id == suggestion.id }) else {
            return
        }

        append(suggestion)
    }
}
