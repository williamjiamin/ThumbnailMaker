//
//  ThumbnailAlignmentTests.swift
//  ThumbnailMakerTests
//
//  FEATURE-07: bounds, align, distribute, nudge and the canvas group-follow hook.
//

import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import ThumbnailMaker

@MainActor
struct ThumbnailAlignmentTests {
    private let tolerance: CGFloat = 0.0001

    private func near(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < tolerance
    }

    /// Shapes with exact normalized sizes: width 0.2, height 0.1.
    private func shape(_ id: String, x: CGFloat, y: CGFloat, z: Int, rotation: Double = 0) -> ThumbnailDocumentLayer {
        .shapeLayer(
            id: id,
            transform: ThumbnailOverlayTransform(x: x, y: y, rotationDegrees: rotation),
            width: 0.2,
            height: 0.1,
            zIndex: z
        )
    }

    private func configuration(_ shapes: [ThumbnailDocumentLayer]) -> SimpleMakerConfigurationModel {
        var configuration = SimpleMakerConfigurationModel()
        configuration.layers = ThumbnailDocumentLayer.defaultLayers(hasText: false, hasProfile: false) + shapes
        return configuration
    }

    private func center(_ configuration: SimpleMakerConfigurationModel, _ id: String) -> CGPoint {
        configuration.arrangeCenter(for: .content(id)) ?? CGPoint(x: -1, y: -1)
    }

    // MARK: Geometry

    @Test func boundsOfUnrotatedAndRotatedShapes() throws {
        let configuration = configuration([
            shape("a", x: 0.5, y: 0.5, z: 30),
            shape("r", x: 0.5, y: 0.5, z: 40, rotation: 90)
        ])
        let flat = try #require(configuration.arrangeItem(for: .content("a")))
        #expect(near(flat.bounds.width, 0.2) && near(flat.bounds.height, 0.1))
        #expect(near(flat.bounds.minX, 0.4) && near(flat.bounds.minY, 0.45))

        // 16:9 reference canvas 1000 x 562.5: the rotated frame is 56.25 x 200 points.
        let rotated = try #require(configuration.arrangeItem(for: .content("r")))
        #expect(near(rotated.bounds.width, 56.25 / 1000))
        #expect(near(rotated.bounds.height, 200 / 562.5))
    }

    @Test func profileBoundsUseWidthTimesSize() throws {
        var configuration = PremiumMakerConfigurationModel()
        configuration.selectedRatio = .ratio1_1
        configuration.circularProfile = CircularProfileConfig(image: UIImage(systemName: "star"), size: 0.2)
        configuration.profileTransform = ThumbnailOverlayTransform(x: 0.5, y: 0.5)
        let item = try #require(configuration.arrangeItem(for: .profileOverlay))
        #expect(near(item.bounds.width, 0.2) && near(item.bounds.height, 0.2))

        var simple = SimpleMakerConfigurationModel()
        simple.overlayText = "Hi"
        #expect(simple.arrangeItem(for: .profileOverlay) == nil)
        #expect(simple.arrangeItem(for: .textOverlay) != nil)
    }

    @Test func translateRigidlyClampsByTheTightestMember() {
        var configuration = configuration([
            shape("a", x: 0.9, y: 0.5, z: 30),
            shape("b", x: 0.5, y: 0.5, z: 40)
        ])
        let applied = configuration.translateRigidly([.content("a"), .content("b")], by: CGVector(dx: 0.2, dy: 0))
        #expect(near(applied.dx, 0.05))
        #expect(near(center(configuration, "a").x, 0.95))
        #expect(near(center(configuration, "b").x, 0.55), "Relative offset is unchanged")
    }

    // MARK: Align

    @Test func alignLeftToSelection() {
        var configuration = configuration([
            shape("a", x: 0.3, y: 0.2, z: 30),
            shape("b", x: 0.6, y: 0.5, z: 40),
            shape("c", x: 0.8, y: 0.8, z: 50)
        ])
        let result = configuration.align([.content("a"), .content("b"), .content("c")], edge: .left, reference: .selection)
        #expect(result.applied)
        for id in ["a", "b", "c"] {
            #expect(near(center(configuration, id).x, 0.3))
        }
        #expect(near(center(configuration, "c").y, 0.8), "Align left never moves vertically")
    }

    @Test func alignBottomToCanvasAndSingleItemFallsBackToCanvas() {
        var configuration = configuration([shape("a", x: 0.3, y: 0.3, z: 30)])
        configuration.align([.content("a")], edge: .horizontalCenter, reference: .selection)
        #expect(near(center(configuration, "a").x, 0.5))
        configuration.align([.content("a")], edge: .bottom, reference: .canvas)
        #expect(near(center(configuration, "a").y, 0.95), "Bottom edge 1.0 is clamped to the 0.95 centre range")
    }

    @Test func groupAlignsAsOneUnitAndKeepsItsInternalOffset() {
        var configuration = configuration([
            shape("a", x: 0.3, y: 0.3, z: 30),
            shape("b", x: 0.4, y: 0.6, z: 40),
            shape("c", x: 0.7, y: 0.5, z: 50)
        ])
        configuration.layers.group(layerIDs: ["a", "b"], newGroupID: "g")
        configuration.align([.content("a"), .content("c")], edge: .right, reference: .selection)
        // Selection right edge = c's right (0.8). The group's right edge (b: 0.5) moves to 0.8.
        #expect(near(center(configuration, "b").x, 0.7))
        #expect(near(center(configuration, "a").x, 0.6), "a keeps its 0.1 offset from b")
        #expect(near(center(configuration, "c").x, 0.7))
    }

    @Test func lockedLayersAreSkippedButStillAReference() {
        var configuration = configuration([
            shape("a", x: 0.3, y: 0.5, z: 30),
            shape("locked", x: 0.7, y: 0.5, z: 40)
        ])
        configuration.layers.toggleLock(for: .content("locked"))
        let result = configuration.align([.content("a"), .content("locked")], edge: .right, reference: .selection)
        #expect(result.applied)
        #expect(result.skippedCount == 1)
        #expect(result.announcement.contains("skipped"))
        #expect(near(center(configuration, "locked").x, 0.7))
        #expect(near(center(configuration, "a").x, 0.7))
    }

    @Test func groupWithALockedMemberIsRefused() {
        var configuration = configuration([
            shape("a", x: 0.3, y: 0.5, z: 30),
            shape("b", x: 0.5, y: 0.5, z: 40)
        ])
        configuration.layers.group(layerIDs: ["a", "b"], newGroupID: "g")
        configuration.layers.toggleLock(for: .content("b"))
        let before = configuration.layers
        let result = configuration.nudge([.content("a")], by: CGVector(dx: 0.1, dy: 0))
        #expect(!result.applied)
        #expect(result.announcement.contains("locked"))
        #expect(configuration.layers == before)
    }

    @Test func hiddenLayersAreNotArranged() {
        var configuration = configuration([
            shape("a", x: 0.3, y: 0.5, z: 30),
            shape("hidden", x: 0.7, y: 0.5, z: 40)
        ])
        configuration.layers.toggleVisibility(for: .content("hidden"))
        configuration.align([.content("a"), .content("hidden")], edge: .right, reference: .selection)
        #expect(near(center(configuration, "hidden").x, 0.7))
        #expect(near(center(configuration, "a").x, 0.9), "The only visible item aligns to the canvas right edge")
    }

    // MARK: Distribute

    @Test func distributeSpacingKeepsExtremesAndEqualisesGaps() {
        var configuration = configuration([
            shape("a", x: 0.2, y: 0.5, z: 30),
            shape("b", x: 0.35, y: 0.5, z: 40),
            shape("c", x: 0.8, y: 0.5, z: 50)
        ])
        let result = configuration.distribute([.content("c"), .content("a"), .content("b")], mode: .horizontalSpacing)
        #expect(result.applied)
        #expect(near(center(configuration, "a").x, 0.2))
        #expect(near(center(configuration, "c").x, 0.8))
        #expect(near(center(configuration, "b").x, 0.5))
    }

    @Test func distributeNeedsThreeUnits() {
        var configuration = configuration([
            shape("a", x: 0.2, y: 0.5, z: 30),
            shape("b", x: 0.35, y: 0.5, z: 40)
        ])
        let before = configuration.layers
        let result = configuration.distribute([.content("a"), .content("b")], mode: .horizontalCenters)
        #expect(!result.applied)
        #expect(configuration.layers == before)
    }

    // MARK: Canvas group follow

    @Test func draggingOneMemberMovesTheWholeGroup() throws {
        var configuration = configuration([
            shape("a", x: 0.3, y: 0.3, z: 30),
            shape("b", x: 0.5, y: 0.4, z: 40),
            shape("solo", x: 0.8, y: 0.8, z: 50)
        ])
        configuration.layers.group(layerIDs: ["a", "b"], newGroupID: "g")
        let start = configuration.arrangeCenter(for: .content("a"))
        configuration.setArrangeCenter(CGPoint(x: 0.4, y: 0.2), for: .content("a"))

        let followed = try #require(configuration.followingGroupMove(of: .content("a"), from: start))
        #expect(near(center(followed, "a").x, 0.4) && near(center(followed, "a").y, 0.2))
        #expect(near(center(followed, "b").x, 0.6) && near(center(followed, "b").y, 0.3))
        #expect(near(center(followed, "solo").x, 0.8))

        #expect(configuration.followingGroupMove(of: .content("solo"), from: CGPoint(x: 0.1, y: 0.1)) == nil)
    }
}
