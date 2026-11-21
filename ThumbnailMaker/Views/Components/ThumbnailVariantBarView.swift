//
//  ThumbnailVariantBarView.swift
//  ThumbnailMaker
//
//  FEATURE-02: A/B/C variant chips. Pure presentation: takes the set plus
//  closures, like `LayerSelectionStripView`.
//

import SwiftUI

struct ThumbnailVariantBarView: View {
    let variantSet: ThumbnailVariantSet
    var isDisabled = false
    let select: (ThumbnailVariantSlot) -> Void
    let duplicate: () -> Void
    let compare: () -> Void
    let rename: (ThumbnailVariantSlot, String) -> Void
    let setPreferred: (ThumbnailVariantSlot?) -> Void
    let remove: (ThumbnailVariantSlot) -> Void
    /// FEATURE-10: opens the batch export queue. Hidden when nil.
    var exportAll: (() -> Void)? = nil

    @State private var renamingSlot: ThumbnailVariantSlot?
    @State private var renameText = ""
    @State private var pendingRemoval: ThumbnailVariantSlot?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var headerLayout: AnyLayout {
        dynamicTypeSize >= .xxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // APP-07/08: title and buttons share a row at standard sizes and
            // stack at large ones. AnyLayout keeps the same views (no titles
            // swapped out or hidden) while the arrangement changes.
            headerLayout {
                headerTitle
                    .frame(maxWidth: .infinity, alignment: .leading)
                headerButtons(stacked: dynamicTypeSize.isAccessibilitySize)
            }

            if let exportAll { // FEATURE-10
                Button(action: exportAll) {
                    Label("Export All…", systemImage: "square.and.arrow.up.on.square")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .disabled(isDisabled)
                .accessibilityIdentifier("variantExportAllButton")
                .accessibilityHint("Exports every variant at several sizes in one go, after a review.")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(variantSet.variants) { variant in
                        chip(for: variant)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("variantBar")
        .alert(
            "Rename Variant",
            isPresented: Binding(
                get: { renamingSlot != nil },
                set: { if !$0 { renamingSlot = nil } }
            )
        ) {
            TextField("Name", text: $renameText)
                .accessibilityIdentifier("variantRenameField")
            Button("Save") {
                if let slot = renamingSlot {
                    rename(slot, renameText)
                }
                renamingSlot = nil
            }
            Button("Cancel", role: .cancel) {
                renamingSlot = nil
            }
        }
        .confirmationDialog(
            "Delete this variant?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Variant", role: .destructive) {
                if let slot = pendingRemoval {
                    remove(slot)
                }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRemoval = nil
            }
        } message: {
            Text("The other variants keep their letters and are not changed.")
        }
    }

    private var headerTitle: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.on.square")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Variants")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func headerButtons(stacked: Bool) -> some View {
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            Button(action: compare) {
                headerLabel("Compare", systemImage: "rectangle.split.3x1")
            }
            .disabled(isDisabled || !variantSet.canCompare)
            .accessibilityIdentifier("variantCompareButton")
            .accessibilityHint("Shows every variant side by side at the same small size.")

            Button(action: duplicate) {
                headerLabel("Duplicate", systemImage: "plus.square.on.square")
            }
            .disabled(isDisabled || !variantSet.canAddVariant)
            .accessibilityIdentifier("variantDuplicateButton")
            .accessibilityHint(
                variantSet.canAddVariant
                    ? "Copies the current variant into a new one."
                    : "A design can have at most three variants."
            )
        }
    }

    private func headerLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
    }

    private func chip(for variant: ThumbnailVariant) -> some View {
        let isActive = variant.slot == variantSet.activeSlot
        let isPreferred = variant.slot == variantSet.preferredSlot

        return Button {
            select(variant.slot)
        } label: {
            HStack(spacing: 6) {
                Text(variant.slot.displayLetter)
                    .font(.subheadline.weight(.bold))
                    .frame(width: 22, height: 22)
                    .background(isActive ? Color.white.opacity(0.25) : Color.blue.opacity(0.15))
                    .clipShape(Circle())
                Text(variant.name)
                    .font(.subheadline)
                    .lineLimit(1)
                if isPreferred {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .background(isActive ? Color.blue : Color(uiColor: .tertiarySystemBackground))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .contextMenu {
            Button {
                renameText = variant.name
                renamingSlot = variant.slot
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button {
                setPreferred(isPreferred ? nil : variant.slot)
            } label: {
                Label(
                    isPreferred ? "Clear Preferred" : "Mark as Preferred (your pick)",
                    systemImage: isPreferred ? "star.slash" : "star"
                )
            }
            .accessibilityIdentifier("variantPreferredToggle_\(variant.slot.rawValue)")

            if variantSet.variants.count > 1 {
                Button(role: .destructive) {
                    pendingRemoval = variant.slot
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .accessibilityIdentifier("variantChip_\(variant.slot.rawValue)")
        .accessibilityLabel(Self.chipAccessibilityLabel(for: variant))
        .accessibilityValue(chipAccessibilityValue(isActive: isActive, isPreferred: isPreferred))
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityAction(named: isPreferred ? "Clear preferred" : "Mark as preferred") {
            setPreferred(isPreferred ? nil : variant.slot)
        }
        .accessibilityAction(named: "Rename") {
            renameText = variant.name
            renamingSlot = variant.slot
        }
    }

    /// "Variant B" rather than "Variant B, variant B" for unrenamed variants.
    static func chipAccessibilityLabel(for variant: ThumbnailVariant) -> String {
        let letterName = "variant \(variant.slot.displayLetter)"
        if variant.name.caseInsensitiveCompare(letterName) == .orderedSame {
            return variant.name
        }
        return "\(variant.name), \(letterName)"
    }

    private func chipAccessibilityValue(isActive: Bool, isPreferred: Bool) -> String {
        var parts: [String] = []
        if isActive { parts.append("Editing") }
        if isPreferred { parts.append("Preferred, your pick") }
        return parts.joined(separator: ", ")
    }
}

/// FEATURE-02 warning shown after a variant operation. Stays outside any
/// collapsed section so the feedback is never hidden (APP-08), with a 44 pt
/// Dismiss target (APP-07).
struct VariantWarningBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Dismiss", action: dismiss)
                .font(.footnote)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityIdentifier("variantWarningDismissButton")
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("variantWarning")
    }
}
