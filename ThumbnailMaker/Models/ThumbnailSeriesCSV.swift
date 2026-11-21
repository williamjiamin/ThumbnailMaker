//
//  ThumbnailSeriesCSV.swift
//  ThumbnailMaker
//
//  FEATURE-15: a documented, tolerant CSV format for series tables
//  (see docs/SERIES_CSV.md).
//
//  - UTF-8 (optional BOM), comma separated, RFC 4180 quoting ("" escapes a
//    quote, quoted fields may contain commas and line breaks), LF / CRLF / CR.
//  - A header row is required. Header names ignore case and surrounding
//    spaces: title (required), episode, image, name. Other columns are ignored
//    and reported once.
//  - Blank lines are skipped. A malformed record (wrong number of fields, an
//    unterminated or stray quote) is reported with its 1-based line number and
//    parsing resumes on the next line, so one bad record never hides the rest.
//

import Foundation

enum ThumbnailSeriesCSVColumn: String, CaseIterable {
    case title
    case episode
    case image
    case name
}

struct ThumbnailSeriesCSVRecord: Equatable {
    let line: Int
    let fields: [ThumbnailSeriesCSVColumn: String]
}

struct ThumbnailSeriesCSVRecordError: Equatable {
    let line: Int
    let reason: String
}

enum ThumbnailSeriesCSVFileError: Equatable, LocalizedError {
    case notUTF8
    case empty
    case missingTitleColumn
    case duplicateHeader(String)
    case tooManyRows(limit: Int)

    var errorDescription: String? {
        switch self {
        case .notUTF8:
            return "This file isn't UTF-8 text. Export it from your spreadsheet as \"CSV UTF-8\"."
        case .empty:
            return "This file is empty."
        case .missingTitleColumn:
            return "The first line must be a header with a \"title\" column (for example: title,episode,image,name)."
        case .duplicateHeader(let name):
            return "The header has the \"\(name)\" column twice."
        case .tooManyRows(let limit):
            return "A series can have up to \(limit) rows. Split the file and import it into separate series."
        }
    }
}

struct ThumbnailSeriesCSVResult: Equatable {
    var records: [ThumbnailSeriesCSVRecord] = []
    var recordErrors: [ThumbnailSeriesCSVRecordError] = []
    var ignoredColumns: [String] = []
    var fileError: ThumbnailSeriesCSVFileError?

    var totalRecordCount: Int { records.count + recordErrors.count }
}

enum ThumbnailSeriesCSVParser {
    static func parse(_ data: Data, rowLimit: Int = ThumbnailSeries.rowLimit) -> ThumbnailSeriesCSVResult {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            bytes = bytes.dropFirst(3)
        }
        guard let text = String(data: bytes, encoding: .utf8) else {
            return ThumbnailSeriesCSVResult(fileError: .notUTF8)
        }
        return parse(text, rowLimit: rowLimit)
    }

    static func parse(_ text: String, rowLimit: Int = ThumbnailSeries.rowLimit) -> ThumbnailSeriesCSVResult {
        var result = ThumbnailSeriesCSVResult()
        // Normalise line endings; line numbers are counted on the result.
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let characters = Array(normalized.unicodeScalars)

        var position = 0
        var line = 1
        var header: [ThumbnailSeriesCSVColumn?]?

        while position < characters.count {
            let startLine = line
            let recordStart = position
            let parsed = parseRecord(characters, from: position)
            if parsed.isBlank {
                position = parsed.nextPosition
                line += parsed.lineCount
                continue
            }

            if let failure = parsed.failure {
                // Resynchronise on the line after the one the record started on.
                if header == nil {
                    return ThumbnailSeriesCSVResult(fileError: .missingTitleColumn)
                }
                result.recordErrors.append(ThumbnailSeriesCSVRecordError(line: startLine, reason: failure))
                position = nextLineStart(characters, from: position)
                line = startLine + 1
                if result.totalRecordCount > rowLimit {
                    return ThumbnailSeriesCSVResult(fileError: .tooManyRows(limit: rowLimit))
                }
                continue
            }

            position = parsed.nextPosition
            line += parsed.lineCount

            guard let columns = header else {
                var seen = Set<ThumbnailSeriesCSVColumn>()
                var mapped: [ThumbnailSeriesCSVColumn?] = []
                for raw in parsed.fields {
                    let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if let column = ThumbnailSeriesCSVColumn(rawValue: key) {
                        if seen.contains(column) {
                            return ThumbnailSeriesCSVResult(fileError: .duplicateHeader(column.rawValue))
                        }
                        seen.insert(column)
                        mapped.append(column)
                    } else {
                        mapped.append(nil)
                        if !key.isEmpty { result.ignoredColumns.append(raw.trimmingCharacters(in: .whitespaces)) }
                    }
                }
                guard seen.contains(.title) else {
                    return ThumbnailSeriesCSVResult(fileError: .missingTitleColumn)
                }
                header = mapped
                continue
            }

            if parsed.fields.count != columns.count {
                result.recordErrors.append(
                    ThumbnailSeriesCSVRecordError(
                        line: startLine,
                        reason: "expected \(columns.count) fields but found \(parsed.fields.count)"
                    )
                )
                if parsed.lineCount > 1 {
                    // A quoted field swallowed later lines: re-read them.
                    position = nextLineStart(characters, from: recordStart)
                    line = startLine + 1
                }
            } else {
                var fields: [ThumbnailSeriesCSVColumn: String] = [:]
                for (column, value) in zip(columns, parsed.fields) {
                    guard let column else { continue }
                    fields[column] = value
                }
                result.records.append(ThumbnailSeriesCSVRecord(line: startLine, fields: fields))
            }

            if result.totalRecordCount > rowLimit {
                return ThumbnailSeriesCSVResult(fileError: .tooManyRows(limit: rowLimit))
            }
        }

        if header == nil {
            return ThumbnailSeriesCSVResult(fileError: .empty)
        }
        return result
    }

    // MARK: Record scanner

    private struct ParsedRecord {
        var fields: [String] = []
        var nextPosition: Int
        /// Line breaks consumed, including the terminating one.
        var lineCount: Int
        var failure: String?
        var isBlank: Bool
    }

    private static let quote: Unicode.Scalar = "\""
    private static let comma: Unicode.Scalar = ","
    private static let newline: Unicode.Scalar = "\n"

    private static func parseRecord(_ characters: [Unicode.Scalar], from start: Int) -> ParsedRecord {
        var fields: [String] = []
        var field = String.UnicodeScalarView()
        var index = start
        var lines = 0
        var inQuotes = false
        var fieldWasQuoted = false

        func finishField() {
            let value = String(field)
            fields.append(fieldWasQuoted ? value : value.trimmingCharacters(in: .whitespaces))
            field = String.UnicodeScalarView()
            fieldWasQuoted = false
        }

        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == quote {
                    let next = index + 1 < characters.count ? characters[index + 1] : nil
                    if next == quote {
                        field.append(quote)
                        index += 2
                        continue
                    }
                    inQuotes = false
                    index += 1
                    // After a closing quote only a separator or the end may follow.
                    var lookahead = index
                    while lookahead < characters.count, characters[lookahead] == " " || characters[lookahead] == "\t" {
                        lookahead += 1
                    }
                    if lookahead < characters.count,
                       characters[lookahead] != comma,
                       characters[lookahead] != newline {
                        return ParsedRecord(nextPosition: index, lineCount: lines, failure: "unexpected text after a closing quote (check for an unclosed quote)", isBlank: false)
                    }
                    index = lookahead
                    continue
                }
                if character == newline { lines += 1 }
                field.append(character)
                index += 1
                continue
            }

            switch character {
            case comma:
                finishField()
                index += 1
            case newline:
                finishField()
                lines += 1
                index += 1
                let blank = fields.count == 1 && fields[0].isEmpty
                return ParsedRecord(fields: fields, nextPosition: index, lineCount: lines, failure: nil, isBlank: blank)
            case quote where String(field).trimmingCharacters(in: .whitespaces).isEmpty:
                field = String.UnicodeScalarView()
                inQuotes = true
                fieldWasQuoted = true
                index += 1
            default:
                field.append(character)
                index += 1
            }
        }

        if inQuotes {
            return ParsedRecord(nextPosition: index, lineCount: lines, failure: "a quoted field is never closed", isBlank: false)
        }
        finishField()
        let blank = fields.count == 1 && fields[0].isEmpty
        return ParsedRecord(fields: fields, nextPosition: index, lineCount: lines, failure: nil, isBlank: blank)
    }

    private static func nextLineStart(_ characters: [Unicode.Scalar], from position: Int) -> Int {
        var index = position
        while index < characters.count, characters[index] != newline {
            index += 1
        }
        return min(index + 1, characters.count)
    }
}

// MARK: - Import / export

struct ThumbnailSeriesCSVImport: Equatable {
    var rows: [ThumbnailSeriesRow]
    var validCount: Int
    var errorCount: Int
    var ignoredColumns: [String]

    var summary: String {
        var parts = ["Imported \(rows.count) row\(rows.count == 1 ? "" : "s")"]
        if errorCount > 0 { parts.append("\(errorCount) need fixing") }
        if !ignoredColumns.isEmpty { parts.append("ignored columns: \(ignoredColumns.joined(separator: ", "))") }
        return parts.joined(separator: " · ")
    }
}

enum ThumbnailSeriesCSVImporter {
    /// Maps records to rows in file order. Malformed records become rows that
    /// carry the error (with the line number) so they can be fixed in place.
    /// `images` maps lowercased original file names to already-added images.
    static func rows(
        from result: ThumbnailSeriesCSVResult,
        images: [String: ThumbnailSeriesImageRef] = [:],
        idProvider: () -> UUID = UUID.init
    ) -> ThumbnailSeriesCSVImport {
        var entries: [(line: Int, row: ThumbnailSeriesRow)] = []
        for record in result.records {
            let title = record.fields[.title] ?? ""
            let episode = record.fields[.episode].flatMap { $0.isEmpty ? nil : $0 }
            let imageName = record.fields[.image].flatMap { $0.isEmpty ? nil : $0 }
            let name = record.fields[.name].flatMap { $0.isEmpty ? nil : $0 }
            let ref = imageName.flatMap { images[$0.lowercased()] }
            entries.append((record.line, ThumbnailSeriesRow(
                id: idProvider(),
                title: title,
                episode: episode,
                imageRef: ref,
                requestedImageName: ref == nil ? imageName : nil,
                outputName: name,
                sourceLine: record.line
            )))
        }
        for error in result.recordErrors {
            entries.append((error.line, ThumbnailSeriesRow(
                id: idProvider(),
                title: "",
                sourceLine: error.line,
                importError: error.reason
            )))
        }
        let rows = entries.sorted { $0.line < $1.line }.map(\.row)
        return ThumbnailSeriesCSVImport(
            rows: rows,
            validCount: result.records.count,
            errorCount: result.recordErrors.count,
            ignoredColumns: result.ignoredColumns
        )
    }
}

enum ThumbnailSeriesCSVWriter {
    static let header = "title,episode,image,name"

    static func csv(for rows: [ThumbnailSeriesRow]) -> String {
        var lines = [header]
        for row in rows {
            let image = row.imageRef?.originalFileName ?? row.requestedImageName ?? ""
            lines.append([row.title, row.episode ?? "", image, row.outputName ?? ""].map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func escape(_ value: String) -> String {
        let needsQuotes = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
            || value != value.trimmingCharacters(in: .whitespaces)
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static let sample = """
    title,episode,image,name
    How I Edit Thumbnails,1,episode-01.jpg,
    "Lighting, Explained",2,episode-02.jpg,
    "The ""Perfect"" Setup",3,,setup-special
    """
}
