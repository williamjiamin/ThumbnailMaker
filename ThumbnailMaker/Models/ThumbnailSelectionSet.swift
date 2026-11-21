//
//  ThumbnailSelectionSet.swift
//  ThumbnailMaker
//
//  FEATURE-07: multi-selection. Selection is UI state (never in the document
//  and never undoable). The editors' existing single `selectedLayer` stays the
//  primary selection, so every single-layer control keeps working unchanged.
//

import Foundation

struct ThumbnailSelectionSet: Equatable {
    private(set) var members: [ThumbnailLayerSelection] = []

    init(_ members: [ThumbnailLayerSelection] = []) {
        var seen = Set<ThumbnailLayerSelection>()
        self.members = members.filter { seen.insert($0).inserted }
    }

    var isEmpty: Bool { members.isEmpty }
    var count: Int { members.count }

    func contains(_ selection: ThumbnailLayerSelection) -> Bool {
        members.contains(selection)
    }

    mutating func toggle(_ selection: ThumbnailLayerSelection) {
        if let index = members.firstIndex(of: selection) {
            members.remove(at: index)
        } else {
            members.append(selection)
        }
    }

    mutating func replace(with selections: [ThumbnailLayerSelection]) {
        self = ThumbnailSelectionSet(selections)
    }

    mutating func removeAll() {
        members.removeAll()
    }

    /// Drops members that no longer exist (after delete, variant switch,
    /// project switch or undo).
    func pruned(to selectable: [ThumbnailLayerSelection]) -> ThumbnailSelectionSet {
        ThumbnailSelectionSet(members.filter(selectable.contains))
    }

    /// Adds every member of each selected layer's group (groups act as one unit).
    func expandedToGroups(
        in layers: [ThumbnailDocumentLayer],
        selectable: [ThumbnailLayerSelection]
    ) -> [ThumbnailLayerSelection] {
        var result: [ThumbnailLayerSelection] = []
        for member in members {
            if let groupID = layers.groupID(for: member) {
                for id in layers.memberIDs(ofGroup: groupID) {
                    if let selection = selectable.first(where: { $0.documentLayerID == id }),
                       !result.contains(selection) {
                        result.append(selection)
                    }
                }
            } else if !result.contains(member) {
                result.append(member)
            }
        }
        return result
    }
}

/// Everything the arrange UI keeps per editor screen.
struct ThumbnailArrangeUIState: Equatable {
    var selection = ThumbnailSelectionSet()
    var isMultiSelectMode = false
    var alignReference: ThumbnailAlignReference = .selection
    var lastAnnouncement: String?

    /// The layers the arrange commands act on: the multi-selection when the
    /// mode is on and non-empty, otherwise the primary layer. Stale members
    /// are dropped.
    func effectiveSelection(
        primary: ThumbnailLayerSelection,
        selectable: [ThumbnailLayerSelection]
    ) -> [ThumbnailLayerSelection] {
        if isMultiSelectMode {
            let pruned = selection.pruned(to: selectable)
            if !pruned.isEmpty {
                return pruned.members
            }
        }
        return selectable.contains(primary) ? [primary] : []
    }
}
