//
//  ThumbnailArrangeEditing.swift
//  ThumbnailMaker
//
//  FEATURE-07: history-safe arrange commands (group, ungroup, align,
//  distribute, nudge) shared by both editors through a small protocol, in the
//  same style as FEATURE-12's ThumbnailShapeCalloutEditing: no private
//  view-model access and no edits to the view-model files.
//
//  Every command is DISCRETE: it settles any pending debounced edit, applies
//  the change in one assignment, then settles again, so one command is exactly
//  one undo step, and a command that changes nothing records no history.
//

import CoreGraphics
import Foundation

@MainActor
protocol ThumbnailArrangeEditing: AnyObject {
    associatedtype ArrangeConfiguration: ThumbnailArrangeableConfiguration
    var arrangeConfiguration: ArrangeConfiguration { get set }
    var selectableLayerSelections: [ThumbnailLayerSelection] { get }
    func commitEditorStateNow()
}

extension ThumbnailArrangeEditing {
    /// Arrow-key / button nudge steps, in normalized canvas units.
    static var arrangeNudgeStep: CGFloat { 0.01 }
    static var arrangeLargeNudgeStep: CGFloat { 0.1 }

    /// Runs `body` on a copy; assigns it (as one undo step) only if the
    /// layers or overlay positions actually changed.
    @discardableResult
    func performArrangeMutation(
        _ body: (inout ArrangeConfiguration) -> ThumbnailArrangeResult
    ) -> ThumbnailArrangeResult {
        let current = arrangeConfiguration
        var next = current
        var result = body(&next)
        next.layers = next.layers.normalizedGroups()

        let changed = next.layers != current.layers
            || next.textTransform != current.textTransform
            || next.arrangeProfileTransform != current.arrangeProfileTransform
        guard changed else {
            result.applied = false
            return result
        }
        commitEditorStateNow()
        arrangeConfiguration = next
        commitEditorStateNow()
        result.applied = true
        return result
    }

    // MARK: Groups

    /// Whether the selection (expanded to groups) could form a new group.
    func canGroup(_ selections: [ThumbnailLayerSelection]) -> Bool {
        var probe = arrangeConfiguration.reconciledArrangeLayers
        return probe.group(layerIDs: selections.map(\.documentLayerID), newGroupID: "probe") != nil
    }

    func canUngroup(_ selections: [ThumbnailLayerSelection]) -> Bool {
        selections.contains { arrangeConfiguration.layers.groupID(for: $0) != nil }
    }

    @discardableResult
    func groupSelection(_ selections: [ThumbnailLayerSelection]) -> ThumbnailArrangeResult {
        performArrangeMutation { configuration in
            // The text/profile singletons may not have a record yet.
            var layers = configuration.reconciledArrangeLayers
            guard let groupID = layers.group(layerIDs: selections.map(\.documentLayerID)) else {
                return .none("Select two or more layers that are not already one group.")
            }
            configuration.layers = layers
            let name = configuration.layers.groupDisplayName(for: groupID) ?? "Group"
            let count = configuration.layers.memberIDs(ofGroup: groupID).count
            return ThumbnailArrangeResult(applied: true, skippedCount: 0, announcement: "Grouped \(count) layers as \(name).")
        }
    }

    @discardableResult
    func ungroupSelection(_ selections: [ThumbnailLayerSelection]) -> ThumbnailArrangeResult {
        performArrangeMutation { configuration in
            let groupIDs = Set(selections.compactMap { configuration.layers.groupID(for: $0) })
            guard !groupIDs.isEmpty else {
                return .none("The selection is not grouped.")
            }
            groupIDs.forEach { configuration.layers.ungroup(groupID: $0) }
            return ThumbnailArrangeResult(
                applied: true,
                skippedCount: 0,
                announcement: groupIDs.count == 1 ? "Ungrouped." : "Ungrouped \(groupIDs.count) groups."
            )
        }
    }

    // MARK: Align, distribute, nudge

    @discardableResult
    func alignSelection(
        _ selections: [ThumbnailLayerSelection],
        edge: ThumbnailAlignEdge,
        reference: ThumbnailAlignReference
    ) -> ThumbnailArrangeResult {
        performArrangeMutation { $0.align(selections, edge: edge, reference: reference) }
    }

    @discardableResult
    func distributeSelection(
        _ selections: [ThumbnailLayerSelection],
        mode: ThumbnailDistributeMode
    ) -> ThumbnailArrangeResult {
        performArrangeMutation { $0.distribute(selections, mode: mode) }
    }

    @discardableResult
    func nudgeSelection(_ selections: [ThumbnailLayerSelection], dx: CGFloat, dy: CGFloat) -> ThumbnailArrangeResult {
        performArrangeMutation { $0.nudge(selections, by: CGVector(dx: dx, dy: dy)) }
    }

    /// Selection summary for the arrange panel, e.g. "3 layers, 1 group, 1 locked skipped".
    func arrangeSummary(for selections: [ThumbnailLayerSelection]) -> String {
        let configuration = arrangeConfiguration
        let plan = configuration.arrangePlan(for: selections)
        let layerCount = plan.units.reduce(0) { $0 + $1.members.count }
        let groupCount = plan.units.filter { $0.members.count > 1 }.count
        var parts = ["\(layerCount) \(layerCount == 1 ? "layer" : "layers")"]
        if groupCount > 0 {
            parts.append("\(groupCount) \(groupCount == 1 ? "group" : "groups")")
        }
        if !plan.skipped.isEmpty {
            parts.append("\(plan.skipped.count) locked or hidden skipped")
        }
        return parts.joined(separator: ", ")
    }
}

extension ThumbnailArrangeableConfiguration {
    /// Layers with the text/profile singleton records present, as the saved
    /// document will have them.
    var reconciledArrangeLayers: [ThumbnailDocumentLayer] {
        layers.reconciledForCurrentOverlays(hasText: !overlayText.isEmpty, hasProfile: arrangeProfileSize != nil)
    }
}

extension SimpleMakerViewModel: ThumbnailArrangeEditing {
    var arrangeConfiguration: SimpleMakerConfigurationModel {
        get { simpleMakerConfiguration }
        set { simpleMakerConfiguration = newValue }
    }
}

extension PremiumMakerViewModel: ThumbnailArrangeEditing {
    var arrangeConfiguration: PremiumMakerConfigurationModel {
        get { premiumMakerConfiguration }
        set { premiumMakerConfiguration = newValue }
    }
}
