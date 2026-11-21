//
//  QuickCreateShellTests.swift
//  ThumbnailMakerTests
//
//  SHELL (1.1.0 rebuild): gradient background fill recipe, the Quick Create
//  layouts, the wizard draft -> document mapping, and finishing the wizard
//  into a real, saved, undoable editor project.
//

import Foundation
import SwiftUI
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ThumbnailBackgroundFillTests {
    private let red = ThumbnailDocumentColor(red: 1, green: 0, blue: 0, alpha: 1)
    private let green = ThumbnailDocumentColor(red: 0, green: 1, blue: 0, alpha: 1)
    private let blue = ThumbnailDocumentColor(red: 0, green: 0, blue: 1, alpha: 1)

    @Test func linearGradientSpacesStopsEvenly() {
        let fill = ThumbnailBackgroundFill.linearGradient([red, green, blue], angleDegrees: 45)
        #expect(fill.kind == .linearGradient)
        #expect(fill.stops.map(\.location) == [0, 0.5, 1])
        #expect(fill.drawsGradient)
        #expect(fill.representativeColor == green)
    }

    @Test func normalizationClampsStopsLocationsAndAngle() {
        let messy = ThumbnailBackgroundFill(
            kind: .linearGradient,
            stops: [
                ThumbnailGradientStop(color: blue, location: 2),
                ThumbnailGradientStop(color: red, location: -1),
                ThumbnailGradientStop(color: green, location: .nan),
                ThumbnailGradientStop(color: green, location: 0.5)
            ],
            angleDegrees: -90
        ).normalized()
        #expect(messy.stops.count == 3)
        #expect(messy.stops.allSatisfy { (0...1).contains($0.location) })
        #expect(messy.stops.map(\.location) == messy.stops.map(\.location).sorted())
        #expect(messy.angleDegrees == 270)

        let single = ThumbnailBackgroundFill(stops: [ThumbnailGradientStop(color: red, location: 0)]).normalized()
        #expect(single.kind == .solid)
        #expect(single.drawsGradient == false)
    }

    @Test func angleMapsToUnitPoints() {
        let horizontal = ThumbnailBackgroundFill.linearGradient([red, blue], angleDegrees: 0)
        #expect(abs(horizontal.startPoint.x - 0) < 0.0001)
        #expect(abs(horizontal.endPoint.x - 1) < 0.0001)
        #expect(abs(horizontal.startPoint.y - 0.5) < 0.0001)

        let vertical = ThumbnailBackgroundFill.linearGradient([red, blue], angleDegrees: 90)
        #expect(abs(vertical.startPoint.y - 0) < 0.0001)
        #expect(abs(vertical.endPoint.y - 1) < 0.0001)
    }

    @Test func documentsWithoutAFillStillDecodeAndOmitTheKey() throws {
        let legacy = ThumbnailDocument(canvas: ThumbnailDocumentCanvas(backgroundColor: red))
        let data = try JSONEncoder().encode(legacy)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("backgroundFill") == false)
        let decoded = try JSONDecoder().decode(ThumbnailDocument.self, from: data)
        #expect(decoded.canvas.backgroundFill == nil)
        #expect(decoded.canvas.backgroundColor == red)
    }

    @Test func fillRoundTripsThroughDocumentAndBothEditorConfigurations() throws {
        let fill = ThumbnailBackgroundFill.linearGradient([red, green, blue], angleDegrees: 30)
        var document = ThumbnailDocument(canvas: ThumbnailDocumentCanvas(backgroundColor: red, backgroundFill: fill))
        document.text.value = "Gradient"

        let decoded = try JSONDecoder().decode(ThumbnailDocument.self, from: JSONEncoder().encode(document))
        #expect(decoded.canvas.backgroundFill == fill)

        let simple = decoded.makeSimpleConfiguration()
        #expect(simple.backgroundFill == fill)
        #expect(simple.document.canvas.backgroundFill == fill)

        let premium = decoded.makePremiumConfiguration()
        #expect(premium.backgroundFill == fill)
        #expect(premium.document.canvas.backgroundFill == fill)
    }

    @Test func corruptFillFallsBackToSolidInsteadOfFailingTheDocument() throws {
        let document = ThumbnailDocument(canvas: ThumbnailDocumentCanvas(backgroundColor: blue))
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any]
        )
        var canvas = try #require(object["canvas"] as? [String: Any])
        canvas["backgroundFill"] = ["kind": 42, "stops": "nope"]
        object["canvas"] = canvas
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ThumbnailDocument.self, from: data)
        #expect(decoded.canvas.backgroundFill == nil)
        #expect(decoded.canvas.backgroundColor == blue)
    }

    @Test func unknownFutureFillKindDecodesAsSolid() throws {
        let json = #"{"kind":"radialGradient","stops":[],"angleDegrees":0}"#
        let fill = try JSONDecoder().decode(ThumbnailBackgroundFill.self, from: Data(json.utf8))
        #expect(fill.kind == .solid)
    }

    @Test func gradientEditIsUndoableInTheSimpleEditor() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json"))
        )
        viewModel.simpleMakerConfiguration.overlayText = "Title"
        viewModel.commitEditorStateNow()

        viewModel.simpleMakerConfiguration.backgroundFill = .epicGameplay
        viewModel.commitEditorStateNow()
        #expect(viewModel.simpleMakerConfiguration.document.canvas.backgroundFill == .epicGameplay)

        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.backgroundFill == nil)
        viewModel.redo()
        #expect(viewModel.simpleMakerConfiguration.backgroundFill == .epicGameplay)
    }

    @Test func brandKitBackgroundReplacesAGradient() {
        var document = ThumbnailDocument(canvas: ThumbnailDocumentCanvas(backgroundColor: red, backgroundFill: .epicGameplay))
        document.text.value = "Brand"
        let kit = BrandKit(
            id: "kit",
            name: "Kit",
            palette: [
                BrandColor(id: "t", name: "Text", color: green),
                BrandColor(id: "b", name: "Background", color: blue)
            ],
            primaryFontRawValue: CustomFont.roboto.rawValue,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let branded = kit.applied(to: document, scope: .projectWide)
        #expect(branded.canvas.backgroundColor == blue)
        #expect(branded.canvas.backgroundFill == nil)
    }

    @Test func styleOnlyTemplateCarriesTheGradient() throws {
        let template = try #require(ThumbnailTemplate.quickCreateLayouts.first { $0.id == "quick-epic-gameplay" })
        let project = ThumbnailDocument(canvas: ThumbnailDocumentCanvas(backgroundColor: red))
        let applied = template.application(over: project, mode: .styleOnly).document
        #expect(applied.canvas.backgroundFill == .epicGameplay)
    }

    @Test func readinessUsesTheGradientForContrast() {
        var configuration = SimpleMakerConfigurationModel()
        configuration.overlayText = "Hello"
        configuration.textColor = .white
        configuration.backgroundColor = .white
        let lowContrast = ThumbnailReadinessAnalyzer.analyze(configuration)
        configuration.backgroundFill = .linearGradient([blue, ThumbnailDocumentColor(red: 0, green: 0, blue: 0.2, alpha: 1)])
        let withGradient = ThumbnailReadinessAnalyzer.analyze(configuration)
        #expect(withGradient.score > lowContrast.score)
    }
}

@MainActor
struct QuickCreateDraftTests {
    @Test func layoutsMatchThe110Screenshots() {
        let names = ThumbnailTemplate.quickCreateLayouts.map(\.name)
        #expect(names == [
            "Blank", "Bold Center", "Bottom Title", "Top Corner",
            "Subtitle", "Full Width", "Minimal", "EPIC GAMEPLAY"
        ])
        let epic = ThumbnailTemplate.quickCreateLayouts.last
        #expect(epic?.document.canvas.backgroundFill?.drawsGradient == true)
        #expect(epic?.category == .gaming)
    }

    @Test func builtInsAreExtendedNotReplaced() {
        #expect(ThumbnailTemplate.builtIns.count == 5)
        #expect(Array(ThumbnailTemplate.allBuiltIns.prefix(5)) == ThumbnailTemplate.builtIns)
        // TEMPLATES: the curated library is appended after the 1.1.0 layouts.
        #expect(ThumbnailTemplate.allBuiltIns.count == 5 + 7 + ThumbnailTemplate.curatedLibrary.count)
        #expect(!ThumbnailTemplate.allBuiltIns.contains { $0.id == ThumbnailTemplate.quickCreateBlankID })
        let ids = ThumbnailTemplate.allBuiltIns.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func formatsMapOntoExistingRatiosAndPresets() {
        #expect(QuickCreateFormat.allCases.map(\.ratioLabel) == ["16:9", "9:16", "1:1", "4:3", "3:4"])
        for format in QuickCreateFormat.allCases {
            #expect(format.exportPreset.aspectRatio == format.aspectRatio)
            #expect(ThumbnailExportPreset.all.contains(format.exportPreset))
        }
    }

    @Test func stepsMoveForwardAndBackWithinBounds() {
        var draft = QuickCreateDraft()
        draft.goBack()
        #expect(draft.step == .template)
        for _ in 0..<10 { draft.goForward() }
        #expect(draft.step == .export)
        draft.goBack()
        #expect(draft.step == .style)
    }

    @Test func categoryFilterKeepsBlankAndResetsAHiddenSelection() {
        var draft = QuickCreateDraft()
        draft.templateID = "quick-bold-center"
        draft.selectCategory(.gaming)
        #expect(draft.visibleLayouts.map(\.id) == [ThumbnailTemplate.quickCreateBlankID, "quick-epic-gameplay"])
        #expect(draft.templateID == ThumbnailTemplate.quickCreateBlankID)

        draft.templateID = "quick-epic-gameplay"
        draft.selectCategory(.all)
        #expect(draft.templateID == "quick-epic-gameplay")
        #expect(draft.visibleLayouts.count == 8)
    }

    @Test func documentUsesFormatTitleFontColorAndExportChoices() throws {
        var draft = QuickCreateDraft()
        draft.format = .pinterest
        draft.templateID = "quick-bottom-title"
        draft.title = "  My Trip  "
        draft.font = .roboto
        draft.titleColor = ThumbnailDocumentColor(red: 1, green: 0, blue: 0, alpha: 1)
        draft.exportFormat = .jpeg

        let document = draft.makeDocument(now: Date(timeIntervalSince1970: 7))
        #expect(document.canvas.aspectRatioRawValue == AspectRatio.ratio3_4.rawValue)
        #expect(document.export.presetID == ThumbnailExportPreset.portraitCover.id)
        #expect(document.export.formatRawValue == ThumbnailExportFormat.jpeg.rawValue)
        #expect(document.text.value.contains("My Trip"))
        #expect(document.text.selectedFontRawValue == CustomFont.roboto.rawValue)
        #expect(document.text.color == ThumbnailDocumentColor(red: 1, green: 0, blue: 0, alpha: 1))
        #expect(abs(document.text.transform.y - 0.8) < 0.001)
        #expect(document.updatedAt == Date(timeIntervalSince1970: 7))
        #expect(document.layers.contains { $0.id == ThumbnailDocumentLayer.textID })
        #expect(draft.projectName == "My Trip")
    }

    @Test func emptyTitleKeepsThePlaceholderAndBlankStaysEmpty() {
        var draft = QuickCreateDraft()
        draft.templateID = "quick-bold-center"
        #expect(draft.makeDocument().text.value == "YOUR TEXT")

        draft.templateID = ThumbnailTemplate.quickCreateBlankID
        let blank = draft.makeDocument()
        #expect(blank.text.value.isEmpty)
        #expect(!blank.layers.contains { $0.content != nil })
        #expect(draft.projectName == "Quick Create")
    }

    @Test func subtitleBecomesASecondTextLayer() throws {
        var draft = QuickCreateDraft()
        draft.templateID = "quick-bold-center"
        draft.title = "Title"
        draft.subtitle = "The subtitle"
        let document = draft.makeDocument(idProvider: { "sub-1" })
        let subtitle = try #require(document.layers.first { $0.id == "sub-1" })
        guard case .text(let content) = subtitle.content else {
            Issue.record("subtitle should be a text layer")
            return
        }
        #expect(content.value == "The subtitle")
        #expect(content.transform.y > document.text.transform.y)

        // A bottom title puts the subtitle above it.
        draft.templateID = "quick-bottom-title"
        let bottom = draft.makeDocument(idProvider: { "sub-2" })
        let above = try #require(bottom.layers.first { $0.id == "sub-2" })
        guard case .text(let aboveContent) = above.content else {
            Issue.record("subtitle should be a text layer")
            return
        }
        #expect(aboveContent.transform.y < bottom.text.transform.y)
    }

    @Test func subtitleLayoutFillsItsOwnLineWithAFreshID() throws {
        var draft = QuickCreateDraft()
        draft.templateID = "quick-subtitle"
        draft.subtitle = "Episode 4"
        let document = draft.makeDocument(idProvider: { "fresh" })
        #expect(!document.layers.contains { $0.id == ThumbnailTemplate.quickCreateSubtitleLayerID })
        let line = try #require(document.layers.first { $0.id == "fresh" })
        guard case .text(let content) = line.content else {
            Issue.record("expected text")
            return
        }
        #expect(content.value == "Episode 4")
        #expect(document.layers.filter { $0.content != nil }.count == 1)
    }

    @Test func styleStepAppliesTextStyleBackgroundAndBrandKitInOrder() throws {
        var draft = QuickCreateDraft()
        draft.templateID = "quick-bold-center"
        draft.subtitle = "Sub"
        draft.textStylePresetID = "boldOutline"
        let styled = draft.makeDocument()
        #expect(styled.text.style?.presetID == "boldOutline")
        let subtitle = try #require(styled.layers.first { $0.content != nil })
        if case .text(let content) = subtitle.content {
            #expect(content.style?.presetID == "boldOutline")
        } else {
            Issue.record("expected text")
        }

        let violet = ThumbnailBackgroundFill.presets[1].fill
        draft.background = .gradient(violet)
        #expect(draft.makeDocument().canvas.backgroundFill == violet)

        let kitBackground = ThumbnailDocumentColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        let kit = BrandKit(
            id: "kit",
            name: "Kit",
            palette: [
                BrandColor(id: "t", name: "Text", color: ThumbnailDocumentColor(red: 1, green: 1, blue: 0, alpha: 1)),
                BrandColor(id: "b", name: "Background", color: kitBackground)
            ],
            primaryFontRawValue: CustomFont.lato.rawValue,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        // An explicit background (chosen after the kit on the same step) wins.
        let withKitAndGradient = draft.makeDocument(brandKit: kit)
        #expect(withKitAndGradient.canvas.backgroundFill == violet)
        #expect(withKitAndGradient.text.selectedFontRawValue == CustomFont.lato.rawValue)

        draft.background = .layout
        let withKit = draft.makeDocument(brandKit: kit)
        #expect(withKit.canvas.backgroundColor == kitBackground)
        #expect(withKit.canvas.backgroundFill == nil)
        #expect(withKit.branding.appliedBrandKitID == "kit")

        let solid = ThumbnailDocumentColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        draft.background = .solid(solid)
        let solidDocument = draft.makeDocument(brandKit: kit)
        #expect(solidDocument.canvas.backgroundColor == solid)
        #expect(solidDocument.canvas.backgroundFill == nil)
    }

    @Test func epicGameplayKeepsItsGradientByDefault() {
        var draft = QuickCreateDraft()
        draft.templateID = "quick-epic-gameplay"
        draft.format = .shorts
        let document = draft.makeDocument()
        #expect(document.canvas.backgroundFill == .epicGameplay)
        #expect(document.canvas.aspectRatioRawValue == AspectRatio.ratio9_16.rawValue)
        #expect(document.export.presetID == ThumbnailExportPreset.shortFormCover.id)
    }

    @Test func initialStageHonoursLaunchArguments() {
        #expect(CreateStage.initial(arguments: []) == .home)
        #expect(CreateStage.initial(arguments: ["-UITestSkipHome"]) == .simpleEditor)
        #expect(CreateStage.initial(arguments: ["-UITestSkipHome", "-UITestStartPremiumTab"]) == .premiumEditor)
        #expect(CreateStage.initial(arguments: ["-UITestStartPremiumTab"]) == .premiumEditor)
    }
}

@MainActor
struct QuickCreateEditorIntegrationTests {
    private func makeViewModel(root: URL, library: ThumbnailProjectLibrary?) -> SimpleMakerViewModel {
        SimpleMakerViewModel(
            draftStore: ThumbnailDraftStore(fileURL: root.appendingPathComponent("Drafts/simple.json")),
            brandKitStore: BrandKitStore(fileURL: root.appendingPathComponent("brand.json")),
            projectLibrary: library
        )
    }

    @Test func finishingCreatesANewSavedProjectAndLeavesTheOldOneAlone() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)
        let viewModel = makeViewModel(root: root, library: library)
        let originalID = try #require(viewModel.activeProjectID)
        viewModel.simpleMakerConfiguration.overlayText = "Keep me"
        viewModel.commitEditorStateNow()

        var draft = QuickCreateDraft()
        draft.templateID = "quick-epic-gameplay"
        draft.title = "Boss Fight"
        draft.format = .instagram
        #expect(viewModel.finishQuickCreate(draft))

        let newID = try #require(viewModel.activeProjectID)
        #expect(newID != originalID)
        #expect(viewModel.activeProjectName == "Boss Fight")
        #expect(viewModel.simpleMakerConfiguration.overlayText == "Boss Fight")
        #expect(viewModel.simpleMakerConfiguration.selectedRatio == .ratio1_1)
        #expect(viewModel.simpleMakerConfiguration.backgroundFill == .epicGameplay)
        #expect(viewModel.simpleMakerConfiguration.exportOptions.preset == .instagramSquare)

        // Saved: the library holds the wizard's document...
        let saved = try library.document(for: newID)
        #expect(saved.text.value == "Boss Fight")
        #expect(saved.canvas.backgroundFill == .epicGameplay)
        // ...and the previous project is untouched.
        #expect(try library.document(for: originalID).text.value == "Keep me")

        // Undoable: one step back is the blank new project.
        #expect(viewModel.canUndo)
        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.overlayText.isEmpty)
        #expect(viewModel.simpleMakerConfiguration.backgroundFill == nil)
        #expect(viewModel.activeProjectID == newID)
        viewModel.redo()
        #expect(viewModel.simpleMakerConfiguration.overlayText == "Boss Fight")
    }

    @Test func finishingWithoutALibraryAppliesInPlaceAndIsUndoable() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let viewModel = makeViewModel(root: root, library: nil)
        #expect(viewModel.activeProjectID == nil)

        var draft = QuickCreateDraft()
        draft.templateID = "quick-top-corner"
        draft.title = "How To"
        #expect(viewModel.finishQuickCreate(draft))
        #expect(viewModel.simpleMakerConfiguration.overlayText == "How To")
        #expect(viewModel.canUndo)
        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.overlayText.isEmpty)
    }

    @Test func startFromScratchKeepsAnEmptyProjectButNeverReplacesWork() throws {
        let root = ProjectTestSupport.makeTemporaryDirectory()
        defer { ProjectTestSupport.cleanUp(root) }
        let library = ProjectTestSupport.makeLibrary(root: root)
        let viewModel = makeViewModel(root: root, library: library)
        let emptyID = try #require(viewModel.activeProjectID)

        #expect(viewModel.startFromScratch())
        #expect(viewModel.activeProjectID == emptyID)

        viewModel.simpleMakerConfiguration.overlayText = "Work"
        viewModel.commitEditorStateNow()
        #expect(viewModel.startFromScratch())
        let freshID = try #require(viewModel.activeProjectID)
        #expect(freshID != emptyID)
        #expect(viewModel.simpleMakerConfiguration.overlayText.isEmpty)
        #expect(try library.document(for: emptyID).text.value == "Work")
    }

    @Test func completingQuickCreateSkipsAnUnstartedFirstExportGuideOnly() {
        let fresh = FirstExportGuideController(store: .inMemory())
        #expect(fresh.progress.status == .notStarted)
        fresh.recordQuickCreateCompleted()
        #expect(fresh.progress.status == .skipped)
        #expect(FirstExportGuideReducer.shouldOfferOnLaunch(
            fresh.progress,
            snapshot: .empty
        ) == false)

        let active = FirstExportGuideController(
            store: .inMemory(FirstExportGuideProgress(status: .active, currentStep: .addVisual))
        )
        active.recordQuickCreateCompleted()
        #expect(active.progress.status == .active)
    }
}
