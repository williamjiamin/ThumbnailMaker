//
//  ThumbnailLayerGroup.swift
//  ThumbnailMaker
//
//  FEATURE-07: layer groups. A group is membership only: each member carries
//  the same `groupID`, and no group-level transform is ever stored. Group
//  operations write the members' own transforms right away, so export,
//  templates, variants and packages render groups with no extra code, and
//  ungrouping never changes how the thumbnail looks.
//
//  A group only counts while it has at least two members in the layer list;
//  a stale single-member id is ignored by every query here and removed by
//  `normalizedGroups()`.
//

import Foundation

extension Array where Element == ThumbnailDocumentLayer {
    /// Group ids with at least two members, ordered by each group's lowest zIndex.
    var groupIDs: [String] {
        var lowestZIndex: [String: Int] = [:]
        var counts: [String: Int] = [:]
        for layer in self {
            guard let groupID = layer.groupID, layer.kind != .background else { continue }
            counts[groupID, default: 0] += 1
            lowestZIndex[groupID] = Swift.min(lowestZIndex[groupID] ?? layer.zIndex, layer.zIndex)
        }
        return counts
            .filter { $0.value >= 2 }
            .map(\.key)
            .sorted { (lowestZIndex[$0] ?? 0, $0) < (lowestZIndex[$1] ?? 0, $1) }
    }

    /// The layer's group, or nil when it has none (or its group is stale).
    func groupID(forLayerID layerID: String) -> String? {
        guard let groupID = record(id: layerID)?.groupID else { return nil }
        return memberIDs(ofGroup: groupID).count >= 2 ? groupID : nil
    }

    func groupID(for selection: ThumbnailLayerSelection) -> String? {
        groupID(forLayerID: selection.documentLayerID)
    }

    /// Member layer ids in zIndex order.
    func memberIDs(ofGroup groupID: String) -> [String] {
        filter { $0.groupID == groupID && $0.kind != .background }
            .sorted { $0.zIndex < $1.zIndex }
            .map(\.id)
    }

    /// "Group 1", "Group 2", ... numbered by lowest zIndex.
    func groupDisplayName(for groupID: String) -> String? {
        guard let index = groupIDs.firstIndex(of: groupID) else { return nil }
        return "Group \(index + 1)"
    }

    /// Puts the given layers into one new group. Needs at least two distinct,
    /// existing, non-background layers. A member of another group moves into
    /// the new group. Returns nil (and changes nothing) when the request is
    /// invalid or those layers already form exactly one group.
    @discardableResult
    mutating func group(layerIDs: [String], newGroupID: String = UUID().uuidString) -> String? {
        var seen = Set<String>()
        let ids = layerIDs.filter { id in
            guard !seen.contains(id),
                  let layer = record(id: id),
                  layer.kind != .background else { return false }
            seen.insert(id)
            return true
        }
        guard ids.count >= 2 else { return nil }

        if let existing = record(id: ids[0])?.groupID,
           Set(memberIDs(ofGroup: existing)) == Set(ids) {
            return nil
        }

        for index in indices where seen.contains(self[index].id) {
            self[index].groupID = newGroupID
        }
        self = normalizedGroups()
        return newGroupID
    }

    /// Clears membership only; every other field is untouched.
    @discardableResult
    mutating func ungroup(groupID: String) -> Bool {
        var changed = false
        for index in indices where self[index].groupID == groupID {
            self[index].groupID = nil
            changed = true
        }
        return changed
    }

    /// Dissolves groups with fewer than two members and clears the
    /// background's membership. Idempotent.
    func normalizedGroups() -> [ThumbnailDocumentLayer] {
        var counts: [String: Int] = [:]
        for layer in self where layer.kind != .background {
            if let groupID = layer.groupID {
                counts[groupID, default: 0] += 1
            }
        }
        var result = self
        for index in result.indices {
            guard let groupID = result[index].groupID else { continue }
            if result[index].kind == .background || (counts[groupID] ?? 0) < 2 {
                result[index].groupID = nil
            }
        }
        return result
    }

    /// Issues fresh group ids (consistently per group). Call wherever layer ids
    /// are regenerated so two imported copies never share a group.
    func remappingGroupIDs(_ makeID: () -> String = { UUID().uuidString }) -> [ThumbnailDocumentLayer] {
        var map: [String: String] = [:]
        var result = self
        for index in result.indices {
            guard let groupID = result[index].groupID else { continue }
            if map[groupID] == nil {
                map[groupID] = makeID()
            }
            result[index].groupID = map[groupID]
        }
        return result.normalizedGroups()
    }
}
