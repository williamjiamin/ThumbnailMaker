//
//  ThumbnailLayerGroupTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-07: group membership model, persistence and multi-selection state.
//

import Foundation
import Testing
@testable import ThumbnailMaker

@MainActor
struct ThumbnailLayerGroupTests {
    private func sampleLayers() -> [ThumbnailDocumentLayer] {
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: true, hasProfile: false)
        layers.append(.shapeLayer(id: "a", zIndex: 30))
        layers.append(.shapeLayer(id: "b", zIndex: 40))
        layers.append(.textLayer(id: "c", zIndex: 50))
        return layers
    }

    @Test func groupNeedsTwoNonBackgroundLayers() {
        var layers = sampleLayers()
        let single = layers.group(layerIDs: ["a"])
        let duplicate = layers.group(layerIDs: ["a", "a"])
        let withBackground = layers.group(layerIDs: ["a", ThumbnailDocumentLayer.backgroundID])
        let withMissing = layers.group(layerIDs: ["a", "missing"])
        #expect(single == nil && duplicate == nil && withBackground == nil && withMissing == nil)
        #expect(layers == sampleLayers(), "Invalid requests change nothing")

        let created = layers.group(layerIDs: ["a", "b"], newGroupID: "g1")
        #expect(created == "g1")
        #expect(layers.memberIDs(ofGroup: "g1") == ["a", "b"])
        #expect(layers.groupID(forLayerID: "c") == nil)
        let regroup = layers.group(layerIDs: ["b", "a"])
        #expect(regroup == nil, "Already exactly one group")
    }

    @Test func regroupingMovesMembersAndDissolvesLeftovers() {
        var layers = sampleLayers()
        layers.group(layerIDs: ["a", "b"], newGroupID: "g1")
        layers.group(layerIDs: ["b", "c"], newGroupID: "g2")
        #expect(layers.memberIDs(ofGroup: "g2") == ["b", "c"])
        #expect(layers.record(id: "a")?.groupID == nil, "A one-member group is dissolved")
        #expect(layers.groupIDs == ["g2"])
    }

    @Test func textSingletonCanJoinAGroup() {
        var layers = sampleLayers()
        layers.group(layerIDs: [ThumbnailDocumentLayer.textID, "a"], newGroupID: "g")
        #expect(layers.groupID(forLayerID: ThumbnailDocumentLayer.textID) == "g")
        #expect(layers.groupDisplayName(for: "g") == "Group 1")
    }

    @Test func ungroupOnlyClearsMembership() {
        var layers = sampleLayers()
        layers.group(layerIDs: ["a", "b"], newGroupID: "g1")
        let first = layers.ungroup(groupID: "g1")
        #expect(first)
        #expect(layers == sampleLayers(), "Every other field is byte-equal after ungroup")
        let second = layers.ungroup(groupID: "g1")
        #expect(!second)
    }

    @Test func deletingAMemberDissolvesATwoLayerGroup() {
        var layers = sampleLayers()
        layers.group(layerIDs: ["a", "b"], newGroupID: "g1")
        layers.deleteContentLayer(id: "a")
        #expect(layers.record(id: "b")?.groupID == nil)
        #expect(layers.groupIDs.isEmpty)
    }

    @Test func staleSingleMemberGroupIsIgnoredAndNormalized() {
        var layers = sampleLayers()
        layers[layers.firstIndex { $0.id == "a" }!].groupID = "stale"
        #expect(layers.groupID(forLayerID: "a") == nil)
        #expect(layers.normalizedGroups().record(id: "a")?.groupID == nil)
        #expect(layers.normalizedGroups() == layers.normalizedGroups().normalizedGroups())
    }

    @Test func duplicateStartsOutsideTheGroup() throws {
        var layers = sampleLayers()
        layers.group(layerIDs: ["a", "b"], newGroupID: "g1")
        let duplicated = layers.duplicateContentLayer(id: "a", newID: "copy")
        let copyID = try #require(duplicated)
        #expect(layers.record(id: copyID)?.groupID == nil)
        #expect(layers.memberIDs(ofGroup: "g1") == ["a", "b"])
    }

    @Test func remappingGroupIDsIsFreshAndConsistent() {
        var layers = sampleLayers()
        layers.group(layerIDs: ["a", "b"], newGroupID: "g1")
        var counter = 0
        let remapped = layers.remappingGroupIDs {
            counter += 1
            return "new\(counter)"
        }
        #expect(remapped.record(id: "a")?.groupID == "new1")
        #expect(remapped.record(id: "b")?.groupID == "new1")
        #expect(counter == 1)
    }

    @Test func reconcilePreservesSingletonGroupID() {
        var layers = sampleLayers()
        layers.group(layerIDs: [ThumbnailDocumentLayer.textID, "a"], newGroupID: "g")
        let reconciled = layers.reconciledForCurrentOverlays(hasText: true, hasProfile: false)
        #expect(reconciled.record(id: ThumbnailDocumentLayer.textID)?.groupID == "g")
        #expect(reconciled.record(id: ThumbnailDocumentLayer.backgroundID)?.groupID == nil)
    }

    // MARK: Persistence

    @Test func legacyLayerJSONDecodesWithoutGroupAndReencodesWithoutKey() throws {
        let legacy = #"{"id":"x","kind":"shape","name":"Shape","isVisible":true,"isLocked":false,"zIndex":30}"#
        let layer = try JSONDecoder().decode(ThumbnailDocumentLayer.self, from: Data(legacy.utf8))
        #expect(layer.groupID == nil)
        let encoded = String(decoding: try JSONEncoder().encode(layer), as: UTF8.self)
        #expect(!encoded.contains("groupID"))
    }

    @Test func documentRoundTripKeepsGroupsAndVersion() throws {
        var configuration = PremiumMakerConfigurationModel()
        configuration.layers.append(.shapeLayer(id: "a", zIndex: 30))
        configuration.layers.append(.shapeLayer(id: "b", zIndex: 40))
        configuration.layers.group(layerIDs: ["a", "b"], newGroupID: "g1")
        let document = configuration.document
        #expect(document.version == 5)

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(ThumbnailDocument.self, from: data)
        #expect(decoded.layers.memberIDs(ofGroup: "g1") == ["a", "b"])
        #expect(PremiumMakerConfigurationModel(document: decoded).layers.groupID(forLayerID: "b") == "g1")
    }

    // MARK: Selection state

    @Test func selectionSetToggleDedupeAndPrune() {
        var set = ThumbnailSelectionSet([.content("a"), .content("a"), .textOverlay])
        #expect(set.members == [.content("a"), .textOverlay])
        set.toggle(.content("b"))
        set.toggle(.content("a"))
        #expect(set.members == [.textOverlay, .content("b")])
        #expect(set.pruned(to: [.content("b")]).members == [.content("b")])
    }

    @Test func selectionExpandsToWholeGroups() {
        var layers = sampleLayers()
        layers.group(layerIDs: ["a", "b"], newGroupID: "g1")
        let selectable = layers.selectableLayerSelections(hasText: true, hasProfile: false)
        let set = ThumbnailSelectionSet([.content("b"), .content("c")])
        #expect(set.expandedToGroups(in: layers, selectable: selectable) == [.content("a"), .content("b"), .content("c")])
    }

    @Test func effectiveSelectionFallsBackToPrimary() {
        var state = ThumbnailArrangeUIState()
        let selectable: [ThumbnailLayerSelection] = [.textOverlay, .content("a")]
        #expect(state.effectiveSelection(primary: .content("a"), selectable: selectable) == [.content("a")])
        state.isMultiSelectMode = true
        state.selection.replace(with: [.textOverlay, .content("gone")])
        #expect(state.effectiveSelection(primary: .content("a"), selectable: selectable) == [.textOverlay])
        state.selection.removeAll()
        #expect(state.effectiveSelection(primary: .content("a"), selectable: selectable) == [.content("a")])
        #expect(state.effectiveSelection(primary: .content("gone"), selectable: selectable).isEmpty)
    }
}
