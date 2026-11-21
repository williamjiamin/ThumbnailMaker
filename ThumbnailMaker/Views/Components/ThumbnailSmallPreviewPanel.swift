//
//  ThumbnailSmallPreviewPanel.swift
//  ThumbnailMaker
//

import SwiftUI

struct ThumbnailSmallPreviewPanel<PreviewContent: View>: View {
    let aspectRatio: AspectRatio
    let isVisible: Bool
    let accessibilitySummary: String?
    @ViewBuilder let previewContent: (CGSize) -> PreviewContent

    init(
        aspectRatio: AspectRatio,
        isVisible: Bool,
        accessibilitySummary: String? = nil,
        @ViewBuilder previewContent: @escaping (CGSize) -> PreviewContent
    ) {
        self.aspectRatio = aspectRatio
        self.isVisible = isVisible
        self.accessibilitySummary = accessibilitySummary
        self.previewContent = previewContent
    }

    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "eye")
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)
                    Text("Small Preview")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                }

                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(ThumbnailSmallPreviewSize.all) { previewSize in
                        let size = previewSize.size(for: aspectRatio)

                        // APP-07: each tile (artwork + caption) is one element
                        // that speaks the caption and the visible title, so no
                        // visible text is left out of the accessibility tree.
                        VStack(alignment: .leading, spacing: 6) {
                            // The artwork's own text elements are replaced by
                            // the tile's label, which already says the title.
                            previewContent(size)
                                .accessibilityRepresentation { Color.clear }
                                .frame(width: size.width, height: size.height)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                )

                            Text(previewSize.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityLabel(for: previewSize.name))
                        .accessibilityValue("\(Int(size.width)) by \(Int(size.height)) points")
                        .accessibilityHint("Use this preview to judge readability at a smaller viewing size.")
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("smallPreviewPanel")
        }
    }

    private func accessibilityLabel(for previewName: String) -> String {
        guard let summary = accessibilitySummary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty else {
            return "\(previewName) thumbnail preview"
        }

        return "\(previewName) thumbnail preview, \(summary)"
    }
}
