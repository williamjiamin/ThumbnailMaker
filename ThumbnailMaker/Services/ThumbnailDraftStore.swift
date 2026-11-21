//
//  ThumbnailDraftStore.swift
//  ThumbnailMaker
//

import Foundation
import SwiftUI
import UIKit

struct ThumbnailDraftColor: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(color: Color) {
        let resolvedColor = UIColor(color)
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        if resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            self.init(
                red: Double(red),
                green: Double(green),
                blue: Double(blue),
                alpha: Double(alpha)
            )
        } else {
            var white: CGFloat = 0
            resolvedColor.getWhite(&white, alpha: &alpha)
            self.init(
                red: Double(white),
                green: Double(white),
                blue: Double(white),
                alpha: Double(alpha)
            )
        }
    }

    var color: Color {
        Color(
            uiColor: UIColor(
                red: CGFloat(red),
                green: CGFloat(green),
                blue: CGFloat(blue),
                alpha: CGFloat(alpha)
            )
        )
    }
}

struct SimpleThumbnailDraft: Codable, Equatable {
    static let currentVersion = 1

    var version = currentVersion
    var updatedAt: Date
    var overlayText: String
    var aspectRatioRawValue: String
    var backgroundColor: ThumbnailDraftColor
    var textColor: ThumbnailDraftColor
    var textSize: Double
    var verticalAlignmentRawValue: String
    var horizontalAlignmentRawValue: String
    var textTransform: ThumbnailOverlayTransform?
    var selectedFontRawValue: String
    var exportPresetID: String
    var exportFormatRawValue: String
    var compressionQuality: Double
    var usesCustomSize: Bool
    var customWidth: Int
    var customHeight: Int
    var imageData: Data?

    init(configuration: SimpleMakerConfigurationModel, updatedAt: Date = Date()) {
        let exportOptions = configuration.exportOptions

        self.updatedAt = updatedAt
        overlayText = configuration.overlayText
        aspectRatioRawValue = configuration.selectedRatio.rawValue
        backgroundColor = ThumbnailDraftColor(color: configuration.backgroundColor)
        textColor = ThumbnailDraftColor(color: configuration.textColor)
        textSize = Double(configuration.textSize)
        verticalAlignmentRawValue = configuration.verticalAlignment.rawValue
        horizontalAlignmentRawValue = configuration.horizontalAlignment.rawValue
        textTransform = configuration.textTransform
        selectedFontRawValue = configuration.selectedFont.rawValue
        exportPresetID = exportOptions.preset.id
        exportFormatRawValue = exportOptions.format.rawValue
        compressionQuality = exportOptions.compressionQuality
        usesCustomSize = exportOptions.usesCustomSize
        customWidth = exportOptions.customSize.width
        customHeight = exportOptions.customSize.height
        imageData = configuration.selectedImage?.jpegData(compressionQuality: 0.92)
            ?? configuration.selectedImage?.pngData()
    }

    func makeConfiguration() -> SimpleMakerConfigurationModel {
        var configuration = SimpleMakerConfigurationModel()
        configuration.overlayText = overlayText
        configuration.selectedRatio = AspectRatio(rawValue: aspectRatioRawValue) ?? .ratio16_9
        configuration.backgroundColor = backgroundColor.color
        configuration.textColor = textColor.color
        configuration.textSize = CGFloat(textSize)
        configuration.verticalAlignment = VerticalAlignment(rawValue: verticalAlignmentRawValue) ?? .center
        configuration.horizontalAlignment = HorizontalAlignment(rawValue: horizontalAlignmentRawValue) ?? .center
        configuration.textTransform = textTransform ?? .centered
        configuration.selectedFont = CustomFont(rawValue: selectedFontRawValue) ?? .goNoto
        configuration.selectedImage = imageData.flatMap(UIImage.init(data:))

        var exportOptions = ThumbnailExportOptions()
        if let preset = ThumbnailExportPreset.all.first(where: { $0.id == exportPresetID }) {
            exportOptions.applyPreset(preset)
        }
        exportOptions.format = ThumbnailExportFormat(rawValue: exportFormatRawValue) ?? .png
        exportOptions.compressionQuality = compressionQuality
        exportOptions.usesCustomSize = usesCustomSize
        exportOptions.customSize = ThumbnailExportSize(width: customWidth, height: customHeight)
        configuration.exportOptions = exportOptions

        return configuration
    }
}

final class ThumbnailDraftStore {
    enum DraftKind {
        case simple
        case premium

        var fileName: String {
            switch self {
            case .simple:
                return "simple-maker-draft.json"
            case .premium:
                return "premium-maker-draft.json"
            }
        }
    }

    let fileURL: URL

    init(fileURL: URL = ThumbnailDraftStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    convenience init(kind: DraftKind) {
        self.init(fileURL: Self.defaultFileURL(for: kind))
    }

    static var defaultFileURL: URL {
        defaultFileURL(for: .simple)
    }

    static func defaultFileURL(for kind: DraftKind) -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return applicationSupport
            .appendingPathComponent("ThumbnailMaker", isDirectory: true)
            .appendingPathComponent("Drafts", isDirectory: true)
            .appendingPathComponent(kind.fileName)
    }

    func save(_ configuration: SimpleMakerConfigurationModel) throws {
        try save(configuration.document)
    }

    func save(_ configuration: PremiumMakerConfigurationModel) throws {
        try save(configuration.document)
    }

    func save(_ document: ThumbnailDocument) throws {
        var document = document
        document.updatedAt = Date()

        let encoder = JSONEncoder.thumbnailDocumentEncoder

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try encoder.encode(document).write(to: fileURL, options: [.atomic])
    }

    func load() throws -> SimpleMakerConfigurationModel? {
        try loadDocument()?.makeSimpleConfiguration()
    }

    func loadPremium() throws -> PremiumMakerConfigurationModel? {
        try loadDocument()?.makePremiumConfiguration()
    }

    func loadDocument() throws -> ThumbnailDocument? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder.thumbnailDocumentDecoder

        do {
            return try decoder.decode(ThumbnailDocument.self, from: data)
        } catch {
            let legacyDraft = try decoder.decode(SimpleThumbnailDraft.self, from: data)
            return ThumbnailDocument(
                configuration: legacyDraft.makeConfiguration(),
                updatedAt: legacyDraft.updatedAt
            )
        }
    }

    func delete() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: fileURL)
    }
}

private extension JSONEncoder {
    static var thumbnailDocumentEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var thumbnailDocumentDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
