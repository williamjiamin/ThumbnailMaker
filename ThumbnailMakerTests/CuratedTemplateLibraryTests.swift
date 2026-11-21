//
//  CuratedTemplateLibraryTests.swift
//  ThumbnailMakerTests
//
//  TEMPLATES: the curated built-in library. Every layout instantiates,
//  renders without clipping text at 1280x720 and at its own aspect, passes
//  the readiness legibility checks, and has a unique id / name in a known
//  category. Existing built-ins keep their ids and order.
//

import Foundation
import SwiftUI
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct CuratedTemplateLibraryTests {
    static let curatedIDs = ThumbnailTemplate.curatedCatalog.map(\.template.id)
    static let landscape = CGSize(width: 1280, height: 720)

    static func entry(_ id: String) throws -> ThumbnailCuratedTemplate {
        try #require(ThumbnailTemplate.curatedEntry(id: id))
    }

    static func preset(of document: ThumbnailDocument) throws -> ThumbnailExportPreset {
        try #require(ThumbnailExportPreset.all.first { $0.id == document.export.presetID })
    }

    // MARK: Library shape

    @Test func libraryHoldsAboutThirtyTemplates() {
        #expect(ThumbnailTemplate.curatedLibrary.count >= 18)
        #expect((28...36).contains(ThumbnailTemplate.allBuiltIns.count))
    }

    @Test func existingBuiltInsKeepTheirIDsAndOrder() {
        #expect(ThumbnailTemplate.builtIns.map(\.id) == [
            "youtube-bold-launch", "short-form-hook", "podcast-clean-title", "gaming-impact", "vlog-story"
        ])
        #expect(ThumbnailTemplate.allBuiltIns.prefix(12).map(\.id) == [
            "youtube-bold-launch", "short-form-hook", "podcast-clean-title", "gaming-impact", "vlog-story",
            "quick-bold-center", "quick-bottom-title", "quick-top-corner", "quick-subtitle",
            "quick-full-width", "quick-minimal", "quick-epic-gameplay"
        ])
        #expect(Array(ThumbnailTemplate.allBuiltIns.suffix(ThumbnailTemplate.curatedLibrary.count))
            == ThumbnailTemplate.curatedLibrary)
    }

    @Test func idsAndNamesAreUniqueAcrossEveryBuiltIn() {
        let all = ThumbnailTemplate.allBuiltIns + [ThumbnailTemplate.quickCreateLayouts[0]]
        let ids = all.map(\.id)
        let names = all.map { $0.name.lowercased() }
        #expect(Set(ids).count == ids.count)
        #expect(Set(names).count == names.count)
        #expect(all.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    @Test func everyRequestedCategoryIsCovered() {
        let requested: [ThumbnailTemplateCategory] = [
            .gaming, .vlog, .tutorial, .reaction, .podcast, .shortForm,
            .beforeAfter, .listicle, .news, .minimal
        ]
        let curated = ThumbnailTemplate.curatedLibrary
        for category in requested {
            #expect(curated.contains { $0.category == category })
        }
        #expect(curated.allSatisfy { requested.contains($0.category) })
        let titles = ThumbnailTemplateCategory.allCases.map(\.title)
        #expect(Set(titles).count == titles.count)
        #expect(curated.filter { $0.document.canvas.aspectRatioRawValue == AspectRatio.ratio9_16.rawValue }.count >= 2)
    }

    @Test func newCategoriesRoundTripAndOlderBuildsFallBack() throws {
        let categories: [ThumbnailTemplateCategory] = [.beforeAfter, .listicle, .news, .minimal]
        let data = try JSONEncoder().encode(categories)
        #expect(try JSONDecoder().decode([ThumbnailTemplateCategory].self, from: data) == categories)
        let unknown = try JSONDecoder().decode([ThumbnailTemplateCategory].self, from: Data("[\"cooking\"]".utf8))
        #expect(unknown == [.youtube])
    }

    // MARK: Layout-only content

    @Test(arguments: curatedIDs)
    func templateIsLayoutOnly(id: String) throws {
        let template = try Self.entry(id).template
        let document = template.document
        #expect(template.origin == .builtIn)
        #expect(template.slots == .builtInDefaults)
        #expect(document.imageData == nil)
        #expect(document.profile == nil)
        #expect(document.formats == nil)
        #expect(document.editorMode == .simple)
        let contentLayers = document.layers.filter { $0.content != nil }
        #expect(contentLayers.allSatisfy { layer in
            if case .image = layer.content { return false }
            return true
        })
        let prefix = ThumbnailTemplate.builtInLayerID(templateID: id, role: "")
        #expect(contentLayers.allSatisfy { $0.id.hasPrefix(prefix) })
        #expect(contentLayers.count <= 3)
        #expect(CustomFont(rawValue: document.text.selectedFontRawValue) != nil)
        #expect(document.text.style != nil)
        let json = try JSONEncoder().encode(template)
        #expect(try JSONDecoder().decode(ThumbnailTemplate.self, from: json) == template)
    }

    @Test(arguments: curatedIDs)
    func headlineFollowsTheShortHeadlineRule(id: String) throws {
        let entry = try Self.entry(id)
        let headline = entry.template.document.text.value
        let words = headline.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        #expect((3...5).contains(words.count))
        #expect(headline.count <= 24)
        #expect(!entry.layoutNote.isEmpty)
    }

    @Test(arguments: curatedIDs)
    func paletteUsesTwoOrThreeColourFamilies(id: String) throws {
        let document = try Self.entry(id).template.document
        #expect((2...3).contains(ThumbnailTemplatePaletteAudit.colorFamilyCount(in: document)))
    }

    // MARK: Instantiation

    @Test(arguments: curatedIDs)
    func templateInstantiatesOverABlankAndAPhotoProject(id: String) throws {
        let template = try Self.entry(id).template
        let updatedAt = Date(timeIntervalSince1970: 7)

        let blank = ThumbnailDocument()
        let applied = template.application(over: blank, mode: .composition, updatedAt: updatedAt).document
        #expect(applied.text.value == template.document.text.value)
        #expect(applied.canvas == template.document.canvas)
        #expect(applied.layers.filter { $0.content != nil }.map(\.id)
            == template.document.layers.filter { $0.content != nil }.map(\.id))
        #expect(applied.updatedAt == updatedAt)

        var photoProject = ThumbnailDocument()
        photoProject.imageData = Data([0x1, 0x2, 0x3])
        let withPhoto = template.application(over: photoProject, mode: .composition).document
        #expect(withPhoto.imageData == photoProject.imageData)

        let personalPath = template.instantiate(over: photoProject, idProvider: { UUID().uuidString })
        #expect(personalPath.document.imageData == photoProject.imageData)
        #expect(personalPath.warnings.isEmpty)
        #expect(personalPath.newContentLayerIDs.count == template.document.layers.filter { $0.content != nil }.count)

        let styled = template.application(over: photoProject, mode: .styleOnly).document
        #expect(styled.text.style == template.document.text.style)
        #expect(styled.canvas.backgroundFill == template.document.canvas.backgroundFill)
    }

    @Test func switchingBuiltInLayoutsReplacesDecorationsInsteadOfStacking() throws {
        let first = try Self.entry("curated-news-breaking").template
        let second = try Self.entry("curated-listicle-top-five").template
        let firstIDs = Set(first.document.layers.filter { $0.content != nil }.map(\.id))
        let secondIDs = Set(second.document.layers.filter { $0.content != nil }.map(\.id))

        var project = first.makeDocument(preservingImagesFrom: ThumbnailDocument())
        let userShape = ThumbnailDocumentLayer.shapeLayer(id: "user-shape", zIndex: 90)
        project.layers.append(userShape)

        let switched = second.makeDocument(preservingImagesFrom: project)
        let switchedIDs = Set(switched.layers.filter { $0.content != nil }.map(\.id))
        #expect(switchedIDs.isDisjoint(with: firstIDs))
        #expect(secondIDs.isSubset(of: switchedIDs))
        #expect(switchedIDs.contains("user-shape"))

        // Re-applying the same layout keeps the creator's edits to its layers.
        var edited = switched
        let badgeID = ThumbnailTemplate.builtInLayerID(templateID: second.id, role: "burst")
        edited.layers.updateShapeContent(id: badgeID) { $0.fillColor = ThumbnailDocumentColor(red: 0, green: 1, blue: 0, alpha: 1) }
        let reapplied = second.makeDocument(preservingImagesFrom: edited)
        #expect(reapplied.layers.record(id: badgeID) == edited.layers.record(id: badgeID))
    }

    @Test func legacyBuiltInsAreUntouchedByTheLayoutSwitchRule() {
        let project = F.photoProjectWithUserLayers()
        for template in ThumbnailTemplate.builtIns + ThumbnailTemplate.quickCreateLayouts {
            let document = template.makeDocument(preservingImagesFrom: project)
            #expect(document.layers.contains { $0.id == "user-text" })
        }
    }

    // MARK: Readiness

    @Test(arguments: curatedIDs)
    func templatePassesReadinessLegibilityChecks(id: String) throws {
        let document = try Self.entry(id).template.makeDocument(updatedAt: Date(timeIntervalSince1970: 0))
        let report = ThumbnailReadinessAnalyzer.analyze(document.makeSimpleConfiguration())
        // A template ships without a photo on purpose; every other check must pass.
        let photoWarning = "Add an image before export so the design has a clear visual subject."
        let otherWarnings = report.findings.filter { $0.severity == .warning && $0.message != photoWarning }
        #expect(otherWarnings.isEmpty)
        #expect(report.findings.contains { $0.message == "Text contrast meets common readability guidance." })
        #expect(report.score >= 90)

        // Same design once the creator adds a photo: the photo warning goes away.
        var configuration = document.makeSimpleConfiguration()
        configuration.selectedImage = F.photo
        let withPhoto = ThumbnailReadinessAnalyzer.analyze(configuration)
        #expect(!withPhoto.hasWarnings)
    }

    @Test(arguments: curatedIDs)
    func headlineIsLegibleAt120PixelsWide(id: String) throws {
        let document = try Self.entry(id).template.document
        let ratio = try #require(AspectRatio(rawValue: document.canvas.aspectRatioRawValue))
        let previewHeight = 120 / ratio.value
        // Font size in points on a 120 px wide thumbnail.
        #expect(previewHeight * CGFloat(document.text.size) >= 15)
    }

    // MARK: Layout (no clipping)

    @Test(arguments: curatedIDs)
    func layoutFitsItsOwnAspectAndSafeZone(id: String) throws {
        let entry = try Self.entry(id)
        let document = entry.template.document
        let preset = try Self.preset(of: document)
        #expect(preset.aspectRatio.rawValue == document.canvas.aspectRatioRawValue)
        let issues = ThumbnailTemplateLayoutAudit.issues(
            in: document,
            canvasSize: preset.size.cgSize,
            safeZone: preset.safeZone,
            focalRegion: entry.focalRegion
        )
        #expect(issues == [])

        let headline = try #require(
            ThumbnailTemplateLayoutAudit.elements(in: document, canvasSize: preset.size.cgSize)
                .first { $0.kind == .headline }
        )
        #expect((1...3).contains(headline.lineCount))
    }

    @Test(arguments: curatedIDs)
    func layoutDoesNotClipAt1280x720(id: String) throws {
        let entry = try Self.entry(id)
        var document = entry.template.document
        if document.canvas.aspectRatioRawValue == AspectRatio.ratio16_9.rawValue {
            let issues = ThumbnailTemplateLayoutAudit.issues(
                in: document,
                canvasSize: Self.landscape,
                safeZone: ThumbnailExportPreset.youTubeThumbnail.safeZone,
                focalRegion: entry.focalRegion
            )
            #expect(issues == [])
        } else {
            // Other aspects reach 1280x720 through the FEATURE-09 size reflow.
            let format = ThumbnailFormatReflow.propose(master: document, kind: .landscape, sourceImageSize: nil)
            document = ThumbnailFormatResolver.resolvedDocument(master: document, format: format)
            let clipping = ThumbnailTemplateLayoutAudit.issues(in: document, canvasSize: Self.landscape, safeZone: nil)
                .filter { issue in
                    switch issue {
                    case .outsideCanvas, .textDoesNotFit: true
                    default: false
                    }
                }
            #expect(clipping == [])
        }
    }

    @Test func auditFlagsAHeadlineThatRunsOffTheCanvas() throws {
        var document = try Self.entry("curated-minimal-less-better").template.document
        document.text.transform.x = 0.9
        let issues = ThumbnailTemplateLayoutAudit.issues(in: document, canvasSize: Self.landscape, safeZone: nil)
        #expect(issues.contains(.outsideCanvas(layerID: ThumbnailDocumentLayer.textID)))

        document.text.transform.x = 0.33
        document.text.value = "THIS HEADLINE IS FAR TOO LONG FOR ANY THUMBNAIL"
        let long = ThumbnailTemplateLayoutAudit.issues(in: document, canvasSize: Self.landscape, safeZone: nil)
        #expect(!long.isEmpty)
    }

    @Test func auditFlagsTextInTheFocalRegionAndOverlappingBadges() throws {
        let entry = try Self.entry("curated-news-breaking")
        var document = entry.template.document
        document.text.transform.x = 0.7
        let issues = ThumbnailTemplateLayoutAudit.issues(
            in: document,
            canvasSize: Self.landscape,
            safeZone: nil,
            focalRegion: entry.focalRegion
        )
        #expect(issues.contains(.textCoversFocalRegion(layerID: ThumbnailDocumentLayer.textID)))

        var crowded = entry.template.document
        let badgeID = ThumbnailTemplate.builtInLayerID(templateID: entry.template.id, role: "badge")
        crowded.layers.updateShapeContent(id: badgeID) { $0.transform.y = crowded.text.transform.y }
        let overlap = ThumbnailTemplateLayoutAudit.issues(in: crowded, canvasSize: Self.landscape, safeZone: nil)
        #expect(overlap.contains(.textOverlapsText(first: badgeID, second: ThumbnailDocumentLayer.textID))
            || overlap.contains(.textOverlapsText(first: ThumbnailDocumentLayer.textID, second: badgeID)))
    }

    // MARK: Rendering

    @Test(arguments: curatedIDs)
    func renderedHeadlineInkStaysOnCanvasAndInsideTheAuditedBox(id: String) throws {
        let document = try Self.entry(id).template.document
        let preset = try Self.preset(of: document)
        // Render at a 1280-wide (or 720-wide for portrait) canvas of its own aspect.
        let long = CGFloat(1280)
        let aspect = preset.size.cgSize
        let canvas = aspect.width >= aspect.height
            ? CGSize(width: long, height: (long * aspect.height / aspect.width).rounded())
            : CGSize(width: 720, height: (720 * aspect.height / aspect.width).rounded())
        let margin: CGFloat = 160
        let text = document.text
        let fontSize = canvas.height * CGFloat(text.size)
        let font = try #require(CustomFont(rawValue: text.selectedFontRawValue))

        let view = ZStack {
            Color.clear
            StyledThumbnailTextView.overlay(
                text: text.value,
                font: font,
                color: text.color.color,
                fontSize: fontSize,
                style: text.style,
                canvasSize: canvas
            )
            .rotationEffect(.degrees(text.transform.rotationDegrees))
            .position(x: text.transform.x * canvas.width + margin, y: text.transform.y * canvas.height + margin)
        }
        .frame(width: canvas.width + 2 * margin, height: canvas.height + 2 * margin)

        let bitmap = try ThumbnailTextStyleRenderingTests.render(view)
        let ink = try #require(bitmap.inkBounds(alphaThreshold: 24))
        let onCanvas = CGRect(x: margin, y: margin, width: canvas.width, height: canvas.height)
        #expect(onCanvas.insetBy(dx: -1, dy: -1).contains(ink))

        let audited = try #require(
            ThumbnailTemplateLayoutAudit.elements(in: document, canvasSize: canvas).first { $0.kind == .headline }
        )
        let slack = fontSize * 0.08
        #expect(audited.rect.offsetBy(dx: margin, dy: margin).insetBy(dx: -slack, dy: -slack).contains(ink))
    }

    @Test(arguments: curatedIDs)
    func fullDocumentRendersAtExportSizes(id: String) throws {
        let document = try Self.entry(id).template.makeDocument(updatedAt: Date(timeIntervalSince1970: 0))
        let renderer = ThumbnailQueueDocumentRenderer()
        let preset = try Self.preset(of: document)
        let own = ThumbnailExportSize(width: preset.size.width / 4, height: preset.size.height / 4)
        let ownImage = try renderer.render(document, size: own)
        #expect(ownImage.size.width * ownImage.scale == CGFloat(own.width))
        #expect(ownImage.size.height * ownImage.scale == CGFloat(own.height))

        if document.canvas.aspectRatioRawValue == AspectRatio.ratio16_9.rawValue {
            let landscape = try renderer.render(document, size: ThumbnailExportSize(width: 1280, height: 720))
            #expect(landscape.size.width * landscape.scale == 1280)
            #expect(landscape.size.height * landscape.scale == 720)
        }
    }
}

// MARK: - Fixtures

private enum F {
    static let photo: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 9)).image { context in
        UIColor.gray.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 9))
    }

    static func photoProjectWithUserLayers() -> ThumbnailDocument {
        var document = ThumbnailDocument()
        document.imageData = Data([0x9])
        document.layers.append(ThumbnailDocumentLayer.textLayer(id: "user-text", value: "Mine", zIndex: 60))
        return document
    }
}
