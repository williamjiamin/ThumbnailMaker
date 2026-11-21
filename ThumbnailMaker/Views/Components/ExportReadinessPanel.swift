//
//  ExportReadinessPanel.swift
//  ThumbnailMaker
//

import SwiftUI

struct ExportReadinessPanel: View {
    let report: ThumbnailExportReport?
    let readinessReport: ThumbnailReadinessReport
    let isChecking: Bool
    let canCheckSize: Bool
    let suggestions: [ThumbnailSuggestion]
    let applySuggestion: (ThumbnailSuggestion) -> Void
    let checkSize: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label("Export Size", systemImage: "gauge.with.dots.needle.50percent")
                    .font(.headline)

                Spacer()

                Button {
                    checkSize()
                } label: {
                    HStack(spacing: 6) {
                        if isChecking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(isChecking ? "Checking" : "Check")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isChecking || !canCheckSize)
                .accessibilityIdentifier("checkExportSizeButton")
                .accessibilityLabel(isChecking ? "Checking export size" : "Check export size")
                .accessibilityHint(
                    canCheckSize
                        ? "Renders the thumbnail and reports its encoded upload file size."
                        : "Add an image before checking export size."
                )
            }

            if let report {
                Label(
                    "\(report.options.format.displayName) · \(report.fileSize.formatted)",
                    systemImage: "doc"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("exportFileSizeLabel")
                .accessibilityLabel("Export file size")
                .accessibilityValue("\(report.options.format.displayName), \(report.fileSize.formatted)")

                ForEach(report.validationMessages) { message in
                    Label {
                        Text(message.message)
                            .font(.footnote)
                    } icon: {
                        Image(systemName: iconName(for: message.severity))
                            .foregroundStyle(color(for: message.severity))
                    }
                    .foregroundStyle(message.severity == .warning ? Color.primary : Color.secondary)
                    .accessibilityLabel("\(accessibilityPrefix(for: message.severity)): \(message.message)")
                }
            } else {
                Text("Check the encoded file size before upload or Files export.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Label(
                "Creator Readiness · \(readinessReport.displayScore)",
                systemImage: readinessReport.hasWarnings ? "exclamationmark.triangle" : "checkmark.seal"
            )
            .font(.subheadline.weight(.semibold))
            .accessibilityIdentifier("creatorReadinessLabel")
            .accessibilityLabel("Creator readiness")
            .accessibilityValue(readinessReport.displayScore)

            ForEach(readinessReport.findings) { finding in
                Label {
                    Text(finding.message)
                        .font(.footnote)
                } icon: {
                    Image(systemName: iconName(for: finding.severity))
                        .foregroundStyle(color(for: finding.severity))
                }
                .foregroundStyle(finding.severity == .warning ? Color.primary : Color.secondary)
                .accessibilityLabel("\(accessibilityPrefix(for: finding.severity)): \(finding.message)")
            }

            if !suggestions.isEmpty {
                Divider()

                Label("Suggestions", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("creatorSuggestionsLabel")

                ForEach(suggestions) { suggestion in
                    Button {
                        applySuggestion(suggestion)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: iconName(for: suggestion.kind))
                                .font(.callout.weight(.semibold))
                                .frame(width: 24, height: 24)
                                .foregroundStyle(.blue)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(suggestion.title)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Color.primary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(1)

                                Text(suggestion.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                            }
                        }
                        .padding(10)
                        .frame(minHeight: 44)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(Color(uiColor: .tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 1)
                    )
                    .accessibilityIdentifier("suggestionButton-\(suggestion.id)")
                    .accessibilityLabel(suggestion.title)
                    .accessibilityHint(suggestion.detail)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("exportReadinessPanel")
    }

    private func iconName(for severity: ThumbnailExportValidationSeverity) -> String {
        switch severity {
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        }
    }

    private func iconName(for kind: ThumbnailSuggestionKind) -> String {
        switch kind {
        case .text:
            return "textformat.size"
        case .contrast:
            return "circle.lefthalf.filled"
        case .crop:
            return "crop"
        case .template:
            return "square.grid.2x2"
        case .brand:
            return "paintpalette"
        }
    }

    private func color(for severity: ThumbnailExportValidationSeverity) -> Color {
        switch severity {
        case .success:
            return .green
        case .warning:
            return .orange
        }
    }

    private func accessibilityPrefix(for severity: ThumbnailExportValidationSeverity) -> String {
        switch severity {
        case .success:
            return "OK"
        case .warning:
            return "Warning"
        }
    }
}

#Preview {
    ExportReadinessPanel(
        report: ThumbnailExportReport(byteCount: 1_200_000, options: ThumbnailExportOptions()),
        readinessReport: ThumbnailReadinessAnalyzer.analyze(SimpleMakerConfigurationModel()),
        isChecking: false,
        canCheckSize: false,
        suggestions: [
            ThumbnailSuggestion(
                id: "text-shorten-dense-title",
                kind: .text,
                title: "Shorten the title",
                detail: "Dense thumbnail text is hard to read in mobile previews.",
                action: .shortenText
            )
        ],
        applySuggestion: { _ in },
        checkSize: {}
    )
    .padding()
}
