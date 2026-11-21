//
//  ThumbnailSeriesCSVHelpView.swift
//  ThumbnailMaker
//
//  FEATURE-15: the CSV format, in the app (mirrors docs/SERIES_CSV.md).
//

import SwiftUI
import UIKit

struct ThumbnailSeriesCSVHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section("Columns") {
                    row("title", "Required. Replaces the headline, or fills {title} in the design's text.")
                    row("episode", "Optional. Fills {episode} (text layers and badge labels).")
                    row("image", "Optional. A file name; add the image files after importing and they're matched by name (case doesn't matter).")
                    row("name", "Optional. The output file name. Defaults to <series>-<episode or row number>.")
                }
                Section("Rules") {
                    Text("The first line must be the header. Column order and letter case don't matter; other columns are ignored.")
                    Text("UTF-8, comma separated. Put a value in double quotes if it has a comma, a quote or a line break, and write a quote inside quotes as \"\".")
                    Text("Up to \(ThumbnailSeries.rowLimit) rows. A broken line is kept as a row that shows its line number, so you can fix it here; every other line imports normally.")
                }
                Section("Sample") {
                    Text(ThumbnailSeriesCSVWriter.sample)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Button(copied ? "Copied" : "Copy Sample CSV") {
                        UIPasteboard.general.string = ThumbnailSeriesCSVWriter.sample
                        copied = true
                    }
                    .accessibilityIdentifier("seriesCopySampleButton")
                }
            }
            .navigationTitle("CSV Format")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    SheetToolbarButton(.done) { dismiss() }
                }
            }
        }
    }

    private func row(_ name: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.body.monospaced().weight(.semibold))
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
    }
}
