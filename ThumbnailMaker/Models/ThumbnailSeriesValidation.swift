//
//  ThumbnailSeriesValidation.swift
//  ThumbnailMaker
//
//  FEATURE-15: per-row checks. Errors block that row from rendering (and only
//  that row); warnings never block. Pure, so it runs on every table edit.
//

import Foundation

enum ThumbnailSeriesRowError: Equatable, LocalizedError {
    case emptyTitle
    case titleTooLong(max: Int)
    case imageNotImported(fileName: String)
    case imageUnreadable(fileName: String)
    case duplicateOutputName(String)
    case malformedCSV(line: Int, reason: String)

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return "Add a title."
        case .titleTooLong(let max):
            return "Titles can be up to \(max) characters."
        case .imageNotImported(let fileName):
            return "Image \"\(fileName)\" hasn't been added yet. Use Add Images and pick it."
        case .imageUnreadable(let fileName):
            return "Image \"\(fileName)\" is missing or unreadable. Pick it again."
        case .duplicateOutputName(let name):
            return "Another row already exports as \"\(name)\". Give this row its own file name."
        case let .malformedCSV(line, reason):
            return "CSV line \(line): \(reason)"
        }
    }
}

struct ThumbnailSeriesRowIssue: Equatable, Identifiable {
    enum Severity: String, Equatable {
        case error
        case warning
    }

    let severity: Severity
    let message: String

    var id: String { "\(severity.rawValue)-\(message)" }

    static func error(_ error: ThumbnailSeriesRowError) -> ThumbnailSeriesRowIssue {
        ThumbnailSeriesRowIssue(severity: .error, message: error.errorDescription ?? "Invalid row")
    }

    static func warning(_ message: String) -> ThumbnailSeriesRowIssue {
        ThumbnailSeriesRowIssue(severity: .warning, message: message)
    }
}

struct ThumbnailSeriesValidationReport: Equatable {
    /// Row id -> issues (rows without issues are absent).
    var issues: [UUID: [ThumbnailSeriesRowIssue]]
    /// Row id -> unique, sanitized output stem.
    var outputStems: [UUID: String]
    /// Rows with no error, in table order.
    var renderableRowIDs: [UUID]

    func issues(for rowID: UUID) -> [ThumbnailSeriesRowIssue] { issues[rowID] ?? [] }

    func hasError(_ rowID: UUID) -> Bool {
        issues(for: rowID).contains { $0.severity == .error }
    }

    var errorRowCount: Int { issues.values.filter { $0.contains { $0.severity == .error } }.count }
}

enum ThumbnailSeriesValidator {
    /// Same limits the readiness analyzer uses for "too much text".
    static let readableCharacterCount = 64
    static let readableWordCount = 10

    /// `<series>-<episode or row number>`, or the row's own name.
    static func outputStem(for row: ThumbnailSeriesRow, index: Int, seriesName: String) -> String {
        if let explicit = row.outputName?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            let cleaned = ThumbnailVariantExportNaming.sanitized(explicit)
            if !cleaned.isEmpty { return cleaned }
        }
        var base = ThumbnailVariantExportNaming.sanitized(seriesName)
        if base.isEmpty { base = "series" }
        let suffix = row.episodeValue.map(ThumbnailVariantExportNaming.sanitized).flatMap { $0.isEmpty ? nil : $0 }
            ?? String(format: "%03d", index + 1)
        return "\(base)-\(suffix)"
    }

    static func validate(
        series: ThumbnailSeries,
        source: ThumbnailSeriesSource?,
        availableImageDigests: Set<String>
    ) -> ThumbnailSeriesValidationReport {
        var issues: [UUID: [ThumbnailSeriesRowIssue]] = [:]
        var stems: [UUID: String] = [:]
        var renderable: [UUID] = []
        var takenStems = Set<String>()

        let showsTitle = source.map(ThumbnailSeriesRecipe.sourceShowsTitle) ?? true
        let usesEpisode = source.map { ThumbnailSeriesRecipe.sourceContainsToken(ThumbnailSeriesRecipe.episodeToken, in: $0) } ?? false
        let usesRowImage = source.map(ThumbnailSeriesRecipe.sourceUsesRowImage) ?? true

        for (index, row) in series.rows.enumerated() {
            var rowIssues: [ThumbnailSeriesRowIssue] = []

            if let importError = row.importError, let line = row.sourceLine {
                rowIssues.append(.error(.malformedCSV(line: line, reason: importError)))
            } else if let importError = row.importError {
                rowIssues.append(.error(.malformedCSV(line: 0, reason: importError)))
            }

            let title = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty {
                rowIssues.append(.error(.emptyTitle))
            } else if title.count > ThumbnailSeriesRow.titleCharacterLimit {
                rowIssues.append(.error(.titleTooLong(max: ThumbnailSeriesRow.titleCharacterLimit)))
            }

            if let ref = row.imageRef {
                if !availableImageDigests.contains(ref.digest) {
                    rowIssues.append(.error(.imageUnreadable(fileName: ref.originalFileName)))
                }
            } else if let requested = row.requestedImageName?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !requested.isEmpty {
                rowIssues.append(.error(.imageNotImported(fileName: requested)))
            }

            let stem = outputStem(for: row, index: index, seriesName: series.name)
            if takenStems.contains(stem) {
                rowIssues.append(.error(.duplicateOutputName(stem)))
            } else {
                takenStems.insert(stem)
            }
            stems[row.id] = stem

            // Warnings (never block).
            if !title.isEmpty {
                let words = title.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                if title.count > readableCharacterCount || words.count > readableWordCount {
                    rowIssues.append(.warning("Long title: it may be hard to read at small sizes."))
                }
                if !showsTitle {
                    rowIssues.append(.warning("The source keeps its own headline and has no {title} token, so this title won't appear."))
                }
            }
            if row.episodeValue != nil && !usesEpisode {
                rowIssues.append(.warning("The source has no {episode} token, so the episode won't appear."))
            }
            if row.imageRef != nil && !usesRowImage {
                rowIssues.append(.warning("The source keeps its own background, so this row's image won't appear."))
            }

            if !rowIssues.isEmpty {
                issues[row.id] = rowIssues
            }
            if !rowIssues.contains(where: { $0.severity == .error }) {
                renderable.append(row.id)
            }
        }

        return ThumbnailSeriesValidationReport(issues: issues, outputStems: stems, renderableRowIDs: renderable)
    }
}
