//
//  ThumbnailAlignment.swift
//  ThumbnailMaker
//
//  FEATURE-07: align, distribute and nudge. Pure functions over
//  ThumbnailArrangeableConfiguration. A "unit" is either one layer or a whole
//  group (groups act as one item, using their union bounds). Rules:
//  - hidden layers are not arranged and do not count toward bounds (hidden
//    group members still move with their group);
//  - locked layers never move; a group with a locked member is skipped whole;
//  - locked (visible) layers still count toward the selection reference box,
//    so "align to the locked logo" works naturally.
//

import CoreGraphics
import Foundation

enum ThumbnailAlignEdge: String, CaseIterable, Identifiable {
    case left, horizontalCenter, right, top, verticalCenter, bottom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: "Align Left"
        case .horizontalCenter: "Align Centers Horizontally"
        case .right: "Align Right"
        case .top: "Align Top"
        case .verticalCenter: "Align Centers Vertically"
        case .bottom: "Align Bottom"
        }
    }

    var systemImage: String {
        switch self {
        case .left: "align.horizontal.left"
        case .horizontalCenter: "align.horizontal.center"
        case .right: "align.horizontal.right"
        case .top: "align.vertical.top"
        case .verticalCenter: "align.vertical.center"
        case .bottom: "align.vertical.bottom"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .left: "arrangeAlignLeft"
        case .horizontalCenter: "arrangeAlignHCenter"
        case .right: "arrangeAlignRight"
        case .top: "arrangeAlignTop"
        case .verticalCenter: "arrangeAlignVCenter"
        case .bottom: "arrangeAlignBottom"
        }
    }
}

enum ThumbnailAlignReference: String, CaseIterable, Identifiable, Equatable {
    case selection
    case canvas

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selection: "Selection"
        case .canvas: "Canvas"
        }
    }
}

enum ThumbnailDistributeMode: String, CaseIterable, Identifiable {
    case horizontalSpacing, verticalSpacing, horizontalCenters, verticalCenters

    var id: String { rawValue }

    var title: String {
        switch self {
        case .horizontalSpacing: "Distribute Horizontally"
        case .verticalSpacing: "Distribute Vertically"
        case .horizontalCenters: "Distribute Centers Horizontally"
        case .verticalCenters: "Distribute Centers Vertically"
        }
    }

    var isHorizontal: Bool {
        self == .horizontalSpacing || self == .horizontalCenters
    }
}

enum ThumbnailArrangeSkipReason: String, Equatable {
    case locked
    case hidden
    case containsLocked
}

struct ThumbnailArrangeUnit: Equatable {
    /// Group id, or the layer id for a single layer.
    var id: String
    /// Layers that move with this unit (hidden group members included).
    var members: [ThumbnailLayerSelection]
    /// Union bounds of visible members.
    var bounds: CGRect
}

struct ThumbnailArrangePlan: Equatable {
    var units: [ThumbnailArrangeUnit] = []
    var skipped: [String: ThumbnailArrangeSkipReason] = [:]
    /// Bounds of every visible selected layer, locked ones included.
    var referenceBounds: CGRect = .null
}

struct ThumbnailArrangeResult: Equatable {
    var applied: Bool
    var skippedCount: Int
    var announcement: String

    static func none(_ announcement: String) -> ThumbnailArrangeResult {
        ThumbnailArrangeResult(applied: false, skippedCount: 0, announcement: announcement)
    }
}

extension ThumbnailArrangeableConfiguration {
    /// Groups the selection into units, expanding each layer to its group.
    func arrangePlan(for selections: [ThumbnailLayerSelection]) -> ThumbnailArrangePlan {
        var plan = ThumbnailArrangePlan()
        var handledGroups = Set<String>()
        var handledLayers = Set<String>()

        for selection in selections {
            let layerID = selection.documentLayerID
            guard !handledLayers.contains(layerID) else { continue }

            if let groupID = layers.groupID(forLayerID: layerID) {
                guard handledGroups.insert(groupID).inserted else { continue }
                let members = layers.memberIDs(ofGroup: groupID).compactMap(arrangeSelection(forLayerID:))
                members.forEach { handledLayers.insert($0.documentLayerID) }
                let visible = members.filter { layers.isVisible($0) }
                let bounds = visible.compactMap { arrangeItem(for: $0)?.bounds }.reduce(CGRect.null) { $0.union($1) }
                if !bounds.isNull {
                    plan.referenceBounds = plan.referenceBounds.union(bounds)
                }
                if members.contains(where: { layers.isLocked($0) }) {
                    plan.skipped[groupID] = .containsLocked
                } else if bounds.isNull {
                    plan.skipped[groupID] = .hidden
                } else {
                    plan.units.append(ThumbnailArrangeUnit(id: groupID, members: members, bounds: bounds))
                }
            } else {
                handledLayers.insert(layerID)
                guard let item = arrangeItem(for: selection) else { continue }
                guard layers.isVisible(selection) else {
                    plan.skipped[layerID] = .hidden
                    continue
                }
                plan.referenceBounds = plan.referenceBounds.union(item.bounds)
                if layers.isLocked(selection) {
                    plan.skipped[layerID] = .locked
                } else {
                    plan.units.append(ThumbnailArrangeUnit(id: layerID, members: [selection], bounds: item.bounds))
                }
            }
        }
        return plan
    }

    /// Aligns each unit's edge or centre to the reference. With the selection
    /// reference and a single visible item, the canvas is used instead.
    @discardableResult
    mutating func align(
        _ selections: [ThumbnailLayerSelection],
        edge: ThumbnailAlignEdge,
        reference: ThumbnailAlignReference
    ) -> ThumbnailArrangeResult {
        let plan = arrangePlan(for: selections)
        guard !plan.units.isEmpty else {
            return .none(Self.refusal(plan: plan, fallback: "Select an unlocked, visible layer to align."))
        }
        let singleItem = plan.units.count == 1 && plan.units[0].bounds == plan.referenceBounds
        let target = (reference == .canvas || singleItem)
            ? CGRect(x: 0, y: 0, width: 1, height: 1)
            : plan.referenceBounds

        var moved = false
        for unit in plan.units {
            let delta = Self.alignmentDelta(for: unit.bounds, to: target, edge: edge)
            let applied = translateRigidly(unit.members, by: delta)
            moved = moved || applied != .zero
        }
        return ThumbnailArrangeResult(
            applied: moved,
            skippedCount: plan.skipped.count,
            announcement: Self.announcement(moved ? edge.title : "Already aligned", plan: plan)
        )
    }

    static func alignmentDelta(for bounds: CGRect, to target: CGRect, edge: ThumbnailAlignEdge) -> CGVector {
        switch edge {
        case .left: CGVector(dx: target.minX - bounds.minX, dy: 0)
        case .horizontalCenter: CGVector(dx: target.midX - bounds.midX, dy: 0)
        case .right: CGVector(dx: target.maxX - bounds.maxX, dy: 0)
        case .top: CGVector(dx: 0, dy: target.minY - bounds.minY)
        case .verticalCenter: CGVector(dx: 0, dy: target.midY - bounds.midY)
        case .bottom: CGVector(dx: 0, dy: target.maxY - bounds.maxY)
        }
    }

    /// Needs three or more units. The two outermost units stay fixed.
    @discardableResult
    mutating func distribute(
        _ selections: [ThumbnailLayerSelection],
        mode: ThumbnailDistributeMode
    ) -> ThumbnailArrangeResult {
        let plan = arrangePlan(for: selections)
        guard plan.units.count >= 3 else {
            return .none(Self.refusal(plan: plan, fallback: "Select three or more unlocked, visible layers or groups to distribute."))
        }
        var moved = false
        for (unit, delta) in Self.distributionDeltas(units: plan.units, mode: mode) {
            let applied = translateRigidly(unit.members, by: delta)
            moved = moved || applied != .zero
        }
        return ThumbnailArrangeResult(
            applied: moved,
            skippedCount: plan.skipped.count,
            announcement: Self.announcement(moved ? mode.title : "Already evenly distributed", plan: plan)
        )
    }

    static func distributionDeltas(
        units: [ThumbnailArrangeUnit],
        mode: ThumbnailDistributeMode
    ) -> [(ThumbnailArrangeUnit, CGVector)] {
        guard units.count >= 3 else { return [] }
        let horizontal = mode.isHorizontal
        let sorted = units.enumerated().sorted { lhs, rhs in
            let left = horizontal ? lhs.element.bounds.midX : lhs.element.bounds.midY
            let right = horizontal ? rhs.element.bounds.midX : rhs.element.bounds.midY
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)

        var result: [(ThumbnailArrangeUnit, CGVector)] = []
        let first = sorted[0], last = sorted[sorted.count - 1]
        let steps = CGFloat(sorted.count - 1)

        switch mode {
        case .horizontalCenters, .verticalCenters:
            let start = horizontal ? first.bounds.midX : first.bounds.midY
            let end = horizontal ? last.bounds.midX : last.bounds.midY
            for (index, unit) in sorted.enumerated() where index > 0 && index < sorted.count - 1 {
                let target = start + (end - start) * CGFloat(index) / steps
                let current = horizontal ? unit.bounds.midX : unit.bounds.midY
                result.append((unit, horizontal ? CGVector(dx: target - current, dy: 0) : CGVector(dx: 0, dy: target - current)))
            }
        case .horizontalSpacing, .verticalSpacing:
            let start = horizontal ? first.bounds.minX : first.bounds.minY
            let end = horizontal ? last.bounds.maxX : last.bounds.maxY
            let totalLength = sorted.reduce(CGFloat(0)) { $0 + (horizontal ? $1.bounds.width : $1.bounds.height) }
            let gap = (end - start - totalLength) / steps
            var cursor = start + (horizontal ? first.bounds.width : first.bounds.height) + gap
            for (index, unit) in sorted.enumerated() where index > 0 && index < sorted.count - 1 {
                let current = horizontal ? unit.bounds.minX : unit.bounds.minY
                result.append((unit, horizontal ? CGVector(dx: cursor - current, dy: 0) : CGVector(dx: 0, dy: cursor - current)))
                cursor += (horizontal ? unit.bounds.width : unit.bounds.height) + gap
            }
        }
        return result
    }

    /// Moves every movable unit by the same normalized delta.
    @discardableResult
    mutating func nudge(_ selections: [ThumbnailLayerSelection], by delta: CGVector) -> ThumbnailArrangeResult {
        let plan = arrangePlan(for: selections)
        guard !plan.units.isEmpty else {
            return .none(Self.refusal(plan: plan, fallback: "Select an unlocked, visible layer to move."))
        }
        var moved = false
        for unit in plan.units {
            moved = translateRigidly(unit.members, by: delta) != .zero || moved
        }
        return ThumbnailArrangeResult(
            applied: moved,
            skippedCount: plan.skipped.count,
            announcement: Self.announcement(moved ? "Moved" : "Already at the canvas edge", plan: plan)
        )
    }

    private static func announcement(_ base: String, plan: ThumbnailArrangePlan) -> String {
        guard !plan.skipped.isEmpty else { return base }
        let count = plan.skipped.count
        return "\(base). \(count) locked or hidden \(count == 1 ? "item" : "items") skipped."
    }

    private static func refusal(plan: ThumbnailArrangePlan, fallback: String) -> String {
        if plan.skipped.values.contains(.containsLocked) {
            return "This group has a locked layer. Unlock it to move the group."
        }
        if plan.skipped.values.contains(.locked) {
            return "Locked layers can't be moved. Unlock them first."
        }
        return fallback
    }
}
