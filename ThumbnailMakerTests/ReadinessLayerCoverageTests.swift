//
//  ReadinessLayerCoverageTests.swift
//  ThumbnailMakerTests
//
//  Verifies that the readiness analyzer considers ALL visible layers, not
//  just the text overlay — APP-06's "consume all visible layers" requirement.
//

import Foundation
import SwiftUI
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ReadinessLayerCoverageTests {
    @Test func analyzerWarnsWhenAllContentLayersHiddenAndTextEmpty() throws {
        var configuration = SimpleMakerConfigurationModel()
        configuration.selectedImage = nil
        configuration.overlayText = ""
        let contentLayer = ThumbnailDocumentLayer.imageLayer(
            imageData: try imageFixtureData(),
            name: "Cutout"
        )
        configuration.layers = ThumbnailDocumentLayer.defaultLayers(hasText: false, hasProfile: false)
            + [contentLayer]

        // With a visible content layer the design has something to show, so the
        // "no visible content" warning must not fire.
        #expect(configuration.visibleContentLayerCount == 1)
        #expect(!ThumbnailReadinessAnalyzer.analyze(configuration).findings.contains {
            $0.message.contains("no visible content")
        })

        // Hiding it leaves nothing visible and no text, which is what the
        // warning is for. The background layer does not count as content.
        configuration.layers.setVisible(false, for: .content(contentLayer.id))

        #expect(configuration.visibleContentLayerCount == 0)
        let report = ThumbnailReadinessAnalyzer.analyze(configuration)
        #expect(report.findings.contains {
            $0.severity == .warning && $0.message.contains("no visible content")
        })
    }

    @Test func analyzerDoesNotWarnWhenTextIsPresent() {
        var configuration = SimpleMakerConfigurationModel()
        configuration.selectedImage = nil
        configuration.overlayText = "Title"
        configuration.textSize = 0.24
        configuration.textColor = .black
        configuration.backgroundColor = .white

        let report = ThumbnailReadinessAnalyzer.analyze(configuration)

        #expect(!report.findings.contains { $0.message.contains("no visible content") })
    }

    @Test func analyzerReportsAllVisibleLayersViaProtocol() throws {
        var configuration = PremiumMakerConfigurationModel()
        configuration.selectedImage = nil
        configuration.overlayText = "Visible title"
        configuration.layers = ThumbnailDocumentLayer.defaultLayers(hasText: true, hasProfile: false)
            + [ThumbnailDocumentLayer.imageLayer(imageData: try imageFixtureData(), name: "Badge")]

        // The protocol must surface every visible layer — the reconciled text
        // overlay and the added content layer — and exclude the background.
        #expect(configuration.visibleContentLayerCount == 2)
    }

    @Test func simpleAndPremiumConfigurationsExposeVisibleContentCount() {
        // A brand-new configuration has no image, no text, and no content
        // layers, so the only layer present is the background.
        let simple = SimpleMakerConfigurationModel()
        let premium = PremiumMakerConfigurationModel()
        #expect(simple.visibleContentLayerCount == 0)
        #expect(premium.visibleContentLayerCount == 0)
    }

    private func imageFixtureData() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format).image { _ in
            UIColor.systemTeal.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        return try #require(image.pngData())
    }
}
