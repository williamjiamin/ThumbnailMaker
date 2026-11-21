//
//  ThumbnailMakerTests.swift
//  ThumbnailMakerTests
//
//  Created by william on 2024/11/22.
//

import SwiftUI
import Testing
import UIKit
@testable import ThumbnailMaker

struct ThumbnailMakerTests {

    @Test func detectsFallbackForUnsupportedCharacters() async throws {
        #expect(FontManager.shared.needsFallback(for: "測試測試", selectedFont: .roboto))
        #expect(!FontManager.shared.needsFallback(for: "Test title", selectedFont: .roboto))
        #expect(!FontManager.shared.needsFallback(for: "測試測試", selectedFont: .goNoto))
    }

    @Test func extractsYouTubeVideoIDsFromCommonURLFormats() async throws {
        let expectedID = "dQw4w9WgXcQ"
        let urls = [
            "https://www.youtube.com/watch?v=\(expectedID)",
            "https://m.youtube.com/watch?v=\(expectedID)&feature=youtu.be",
            "https://youtu.be/\(expectedID)?si=abc123",
            "https://www.youtube.com/embed/\(expectedID)",
            "https://www.youtube.com/shorts/\(expectedID)",
            "https://www.youtube.com/live/\(expectedID)",
            expectedID
        ]

        for url in urls {
            #expect(YouTubeService.extractVideoID(from: url) == expectedID)
        }
    }

    @Test func rejectsNonYouTubeOrMalformedVideoIDs() async throws {
        let invalidInputs = [
            "",
            "https://example.com/watch?v=dQw4w9WgXcQ",
            "https://notyoutube.com/watch?v=dQw4w9WgXcQ",
            "https://www.youtube.com/watch?v=too-short",
            "not-a-video-id"
        ]

        for input in invalidInputs {
            #expect(YouTubeService.extractVideoID(from: input) == nil)
        }
    }

    @Test func exportPresetsCoverCoreCreatorFormats() async throws {
        let presetsByID = Dictionary(
            uniqueKeysWithValues: ThumbnailExportPreset.all.map { ($0.id, $0) }
        )

        #expect(presetsByID["youtube-thumbnail"]?.size == ThumbnailExportSize(width: 3840, height: 2160))
        #expect(presetsByID["short-form-cover"]?.size == ThumbnailExportSize(width: 1080, height: 1920))
        #expect(presetsByID["instagram-square"]?.size == ThumbnailExportSize(width: 1080, height: 1080))
        #expect(presetsByID["instagram-reels-cover"]?.size == ThumbnailExportSize(width: 1080, height: 1682))
        #expect(presetsByID["podcast-cover"]?.size == ThumbnailExportSize(width: 3000, height: 3000))
    }

    @Test func exportPresetsProvideValidSafeZoneGuides() async throws {
        let safeZones = ThumbnailExportPreset.all.compactMap(\.safeZone)

        #expect(safeZones.count == ThumbnailExportPreset.all.count)
        for safeZone in safeZones {
            #expect(safeZone.hasValidNormalizedInsets)
            #expect(!safeZone.name.isEmpty)
            #expect(!safeZone.guidance.isEmpty)

            let rect = safeZone.contentRect(in: CGSize(width: 1000, height: 1000))
            #expect(rect.minX >= 0)
            #expect(rect.minY >= 0)
            #expect(rect.maxX <= 1000)
            #expect(rect.maxY <= 1000)
            #expect(rect.width > 0)
            #expect(rect.height > 0)
        }
    }

    @Test func shortFormSafeZoneUsesExpectedVerticalUiInsets() async throws {
        let safeZone = try #require(ThumbnailExportPreset.shortFormCover.safeZone)
        let rect = safeZone.contentRect(in: CGSize(width: 1080, height: 1920))

        #expect(abs(rect.minX - 86.4) < 0.01)
        #expect(abs(rect.minY - 230.4) < 0.01)
        #expect(abs(rect.width - 777.6) < 0.01)
        #expect(abs(rect.height - 1228.8) < 0.01)
    }

    @Test func instagramReelsCoverUsesPlatformCoverCropRatio() async throws {
        let preset = ThumbnailExportPreset.instagramReelsCover
        let safeZone = try #require(preset.safeZone)
        let rect = safeZone.contentRect(in: preset.size.cgSize)

        #expect(preset.aspectRatio == .ratioReelsCover)
        #expect(abs(preset.aspectRatio.value - (420.0 / 654.0)) < 0.001)
        #expect(preset.size.width == 1080)
        #expect(preset.size.height == 1682)
        #expect(abs((Double(preset.size.width) / Double(preset.size.height)) - (420.0 / 654.0)) < 0.001)
        #expect(abs(rect.minX - 86.4) < 0.01)
        #expect(abs(rect.minY - 168.2) < 0.01)
        #expect(abs(rect.width - 907.2) < 0.01)
        #expect(abs(rect.height - 1278.32) < 0.01)
        #expect(safeZone.guidance.localizedCaseInsensitiveContains("420 x 654"))
    }

    @Test func backgroundRemovalReportsCurrentPlatformSupport() async throws {
        if #available(iOS 17.0, macCatalyst 17.0, *) {
            #expect(BackgroundRemovalService.supportsForegroundMask)
        } else {
            #expect(!BackgroundRemovalService.supportsForegroundMask)
        }
    }

    @Test func backgroundRemovalRejectsImagesWithoutCGImage() async throws {
        let service = BackgroundRemovalService()

        do {
            _ = try await service.removeBackground(from: UIImage())
            Issue.record("Expected background removal to reject an empty image")
        } catch let error as BackgroundRemovalError {
            #expect(error == .missingCGImage || error == .foregroundMaskUnavailable)
        }
    }

    @Test func suggestedFaceCropPadsAndClampsNormalizedBounds() async throws {
        let crop = try #require(
            BackgroundRemovalService.suggestedFaceCrop(
                for: [
                    CGRect(x: 0.74, y: 0.76, width: 0.22, height: 0.2),
                    CGRect(x: 0.08, y: 0.12, width: 0.18, height: 0.16)
                ],
                padding: 0.25
            )
        )

        #expect(crop.minX >= 0)
        #expect(crop.minY >= 0)
        #expect(crop.maxX <= 1)
        #expect(crop.maxY <= 1)
        #expect(crop.contains(CGPoint(x: 0.17, y: 0.2)))
        #expect(crop.contains(CGPoint(x: 0.85, y: 0.86)))
    }

    @Test func normalizedVisionCropProducesExpectedImageBounds() async throws {
        let image = Self.makeSolidImage(size: CGSize(width: 80, height: 40))

        let fullCrop = try #require(
            BackgroundRemovalService.croppedImage(
                image,
                toNormalizedVisionRect: CGRect(x: 0, y: 0, width: 1, height: 1)
            )
        )
        let quarterCrop = try #require(
            BackgroundRemovalService.croppedImage(
                image,
                toNormalizedVisionRect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
            )
        )

        #expect(fullCrop.size == image.size)
        #expect(quarterCrop.size == CGSize(width: 40, height: 20))
        #expect(
            BackgroundRemovalService.croppedImage(
                image,
                toNormalizedVisionRect: CGRect(x: 0.2, y: 0.2, width: 0, height: 0.4)
            ) == nil
        )
    }

    @Test func brandKitRoundTripsThroughCodable() async throws {
        let brandKit = Self.makeBrandKit()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(brandKit)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BrandKit.self, from: data)

        #expect(decoded == brandKit)
        #expect(decoded.version == BrandKit.currentVersion)
    }

    @Test func brandKitDecodesLegacyWithoutVersion() async throws {
        let legacyJSON = """
        {
          "id": "legacy-kit",
          "name": "Legacy Kit",
          "palette": [],
          "primaryFontRawValue": "\(CustomFont.roboto.rawValue)",
          "updatedAt": "2026-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BrandKit.self, from: legacyJSON)

        #expect(decoded.version == BrandKit.currentVersion)
        #expect(decoded.primaryFont == .roboto)
    }

    @Test func brandKitAppliesPaletteAndFontToConfiguration() async throws {
        let brandKit = Self.makeBrandKit()
        var configuration = SimpleMakerConfigurationModel()
        configuration.textColor = .white
        configuration.backgroundColor = .black
        configuration.selectedFont = .roboto

        let styled = brandKit.applied(to: configuration)

        #expect(styled.selectedFont == .montserrat)
        #expect(configuration.selectedFont == .roboto)
        #expect(Self.colorComponents(styled.textColor) == [255, 214, 64, 255])
        #expect(Self.colorComponents(styled.backgroundColor) == [18, 26, 38, 255])
    }

    @Test func brandKitStoreRoundTripsAndReturnsNilWhenMissing() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("brand-kit.json")
        let store = BrandKitStore(fileURL: url)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        #expect(try store.load() == nil)

        let brandKit = Self.makeBrandKit()
        try store.save(brandKit)

        let restored = try #require(try store.load())
        #expect(restored.id == brandKit.id)
        #expect(restored.name == brandKit.name)
        #expect(restored.palette == brandKit.palette)
        #expect(restored.primaryFont == .montserrat)

        try store.delete()
        #expect(try store.load() == nil)
    }

    @Test func thumbnailTemplateRoundTripsThroughCodable() async throws {
        let template = try #require(ThumbnailTemplate.builtIns.first)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(template)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ThumbnailTemplate.self, from: data)

        #expect(decoded == template)
        #expect(decoded.version == ThumbnailTemplate.currentVersion)
    }

    @Test func thumbnailTemplateInstantiationStripsImageData() async throws {
        var template = try #require(ThumbnailTemplate.builtIns.first)
        template.document.imageData = Data([1, 2, 3])
        template.document.profile = ThumbnailDocumentProfile(imageData: Data([4, 5, 6]))

        let updatedAt = Date(timeIntervalSince1970: 1_900_000_000)
        let document = template.makeDocument(updatedAt: updatedAt)

        #expect(document.imageData == nil)
        #expect(document.profile?.imageData == nil)
        #expect(document.updatedAt == updatedAt)
    }

    @Test func thumbnailTemplateApplicationPreservesBackgroundImageData() async throws {
        let template = try #require(ThumbnailTemplate.builtIns.first)
        let imageData = Data([9, 8, 7])
        let existingDocument = ThumbnailDocument(
            imageData: imageData,
            text: ThumbnailDocumentText(value: "Existing")
        )
        let updatedAt = Date(timeIntervalSince1970: 1_900_000_100)

        let document = template.makeDocument(
            preservingImagesFrom: existingDocument,
            updatedAt: updatedAt
        )

        #expect(document.imageData == imageData)
        #expect(document.profile == nil)
        #expect(document.canvas == template.document.canvas)
        #expect(document.text == template.document.text)
        #expect(document.export == template.document.export)
        #expect(document.updatedAt == updatedAt)
    }

    @Test func thumbnailTemplateApplicationPreservesExistingProfileImageAndLayer() async throws {
        let template = try #require(ThumbnailTemplate.builtIns.first)
        let profileData = Data([4, 5, 6])
        var profileLayer = ThumbnailDocumentLayer.defaultProfileLayer
        profileLayer.isLocked = true
        profileLayer.zIndex = 12
        let existingDocument = ThumbnailDocument(
            text: ThumbnailDocumentText(value: "Existing"),
            profile: ThumbnailDocumentProfile(
                imageData: profileData,
                size: 0.31,
                transform: ThumbnailOverlayTransform(
                    x: 0.74,
                    y: 0.22,
                    rotationDegrees: 11
                )
            ),
            layers: [
                ThumbnailDocumentLayer.defaultBackgroundLayer,
                profileLayer,
                ThumbnailDocumentLayer.defaultTextLayer
            ]
        )

        let document = template.makeDocument(preservingImagesFrom: existingDocument)

        #expect(document.profile?.imageData == profileData)
        #expect(document.profile?.size == 0.31)
        #expect(document.profile?.transform == ThumbnailOverlayTransform(
            x: 0.74,
            y: 0.22,
            rotationDegrees: 11
        ))
        #expect(document.layers.record(for: .profile)?.isLocked == true)
        #expect(document.layers.record(for: .profile)?.zIndex == 12)
        #expect(document.layers.map(\.id).contains(ThumbnailDocumentLayer.profileID))
    }

    @Test func builtInTemplatesAreStableAndUnique() async throws {
        let firstRead = ThumbnailTemplate.builtIns
        let secondRead = ThumbnailTemplate.builtIns
        let ids = firstRead.map(\.id)

        #expect(!firstRead.isEmpty)
        #expect(firstRead == secondRead)
        #expect(Set(ids).count == ids.count)
        #expect(firstRead.allSatisfy { $0.document.imageData == nil })
        #expect(
            firstRead.first { $0.id == "podcast-clean-title" }?.document.export.presetID
                == ThumbnailExportPreset.podcastCover.id
        )
    }

    @Test func boldLaunchTemplateTextFrameStaysInsideCanvas() async throws {
        let template = try #require(ThumbnailTemplate.builtIns.first { $0.id == "youtube-bold-launch" })
        let aspectRatio = try #require(AspectRatio(rawValue: template.document.canvas.aspectRatioRawValue))
        let dimensions = aspectRatio.dimensions
        let transform = template.document.text.transform
        let textFrame = rotatedBounds(
            center: CGPoint(x: dimensions.width * transform.x, y: dimensions.height * transform.y),
            size: CGSize(
                width: dimensions.width * 0.96,
                height: dimensions.height * (template.document.text.size + 0.06)
            ),
            degrees: transform.rotationDegrees
        )

        #expect(textFrame.minX >= 0)
        #expect(textFrame.maxX <= dimensions.width)
        #expect(textFrame.minY >= 0)
        #expect(textFrame.maxY <= dimensions.height)
    }

    @Test func suggestionEngineRecommendsShortenForDenseText() async throws {
        var configuration = SimpleMakerConfigurationModel()
        configuration.overlayText = "This is a very long thumbnail title with too many words for a small mobile preview"

        let suggestions = LocalThumbnailSuggestionProvider().suggestions(
            for: configuration,
            brandKit: nil,
            templates: ThumbnailTemplate.builtIns
        )

        #expect(suggestions.contains { $0.action == .shortenText })
    }

    @Test func suggestionEngineRecommendsBrandColorOnLowContrast() async throws {
        var configuration = SimpleMakerConfigurationModel()
        configuration.overlayText = "Low contrast"
        configuration.backgroundColor = .white
        configuration.textColor = .white

        let suggestions = LocalThumbnailSuggestionProvider().suggestions(
            for: configuration,
            brandKit: Self.makeBrandKit(),
            templates: ThumbnailTemplate.builtIns
        )

        #expect(suggestions.contains { $0.action == .applyBrandColor(role: .text) })
        #expect(suggestions.contains { $0.id == "brand-apply-kit" })
        #expect(suggestions.first { $0.id == "brand-apply-kit" }?.isCurrentlyActionableInEditor == true)
    }

    @Test func suggestionEngineOnlyRecommendsBrandKitWhenPaletteExists() async throws {
        var configuration = SimpleMakerConfigurationModel()
        configuration.overlayText = "Low contrast"
        configuration.backgroundColor = .white
        configuration.textColor = .white
        let provider = LocalThumbnailSuggestionProvider()

        let nilBrandSuggestions = provider.suggestions(
            for: configuration,
            brandKit: nil,
            templates: ThumbnailTemplate.builtIns
        )
        let emptyBrandSuggestions = provider.suggestions(
            for: configuration,
            brandKit: BrandKit(
                id: "empty-kit",
                name: "Empty Kit",
                palette: [],
                primaryFontRawValue: CustomFont.roboto.rawValue,
                updatedAt: Date(timeIntervalSince1970: 1)
            ),
            templates: ThumbnailTemplate.builtIns
        )

        #expect(!nilBrandSuggestions.contains {
            if case .applyBrandColor = $0.action { return true }
            return false
        })
        #expect(!emptyBrandSuggestions.contains {
            if case .applyBrandColor = $0.action { return true }
            return false
        })
    }

    @Test func suggestionEngineIsDeterministic() async throws {
        var configuration = SimpleMakerConfigurationModel()
        configuration.overlayText = "Stable suggestions"
        configuration.backgroundColor = .white
        configuration.textColor = .white

        let provider = LocalThumbnailSuggestionProvider()
        let first = provider.suggestions(
            for: configuration,
            brandKit: Self.makeBrandKit(),
            templates: ThumbnailTemplate.builtIns
        )
        let second = provider.suggestions(
            for: configuration,
            brandKit: Self.makeBrandKit(),
            templates: ThumbnailTemplate.builtIns
        )

        #expect(first == second)
    }

    @Test func titleIdeaProviderReturnsEmptyForBlankTitle() async throws {
        let provider = LocalThumbnailIdeaProvider()

        #expect(
            provider.ideas(
                forTitle: "   ",
                ratio: .ratio16_9,
                brandKit: nil,
                templates: ThumbnailTemplate.builtIns
            ).isEmpty
        )
    }

    @Test func titleIdeaProviderIsDeterministicAndInjectsCurrentTitle() async throws {
        let provider = LocalThumbnailIdeaProvider()
        let title = "How I grew my channel"
        let first = provider.ideas(
            forTitle: title,
            ratio: .ratio16_9,
            brandKit: Self.makeBrandKit(),
            templates: ThumbnailTemplate.builtIns
        )
        let second = provider.ideas(
            forTitle: title,
            ratio: .ratio16_9,
            brandKit: Self.makeBrandKit(),
            templates: ThumbnailTemplate.builtIns
        )

        #expect(!first.isEmpty)
        #expect(first == second)
        #expect(first.allSatisfy { $0.template.document.text.value == title })
        #expect(first.count <= 5)
    }

    @Test func titleIdeaProviderPrefersMatchingRatioAndProducesVariantKinds() async throws {
        let ideas = LocalThumbnailIdeaProvider().ideas(
            forTitle: "Wait for this secret short",
            ratio: .ratio9_16,
            brandKit: nil,
            templates: ThumbnailTemplate.builtIns
        )

        #expect(ideas.contains { $0.kind == .layout })
        #expect(ideas.contains { $0.kind == .style || $0.kind == .color })
        #expect(ideas.contains {
            $0.kind == .layout
                && $0.template.document.canvas.aspectRatioRawValue == AspectRatio.ratio9_16.rawValue
        })
        #expect(ideas.count <= 5)
    }

    @Test func titleIdeaProviderUsesBrandPaletteForColorIdeas() async throws {
        let brandKit = Self.makeBrandKit()
        let ideas = LocalThumbnailIdeaProvider().ideas(
            forTitle: "Launch my next video",
            ratio: .ratio16_9,
            brandKit: brandKit,
            templates: ThumbnailTemplate.builtIns
        )
        let colorIdea = try #require(ideas.first { $0.kind == .color })

        #expect(colorIdea.template.document.text.color == brandKit.palette[0].color)
        #expect(colorIdea.template.document.canvas.backgroundColor == brandKit.palette[1].color)
    }

    @Test func suggestionTextShortenerClearsDenseTextAndIsIdempotent() async throws {
        let denseText = "🚀 This launch plan needs a much tighter thumbnail title before people can read it on phones"
        let shortenedText = ThumbnailSuggestionTextShortener.shortened(denseText)
        var configuration = SimpleMakerConfigurationModel()
        configuration.overlayText = shortenedText

        let report = ThumbnailReadinessAnalyzer.analyze(configuration)

        #expect(shortenedText.count <= ThumbnailSuggestionTextShortener.maximumCharacterCount)
        #expect(
            shortenedText
                .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                .count <= ThumbnailSuggestionTextShortener.maximumWordCount
        )
        #expect(shortenedText.hasPrefix("🚀"))
        #expect(ThumbnailSuggestionTextShortener.shortened(shortenedText) == shortenedText)
        #expect(!report.findings.contains {
            $0.message.localizedCaseInsensitiveContains("dense")
        })
        #expect(ThumbnailSuggestionTextShortener.shortened("") == "")
        #expect(ThumbnailSuggestionTextShortener.shortened("Short title") == "Short title")
    }

    @MainActor
    @Test func simpleViewModelAppliesActionableSuggestionsWithUndo() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("simple-maker-draft.json")
        let store = ThumbnailDraftStore(fileURL: url)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let viewModel = SimpleMakerViewModel(
            draftStore: store,
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        let denseText = "This is a very long thumbnail title with too many words for a small mobile preview"
        viewModel.simpleMakerConfiguration.selectedImage = Self.makeSolidImage()
        viewModel.simpleMakerConfiguration.overlayText = denseText

        let suggestion = try #require(
            viewModel.actionableSuggestions.first { $0.action == .shortenText }
        )

        #expect(viewModel.actionableSuggestions.contains { $0.action == .cropToDetectedFace })
        #expect(!viewModel.actionableSuggestions.contains {
            if case .applyBrandColor = $0.action { return true }
            return false
        })

        viewModel.apply(suggestion)

        let report = ThumbnailReadinessAnalyzer.analyze(viewModel.simpleMakerConfiguration)
        #expect(viewModel.simpleMakerConfiguration.overlayText != denseText)
        #expect(viewModel.simpleMakerConfiguration.overlayText.count <= ThumbnailSuggestionTextShortener.maximumCharacterCount)
        #expect(!report.findings.contains {
            $0.message.localizedCaseInsensitiveContains("dense")
        })
        #expect(viewModel.canUndo)

        viewModel.undo()

        #expect(viewModel.simpleMakerConfiguration.overlayText == denseText)
        #expect(viewModel.canRedo)
    }

    @MainActor
    @Test func simpleViewModelCropToDetectedFaceIsUndoable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("simple-maker-draft.json")
        let store = ThumbnailDraftStore(fileURL: url)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let originalImage = Self.makeSolidImage(size: CGSize(width: 80, height: 40))
        let viewModel = SimpleMakerViewModel(
            draftStore: store,
            subjectProcessor: StubSubjectProcessor(
                crop: CGRect(x: 0, y: 0, width: 0.5, height: 1)
            )
        )
        viewModel.simpleMakerConfiguration.selectedImage = originalImage

        await viewModel.cropSelectedImageToDetectedFace()

        #expect(viewModel.simpleMakerConfiguration.selectedImage?.size == CGSize(width: 40, height: 40))
        #expect(viewModel.canUndo)

        viewModel.undo()

        #expect(viewModel.simpleMakerConfiguration.selectedImage?.size == originalImage.size)
        #expect(viewModel.canRedo)
    }

    @MainActor
    @Test func simpleViewModelCropWithNoSelectedImageIsNoOp() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("simple-maker-draft.json")
        let store = ThumbnailDraftStore(fileURL: url)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let viewModel = SimpleMakerViewModel(
            draftStore: store,
            subjectProcessor: StubSubjectProcessor(
                crop: CGRect(x: 0, y: 0, width: 0.5, height: 1)
            )
        )

        await viewModel.cropSelectedImageToDetectedFace()

        #expect(viewModel.simpleMakerConfiguration.selectedImage == nil)
        #expect(!viewModel.canUndo)
        #expect(!viewModel.showingSaveAlert)
    }

    @MainActor
    @Test func simpleViewModelRemoveBackgroundProcessesActiveImageLayerWithUndo() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("simple-maker-draft.json")
        let store = ThumbnailDraftStore(fileURL: url)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let originalLayerImage = Self.makeSolidImage(size: CGSize(width: 80, height: 40))
        let processedLayerImage = Self.makeSolidImage(color: .red, size: CGSize(width: 24, height: 24))
        let viewModel = SimpleMakerViewModel(
            draftStore: store,
            subjectProcessor: StubSubjectProcessor(backgroundRemovedImage: processedLayerImage)
        )
        let layerData = try #require(originalLayerImage.pngData())
        let selection = viewModel.addImageLayer(imageData: layerData)
        guard case .content(let layerID) = selection else {
            Issue.record("Expected image content layer selection")
            return
        }

        #expect(viewModel.canRemoveBackground(from: selection))
        guard case .image(let addedContent) = viewModel.simpleMakerConfiguration.layers.record(id: layerID)?.content else {
            Issue.record("Expected image layer content")
            return
        }
        let originalBytes = addedContent.imageData

        await viewModel.removeBackground(from: selection)

        // FEATURE-11: cutout is non-destructive. The layer keeps its original
        // bytes and gains a mask recipe instead.
        let processedLayer = try #require(viewModel.simpleMakerConfiguration.layers.record(id: layerID))
        if case .image(let imageContent) = processedLayer.content {
            #expect(imageContent.imageData == originalBytes)
            #expect(UIImage(data: imageContent.imageData)?.size == originalLayerImage.size)
        } else {
            Issue.record("Expected image layer content")
        }
        #expect(processedLayer.cutout?.automaticBase != nil)
        #expect(processedLayer.cutout?.automaticBase?.sourcePixelWidth == 80)
        #expect(processedLayerImage.size.width == 24)
        #expect(viewModel.canUndo)

        viewModel.undo()

        let restoredLayer = try #require(viewModel.simpleMakerConfiguration.layers.record(id: layerID))
        if case .image(let imageContent) = restoredLayer.content {
            #expect(imageContent.imageData == originalBytes)
        } else {
            Issue.record("Expected image layer content")
        }
        #expect(restoredLayer.cutout == nil)
        #expect(viewModel.canRedo)
    }

    @MainActor
    @Test func simpleViewModelAppliesTemplateSuggestionAndIgnoresUnknownTemplate() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("simple-maker-draft.json")
        let store = ThumbnailDraftStore(fileURL: url)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let viewModel = SimpleMakerViewModel(
            draftStore: store,
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        viewModel.simpleMakerConfiguration.overlayText = "Starter"

        let suggestion = try #require(
            viewModel.actionableSuggestions.first {
                if case .applyTemplate = $0.action { return true }
                return false
            }
        )
        let templateID: String
        if case .applyTemplate(let id) = suggestion.action {
            templateID = id
        } else {
            Issue.record("Expected a template suggestion")
            return
        }
        let template = try #require(ThumbnailTemplate.builtIns.first { $0.id == templateID })
        let beforeUnknownTemplate = ThumbnailDocumentHistory.snapshot(
            viewModel.simpleMakerConfiguration.document
        )

        viewModel.apply(
            ThumbnailSuggestion(
                id: "template-missing",
                kind: .template,
                title: "Missing template",
                detail: "This should not change the document.",
                action: .applyTemplate(id: "missing-template")
            )
        )

        #expect(
            ThumbnailDocumentHistory.snapshot(viewModel.simpleMakerConfiguration.document)
                == beforeUnknownTemplate
        )

        viewModel.apply(suggestion)

        #expect(viewModel.simpleMakerConfiguration.overlayText == template.document.text.value)
        #expect(viewModel.simpleMakerConfiguration.selectedRatio.rawValue == template.document.canvas.aspectRatioRawValue)
        #expect(viewModel.canUndo)
        #expect(!viewModel.actionableSuggestions.contains {
            if case .applyTemplate(let id) = $0.action {
                return id == template.id
            }
            return false
        })

        viewModel.undo()

        #expect(viewModel.simpleMakerConfiguration.overlayText == "Starter")
        #expect(viewModel.canRedo)
    }

    @MainActor
    @Test func simpleViewModelApplyingTitleIdeaUpdatesConfigAndSupportsUndo() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("simple-maker-draft.json")
        let store = ThumbnailDraftStore(fileURL: url)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let viewModel = SimpleMakerViewModel(
            draftStore: store,
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        let title = "How to make better thumbnails"
        viewModel.simpleMakerConfiguration.overlayText = title
        viewModel.simpleMakerConfiguration.selectedRatio = .ratio9_16
        let beforeDocument = ThumbnailDocumentHistory.snapshot(
            viewModel.simpleMakerConfiguration.document
        )

        let idea = try #require(viewModel.titleIdeas.first)
        viewModel.apply(idea: idea)

        #expect(viewModel.simpleMakerConfiguration.overlayText == title)
        #expect(
            ThumbnailDocumentHistory.snapshot(viewModel.simpleMakerConfiguration.document)
                != beforeDocument
        )
        #expect(viewModel.canUndo)

        viewModel.undo()

        #expect(
            ThumbnailDocumentHistory.snapshot(viewModel.simpleMakerConfiguration.document)
                == beforeDocument
        )
        #expect(viewModel.canRedo)
    }

    @MainActor
    @Test func premiumViewModelAppliesActionableSuggestionsWithUndo() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("premium-maker-draft.json")
        let store = ThumbnailDraftStore(fileURL: url)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let viewModel = PremiumMakerViewModel(
            draftStore: store,
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        let denseText = "Premium creator thumbnails need fewer words so the title still works in tiny previews"
        viewModel.premiumMakerConfiguration.selectedImage = Self.makeSolidImage()
        viewModel.premiumMakerConfiguration.overlayText = denseText

        let suggestion = try #require(
            viewModel.actionableSuggestions.first { $0.action == .shortenText }
        )

        #expect(viewModel.actionableSuggestions.contains { $0.action == .cropToDetectedFace })
        #expect(!viewModel.actionableSuggestions.contains {
            if case .applyBrandColor = $0.action { return true }
            return false
        })

        viewModel.apply(suggestion)

        #expect(viewModel.premiumMakerConfiguration.overlayText != denseText)
        #expect(viewModel.premiumMakerConfiguration.overlayText.count <= ThumbnailSuggestionTextShortener.maximumCharacterCount)
        #expect(viewModel.canUndo)

        viewModel.undo()

        #expect(viewModel.premiumMakerConfiguration.overlayText == denseText)
        #expect(viewModel.canRedo)
    }

    @MainActor
    @Test func premiumViewModelApplyingTitleIdeaUpdatesConfigAndSupportsUndo() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("premium-maker-draft.json")
        let store = ThumbnailDraftStore(fileURL: url)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let viewModel = PremiumMakerViewModel(
            draftStore: store,
            brandKitStore: BrandKitStore(fileURL: directory.appendingPathComponent("brand-kit.json"))
        )
        let title = "I won the final boss fight"
        viewModel.premiumMakerConfiguration.overlayText = title
        viewModel.premiumMakerConfiguration.selectedRatio = .ratio16_9
        let beforeDocument = ThumbnailDocumentHistory.snapshot(
            viewModel.premiumMakerConfiguration.document
        )

        let idea = try #require(viewModel.titleIdeas.first)
        viewModel.apply(idea: idea)

        #expect(viewModel.premiumMakerConfiguration.overlayText == title)
        #expect(
            ThumbnailDocumentHistory.snapshot(viewModel.premiumMakerConfiguration.document)
                != beforeDocument
        )
        #expect(viewModel.canUndo)

        viewModel.undo()

        #expect(
            ThumbnailDocumentHistory.snapshot(viewModel.premiumMakerConfiguration.document)
                == beforeDocument
        )
        #expect(viewModel.canRedo)
    }

    @MainActor
    @Test func simpleViewModelAppliesSavedBrandKitWithUndo() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let draftURL = directory.appendingPathComponent("simple-maker-draft.json")
        let brandURL = directory.appendingPathComponent("brand-kit.json")
        let store = ThumbnailDraftStore(fileURL: draftURL)
        let brandStore = BrandKitStore(fileURL: brandURL)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let viewModel = SimpleMakerViewModel(draftStore: store, brandKitStore: brandStore)
        let brandKit = Self.makeBrandKit()
        viewModel.simpleMakerConfiguration.overlayText = "Brand me"
        viewModel.simpleMakerConfiguration.textColor = .white
        viewModel.simpleMakerConfiguration.backgroundColor = .white
        viewModel.simpleMakerConfiguration.selectedFont = .roboto
        viewModel.saveBrandKit(brandKit)

        let suggestion = try #require(
            viewModel.actionableSuggestions.first { $0.action == .applyBrandColor(role: .text) }
        )

        viewModel.apply(suggestion)

        #expect(Self.colorComponents(viewModel.simpleMakerConfiguration.textColor) == [255, 214, 64, 255])
        #expect(Self.colorComponents(viewModel.simpleMakerConfiguration.backgroundColor) == [18, 26, 38, 255])
        #expect(viewModel.simpleMakerConfiguration.selectedFont == .montserrat)
        #expect(viewModel.canUndo)
        #expect(!viewModel.actionableSuggestions.contains { $0.id == suggestion.id })

        viewModel.undo()

        #expect(Self.colorComponents(viewModel.simpleMakerConfiguration.textColor) == Self.colorComponents(.white))
        #expect(Self.colorComponents(viewModel.simpleMakerConfiguration.backgroundColor) == Self.colorComponents(.white))
        #expect(viewModel.simpleMakerConfiguration.selectedFont == .roboto)
        #expect(viewModel.canRedo)

        let restoredViewModel = SimpleMakerViewModel(draftStore: store, brandKitStore: brandStore)
        #expect(restoredViewModel.brandKit?.id == brandKit.id)
        #expect(restoredViewModel.brandKit?.name == brandKit.name)
        #expect(restoredViewModel.brandKit?.palette == brandKit.palette)
        #expect(restoredViewModel.brandKit?.primaryFont == brandKit.primaryFont)
    }

    @MainActor
    @Test func premiumViewModelAppliesSavedBrandKitWithUndo() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let draftURL = directory.appendingPathComponent("premium-maker-draft.json")
        let brandURL = directory.appendingPathComponent("brand-kit.json")
        let store = ThumbnailDraftStore(fileURL: draftURL)
        let brandStore = BrandKitStore(fileURL: brandURL)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let viewModel = PremiumMakerViewModel(draftStore: store, brandKitStore: brandStore)
        viewModel.premiumMakerConfiguration.overlayText = "Premium brand"
        viewModel.premiumMakerConfiguration.textColor = .white
        viewModel.premiumMakerConfiguration.backgroundColor = .white
        viewModel.premiumMakerConfiguration.selectedFont = .roboto
        viewModel.saveBrandKit(Self.makeBrandKit())

        await viewModel.applyAsync(
            ThumbnailSuggestion(
                id: "brand-apply-kit-test",
                kind: .brand,
                title: "Apply brand kit",
                detail: "Apply saved colors and typography.",
                action: .applyBrandColor(role: .text)
            )
        )

        #expect(Self.colorComponents(viewModel.premiumMakerConfiguration.textColor) == [255, 214, 64, 255])
        #expect(Self.colorComponents(viewModel.premiumMakerConfiguration.backgroundColor) == [18, 26, 38, 255])
        #expect(viewModel.premiumMakerConfiguration.selectedFont == .montserrat)
        #expect(viewModel.canUndo)

        viewModel.undo()

        #expect(Self.colorComponents(viewModel.premiumMakerConfiguration.textColor) == Self.colorComponents(.white))
        #expect(Self.colorComponents(viewModel.premiumMakerConfiguration.backgroundColor) == Self.colorComponents(.white))
        #expect(viewModel.premiumMakerConfiguration.selectedFont == .roboto)
        #expect(viewModel.canRedo)
    }

    @Test func exportOptionsSwitchBetweenPresetsAndCustomSizes() async throws {
        var options = ThumbnailExportOptions()

        #expect(options.outputSize == ThumbnailExportPreset.youTubeThumbnail.size)
        #expect(options.activeSafeZone == ThumbnailExportPreset.youTubeThumbnail.safeZone)

        options.applyPreset(.shortFormCover)
        #expect(options.outputSize == ThumbnailExportSize(width: 1080, height: 1920))
        #expect(!options.usesCustomSize)
        #expect(options.activeSafeZone == ThumbnailExportPreset.shortFormCover.safeZone)

        options.usesCustomSize = true
        options.customSize = ThumbnailExportSize(width: 1440, height: 1800)
        #expect(options.outputSize == ThumbnailExportSize(width: 1440, height: 1800))
        #expect(options.activeSafeZone == nil)
    }

    @MainActor
    @Test func encodesConfiguredExportFormats() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }

        var options = ThumbnailExportOptions()

        options.format = .png
        #expect(try ThumbnailExporter.encodedData(for: image, options: options).isEmpty == false)

        options.format = .jpeg
        options.compressionQuality = 0.75
        #expect(try ThumbnailExporter.encodedData(for: image, options: options).isEmpty == false)

        if ThumbnailExportFormat.webP.canEncodeOnCurrentPlatform {
            options.format = .webP
            #expect(try ThumbnailExporter.encodedData(for: image, options: options).isEmpty == false)
        }
    }

    @MainActor
    @Test func webPEncodingReportsPlatformAvailability() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }

        var options = ThumbnailExportOptions()
        options.format = .webP
        options.compressionQuality = 0.7

        if ThumbnailExportFormat.webP.canEncodeOnCurrentPlatform {
            #expect(try ThumbnailExporter.encodedData(for: image, options: options).isEmpty == false)
        } else {
            do {
                _ = try ThumbnailExporter.encodedData(for: image, options: options)
                Issue.record("Expected WebP export to report unsupported format on this platform")
            } catch let error as ThumbnailExportError {
                #expect(error == .unsupportedFormat(.webP))
            } catch {
                Issue.record("Expected ThumbnailExportError.unsupportedFormat, got \(error)")
            }
        }
    }

    @MainActor
    @Test func rendersAtConfiguredExportSize() async throws {
        var options = ThumbnailExportOptions()
        options.usesCustomSize = true
        options.customSize = ThumbnailExportSize(width: 320, height: 180)

        let targetSize = options.outputSize.cgSize
        let image = try ThumbnailExporter.render(
            content: Color.red.frame(width: targetSize.width, height: targetSize.height),
            options: options
        )

        #expect(image.size == targetSize)
    }

    @Test func writesTemporaryExportFileWithExpectedExtension() async throws {
        var options = ThumbnailExportOptions()
        options.format = .jpeg

        let url = try ThumbnailExporter.writeTemporaryExport(
            data: Data([1, 2, 3]),
            options: options,
            baseFileName: "YouTube Thumbnail!"
        )
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        #expect(url.pathExtension == "jpg")
        #expect(url.lastPathComponent.hasPrefix("YouTube-Thumbnail-"))
        #expect(try Data(contentsOf: url) == Data([1, 2, 3]))
    }

    @Test func exportValidationFlagsYouTubeSizeAndFormatIssues() async throws {
        var options = ThumbnailExportOptions()

        let underLimitMessages = options.validationMessages(forByteCount: 1_500_000)
        #expect(underLimitMessages.contains { $0.severity == .success })

        let overMobileLimitMessages = options.validationMessages(forByteCount: 2_000_001)
        #expect(overMobileLimitMessages.contains {
            $0.severity == .warning
                && $0.message.contains("mobile video thumbnail limit")
        })

        options.format = .webP
        let webPMessages = options.validationMessages(forByteCount: 1_000_000)
        #expect(webPMessages.contains {
            $0.severity == .warning
                && $0.message.contains("JPG, GIF, and PNG")
        })
    }

    @MainActor
    @Test func preparesFileExportWithMetadataAndExactBytes() async throws {
        var options = ThumbnailExportOptions()
        options.usesCustomSize = true
        options.customSize = ThumbnailExportSize(width: 24, height: 24)
        options.format = .jpeg

        let preparedExport = try ThumbnailExporter.preparedFileExport(
            content: Color.green.frame(width: 24, height: 24),
            options: options,
            baseFileName: "YouTube Thumbnail!"
        )

        #expect(preparedExport.fileName == "YouTube-Thumbnail.jpg")
        #expect(preparedExport.contentType == options.format.contentType)
        #expect(!preparedExport.data.isEmpty)
        #expect(preparedExport.fileSize.byteCount == preparedExport.data.count)
    }

    @MainActor
    @Test func simpleViewModelPreparesShareAndFileExportArtifacts() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple-export-draft.json"))
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let viewModel = SimpleMakerViewModel(draftStore: store)
        viewModel.simpleMakerConfiguration.selectedImage = Self.makeSolidImage(size: CGSize(width: 64, height: 36))
        viewModel.simpleMakerConfiguration.exportOptions.usesCustomSize = true
        viewModel.simpleMakerConfiguration.exportOptions.customSize = ThumbnailExportSize(width: 64, height: 36)
        viewModel.simpleMakerConfiguration.exportOptions.format = .jpeg
        viewModel.simpleMakerConfiguration.exportOptions.compressionQuality = 0.72

        let content = Color.red.frame(width: 64, height: 36)

        await viewModel.shareImageWithOverlay(content: content)

        let shareURL = try #require(viewModel.shareItem?.url)
        defer {
            try? FileManager.default.removeItem(at: shareURL)
        }

        #expect(!viewModel.isPreparingShare)
        #expect(viewModel.saveError == nil)
        #expect(FileManager.default.fileExists(atPath: shareURL.path))
        #expect(shareURL.pathExtension == "jpg")
        #expect(try Data(contentsOf: shareURL).isEmpty == false)
        #expect(viewModel.exportReport?.options.format == .jpeg)
        #expect(viewModel.exportReport?.byteCount == (try Data(contentsOf: shareURL).count))

        await viewModel.prepareFileExport(content: content)

        let fileExport = try #require(viewModel.fileExport)
        #expect(!viewModel.isPreparingFileExport)
        #expect(viewModel.isFileExporterPresented)
        #expect(fileExport.fileName == "youtube-thumbnail.jpg")
        #expect(fileExport.contentType == viewModel.simpleMakerConfiguration.exportOptions.format.contentType)
        #expect(!fileExport.data.isEmpty)
        #expect(viewModel.exportReport?.byteCount == fileExport.data.count)

        viewModel.handleFileExportCompletion(.success(URL(fileURLWithPath: "/tmp/thumbnailmaker-test-export.jpg")))
        #expect(viewModel.successMessage == "Thumbnail exported to Files")
        #expect(viewModel.showingSaveAlert)
    }

    @MainActor
    @Test func premiumViewModelPreparesShareAndFileExportArtifacts() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium-export-draft.json"))
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let viewModel = PremiumMakerViewModel(draftStore: store)
        viewModel.premiumMakerConfiguration.selectedImage = Self.makeSolidImage(size: CGSize(width: 72, height: 128))
        viewModel.premiumMakerConfiguration.overlayText = "Export proof"
        viewModel.premiumMakerConfiguration.exportOptions.applyPreset(.shortFormCover)
        viewModel.premiumMakerConfiguration.exportOptions.usesCustomSize = true
        viewModel.premiumMakerConfiguration.exportOptions.customSize = ThumbnailExportSize(width: 72, height: 128)
        viewModel.premiumMakerConfiguration.exportOptions.format = .png

        let content = Color.blue.frame(width: 72, height: 128)

        await viewModel.shareImageWithOverlay(content: content)

        let shareURL = try #require(viewModel.shareItem?.url)
        defer {
            try? FileManager.default.removeItem(at: shareURL)
        }

        #expect(!viewModel.isPreparingShare)
        #expect(viewModel.saveError == nil)
        #expect(FileManager.default.fileExists(atPath: shareURL.path))
        #expect(shareURL.pathExtension == "png")
        #expect(try Data(contentsOf: shareURL).isEmpty == false)
        #expect(viewModel.exportReport?.options.preset == .shortFormCover)

        await viewModel.prepareFileExport(content: content)

        let fileExport = try #require(viewModel.fileExport)
        #expect(!viewModel.isPreparingFileExport)
        #expect(viewModel.isFileExporterPresented)
        #expect(fileExport.fileName == "short-form-cover.png")
        #expect(fileExport.contentType == viewModel.premiumMakerConfiguration.exportOptions.format.contentType)
        #expect(!fileExport.data.isEmpty)
        #expect(viewModel.exportReport?.byteCount == fileExport.data.count)
    }

    @Test func smallPreviewSizesPreserveSelectedAspectRatio() async throws {
        let search16x9 = ThumbnailSmallPreviewSize.search.size(for: .ratio16_9)
        #expect(search16x9.width == 160)
        #expect(abs(search16x9.height - 90) < 0.01)

        let mobile9x16 = ThumbnailSmallPreviewSize.mobile.size(for: .ratio9_16)
        #expect(mobile9x16.width == 96)
        #expect(abs(mobile9x16.height - (96 * 16 / 9)) < 0.01)
    }

    @MainActor
    @Test func readinessAnalyzerScoresConciseReadableThumbnail() async throws {
        var configuration = SimpleMakerConfigurationModel()
        configuration.selectedImage = Self.makeSolidImage()
        configuration.overlayText = "Big Win"
        configuration.textSize = 0.24
        configuration.textColor = .white
        configuration.backgroundColor = .black

        let report = ThumbnailReadinessAnalyzer.analyze(configuration)

        #expect(report.score == 100)
        #expect(report.findings.contains { $0.severity == .success })
        #expect(!report.findings.contains { $0.severity == .warning })
    }

    @Test func readinessAnalyzerFlagsLowContrastText() async throws {
        var configuration = SimpleMakerConfigurationModel()
        configuration.overlayText = "Hard to read"
        configuration.textSize = 0.24
        configuration.textColor = .white
        configuration.backgroundColor = .white

        let report = ThumbnailReadinessAnalyzer.analyze(configuration)

        #expect(report.score < 80)
        #expect(report.findings.contains {
            $0.severity == .warning && $0.message.contains("contrast")
        })
    }

    @MainActor
    @Test func readinessAnalyzerFlagsDenseTinyMobileText() async throws {
        var configuration = SimpleMakerConfigurationModel()
        configuration.selectedImage = Self.makeSolidImage()
        configuration.overlayText = "This is a very long thumbnail title that will collapse in small previews"
        configuration.selectedRatio = .ratio16_9
        configuration.textSize = 0.08

        let report = ThumbnailReadinessAnalyzer.analyze(configuration)

        #expect(report.score <= 60)
        #expect(report.findings.contains {
            $0.severity == .warning && $0.message.contains("dense")
        })
        #expect(report.findings.contains {
            $0.severity == .warning && $0.message.contains("too small")
        })
    }

    @MainActor
    @Test func readinessAnalyzerTreatsHiddenTextLayerAsAbsent() async throws {
        var configuration = SimpleMakerConfigurationModel()
        configuration.selectedImage = Self.makeSolidImage()
        configuration.overlayText = "Hidden title"
        configuration.textSize = 0.24
        configuration.layers = ThumbnailDocumentLayer.defaultLayers(hasText: true, hasProfile: false)
        configuration.layers.setVisible(false, for: .text)

        let report = ThumbnailReadinessAnalyzer.analyze(configuration)

        #expect(report.score == 80)
        #expect(report.findings.contains {
            $0.severity == .warning && $0.message.contains("Add a short focal phrase")
        })
        #expect(!report.findings.contains {
            $0.message.contains("too small") || $0.message.contains("contrast")
        })
    }

    @Test func layerRecordsReconcileVisibleLockStateForCurrentOverlays() async throws {
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: true, hasProfile: false)
        layers[0].zIndex = 999
        layers.setVisible(false, for: .text)
        layers.setLocked(true, for: .text)

        let reconciled = layers.reconciledForCurrentOverlays(hasText: true, hasProfile: true)
        let textLayer = try #require(reconciled.record(for: .text))
        let profileLayer = try #require(reconciled.record(for: .profile))
        let backgroundLayer = try #require(reconciled.first { $0.id == ThumbnailDocumentLayer.backgroundID })

        #expect(textLayer.isVisible == false)
        #expect(textLayer.isLocked)
        #expect(profileLayer.isVisible)
        #expect(!profileLayer.isLocked)
        #expect(backgroundLayer.isLocked)
        #expect(backgroundLayer.zIndex == 0)
        #expect(reconciled.map(\.id) == [
            ThumbnailDocumentLayer.backgroundID,
            ThumbnailDocumentLayer.profileID,
            ThumbnailDocumentLayer.textID
        ])
    }

    @MainActor
    @Test func liveMakerViewModelsReconcileOverlayLayerRecords() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let simpleStore = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("simple.json"))
        let premiumStore = ThumbnailDraftStore(fileURL: directory.appendingPathComponent("premium.json"))
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let simpleViewModel = SimpleMakerViewModel(draftStore: simpleStore)
        simpleViewModel.simpleMakerConfiguration.overlayText = "Live text"
        #expect(simpleViewModel.simpleMakerConfiguration.layers.record(for: .text) == nil)

        simpleViewModel.reconcileLayersForCurrentOverlays()

        #expect(simpleViewModel.simpleMakerConfiguration.layers.record(for: .text) != nil)
        simpleViewModel.toggleLayerLock(.textOverlay)
        #expect(simpleViewModel.simpleMakerConfiguration.layers.isLocked(.text))
        simpleViewModel.toggleLayerVisibility(.textOverlay)
        #expect(!simpleViewModel.simpleMakerConfiguration.layers.isVisible(.text))

        let premiumViewModel = PremiumMakerViewModel(draftStore: premiumStore)
        premiumViewModel.premiumMakerConfiguration.overlayText = "Live text"
        #expect(premiumViewModel.premiumMakerConfiguration.layers.record(for: .text) == nil)

        premiumViewModel.reconcileLayersForCurrentOverlays()

        #expect(premiumViewModel.premiumMakerConfiguration.layers.record(for: .text) != nil)
        premiumViewModel.toggleLayerLock(.textOverlay)
        #expect(premiumViewModel.premiumMakerConfiguration.layers.isLocked(.text))
        premiumViewModel.toggleLayerVisibility(.textOverlay)
        #expect(!premiumViewModel.premiumMakerConfiguration.layers.isVisible(.text))
    }

    @Test func layerRecordsMoveCurrentOverlaysForwardAndBackward() async throws {
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: true, hasProfile: true)

        #expect(layers.sortedEditorLayers([.text, .profile]) == [.profile, .text])
        #expect(!layers.canMoveForward(.text, within: [.text, .profile]))
        #expect(layers.canMoveBackward(.text, within: [.text, .profile]))
        #expect(!layers.canMoveForward(.profile, within: [.text]))
        #expect(!layers.canMoveBackward(.profile, within: [.text]))

        let unchangedLayers = layers
        layers.moveForward(.text, within: [.text, .profile])
        #expect(layers == unchangedLayers)

        layers.moveBackward(.text, within: [.text, .profile])

        #expect(layers.sortedEditorLayers([.text, .profile]) == [.text, .profile])
        #expect(layers.record(for: .text)?.zIndex == 10)
        #expect(layers.record(for: .profile)?.zIndex == 20)
        #expect(layers.canMoveForward(.text, within: [.text, .profile]))
        #expect(!layers.canMoveBackward(.text, within: [.text, .profile]))

        layers.moveForward(.text, within: [.text, .profile])

        #expect(layers.sortedEditorLayers([.text, .profile]) == [.profile, .text])
        #expect(layers.record(for: .profile)?.zIndex == 10)
        #expect(layers.record(for: .text)?.zIndex == 20)

        var textOnlyLayers = ThumbnailDocumentLayer.defaultLayers(hasText: true, hasProfile: false)
        textOnlyLayers.moveBackward(.text, within: [.text, .profile])
        #expect(textOnlyLayers.sortedEditorLayers([.text, .profile]) == [.text, .profile])
        #expect(textOnlyLayers.record(for: .text)?.zIndex == 10)
        #expect(textOnlyLayers.record(for: .profile)?.zIndex == 20)
    }

    @Test func imageContentLayersRoundTripAndSurviveReconcile() async throws {
        let imageData = try #require(Self.makeSolidImage(color: .blue).pngData())
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: true, hasProfile: false)
        let layerID = layers.addImageLayer(
            imageData: imageData,
            id: "image-layer-1",
            transform: ThumbnailOverlayTransform(x: 0.34, y: 0.62, rotationDegrees: 11),
            size: 0.41
        )
        layers.setLocked(true, for: .text)

        let document = ThumbnailDocument(
            updatedAt: Date(timeIntervalSince1970: 10),
            text: ThumbnailDocumentText(value: "Layered"),
            layers: layers
        )

        let decoded = try Self.roundTrip(document)
        let decodedLayer = try #require(decoded.layers.record(id: layerID))
        #expect(decoded.version == ThumbnailDocument.currentVersion)
        #expect(decodedLayer.kind == .image)
        #expect(decodedLayer.name == "Image 1")
        #expect(decodedLayer.zIndex >= ThumbnailDocumentLayer.contentLayerZIndexStart)

        guard case .image(let content) = decodedLayer.content else {
            Issue.record("Expected image layer content to round-trip")
            return
        }

        #expect(content.imageData == imageData)
        #expect(content.transform == ThumbnailOverlayTransform(x: 0.34, y: 0.62, rotationDegrees: 11))
        #expect(content.size == 0.41)

        let reconciledWithoutText = decoded.layers.reconciledForCurrentOverlays(
            hasText: false,
            hasProfile: false
        )

        #expect(reconciledWithoutText.record(for: .text) == nil)
        #expect(reconciledWithoutText.record(id: layerID)?.content == decodedLayer.content)
        #expect(reconciledWithoutText.map(\.id).contains(layerID))
    }

    @Test func thumbnailDocumentMigratesVersionTwoDocumentToCurrentSchema() async throws {
        let legacyJSON = """
        {
          "version": 2,
          "updatedAt": "2026-01-01T00:00:00Z",
          "editorMode": "premium",
          "canvas": {
            "aspectRatioRawValue": "\(AspectRatio.ratio16_9.rawValue)",
            "backgroundColor": {
              "red": 0.08,
              "green": 0.1,
              "blue": 0.14,
              "alpha": 1
            }
          },
          "imageData": "AQID",
          "text": {
            "value": "Legacy Title",
            "color": {
              "red": 1,
              "green": 1,
              "blue": 1,
              "alpha": 1
            },
            "size": 0.18,
            "verticalAlignmentRawValue": "\(VerticalAlignment.center.rawValue)",
            "horizontalAlignmentRawValue": "\(HorizontalAlignment.center.rawValue)",
            "transform": {
              "x": 0.41,
              "y": 0.58,
              "rotationDegrees": 7,
              "isFlippedHorizontally": false
            },
            "selectedFontRawValue": "\(CustomFont.roboto.rawValue)"
          },
          "profile": {
            "imageData": "BAUG",
            "positionRawValue": "bottomLeft",
            "size": 0.22
          },
          "macro": {
            "isEnabled": false,
            "startNumber": 1,
            "endNumber": 1,
            "appendPositionRawValue": "\(MacroConfig.AppendPosition.after.rawValue)"
          },
          "export": {
            "presetID": "\(ThumbnailExportPreset.youTubeThumbnail.id)",
            "formatRawValue": "\(ThumbnailExportFormat.png.rawValue)",
            "compressionQuality": 0.9,
            "usesCustomSize": false,
            "customWidth": 1920,
            "customHeight": 1080
          }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ThumbnailDocument.self, from: legacyJSON)
        let profile = try #require(decoded.profile)

        #expect(decoded.version == ThumbnailDocument.currentVersion)
        #expect(decoded.editorMode == .premium)
        #expect(decoded.imageData == Data([1, 2, 3]))
        #expect(decoded.text.value == "Legacy Title")
        #expect(decoded.text.transform == ThumbnailOverlayTransform(x: 0.41, y: 0.58, rotationDegrees: 7))
        #expect(profile.imageData == Data([4, 5, 6]))
        #expect(profile.size == 0.22)
        #expect(profile.transform == ThumbnailOverlayTransform(x: 0.16, y: 0.82))
        #expect(decoded.layers.map(\.id) == [
            ThumbnailDocumentLayer.backgroundID,
            ThumbnailDocumentLayer.profileID,
            ThumbnailDocumentLayer.textID
        ])
    }

    @Test func imageContentLayerMutatorsDuplicateDeleteAndReorder() async throws {
        let imageData = try #require(Self.makeSolidImage(color: .cyan).pngData())
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: true, hasProfile: true)
        let firstID = layers.addImageLayer(imageData: imageData, id: "image-layer-1")
        let duplicatedIDCandidate = layers.duplicateContentLayer(id: firstID, newID: "image-layer-2")
        let duplicatedID = try #require(duplicatedIDCandidate)

        let firstLayer = try #require(layers.record(id: firstID))
        let duplicatedLayer = try #require(layers.record(id: duplicatedID))
        #expect(duplicatedLayer.id != firstLayer.id)
        #expect(duplicatedLayer.name == "Image 1 Copy")
        #expect(duplicatedLayer.zIndex > firstLayer.zIndex)

        guard case .image(let firstContent) = firstLayer.content,
              case .image(let duplicatedContent) = duplicatedLayer.content else {
            Issue.record("Expected both content layers to be image layers")
            return
        }

        #expect(duplicatedContent.imageData == firstContent.imageData)
        #expect(duplicatedContent.transform.x > firstContent.transform.x)
        #expect(duplicatedContent.transform.y > firstContent.transform.y)

        let selections = layers.selectableLayerSelections(hasText: true, hasProfile: true)
        #expect(selections.contains(.content(firstID)))
        #expect(selections.contains(.content(duplicatedID)))
        #expect(layers.canMoveBackward(.content(duplicatedID), within: selections))

        layers.moveBackward(.content(duplicatedID), within: selections)
        #expect(layers.record(id: duplicatedID)?.zIndex == firstLayer.zIndex)

        layers.deleteContentLayer(id: duplicatedID)
        #expect(layers.record(id: duplicatedID) == nil)
        #expect(layers.record(id: firstID) != nil)
    }

    @Test func stickerContentLayersRoundTripAndLegacyDecodeDefaultsToImage() async throws {
        let imageData = try #require(Self.makeSolidImage(color: .systemPink).pngData())
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: false, hasProfile: false)
        let layerID = layers.addStickerLayer(
            imageData: imageData,
            id: "sticker-layer-1",
            transform: ThumbnailOverlayTransform(x: 0.62, y: 0.44, rotationDegrees: -6),
            size: 0.2
        )

        let document = ThumbnailDocument(
            updatedAt: Date(timeIntervalSince1970: 21),
            layers: layers
        )

        let decoded = try Self.roundTrip(document)
        let decodedLayer = try #require(decoded.layers.record(id: layerID))
        #expect(decodedLayer.kind == .image)
        #expect(decodedLayer.name == "Sticker 1")

        guard case .image(let stickerContent) = decodedLayer.content else {
            Issue.record("Expected sticker to round-trip as flagged image content")
            return
        }

        #expect(stickerContent.isSticker)
        #expect(stickerContent.imageData == imageData)
        #expect(stickerContent.transform == ThumbnailOverlayTransform(x: 0.62, y: 0.44, rotationDegrees: -6))
        #expect(stickerContent.size == 0.2)

        let legacyContentJSON = """
        {
          "imageData": "\(imageData.base64EncodedString())",
          "transform": {
            "x": 0.33,
            "y": 0.66,
            "rotationDegrees": 9,
            "isFlippedHorizontally": true
          },
          "size": 0.21
        }
        """.data(using: .utf8)!

        let legacyContent = try JSONDecoder().decode(ThumbnailImageLayerContent.self, from: legacyContentJSON)
        #expect(!legacyContent.isSticker)
        #expect(legacyContent.transform == ThumbnailOverlayTransform(x: 0.33, y: 0.66, rotationDegrees: 9, isFlippedHorizontally: true))
        #expect(legacyContent.size == 0.21)
    }

    @Test func stickerContentLayerMutatorsDuplicateDeleteAndReorder() async throws {
        let imageData = try #require(Self.makeSolidImage(color: .systemTeal).pngData())
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: false, hasProfile: false)
        let firstID = layers.addStickerLayer(imageData: imageData, id: "sticker-layer-1")
        let duplicatedIDCandidate = layers.duplicateContentLayer(id: firstID, newID: "sticker-layer-2")
        let duplicatedID = try #require(duplicatedIDCandidate)

        let firstLayer = try #require(layers.record(id: firstID))
        let duplicatedLayer = try #require(layers.record(id: duplicatedID))
        #expect(duplicatedLayer.name == "Sticker 1 Copy")
        #expect(duplicatedLayer.zIndex > firstLayer.zIndex)

        guard case .image(let firstContent) = firstLayer.content,
              case .image(let duplicatedContent) = duplicatedLayer.content else {
            Issue.record("Expected both sticker layers to remain image-backed")
            return
        }

        #expect(firstContent.isSticker)
        #expect(duplicatedContent.isSticker)
        #expect(duplicatedContent.imageData == firstContent.imageData)
        #expect(duplicatedContent.transform.x > firstContent.transform.x)
        #expect(duplicatedContent.transform.y > firstContent.transform.y)

        let selections = layers.selectableLayerSelections(hasText: false, hasProfile: false)
        #expect(selections.contains(.content(firstID)))
        #expect(selections.contains(.content(duplicatedID)))
        #expect(layers.canMoveBackward(.content(duplicatedID), within: selections))

        layers.moveBackward(.content(duplicatedID), within: selections)
        #expect(layers.record(id: duplicatedID)?.zIndex == firstLayer.zIndex)

        layers.deleteContentLayer(id: duplicatedID)
        #expect(layers.record(id: duplicatedID) == nil)
        #expect(layers.record(id: firstID) != nil)
    }

    @Test func shapeContentLayersRoundTripAndSurviveReconcile() async throws {
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: true, hasProfile: false)
        let layerID = layers.addShapeLayer(
            shapeKind: .ellipse,
            id: "shape-layer-1",
            fillColor: ThumbnailDocumentColor(red: 0.96, green: 0.34, blue: 0.14, alpha: 1),
            strokeColor: ThumbnailDocumentColor(red: 1, green: 1, blue: 1, alpha: 0.82),
            strokeWidth: 0.018,
            transform: ThumbnailOverlayTransform(x: 0.62, y: 0.42, rotationDegrees: -9),
            width: 0.28,
            height: 0.18
        )

        let document = ThumbnailDocument(
            updatedAt: Date(timeIntervalSince1970: 14),
            text: ThumbnailDocumentText(value: "Shape"),
            layers: layers
        )

        let decoded = try Self.roundTrip(document)
        let decodedLayer = try #require(decoded.layers.record(id: layerID))
        #expect(decodedLayer.kind == .shape)
        #expect(decodedLayer.name == "Ellipse 1")

        guard case .shape(let content) = decodedLayer.content else {
            Issue.record("Expected shape layer content to round-trip")
            return
        }

        #expect(content.shapeKind == .ellipse)
        #expect(content.fillColor == ThumbnailDocumentColor(red: 0.96, green: 0.34, blue: 0.14, alpha: 1))
        #expect(content.strokeColor == ThumbnailDocumentColor(red: 1, green: 1, blue: 1, alpha: 0.82))
        #expect(content.strokeWidth == 0.018)
        #expect(content.transform == ThumbnailOverlayTransform(x: 0.62, y: 0.42, rotationDegrees: -9))
        #expect(content.width == 0.28)
        #expect(content.height == 0.18)

        let reconciledWithoutText = decoded.layers.reconciledForCurrentOverlays(
            hasText: false,
            hasProfile: false
        )

        #expect(reconciledWithoutText.record(for: .text) == nil)
        #expect(reconciledWithoutText.record(id: layerID)?.content == decodedLayer.content)
        #expect(reconciledWithoutText.selectableLayerSelections(hasText: false, hasProfile: false) == [.content(layerID)])
    }

    @Test func shapeContentLayerMutatorsDuplicateDeleteAndReorder() async throws {
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: true, hasProfile: false)
        let firstID = layers.addShapeLayer(shapeKind: .rectangle, id: "shape-layer-1")
        let duplicatedIDCandidate = layers.duplicateContentLayer(id: firstID, newID: "shape-layer-2")
        let duplicatedID = try #require(duplicatedIDCandidate)

        let firstLayer = try #require(layers.record(id: firstID))
        let duplicatedLayer = try #require(layers.record(id: duplicatedID))
        #expect(duplicatedLayer.name == "Rectangle 1 Copy")
        #expect(duplicatedLayer.zIndex > firstLayer.zIndex)

        guard case .shape(let firstContent) = firstLayer.content,
              case .shape(let duplicatedContent) = duplicatedLayer.content else {
            Issue.record("Expected both content layers to be shape layers")
            return
        }

        #expect(duplicatedContent.shapeKind == firstContent.shapeKind)
        #expect(duplicatedContent.transform.x > firstContent.transform.x)
        #expect(duplicatedContent.transform.y > firstContent.transform.y)

        let selections = layers.selectableLayerSelections(hasText: true, hasProfile: false)
        #expect(selections.contains(.content(firstID)))
        #expect(selections.contains(.content(duplicatedID)))
        #expect(layers.canMoveBackward(.content(duplicatedID), within: selections))

        layers.moveBackward(.content(duplicatedID), within: selections)
        #expect(layers.record(id: duplicatedID)?.zIndex == firstLayer.zIndex)

        layers.deleteContentLayer(id: duplicatedID)
        #expect(layers.record(id: duplicatedID) == nil)
        #expect(layers.record(id: firstID) != nil)
    }

    @Test func textContentLayersRoundTripAndSurviveReconcile() async throws {
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: true, hasProfile: false)
        let layerID = layers.addTextLayer(
            value: "Layer title",
            id: "text-layer-1",
            color: ThumbnailDocumentColor(red: 1, green: 0.92, blue: 0.16, alpha: 1),
            size: 0.17,
            selectedFontRawValue: CustomFont.montserrat.rawValue,
            transform: ThumbnailOverlayTransform(x: 0.42, y: 0.38, rotationDegrees: 12)
        )
        layers.setLocked(true, for: .text)

        let document = ThumbnailDocument(
            updatedAt: Date(timeIntervalSince1970: 18),
            text: ThumbnailDocumentText(value: "Legacy singleton"),
            layers: layers
        )

        let decoded = try Self.roundTrip(document)
        let decodedLayer = try #require(decoded.layers.record(id: layerID))
        #expect(decoded.version == ThumbnailDocument.currentVersion)
        #expect(decodedLayer.kind == .text)
        #expect(decodedLayer.name == "Text 1")
        #expect(decoded.layers.record(for: .text)?.content == nil)

        guard case .text(let content) = decodedLayer.content else {
            Issue.record("Expected text layer content to round-trip")
            return
        }

        #expect(content.value == "Layer title")
        #expect(content.color == ThumbnailDocumentColor(red: 1, green: 0.92, blue: 0.16, alpha: 1))
        #expect(content.size == 0.17)
        #expect(content.selectedFont == .montserrat)
        #expect(content.transform == ThumbnailOverlayTransform(x: 0.42, y: 0.38, rotationDegrees: 12))

        let reconciledWithoutText = decoded.layers.reconciledForCurrentOverlays(
            hasText: false,
            hasProfile: false
        )

        #expect(reconciledWithoutText.record(for: .text) == nil)
        #expect(reconciledWithoutText.record(id: layerID)?.content == decodedLayer.content)
        #expect(reconciledWithoutText.selectableLayerSelections(hasText: false, hasProfile: false) == [.content(layerID)])
    }

    @Test func textContentLayerMutatorsDuplicateDeleteAndReorder() async throws {
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: true, hasProfile: false)
        let firstID = layers.addTextLayer(value: "First", id: "text-layer-1")
        layers.updateTextContent(id: firstID) { content in
            content.value = "Updated"
            content.size = 0.2
            content.selectedFont = .roboto
        }
        let duplicatedIDCandidate = layers.duplicateContentLayer(id: firstID, newID: "text-layer-2")
        let duplicatedID = try #require(duplicatedIDCandidate)

        let firstLayer = try #require(layers.record(id: firstID))
        let duplicatedLayer = try #require(layers.record(id: duplicatedID))
        #expect(duplicatedLayer.name == "Text 1 Copy")
        #expect(duplicatedLayer.zIndex > firstLayer.zIndex)

        guard case .text(let firstContent) = firstLayer.content,
              case .text(let duplicatedContent) = duplicatedLayer.content else {
            Issue.record("Expected both content layers to be text layers")
            return
        }

        #expect(firstContent.value == "Updated")
        #expect(firstContent.size == 0.2)
        #expect(firstContent.selectedFont == .roboto)
        #expect(duplicatedContent.value == firstContent.value)
        #expect(duplicatedContent.transform.x > firstContent.transform.x)
        #expect(duplicatedContent.transform.y > firstContent.transform.y)

        let selections = layers.selectableLayerSelections(hasText: true, hasProfile: false)
        #expect(selections.contains(.content(firstID)))
        #expect(selections.contains(.content(duplicatedID)))
        #expect(layers.canMoveBackward(.content(duplicatedID), within: selections))

        layers.moveBackward(.content(duplicatedID), within: selections)
        #expect(layers.record(id: duplicatedID)?.zIndex == firstLayer.zIndex)

        layers.deleteContentLayer(id: duplicatedID)
        #expect(layers.record(id: duplicatedID) == nil)
        #expect(layers.record(id: firstID) != nil)
    }

    @Test func templateApplicationPreservesExistingImageContentLayers() async throws {
        let imageData = try #require(Self.makeSolidImage(color: .magenta).pngData())
        var layers = ThumbnailDocumentLayer.defaultLayers(hasText: true, hasProfile: false)
        let layerID = layers.addImageLayer(
            imageData: imageData,
            id: "preserved-image-layer",
            transform: ThumbnailOverlayTransform(x: 0.24, y: 0.7),
            size: 0.38
        )
        let existingDocument = ThumbnailDocument(
            updatedAt: Date(timeIntervalSince1970: 1),
            text: ThumbnailDocumentText(value: "Existing"),
            layers: layers
        )
        let template = try #require(ThumbnailTemplate.builtIns.first)

        let strippedDocument = ThumbnailTemplate(
            id: "local-template",
            name: "Local",
            category: .youtube,
            document: existingDocument
        )
        .makeDocument()

        #expect(strippedDocument.layers.record(id: layerID) == nil)

        let appliedDocument = template.makeDocument(preservingImagesFrom: existingDocument)
        let preservedLayer = try #require(appliedDocument.layers.record(id: layerID))

        guard case .image(let content) = preservedLayer.content else {
            Issue.record("Expected preserved content layer to remain an image")
            return
        }

        #expect(content.imageData == imageData)
        #expect(content.transform == ThumbnailOverlayTransform(x: 0.24, y: 0.7))
        #expect(content.size == 0.38)
    }

    @MainActor
    @Test func simpleViewModelTextLayerOperationsAreUndoable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("simple-maker-text-layer-draft.json")
        let store = ThumbnailDraftStore(fileURL: url)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let viewModel = SimpleMakerViewModel(draftStore: store)

        let firstSelection = viewModel.addTextLayer(value: "Layer headline")
        guard case .content(let firstID) = firstSelection else {
            Issue.record("Expected addTextLayer to select the new content layer")
            return
        }

        let firstLayer = try #require(viewModel.simpleMakerConfiguration.layers.record(id: firstID))
        guard case .text(let firstContent) = firstLayer.content else {
            Issue.record("Expected addTextLayer to create text content")
            return
        }

        #expect(firstContent.value == "Layer headline")
        #expect(viewModel.canUndo)

        let duplicatedSelection = try #require(viewModel.duplicateLayer(firstSelection))
        guard case .content(let duplicatedID) = duplicatedSelection else {
            Issue.record("Expected duplicateLayer to select the duplicated text layer")
            return
        }

        #expect(viewModel.simpleMakerConfiguration.layers.record(id: duplicatedID) != nil)

        let nextSelection = viewModel.deleteLayer(duplicatedSelection)
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: duplicatedID) == nil)
        #expect(nextSelection == firstSelection)

        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: duplicatedID) != nil)

        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: duplicatedID) == nil)
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: firstID) != nil)

        viewModel.undo()
        #expect(!viewModel.simpleMakerConfiguration.layers.hasContentLayers)
    }

    @MainActor
    @Test func simpleViewModelShapeLayerOperationsAreUndoable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("simple-maker-shape-draft.json")
        let store = ThumbnailDraftStore(fileURL: url)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let viewModel = SimpleMakerViewModel(draftStore: store)

        let firstSelection = viewModel.addShapeLayer(.ellipse)
        guard case .content(let firstID) = firstSelection else {
            Issue.record("Expected addShapeLayer to select the new content layer")
            return
        }

        let firstLayer = try #require(viewModel.simpleMakerConfiguration.layers.record(id: firstID))
        guard case .shape(let firstContent) = firstLayer.content else {
            Issue.record("Expected addShapeLayer to create shape content")
            return
        }

        #expect(firstContent.shapeKind == .ellipse)
        #expect(viewModel.canUndo)

        let duplicatedSelection = try #require(viewModel.duplicateLayer(firstSelection))
        guard case .content(let duplicatedID) = duplicatedSelection else {
            Issue.record("Expected duplicateLayer to select the duplicated shape layer")
            return
        }

        #expect(viewModel.simpleMakerConfiguration.layers.record(id: duplicatedID) != nil)

        let nextSelection = viewModel.deleteLayer(duplicatedSelection)
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: duplicatedID) == nil)
        #expect(nextSelection == firstSelection)

        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: duplicatedID) != nil)

        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: duplicatedID) == nil)
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: firstID) != nil)

        viewModel.undo()
        #expect(!viewModel.simpleMakerConfiguration.layers.hasContentLayers)
    }

    @MainActor
    @Test func simpleViewModelImageLayerOperationsAreUndoable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("simple-maker-layer-draft.json")
        let store = ThumbnailDraftStore(fileURL: url)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let imageData = try #require(Self.makeSolidImage(color: .purple).pngData())
        let viewModel = SimpleMakerViewModel(draftStore: store)

        let firstSelection = viewModel.addImageLayer(imageData: imageData)
        guard case .content(let firstID) = firstSelection else {
            Issue.record("Expected addImageLayer to select the new content layer")
            return
        }

        #expect(viewModel.simpleMakerConfiguration.layers.record(id: firstID) != nil)
        #expect(viewModel.canUndo)

        let duplicatedSelection = try #require(viewModel.duplicateLayer(firstSelection))
        guard case .content(let duplicatedID) = duplicatedSelection else {
            Issue.record("Expected duplicateLayer to select the duplicated layer")
            return
        }

        #expect(viewModel.simpleMakerConfiguration.layers.record(id: duplicatedID) != nil)

        let nextSelection = viewModel.deleteLayer(duplicatedSelection)
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: duplicatedID) == nil)
        #expect(nextSelection == firstSelection)

        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: duplicatedID) != nil)

        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: duplicatedID) == nil)
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: firstID) != nil)

        viewModel.undo()
        #expect(!viewModel.simpleMakerConfiguration.layers.hasContentLayers)
    }

    @MainActor
    @Test func simpleViewModelStickerLayerOperationsAreUndoable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("simple-maker-sticker-draft.json")
        let store = ThumbnailDraftStore(fileURL: url)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let imageData = try #require(Self.makeSolidImage(color: .systemTeal).pngData())
        let viewModel = SimpleMakerViewModel(draftStore: store)

        let firstSelection = viewModel.addStickerLayer(imageData: imageData)
        guard case .content(let firstID) = firstSelection else {
            Issue.record("Expected addStickerLayer to select the new content layer")
            return
        }

        let firstLayer = try #require(viewModel.simpleMakerConfiguration.layers.record(id: firstID))
        guard case .image(let firstContent) = firstLayer.content else {
            Issue.record("Expected addStickerLayer to create image-backed sticker content")
            return
        }

        #expect(firstContent.isSticker)
        #expect(viewModel.canUndo)

        let duplicatedSelection = try #require(viewModel.duplicateLayer(firstSelection))
        guard case .content(let duplicatedID) = duplicatedSelection else {
            Issue.record("Expected duplicateLayer to select the duplicated sticker layer")
            return
        }

        let duplicatedLayer = try #require(viewModel.simpleMakerConfiguration.layers.record(id: duplicatedID))
        guard case .image(let duplicatedContent) = duplicatedLayer.content else {
            Issue.record("Expected duplicated sticker to stay image-backed")
            return
        }
        #expect(duplicatedContent.isSticker)

        let nextSelection = viewModel.deleteLayer(duplicatedSelection)
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: duplicatedID) == nil)
        #expect(nextSelection == firstSelection)

        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: duplicatedID) != nil)

        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: duplicatedID) == nil)
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: firstID) != nil)

        viewModel.undo()
        #expect(!viewModel.simpleMakerConfiguration.layers.hasContentLayers)
    }

    @MainActor
    @Test func simpleViewModelLayerReorderOperationsAreUndoable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("simple-maker-reorder-draft.json")
        let store = ThumbnailDraftStore(fileURL: url)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let imageData = try #require(Self.makeSolidImage(color: .systemPurple).pngData())
        let viewModel = SimpleMakerViewModel(draftStore: store)

        let imageSelection = viewModel.addImageLayer(imageData: imageData)
        let shapeSelection = viewModel.addShapeLayer(.rectangle)
        guard case .content(let imageID) = imageSelection,
              case .content(let shapeID) = shapeSelection else {
            Issue.record("Expected image and shape additions to create content layers")
            return
        }

        let initialImageZIndex = try #require(viewModel.simpleMakerConfiguration.layers.record(id: imageID)).zIndex
        let initialShapeZIndex = try #require(viewModel.simpleMakerConfiguration.layers.record(id: shapeID)).zIndex
        #expect(initialImageZIndex < initialShapeZIndex)

        let selections = viewModel.selectableLayerSelections
        #expect(viewModel.simpleMakerConfiguration.layers.canMoveForward(imageSelection, within: selections))
        viewModel.moveLayerForward(imageSelection, within: selections)

        let movedImageZIndex = try #require(viewModel.simpleMakerConfiguration.layers.record(id: imageID)).zIndex
        let movedShapeZIndex = try #require(viewModel.simpleMakerConfiguration.layers.record(id: shapeID)).zIndex
        #expect(movedImageZIndex > movedShapeZIndex)
        #expect(viewModel.canUndo)

        viewModel.undo()
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: imageID)?.zIndex == initialImageZIndex)
        #expect(viewModel.simpleMakerConfiguration.layers.record(id: shapeID)?.zIndex == initialShapeZIndex)
    }

    @Test func overlayTransformMovesRotatesFlipsAndClamps() async throws {
        var transform = ThumbnailOverlayTransform.centered

        transform.move(by: CGSize(width: 200, height: -100), in: CGSize(width: 400, height: 200))
        #expect(transform.x == 0.95)
        #expect(transform.y == 0.05)

        transform.rotate(by: 195)
        #expect(transform.rotationDegrees == -165)

        transform.flipHorizontally()
        #expect(transform.isFlippedHorizontally)

        transform.reset()
        #expect(transform == .centered)
    }

    @Test func overlayTransformAccessibilityNudgeMovesFromCenterWithoutSnap() async throws {
        let canvasSize = CGSize(width: 400, height: 200)
        var transform = ThumbnailOverlayTransform.centered

        transform.move(by: CGSize(width: canvasSize.width * 0.02, height: 0), in: canvasSize)
        #expect(abs(transform.x - 0.52) < 0.000_001)
        #expect(transform.y == 0.5)

        transform.move(by: CGSize(width: 0, height: -canvasSize.height * 0.02), in: canvasSize)
        #expect(abs(transform.x - 0.52) < 0.000_001)
        #expect(abs(transform.y - 0.48) < 0.000_001)
    }

    @Test func overlayTransformSnapsToCenterWithinThreshold() async throws {
        #expect(ThumbnailOverlayTransform.snapped(0.5) == 0.5)
        #expect(ThumbnailOverlayTransform.snapped(0.48) == 0.5)
        #expect(ThumbnailOverlayTransform.snapped(0.53) == 0.5)
        #expect(ThumbnailOverlayTransform.snapped(0.46) == 0.46)
        #expect(ThumbnailOverlayTransform.snapped(0.1) == 0.1)

        var transform = ThumbnailOverlayTransform(x: 0.48, y: 0.53)
        transform.moveWithSnap(by: .zero, in: CGSize(width: 400, height: 200))
        #expect(transform.x == 0.5)
        #expect(transform.y == 0.5)

        var unsnapped = ThumbnailOverlayTransform(x: 0.3, y: 0.7)
        unsnapped.moveWithSnap(by: .zero, in: CGSize(width: 400, height: 200))
        #expect(unsnapped.x == 0.3)
        #expect(unsnapped.y == 0.7)
    }

    @Test func overlayTransformReportsCenterSnapGuides() async throws {
        let both = ThumbnailOverlayTransform.centerSnapGuide(forNormalized: 0.49, y: 0.51)
        #expect(both.contains(.xCentered))
        #expect(both.contains(.yCentered))

        let xOnly = ThumbnailOverlayTransform.centerSnapGuide(forNormalized: 0.49, y: 0.3)
        #expect(xOnly.contains(.xCentered))
        #expect(!xOnly.contains(.yCentered))

        let none = ThumbnailOverlayTransform.centerSnapGuide(forNormalized: 0.2, y: 0.8)
        #expect(none.isEmpty)
    }

    @Test func centerSnapGuidePreferenceMergesAxes() async throws {
        var guide: CenterSnapGuide = []
        CenterSnapGuidePreferenceKey.reduce(value: &guide) { .xCentered }
        CenterSnapGuidePreferenceKey.reduce(value: &guide) { .yCentered }

        #expect(guide == [.xCentered, .yCentered])
    }

    @Test func overlayHandleResizeAdjustsSizeAndClamps() async throws {
        let canvasSize = CGSize(width: 400, height: 200)

        let enlarged = ThumbnailOverlayTransform.adjustedOverlaySize(
            0.15,
            by: CGSize(width: 80, height: 40),
            in: canvasSize,
            limits: 0.08...0.34
        )
        #expect(abs(enlarged - 0.18) < 0.001)

        let clamped = ThumbnailOverlayTransform.adjustedOverlaySize(
            0.33,
            by: CGSize(width: 300, height: 300),
            in: canvasSize,
            limits: 0.08...0.34
        )
        #expect(clamped == 0.34)
    }

    @Test func overlayHandleRotationUsesCanvasSpaceAroundLayerCenter() async throws {
        let center = CGPoint(x: 100, y: 100)

        let clockwiseQuarterTurn = ThumbnailOverlayTransform.rotationDelta(
            from: CGPoint(x: 100, y: 40),
            to: CGPoint(x: 160, y: 100),
            around: center
        )
        #expect(abs(clockwiseQuarterTurn - 90) < 0.001)

        let normalizedWrap = ThumbnailOverlayTransform.rotationDelta(
            from: CGPoint(x: 100, y: 40),
            to: CGPoint(x: 40, y: 100),
            around: center
        )
        #expect(abs(normalizedWrap + 90) < 0.001)
    }

    @Test func documentHistoryNormalizesDatesAndCoalescesIdenticalSnapshots() async throws {
        var history = ThumbnailDocumentHistory()
        let first = Self.makeHistoryDocument("Same", updatedAt: Date(timeIntervalSince1970: 10))
        let sameContentLater = Self.makeHistoryDocument("Same", updatedAt: Date(timeIntervalSince1970: 20))

        history.record(first)
        history.record(sameContentLater)

        #expect(history.canUndo)
        let undoResult = history.undo(current: Self.makeHistoryDocument("Current"))
        #expect(undoResult?.text.value == "Same")
        #expect(!history.canUndo)
    }

    @Test func documentHistorySnapshotsKeepStableLayerIDs() async throws {
        let first = ThumbnailDocumentHistory.snapshot(
            Self.makeHistoryDocument("Stable", updatedAt: Date(timeIntervalSince1970: 10))
        )
        let sameContentLater = ThumbnailDocumentHistory.snapshot(
            Self.makeHistoryDocument("Stable", updatedAt: Date(timeIntervalSince1970: 20))
        )

        #expect(first.layers.map(\.id) == [ThumbnailDocumentLayer.backgroundID, ThumbnailDocumentLayer.textID])
        #expect(first.layers == sameContentLater.layers)
        #expect(first == sameContentLater)
    }

    @Test func documentHistoryUndoRedoAndNewEditsClearRedo() async throws {
        var history = ThumbnailDocumentHistory()
        let first = Self.makeHistoryDocument("First")
        let second = Self.makeHistoryDocument("Second")

        history.record(first)

        let undoCandidate = history.undo(current: second)
        let undone = try #require(undoCandidate)
        #expect(undone.text.value == "First")
        #expect(history.canRedo)

        history.record(undone)
        #expect(!history.canRedo)
    }

    @Test func documentHistoryRespectsLimit() async throws {
        var history = ThumbnailDocumentHistory(limit: 2)

        history.record(Self.makeHistoryDocument("One"))
        history.record(Self.makeHistoryDocument("Two"))
        history.record(Self.makeHistoryDocument("Three"))

        let firstUndo = history.undo(current: Self.makeHistoryDocument("Four"))
        let secondUndo = history.undo(current: Self.makeHistoryDocument("Three"))
        let thirdUndo = history.undo(current: Self.makeHistoryDocument("Two"))

        #expect(firstUndo?.text.value == "Three")
        #expect(secondUndo?.text.value == "Two")
        #expect(thirdUndo == nil)
    }

    @MainActor
    @Test func thumbnailDocumentRoundTripsSimpleConfiguration() async throws {
        var configuration = SimpleMakerConfigurationModel()
        configuration.selectedImage = Self.makeSolidImage(size: CGSize(width: 96, height: 54))
        configuration.overlayText = "Document text"
        configuration.selectedRatio = .ratio4_3
        configuration.backgroundColor = .black
        configuration.textColor = .green
        configuration.textSize = 0.22
        configuration.textTransform = ThumbnailOverlayTransform(
            x: 0.27,
            y: 0.63,
            rotationDegrees: 12,
            isFlippedHorizontally: true
        )
        configuration.selectedFont = .montserrat
        configuration.layers = ThumbnailDocumentLayer.defaultLayers(hasText: true, hasProfile: false)
        configuration.layers.setVisible(false, for: .text)
        configuration.layers.setLocked(true, for: .text)

        var exportOptions = ThumbnailExportOptions()
        exportOptions.applyPreset(.videoCover)
        exportOptions.format = .jpeg
        exportOptions.compressionQuality = 0.7
        exportOptions.usesCustomSize = true
        exportOptions.customSize = ThumbnailExportSize(width: 900, height: 500)
        configuration.exportOptions = exportOptions

        let document = ThumbnailDocument(
            configuration: configuration,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let decoded = try Self.roundTrip(document)
        let restored = decoded.makeSimpleConfiguration()

        #expect(decoded.editorMode == .simple)
        #expect(decoded.version == ThumbnailDocument.currentVersion)
        #expect(decoded.layers.map(\.id) == [ThumbnailDocumentLayer.backgroundID, ThumbnailDocumentLayer.textID])
        #expect(decoded.layers.map(\.kind) == [.background, .text])
        #expect(decoded.layers.record(for: .text)?.isVisible == false)
        #expect(decoded.layers.record(for: .text)?.isLocked == true)
        #expect(restored.overlayText == "Document text")
        #expect(restored.layers.record(for: .text)?.isVisible == false)
        #expect(restored.layers.record(for: .text)?.isLocked == true)
        #expect(restored.selectedRatio == .ratio4_3)
        #expect(restored.selectedImage?.size == CGSize(width: 96, height: 54))
        #expect(restored.textTransform == configuration.textTransform)
        #expect(restored.selectedFont == .montserrat)
        #expect(restored.exportOptions.preset == .videoCover)
        #expect(restored.exportOptions.format == .jpeg)
        #expect(restored.exportOptions.compressionQuality == 0.7)
        #expect(restored.exportOptions.customSize == ThumbnailExportSize(width: 900, height: 500))
    }

    @MainActor
    @Test func thumbnailDocumentRoundTripsPremiumConfiguration() async throws {
        var configuration = PremiumMakerConfigurationModel()
        configuration.selectedImage = Self.makeSolidImage(size: CGSize(width: 160, height: 90))
        configuration.overlayText = "Premium document"
        configuration.selectedRatio = .ratio1_1
        configuration.backgroundColor = .purple
        configuration.textColor = .yellow
        configuration.textSize = 0.19
        configuration.textTransform = ThumbnailOverlayTransform(x: 0.2, y: 0.8, rotationDegrees: -8)
        configuration.circularProfile = CircularProfileConfig(
            image: Self.makeSolidImage(color: .orange, size: CGSize(width: 48, height: 48)),
            size: 0.31
        )
        configuration.profileTransform = ThumbnailOverlayTransform(
            x: 0.18,
            y: 0.24,
            rotationDegrees: 22,
            isFlippedHorizontally: true
        )
        configuration.layers = ThumbnailDocumentLayer.defaultLayers(hasText: true, hasProfile: true)
        configuration.layers.setLocked(true, for: .text)
        configuration.layers.setVisible(false, for: .profile)
        configuration.layers.moveBackward(.text, within: [.text, .profile])
        configuration.macroConfig = MacroConfig(
            isEnabled: true,
            startNumber: 2,
            endNumber: 5,
            appendPosition: .before
        )

        var exportOptions = ThumbnailExportOptions()
        exportOptions.applyPreset(.podcastCover)
        exportOptions.format = .png
        configuration.exportOptions = exportOptions

        let decoded = try Self.roundTrip(ThumbnailDocument(configuration: configuration))
        let restored = decoded.makePremiumConfiguration()

        #expect(decoded.editorMode == .premium)
        #expect(decoded.version == ThumbnailDocument.currentVersion)
        #expect(
            decoded.layers.map(\.id) == [
                ThumbnailDocumentLayer.backgroundID,
                ThumbnailDocumentLayer.textID,
                ThumbnailDocumentLayer.profileID
            ]
        )
        #expect(decoded.layers.map(\.kind) == [.background, .text, .profile])
        #expect(decoded.layers.record(for: .text)?.isLocked == true)
        #expect(decoded.layers.record(for: .profile)?.isVisible == false)
        #expect(decoded.layers.sortedEditorLayers([.text, .profile]) == [.text, .profile])
        #expect(restored.overlayText == "Premium document")
        #expect(restored.layers.record(for: .text)?.isLocked == true)
        #expect(restored.layers.record(for: .profile)?.isVisible == false)
        #expect(restored.layers.sortedEditorLayers([.text, .profile]) == [.text, .profile])
        #expect(restored.selectedRatio == .ratio1_1)
        #expect(restored.selectedImage?.size == CGSize(width: 160, height: 90))
        #expect(restored.textTransform == configuration.textTransform)
        #expect(restored.circularProfile?.size == 0.31)
        #expect(restored.circularProfile?.image?.size == CGSize(width: 48, height: 48))
        #expect(restored.profileTransform == configuration.profileTransform)
        #expect(restored.macroConfig == configuration.macroConfig)
        #expect(restored.exportOptions.preset == .podcastCover)
        #expect(restored.exportOptions.format == .png)
    }

    @MainActor
    @Test func thumbnailDocumentDecodesLegacyDocumentWithoutLayers() async throws {
        var configuration = PremiumMakerConfigurationModel()
        configuration.overlayText = "Legacy layered document"
        configuration.circularProfile = CircularProfileConfig(
            image: Self.makeSolidImage(color: .orange, size: CGSize(width: 24, height: 24)),
            size: 0.25
        )

        let document = ThumbnailDocument(
            configuration: configuration,
            updatedAt: Date(timeIntervalSince1970: 300)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(document)

        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "layers")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ThumbnailDocument.self, from: legacyData)

        #expect(decoded.version == ThumbnailDocument.currentVersion)
        #expect(decoded.layers.map(\.id) == [
            ThumbnailDocumentLayer.backgroundID,
            ThumbnailDocumentLayer.profileID,
            ThumbnailDocumentLayer.textID
        ])
        #expect(decoded.layers.map(\.zIndex) == [0, 10, 20])
        #expect(decoded.profile?.transform == .profileDefault)
        #expect(decoded.text.value == "Legacy layered document")
    }

    @MainActor
    @Test func legacyProfilePositionMigratesToTransformWhenMissingTransform() async throws {
        var configuration = PremiumMakerConfigurationModel()
        configuration.overlayText = "Legacy profile position"
        configuration.circularProfile = CircularProfileConfig(
            image: Self.makeSolidImage(color: .orange, size: CGSize(width: 24, height: 24)),
            size: 0.25
        )

        let document = ThumbnailDocument(
            configuration: configuration,
            updatedAt: Date(timeIntervalSince1970: 310)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(document)

        let baseObject = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let baseProfile = try #require(baseObject["profile"] as? [String: Any])
        #expect(baseProfile["positionRawValue"] == nil)

        let legacyMappings: [(String?, ThumbnailOverlayTransform)] = [
            ("topLeft", ThumbnailOverlayTransform(x: 0.16, y: 0.18)),
            ("topCenter", ThumbnailOverlayTransform(x: 0.5, y: 0.18)),
            ("topRight", .profileDefault),
            ("middleLeft", ThumbnailOverlayTransform(x: 0.16, y: 0.5)),
            ("middleCenter", .centered),
            ("middleRight", ThumbnailOverlayTransform(x: 0.84, y: 0.5)),
            ("bottomLeft", ThumbnailOverlayTransform(x: 0.16, y: 0.82)),
            ("bottomCenter", ThumbnailOverlayTransform(x: 0.5, y: 0.82)),
            ("bottomRight", ThumbnailOverlayTransform(x: 0.84, y: 0.82)),
            ("unknownLegacyPosition", .profileDefault),
            (nil, .profileDefault)
        ]

        for (positionRawValue, expectedTransform) in legacyMappings {
            var object = baseObject
            var profile = baseProfile
            profile.removeValue(forKey: "transform")
            if let positionRawValue {
                profile["positionRawValue"] = positionRawValue
            } else {
                profile.removeValue(forKey: "positionRawValue")
            }
            object["profile"] = profile

            let legacyData = try JSONSerialization.data(withJSONObject: object)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(ThumbnailDocument.self, from: legacyData)
            let restored = decoded.makePremiumConfiguration()

            #expect(restored.circularProfile?.size == 0.25)
            #expect(restored.circularProfile?.image?.size == CGSize(width: 24, height: 24))
            #expect(restored.profileTransform == expectedTransform)
        }
    }

    @Test func loadingMissingSimpleDraftReturnsNil() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("simple-maker-draft.json")
        let store = ThumbnailDraftStore(fileURL: url)

        #expect(try store.load() == nil)
    }

    @MainActor
    @Test func simpleDraftStoreMigratesLegacySimpleDraft() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("simple-maker-draft.json")
        let store = ThumbnailDraftStore(fileURL: url)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        var configuration = SimpleMakerConfigurationModel()
        configuration.overlayText = "Legacy draft"
        configuration.textTransform = ThumbnailOverlayTransform(x: 0.4, y: 0.7, rotationDegrees: 18)
        configuration.selectedImage = Self.makeSolidImage(size: CGSize(width: 60, height: 34))

        let legacyDraft = SimpleThumbnailDraft(
            configuration: configuration,
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try encoder.encode(legacyDraft).write(to: url)

        let migratedDocument = try #require(try store.loadDocument())
        let restored = try #require(try store.load())

        #expect(migratedDocument.editorMode == .simple)
        #expect(migratedDocument.updatedAt == Date(timeIntervalSince1970: 200))
        #expect(migratedDocument.layers.map(\.id) == [
            ThumbnailDocumentLayer.backgroundID,
            ThumbnailDocumentLayer.textID
        ])
        #expect(restored.overlayText == "Legacy draft")
        #expect(restored.textTransform == ThumbnailOverlayTransform(x: 0.4, y: 0.7, rotationDegrees: 18))
        #expect(restored.selectedImage?.size == CGSize(width: 60, height: 34))
    }

    @MainActor
    @Test func simpleDraftStoreRoundTripsConfiguration() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("simple-maker-draft.json")
        let store = ThumbnailDraftStore(fileURL: url)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 80, height: 45),
            format: format
        ).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 45))
            UIColor.systemYellow.setFill()
            context.fill(CGRect(x: 10, y: 12, width: 30, height: 16))
        }

        var configuration = SimpleMakerConfigurationModel()
        configuration.selectedImage = image
        configuration.overlayText = "Saved draft"
        configuration.selectedRatio = .ratio9_16
        configuration.backgroundColor = .red
        configuration.textColor = .yellow
        configuration.textSize = 0.24
        configuration.verticalAlignment = .top
        configuration.horizontalAlignment = .trailing
        configuration.textTransform = ThumbnailOverlayTransform(
            x: 0.32,
            y: 0.71,
            rotationDegrees: -15,
            isFlippedHorizontally: true
        )
        configuration.selectedFont = .montserrat
        configuration.usesFallbackFont = true

        var exportOptions = ThumbnailExportOptions()
        exportOptions.applyPreset(.shortFormCover)
        exportOptions.format = .jpeg
        exportOptions.compressionQuality = 0.62
        exportOptions.usesCustomSize = true
        exportOptions.customSize = ThumbnailExportSize(width: 720, height: 1280)
        configuration.exportOptions = exportOptions

        try store.save(configuration)

        let restored = try #require(try store.load())
        #expect(restored.overlayText == "Saved draft")
        #expect(restored.selectedRatio == .ratio9_16)
        #expect(restored.textSize == 0.24)
        #expect(restored.verticalAlignment == .top)
        #expect(restored.horizontalAlignment == .trailing)
        #expect(restored.textTransform == ThumbnailOverlayTransform(
            x: 0.32,
            y: 0.71,
            rotationDegrees: -15,
            isFlippedHorizontally: true
        ))
        #expect(restored.selectedFont == .montserrat)
        #expect(restored.selectedImage?.size == image.size)
        #expect(restored.exportOptions.preset == .shortFormCover)
        #expect(restored.exportOptions.format == .jpeg)
        #expect(restored.exportOptions.compressionQuality == 0.62)
        #expect(restored.exportOptions.usesCustomSize)
        #expect(restored.exportOptions.customSize == ThumbnailExportSize(width: 720, height: 1280))
        #expect(Self.colorComponents(restored.backgroundColor) == Self.colorComponents(.red))
        #expect(Self.colorComponents(restored.textColor) == Self.colorComponents(.yellow))
    }

    @MainActor
    @Test func premiumDraftStoreRoundTripsConfiguration() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("premium-maker-draft.json")
        let store = ThumbnailDraftStore(fileURL: url)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        var configuration = PremiumMakerConfigurationModel()
        configuration.selectedImage = Self.makeSolidImage(size: CGSize(width: 120, height: 68))
        configuration.overlayText = "Premium saved"
        configuration.textTransform = ThumbnailOverlayTransform(x: 0.52, y: 0.33, rotationDegrees: 9)
        configuration.circularProfile = CircularProfileConfig(
            image: Self.makeSolidImage(color: .cyan, size: CGSize(width: 32, height: 32)),
            size: 0.28
        )
        configuration.profileTransform = ThumbnailOverlayTransform(
            x: 0.81,
            y: 0.41,
            rotationDegrees: -30,
            isFlippedHorizontally: true
        )
        configuration.macroConfig = MacroConfig(
            isEnabled: true,
            startNumber: 9,
            endNumber: 4,
            appendPosition: .after
        )

        var exportOptions = ThumbnailExportOptions()
        exportOptions.applyPreset(.portraitCover)
        exportOptions.format = .webP
        exportOptions.compressionQuality = 0.58
        configuration.exportOptions = exportOptions

        try store.save(configuration)

        let restored = try #require(try store.loadPremium())
        #expect(restored.overlayText == "Premium saved")
        #expect(restored.selectedImage?.size == CGSize(width: 120, height: 68))
        #expect(restored.textTransform == configuration.textTransform)
        #expect(restored.circularProfile?.size == 0.28)
        #expect(restored.circularProfile?.image?.size == CGSize(width: 32, height: 32))
        #expect(restored.profileTransform == configuration.profileTransform)
        #expect(restored.macroConfig == configuration.macroConfig)
        #expect(restored.exportOptions.preset == .portraitCover)
        #expect(restored.exportOptions.format == .webP)
        #expect(restored.exportOptions.compressionQuality == 0.58)
    }

    @MainActor
    @Test func premiumViewModelRestoresDraft() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("premium-maker-draft.json")
        let store = ThumbnailDraftStore(fileURL: url)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        var configuration = PremiumMakerConfigurationModel()
        configuration.overlayText = "Restored premium"
        configuration.selectedImage = Self.makeSolidImage(size: CGSize(width: 100, height: 56))
        try store.save(configuration)

        let viewModel = PremiumMakerViewModel(draftStore: store)

        #expect(viewModel.restoredDraft)
        #expect(viewModel.premiumMakerConfiguration.overlayText == "Restored premium")
        #expect(viewModel.premiumMakerConfiguration.selectedImage?.size == CGSize(width: 100, height: 56))
    }

    @MainActor
    @Test func simpleViewModelUndoRedoRestoresDocumentSnapshots() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("simple-maker-draft.json")
        let store = ThumbnailDraftStore(fileURL: url)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let viewModel = SimpleMakerViewModel(draftStore: store)
        viewModel.simpleMakerConfiguration.overlayText = "First"
        viewModel.commitEditorStateNow()
        viewModel.simpleMakerConfiguration.overlayText = "Second"

        viewModel.undo()

        #expect(viewModel.simpleMakerConfiguration.overlayText == "First")
        #expect(viewModel.canRedo)

        viewModel.redo()

        #expect(viewModel.simpleMakerConfiguration.overlayText == "Second")
        #expect(viewModel.canUndo)
        #expect(!viewModel.canRedo)
    }

    @MainActor
    @Test func premiumViewModelUndoRedoRestoresProfileSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("premium-maker-draft.json")
        let store = ThumbnailDraftStore(fileURL: url)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let viewModel = PremiumMakerViewModel(draftStore: store)
        viewModel.premiumMakerConfiguration.overlayText = "Base"
        viewModel.commitEditorStateNow()
        viewModel.premiumMakerConfiguration.overlayText = "With profile"
        viewModel.premiumMakerConfiguration.circularProfile = CircularProfileConfig(
            image: Self.makeSolidImage(color: .orange, size: CGSize(width: 40, height: 40)),
            size: 0.32
        )
        viewModel.premiumMakerConfiguration.profileTransform = ThumbnailOverlayTransform(
            x: 0.8,
            y: 0.2,
            rotationDegrees: 15,
            isFlippedHorizontally: true
        )

        viewModel.undo()

        #expect(viewModel.premiumMakerConfiguration.overlayText == "Base")
        #expect(viewModel.premiumMakerConfiguration.circularProfile == nil)
        #expect(viewModel.canRedo)

        viewModel.redo()

        #expect(viewModel.premiumMakerConfiguration.overlayText == "With profile")
        #expect(viewModel.premiumMakerConfiguration.circularProfile != nil)
        #expect(viewModel.premiumMakerConfiguration.circularProfile?.size == 0.32)
        #expect(viewModel.premiumMakerConfiguration.profileTransform == ThumbnailOverlayTransform(
            x: 0.8,
            y: 0.2,
            rotationDegrees: 15,
            isFlippedHorizontally: true
        ))
    }

    @MainActor
    @Test func simpleViewModelApplyTemplatePreservesLiveImageAndUndoRedo() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("simple-maker-draft.json")
        let store = ThumbnailDraftStore(fileURL: url)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let viewModel = SimpleMakerViewModel(draftStore: store)
        let image = Self.makeSolidImage(color: .blue, size: CGSize(width: 96, height: 54))
        viewModel.simpleMakerConfiguration.selectedImage = image
        viewModel.simpleMakerConfiguration.overlayText = "Before"
        viewModel.simpleMakerConfiguration.textColor = .red
        let template = try #require(ThumbnailTemplate.builtIns.first)

        viewModel.applyTemplate(template)

        #expect(viewModel.simpleMakerConfiguration.overlayText == template.document.text.value)
        #expect(viewModel.simpleMakerConfiguration.selectedRatio.rawValue == template.document.canvas.aspectRatioRawValue)
        #expect(viewModel.simpleMakerConfiguration.selectedImage?.size == image.size)
        #expect(viewModel.canUndo)

        viewModel.undo()

        #expect(viewModel.simpleMakerConfiguration.overlayText == "Before")
        #expect(viewModel.simpleMakerConfiguration.selectedImage?.size == image.size)
        #expect(Self.colorComponents(viewModel.simpleMakerConfiguration.textColor) == Self.colorComponents(.red))
        #expect(viewModel.canRedo)

        viewModel.redo()

        #expect(viewModel.simpleMakerConfiguration.overlayText == template.document.text.value)
        #expect(viewModel.simpleMakerConfiguration.selectedImage?.size == image.size)
    }

    @MainActor
    @Test func premiumViewModelApplyTemplatePreservesLiveImagesAndProfileLayer() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("premium-maker-draft.json")
        let store = ThumbnailDraftStore(fileURL: url)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let viewModel = PremiumMakerViewModel(draftStore: store)
        let backgroundImage = Self.makeSolidImage(color: .blue, size: CGSize(width: 120, height: 68))
        let profileImage = Self.makeSolidImage(color: .orange, size: CGSize(width: 40, height: 40))
        viewModel.premiumMakerConfiguration.selectedImage = backgroundImage
        viewModel.premiumMakerConfiguration.overlayText = "Before premium"
        viewModel.premiumMakerConfiguration.circularProfile = CircularProfileConfig(
            image: profileImage,
            size: 0.29
        )
        viewModel.premiumMakerConfiguration.profileTransform = ThumbnailOverlayTransform(
            x: 0.78,
            y: 0.26,
            rotationDegrees: -8
        )
        viewModel.premiumMakerConfiguration.layers.setLocked(true, for: .profile)
        let template = try #require(ThumbnailTemplate.builtIns.first)

        viewModel.applyTemplate(template)

        #expect(viewModel.premiumMakerConfiguration.overlayText == template.document.text.value)
        #expect(viewModel.premiumMakerConfiguration.selectedRatio.rawValue == template.document.canvas.aspectRatioRawValue)
        #expect(viewModel.premiumMakerConfiguration.selectedImage?.size == backgroundImage.size)
        #expect(viewModel.premiumMakerConfiguration.circularProfile?.image?.size == profileImage.size)
        #expect(viewModel.premiumMakerConfiguration.circularProfile?.size == 0.29)
        #expect(viewModel.premiumMakerConfiguration.layers.record(for: .profile)?.isLocked == true)
        #expect(viewModel.canUndo)

        viewModel.undo()

        #expect(viewModel.premiumMakerConfiguration.overlayText == "Before premium")
        #expect(viewModel.premiumMakerConfiguration.selectedImage?.size == backgroundImage.size)
        #expect(viewModel.premiumMakerConfiguration.circularProfile?.image?.size == profileImage.size)
        #expect(viewModel.premiumMakerConfiguration.circularProfile?.size == 0.29)
        #expect(viewModel.premiumMakerConfiguration.profileTransform == ThumbnailOverlayTransform(
            x: 0.78,
            y: 0.26,
            rotationDegrees: -8
        ))
        #expect(viewModel.premiumMakerConfiguration.layers.record(for: .profile)?.isLocked == true)
        #expect(viewModel.canRedo)

        viewModel.redo()

        #expect(viewModel.premiumMakerConfiguration.overlayText == template.document.text.value)
        #expect(viewModel.premiumMakerConfiguration.selectedImage?.size == backgroundImage.size)
        #expect(viewModel.premiumMakerConfiguration.circularProfile?.image?.size == profileImage.size)
    }

    private static func colorComponents(_ color: Color) -> [Int] {
        let resolvedColor = UIColor(color)
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return [red, green, blue, alpha].map { Int(round($0 * 255)) }
    }

    private func rotatedBounds(center: CGPoint, size: CGSize, degrees: Double) -> CGRect {
        let radians = CGFloat(degrees) * .pi / 180
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        let rotatedHalfWidth = abs(halfWidth * cos(radians)) + abs(halfHeight * sin(radians))
        let rotatedHalfHeight = abs(halfWidth * sin(radians)) + abs(halfHeight * cos(radians))

        return CGRect(
            x: center.x - rotatedHalfWidth,
            y: center.y - rotatedHalfHeight,
            width: rotatedHalfWidth * 2,
            height: rotatedHalfHeight * 2
        )
    }

    private static func makeBrandKit() -> BrandKit {
        BrandKit(
            id: "creator-kit",
            name: "Creator Kit",
            palette: [
                BrandColor(
                    id: "creator-kit-gold",
                    name: "Gold",
                    color: ThumbnailDocumentColor(red: 1.0, green: 214.0 / 255.0, blue: 64.0 / 255.0, alpha: 1)
                ),
                BrandColor(
                    id: "creator-kit-ink",
                    name: "Ink",
                    color: ThumbnailDocumentColor(red: 18.0 / 255.0, green: 26.0 / 255.0, blue: 38.0 / 255.0, alpha: 1)
                )
            ],
            primaryFontRawValue: CustomFont.montserrat.rawValue,
            secondaryFontRawValue: CustomFont.openSans.rawValue,
            logoImageData: Data([7, 8, 9]),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private static func makeSolidImage(
        color: UIColor = .black,
        size: CGSize = CGSize(width: 80, height: 45)
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private static func roundTrip(_ document: ThumbnailDocument) throws -> ThumbnailDocument {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(document)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ThumbnailDocument.self, from: data)
    }

    private static func makeHistoryDocument(
        _ text: String,
        updatedAt: Date = Date(timeIntervalSince1970: 1)
    ) -> ThumbnailDocument {
        ThumbnailDocument(
            updatedAt: updatedAt,
            text: ThumbnailDocumentText(value: text)
        )
    }

    private struct StubSubjectProcessor: ThumbnailSubjectProcessing {
        var crop: CGRect? = nil
        var backgroundRemovedImage: UIImage? = nil

        func removeBackground(from image: UIImage) async throws -> UIImage {
            backgroundRemovedImage ?? image
        }

        func suggestedFaceCrop(in image: UIImage, padding: CGFloat) async throws -> CGRect? {
            crop
        }
    }
}
