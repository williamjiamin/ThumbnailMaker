//
//  ThumbnailSeriesRecipe.swift
//  ThumbnailMaker
//
//  FEATURE-15: the deterministic, reversible core. A row's thumbnail is a pure
//  function of (source, row, image bytes):
//
//  1. Build a stand-in "project" document from the row: its title (or the
//     template's own headline when the design uses a `{title}` token), its
//     image (or the source's fallback image) and the source's fallback profile.
//  2. Render it THROUGH the personal template:
//     `ThumbnailTemplate.instantiate(over:)` applies the template's slot
//     policies exactly as applying a template in the editor does.
//  3. Replace `{title}` / `{episode}` tokens in the headline, text layers and
//     shape labels.
//
//  The source is never mutated, ids are deterministic and `updatedAt` is the
//  source's capture date, so the same inputs always give an equal document.
//

import Foundation

enum ThumbnailSeriesRecipe {
    static let titleToken = "{title}"
    static let episodeToken = "{episode}"

    /// A row image gets the source's fit mode, centred, zoom 1: a focus/zoom
    /// tuned for another photo is never reused.
    static func rowImageRecipe(for source: ThumbnailSeriesSource) -> ThumbnailImageFrameRecipe {
        let fit = source.template.document.imageData != nil
            ? source.template.document.imageRecipe.fit
            : source.fallbackImageRecipe.fit
        return ThumbnailImageFrameRecipe(fit: fit)
    }

    static func document(
        for row: ThumbnailSeriesRow,
        in source: ThumbnailSeriesSource,
        imageData: Data?
    ) -> ThumbnailDocument {
        let template = source.template
        let usesTitleToken = sourceContainsToken(titleToken, in: source)

        var project = template.document
        project.text.value = usesTitleToken ? template.document.text.value : row.title
        if let imageData {
            project.imageData = imageData
            project.imageRecipe = rowImageRecipe(for: source)
        } else {
            project.imageData = source.fallbackImageData
            project.imageRecipe = source.fallbackImageRecipe
        }
        project.profile = source.fallbackProfile

        var counter = 0
        var document = template.instantiate(
            over: project,
            updatedAt: source.capturedAt,
            idProvider: {
                counter += 1
                return "series-layer-\(counter)"
            }
        ).document

        let replacements = [
            titleToken: row.title,
            episodeToken: row.episodeValue ?? ""
        ]
        document.text.value = substitute(document.text.value, replacements)
        for index in document.layers.indices {
            switch document.layers[index].content {
            case .text(var content):
                content.value = substitute(content.value, replacements)
                document.layers[index].content = .text(content)
            case .shape(var content):
                if var label = content.label {
                    label.text = substitute(label.text, replacements)
                    content.label = label
                    document.layers[index].content = .shape(content)
                }
            default:
                break
            }
        }
        document.layers = document.layers.reconciledForCurrentOverlays(
            hasText: !document.text.value.isEmpty,
            hasProfile: document.profile?.imageData != nil
        )
        document.updatedAt = source.capturedAt
        return document
    }

    static func substitute(_ value: String, _ replacements: [String: String]) -> String {
        guard value.contains("{") else { return value }
        var result = value
        for (token, replacement) in replacements.sorted(by: { $0.key < $1.key }) {
            result = result.replacingOccurrences(of: token, with: replacement)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    static func sourceContainsToken(_ token: String, in source: ThumbnailSeriesSource) -> Bool {
        let document = source.template.document
        if document.text.value.contains(token) { return true }
        return document.layers.contains { layer in
            switch layer.content {
            case .text(let content): return content.value.contains(token)
            case .shape(let content): return content.label?.text.contains(token) ?? false
            default: return false
            }
        }
    }

    /// Whether a row's title will be visible at all: either the template
    /// takes the project's headline, or it uses a `{title}` token.
    static func sourceShowsTitle(_ source: ThumbnailSeriesSource) -> Bool {
        source.template.slots.title != .retained || sourceContainsToken(titleToken, in: source)
    }

    /// Whether the template takes the row's image (vs. keeping its own).
    static func sourceUsesRowImage(_ source: ThumbnailSeriesSource) -> Bool {
        source.template.slots.backgroundImage == .replaceFromProject
    }

    static func documentDigest(_ document: ThumbnailDocument) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = (try? encoder.encode(document)) ?? Data()
        return ThumbnailVariantAssetLibrary.digest(data)
    }
}
