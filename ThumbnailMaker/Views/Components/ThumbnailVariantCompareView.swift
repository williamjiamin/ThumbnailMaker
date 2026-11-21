//
//  ThumbnailVariantCompareView.swift
//  ThumbnailMaker
//
//  FEATURE-02: 2-3 variants side by side, every pane at one identical size.
//  Editor-agnostic: the host renders each pane's document.
//
//  This view makes no claim about which variant will perform better. The only
//  "preferred" marker is the user's own pick.
//

import SwiftUI

struct ThumbnailVariantCompareView<PaneContent: View>: View {
    let makeComparison: (ThumbnailSmallPreviewSize) -> ThumbnailVariantComparison?
    let readinessNote: String?
    let setPreferred: (ThumbnailVariantSlot?) -> Void
    let edit: (ThumbnailVariantSlot) -> Void
    @ViewBuilder let paneContent: (ThumbnailVariantComparison.Pane, CGSize) -> PaneContent

    @Environment(\.dismiss) private var dismiss
    @State private var previewSizeID = ThumbnailSmallPreviewSize.search.id

    private var sizeOptions: some View {
        ForEach(ThumbnailSmallPreviewSize.all) { size in
            Text("\(size.name) (\(Int(size.width)) pt)").tag(size.id)
        }
    }

    private var previewSize: ThumbnailSmallPreviewSize {
        ThumbnailSmallPreviewSize.all.first { $0.id == previewSizeID } ?? .search
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Preview size", selection: $previewSizeID) {
                        sizeOptions
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("variantCompareSizePicker")

                    if let comparison = makeComparison(previewSize) {
                        panes(for: comparison)
                    } else {
                        Text("Add a second variant to compare.")
                            .foregroundStyle(.secondary)
                    }

                    if let readinessNote {
                        Label(readinessNote, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Compare Variants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    SheetToolbarButton(.done) { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("variantCompareSheet")
    }

    static func artworkLabel(for pane: ThumbnailVariantComparison.Pane) -> String {
        let title = pane.document.text.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = "Variant \(pane.slot.displayLetter) preview"
        return title.isEmpty ? base : "\(base), title: \(title)"
    }

    private func panes(for comparison: ThumbnailVariantComparison) -> some View {
        let size = comparison.renderSize
        let columns = [GridItem(.adaptive(minimum: max(size.width, 96) + 8), spacing: 16, alignment: .top)]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(comparison.panes) { pane in
                VStack(alignment: .leading, spacing: 6) {
                    // APP-07: the artwork is one labelled image; its own
                    // canvas text elements are replaced by that label.
                    paneContent(pane, size)
                        .accessibilityRepresentation { Color.clear }
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(pane.isActive ? Color.blue : Color.primary.opacity(0.12), lineWidth: pane.isActive ? 2 : 1)
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Self.artworkLabel(for: pane))
                        .accessibilityAddTraits(.isImage)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(pane.slot.displayLetter) · \(pane.name)")
                            .font(.caption.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        if pane.isPreferred {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                        }
                    }

                    if let note = pane.aspectRatioNote {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Stacked so each action keeps a full 44 pt target and its
                    // title can wrap at large text sizes.
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            setPreferred(pane.isPreferred ? nil : pane.slot)
                        } label: {
                            Text(pane.isPreferred ? "Your pick" : "Mark preferred")
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                                .minimumHitTarget(alignment: .leading)
                        }
                        .accessibilityAddTraits(pane.isPreferred ? .isSelected : [])
                        .accessibilityIdentifier("variantComparePreferred_\(pane.slot.rawValue)")

                        if !pane.isActive {
                            Button {
                                edit(pane.slot)
                                dismiss()
                            } label: {
                                Text("Edit")
                                    .font(.caption)
                                    .minimumHitTarget(alignment: .leading)
                            }
                            .accessibilityLabel("Edit variant \(pane.slot.displayLetter)")
                            .accessibilityIdentifier("variantCompareEdit_\(pane.slot.rawValue)")
                        }
                    }
                }
                .frame(width: max(size.width, 96), alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Variant \(pane.slot.displayLetter), \(pane.name)\(pane.isPreferred ? ", preferred, your pick" : "")")
                .accessibilityValue("\(Int(size.width)) by \(Int(size.height)) points")
                .accessibilityIdentifier("variantComparePane_\(pane.slot.rawValue)")
            }
        }
    }
}
