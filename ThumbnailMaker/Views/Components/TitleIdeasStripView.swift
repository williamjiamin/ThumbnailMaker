//
//  TitleIdeasStripView.swift
//  ThumbnailMaker
//

import SwiftUI

struct TitleIdeasStripView: View {
    let ideas: [ThumbnailIdea]
    let applyIdea: (ThumbnailIdea) -> Void

    var body: some View {
        if !ideas.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Ideas for your title", systemImage: "wand.and.stars")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("titleIdeasLabel")

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(ideas) { idea in
                            ideaButton(idea)
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .accessibilityIdentifier("titleIdeasStrip")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .contain)
        }
    }

    private func ideaButton(_ idea: ThumbnailIdea) -> some View {
        Button(action: {
            applyIdea(idea)
        }) {
            TitleIdeaCardContent(idea: idea, iconName: iconName(for: idea.kind))
        }
        .buttonStyle(.plain)
        .background(Color(uiColor: .tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier("ideaCard-\(idea.id)")
        .accessibilityLabel(idea.headline)
        .accessibilityHint(idea.rationale)
    }

    private func iconName(for kind: ThumbnailIdeaKind) -> String {
        switch kind {
        case .layout:
            return "rectangle.3.group"
        case .style:
            return "textformat"
        case .color:
            return "paintpalette"
        }
    }
}

private struct TitleIdeaCardContent: View {
    let idea: ThumbnailIdea
    let iconName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.purple)
                    .accessibilityHidden(true)

                Text(idea.headline)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Text(idea.rationale)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .padding(10)
        .frame(width: 220, alignment: .topLeading)
        .frame(minHeight: 96, alignment: .topLeading)
        .contentShape(Rectangle())
    }
}

#Preview {
    TitleIdeasStripView(
        ideas: LocalThumbnailIdeaProvider().ideas(
            forTitle: "How I grew my channel",
            ratio: .ratio16_9,
            brandKit: BrandKit.defaultCreatorKit(),
            templates: ThumbnailTemplate.builtIns
        ),
        applyIdea: { _ in }
    )
    .padding()
}
