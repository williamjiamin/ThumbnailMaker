//
//  ThumbnailReadinessAnalyzer.swift
//  ThumbnailMaker
//

import Foundation
import SwiftUI
import UIKit

protocol ThumbnailReadinessConfiguration {
    var selectedImage: UIImage? { get }
    var overlayText: String { get }
    var selectedRatio: AspectRatio { get }
    var backgroundColor: Color { get }
    /// SHELL: a gradient background is checked against its middle stop.
    var backgroundFill: ThumbnailBackgroundFill? { get }
    var textColor: Color { get }
    var textSize: CGFloat { get }
    var isTextLayerVisible: Bool { get }
    var visibleContentLayerCount: Int { get }
    /// DONOR: names of visible text layers too long for their box.
    var overflowingTextLayerNames: [String] { get }
}

extension ThumbnailReadinessConfiguration {
    var overflowingTextLayerNames: [String] { [] }
}

/// Reference canvas the readiness check measures text layers on. Every text
/// metric scales with the canvas, so one reference size answers for all.
enum ThumbnailReadinessCanvas {
    static func size(for ratio: AspectRatio) -> CGSize {
        CGSize(width: ratio.dimensions.width, height: ratio.dimensions.height)
    }
}

extension SimpleMakerConfigurationModel: ThumbnailReadinessConfiguration {
    var isTextLayerVisible: Bool {
        layers.isVisible(ThumbnailEditorLayer.text)
    }

    var visibleContentLayerCount: Int {
        layers.visibleContentLayerCount(hasText: !overlayText.isEmpty, hasProfile: false)
    }

    var overflowingTextLayerNames: [String] {
        layers.overflowingTextLayerNames(canvasSize: ThumbnailReadinessCanvas.size(for: selectedRatio))
    }
}

extension PremiumMakerConfigurationModel: ThumbnailReadinessConfiguration {
    var isTextLayerVisible: Bool {
        layers.isVisible(ThumbnailEditorLayer.text)
    }

    var visibleContentLayerCount: Int {
        layers.visibleContentLayerCount(
            hasText: !overlayText.isEmpty,
            hasProfile: circularProfile?.image != nil
        )
    }

    var overflowingTextLayerNames: [String] {
        layers.overflowingTextLayerNames(canvasSize: ThumbnailReadinessCanvas.size(for: selectedRatio))
    }
}

struct ThumbnailReadinessFinding: Identifiable, Equatable {
    let severity: ThumbnailExportValidationSeverity
    let message: String

    var id: String {
        "\(severity.rawValue)-\(message)"
    }
}

struct ThumbnailReadinessReport: Equatable {
    let score: Int
    let findings: [ThumbnailReadinessFinding]

    var displayScore: String {
        "\(score)/100"
    }

    var hasWarnings: Bool {
        findings.contains { $0.severity == .warning }
    }
}

enum ThumbnailReadinessAnalyzer {
    private static let minimumMobileTextHeight: CGFloat = 12
    private static let preferredMobileTextHeight: CGFloat = 16
    private static let maximumCharacterCount = 64
    private static let maximumWordCount = 10

    static func analyze<Configuration: ThumbnailReadinessConfiguration>(
        _ configuration: Configuration
    ) -> ThumbnailReadinessReport {
        let trimmedText = (configuration.isTextLayerVisible ? configuration.overlayText : "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var findings: [ThumbnailReadinessFinding] = []
        var score = 100

        if trimmedText.isEmpty {
            findings.append(
                warning("Add a short focal phrase so the thumbnail still communicates at small size.")
            )
            score -= 20
        } else {
            score += appendTextDensityFindings(for: trimmedText, to: &findings)
            score += appendSmallPreviewFindings(for: configuration, to: &findings)
            score += appendContrastFindings(for: configuration, to: &findings)
        }

        score += appendTextOverflowFindings(for: configuration.overflowingTextLayerNames, to: &findings)

        if configuration.selectedImage == nil {
            findings.append(
                warning("Add an image before export so the design has a clear visual subject.")
            )
            score -= 10
        }

        // `visibleContentLayerCount` counts visible non-background layers, so a
        // background image has to be checked separately: a design with only a
        // background photo still has visible content.
        let hasVisibleContent = configuration.visibleContentLayerCount > 0
            || configuration.selectedImage != nil
            || !trimmedText.isEmpty
        if !hasVisibleContent {
            findings.append(
                warning("The design has no visible content yet — add a focal image or text.")
            )
            score -= 5
        }

        if !findings.contains(where: { $0.severity == .warning }) {
            findings.append(
                success("Readiness checks look good for a quick small-preview scan.")
            )
        }

        return ThumbnailReadinessReport(
            score: max(0, min(100, score)),
            findings: findings
        )
    }

    /// DONOR: the meme maker's "too long for its box" warning. A text layer
    /// that cannot fit at any size the renderer uses would export truncated.
    @discardableResult
    static func appendTextOverflowFindings(
        for layerNames: [String],
        to findings: inout [ThumbnailReadinessFinding]
    ) -> Int {
        guard !layerNames.isEmpty else { return 0 }
        let subject = layerNames.count == 1
            ? "\"\(layerNames[0])\" is"
            : "\(layerNames.count) text layers are"
        findings.append(
            warning("\(subject) too long for its box and will be cut off. Shorten the text or turn on Auto-fit.")
        )
        return -15
    }

    @discardableResult
    private static func appendTextDensityFindings(
        for text: String,
        to findings: inout [ThumbnailReadinessFinding]
    ) -> Int {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard text.count > maximumCharacterCount || words.count > maximumWordCount else {
            return 0
        }

        findings.append(
            warning("Text is dense for mobile previews. Aim for \(maximumWordCount) words or fewer.")
        )
        return -20
    }

    @discardableResult
    private static func appendSmallPreviewFindings<Configuration: ThumbnailReadinessConfiguration>(
        for configuration: Configuration,
        to findings: inout [ThumbnailReadinessFinding]
    ) -> Int {
        let mobileHeight = ThumbnailSmallPreviewSize.mobile
            .size(for: configuration.selectedRatio)
            .height
        let textHeight = mobileHeight * configuration.textSize

        if textHeight < minimumMobileTextHeight {
            findings.append(
                warning("Text may be too small in mobile previews. Increase the text size or shorten the title.")
            )
            return -20
        }

        if textHeight >= preferredMobileTextHeight {
            findings.append(
                success("Text size is readable in the mobile preview.")
            )
        }

        return 0
    }

    @discardableResult
    private static func appendContrastFindings<Configuration: ThumbnailReadinessConfiguration>(
        for configuration: Configuration,
        to findings: inout [ThumbnailReadinessFinding]
    ) -> Int {
        guard configuration.selectedImage == nil else { return 0 }

        let contrast = contrastRatio(
            between: configuration.textColor,
            and: configuration.backgroundFill?.representativeColor?.color ?? configuration.backgroundColor
        )

        if contrast < 3 {
            findings.append(
                warning("Text contrast is low against the canvas background.")
            )
            return -25
        }

        if contrast < 4.5 {
            findings.append(
                warning("Text contrast is borderline for small previews.")
            )
            return -10
        }

        findings.append(
            success("Text contrast meets common readability guidance.")
        )
        return 0
    }

    private static func contrastRatio(between firstColor: Color, and secondColor: Color) -> Double {
        let first = rgbaComponents(for: firstColor)
        let second = rgbaComponents(for: secondColor)
        let firstLuminance = relativeLuminance(red: first.red, green: first.green, blue: first.blue)
        let secondLuminance = relativeLuminance(red: second.red, green: second.green, blue: second.blue)
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)

        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(red: Double, green: Double, blue: Double) -> Double {
        0.2126 * linearized(red) + 0.7152 * linearized(green) + 0.0722 * linearized(blue)
    }

    private static func linearized(_ value: Double) -> Double {
        value <= 0.03928
            ? value / 12.92
            : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func rgbaComponents(for color: Color) -> (
        red: Double,
        green: Double,
        blue: Double,
        alpha: Double
    ) {
        let resolvedColor = UIColor(color)
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        if resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return (Double(red), Double(green), Double(blue), Double(alpha))
        }

        var white: CGFloat = 0
        resolvedColor.getWhite(&white, alpha: &alpha)
        return (Double(white), Double(white), Double(white), Double(alpha))
    }

    private static func success(_ message: String) -> ThumbnailReadinessFinding {
        ThumbnailReadinessFinding(severity: .success, message: message)
    }

    private static func warning(_ message: String) -> ThumbnailReadinessFinding {
        ThumbnailReadinessFinding(severity: .warning, message: message)
    }
}
