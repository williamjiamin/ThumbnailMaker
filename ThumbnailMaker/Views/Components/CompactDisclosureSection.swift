//
//  CompactDisclosureSection.swift
//  ThumbnailMaker
//
//  APP-08: a collapsible card for secondary editor sections on compact
//  width. The header is a single 44 pt button that speaks its expanded state
//  and a short summary of what is inside.
//

import SwiftUI

struct CompactDisclosureSection<Content: View>: View {
    let title: String
    let systemImage: String
    var summary: String?
    /// Container identifier; the header button is "<identifier>Toggle".
    let identifier: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.headline)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let summary, !isExpanded {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(Color.accessibleSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(ThumbnailAccessibilityText.disclosureValue(isExpanded: isExpanded, summary: summary))
            .accessibilityAddTraits([.isButton, .isHeader])
            .accessibilityHint(isExpanded ? "Collapses this section." : "Expands this section.")
            .accessibilityIdentifier("\(identifier)Toggle")

            if isExpanded {
                content()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
