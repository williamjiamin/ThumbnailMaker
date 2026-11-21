//
//  ArrangePanelView.swift
//  ThumbnailMaker
//
//  FEATURE-07: the arrange panel under the layer strip in both editors.
//  Multi-select, select all, group / ungroup, align (to selection or canvas),
//  distribute and nudge. Every button is also the accessible, keyboard-
//  reachable alternative to dragging on the canvas.
//

import SwiftUI
import UIKit

struct ArrangePanelView<Editor: ThumbnailArrangeEditing & ObservableObject>: View {
    @ObservedObject var editor: Editor
    @Binding var state: ThumbnailArrangeUIState
    @Binding var primary: ThumbnailLayerSelection
    /// APP-08: when set (compact phone layout), the panel collapses to its
    /// header so the layer strip and inspector stay close to the canvas.
    var isExpanded: Binding<Bool>? = nil
    @ScaledMetric(relativeTo: .body) private var controlSize: CGFloat = 44

    private var selectable: [ThumbnailLayerSelection] {
        editor.selectableLayerSelections
    }

    private var targets: [ThumbnailLayerSelection] {
        state.effectiveSelection(primary: primary, selectable: selectable)
    }

    var body: some View {
        if !selectable.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                header
                if showsTools {
                    Text(editor.arrangeSummary(for: targets))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("arrangeSelectionSummary")

                    if state.isMultiSelectMode {
                        multiSelectRow
                    }
                    groupRow
                    alignGrid
                    distributeAndNudgeRow

                    if let message = state.lastAnnouncement {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("arrangeAnnouncement")
                    }
                }
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("arrangePanel")
            .onChange(of: selectable) { _, newValue in
                let pruned = state.selection.pruned(to: newValue)
                if pruned != state.selection {
                    state.selection = pruned
                }
            }
        }
    }

    private var showsTools: Bool {
        isExpanded?.wrappedValue ?? true
    }

    @ViewBuilder
    private var header: some View {
        if let isExpanded {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.snappy) {
                        isExpanded.wrappedValue.toggle()
                    }
                    // A hidden multi-select mode would silently change what
                    // tapping the layer strip does.
                    if !isExpanded.wrappedValue {
                        state.isMultiSelectMode = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        headerTitle
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90))
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("arrangePanelToggle")
                .accessibilityLabel("Arrange")
                .accessibilityValue(ThumbnailAccessibilityText.disclosureValue(
                    isExpanded: isExpanded.wrappedValue,
                    summary: nil
                ))
                .accessibilityHint("Shows group, align, distribute and nudge tools.")

                if isExpanded.wrappedValue {
                    multiSelectToggle
                }
            }
        } else {
            HStack(spacing: 8) {
                headerTitle
                Spacer()
                multiSelectToggle
            }
        }
    }

    private var headerTitle: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.on.square.dashed")
                .font(.headline)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Arrange")
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var multiSelectToggle: some View {
            Toggle(isOn: Binding(
                get: { state.isMultiSelectMode },
                set: { isOn in
                    state.isMultiSelectMode = isOn
                    if isOn, state.selection.isEmpty, selectable.contains(primary) {
                        state.selection.replace(with: [primary])
                    }
                }
            )) {
                Text("Multi-select")
                    .minimumHitTarget()
            }
            .toggleStyle(.button)
            .font(.subheadline.weight(.semibold))
            .accessibilityIdentifier("arrangeMultiSelectToggle")
            .accessibilityHint("When on, tapping layers in the strip adds or removes them from the selection.")
    }

    private var multiSelectRow: some View {
        HStack(spacing: 8) {
            Button("Select All") {
                state.selection.replace(with: selectable)
                announce("Selected \(selectable.count) layers.")
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .accessibilityIdentifier("arrangeSelectAllButton")

            Button("Clear") {
                state.selection.removeAll()
                announce("Selection cleared.")
            }
            .disabled(state.selection.isEmpty)
            .accessibilityIdentifier("arrangeClearSelectionButton")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .font(.subheadline)
    }

    private var groupRow: some View {
        HStack(spacing: 8) {
            Button {
                run { editor.groupSelection(targets) }
            } label: {
                Label("Group", systemImage: "square.on.square")
            }
            .disabled(!editor.canGroup(targets))
            .keyboardShortcut("g", modifiers: .command)
            .accessibilityIdentifier("arrangeGroupButton")
            .accessibilityHint(editor.canGroup(targets)
                ? "Groups the selected layers so they move together."
                : "Turn on Multi-select and pick two or more layers.")

            Button {
                run { editor.ungroupSelection(targets) }
            } label: {
                Label("Ungroup", systemImage: "square.dashed")
            }
            .disabled(!editor.canUngroup(targets))
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .accessibilityIdentifier("arrangeUngroupButton")

            Spacer(minLength: 0)

            Picker("Align to", selection: $state.alignReference) {
                ForEach(ThumbnailAlignReference.allCases) { reference in
                    Text(reference.title).tag(reference)
                }
            }
            .pickerStyle(.menu)
            .frame(minHeight: 44)
            .accessibilityIdentifier("arrangeAlignReferencePicker")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .font(.subheadline)
    }

    private var alignGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: controlSize), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(ThumbnailAlignEdge.allCases) { edge in
                iconButton(edge.systemImage, label: edge.title, identifier: edge.accessibilityIdentifier) {
                    run { editor.alignSelection(targets, edge: edge, reference: state.alignReference) }
                }
                .modifier(AlignShortcut(edge: edge))
            }
        }
    }

    private var distributeAndNudgeRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: controlSize), spacing: 8)], alignment: .leading, spacing: 8) {
            iconButton(
                "distribute.horizontal.center",
                label: ThumbnailDistributeMode.horizontalSpacing.title,
                identifier: "arrangeDistributeHorizontal"
            ) {
                run { editor.distributeSelection(targets, mode: .horizontalSpacing) }
            }
            iconButton(
                "distribute.vertical.center",
                label: ThumbnailDistributeMode.verticalSpacing.title,
                identifier: "arrangeDistributeVertical"
            ) {
                run { editor.distributeSelection(targets, mode: .verticalSpacing) }
            }
            iconButton("arrow.left", label: "Move left", identifier: "arrangeNudgeLeft") {
                run { editor.nudgeSelection(targets, dx: -Editor.arrangeNudgeStep, dy: 0) }
            }
            iconButton("arrow.right", label: "Move right", identifier: "arrangeNudgeRight") {
                run { editor.nudgeSelection(targets, dx: Editor.arrangeNudgeStep, dy: 0) }
            }
            iconButton("arrow.up", label: "Move up", identifier: "arrangeNudgeUp") {
                run { editor.nudgeSelection(targets, dx: 0, dy: -Editor.arrangeNudgeStep) }
            }
            iconButton("arrow.down", label: "Move down", identifier: "arrangeNudgeDown") {
                run { editor.nudgeSelection(targets, dx: 0, dy: Editor.arrangeNudgeStep) }
            }
        }
    }

    private func iconButton(
        _ systemName: String,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .frame(width: controlSize, height: controlSize)
                .background(Color(uiColor: .tertiarySystemBackground))
                .clipShape(Circle())
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .disabled(targets.isEmpty)
        .opacity(targets.isEmpty ? 0.38 : 1)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
        .help(label)
    }

    private func run(_ command: () -> ThumbnailArrangeResult) {
        announce(command().announcement)
    }

    private func announce(_ message: String) {
        state.lastAnnouncement = message
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

/// Option-Command-arrow aligns to the matching edge.
private struct AlignShortcut: ViewModifier {
    let edge: ThumbnailAlignEdge

    func body(content: Content) -> some View {
        switch edge {
        case .left: content.keyboardShortcut(.leftArrow, modifiers: [.command, .option])
        case .right: content.keyboardShortcut(.rightArrow, modifiers: [.command, .option])
        case .top: content.keyboardShortcut(.upArrow, modifiers: [.command, .option])
        case .bottom: content.keyboardShortcut(.downArrow, modifiers: [.command, .option])
        case .horizontalCenter, .verticalCenter: content
        }
    }
}
