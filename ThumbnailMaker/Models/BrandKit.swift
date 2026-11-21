//
//  BrandKit.swift
//  ThumbnailMaker
//

import Foundation
import SwiftUI

struct BrandColor: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var color: ThumbnailDocumentColor

    init(id: String, name: String, color: ThumbnailDocumentColor) {
        self.id = id
        self.name = name
        self.color = color
    }
}

struct BrandKit: Codable, Equatable, Identifiable {
    static let currentVersion = 2

    var version = currentVersion
    var id: String
    var name: String
    var palette: [BrandColor]
    var primaryFontRawValue: String
    var secondaryFontRawValue: String?
    var logoImageData: Data?
    /// FEATURE-08: named reusable layer styles owned by this kit.
    var styles: [ThumbnailLayerStyle] = []
    var updatedAt: Date

    init(
        version: Int = BrandKit.currentVersion,
        id: String,
        name: String,
        palette: [BrandColor] = [],
        primaryFontRawValue: String = CustomFont.goNoto.rawValue,
        secondaryFontRawValue: String? = nil,
        logoImageData: Data? = nil,
        styles: [ThumbnailLayerStyle] = [],
        updatedAt: Date = Date()
    ) {
        self.version = version
        self.id = id
        self.name = name
        self.palette = palette
        self.primaryFontRawValue = primaryFontRawValue
        self.secondaryFontRawValue = secondaryFontRawValue
        self.logoImageData = logoImageData
        self.styles = styles
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case id
        case name
        case palette
        case primaryFontRawValue
        case secondaryFontRawValue
        case logoImageData
        case styles
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion

        version = max(decodedVersion, Self.currentVersion)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        palette = try container.decodeIfPresent([BrandColor].self, forKey: .palette) ?? []
        primaryFontRawValue = try container.decodeIfPresent(
            String.self,
            forKey: .primaryFontRawValue
        ) ?? CustomFont.goNoto.rawValue
        secondaryFontRawValue = try container.decodeIfPresent(String.self, forKey: .secondaryFontRawValue)
        logoImageData = try container.decodeIfPresent(Data.self, forKey: .logoImageData)
        styles = try container.decodeIfPresent([ThumbnailLayerStyle].self, forKey: .styles) ?? []
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
    }
}

extension BrandKit {
    static func defaultCreatorKit(id: String = UUID().uuidString) -> BrandKit {
        BrandKit(
            id: id,
            name: "Creator Brand",
            palette: [
                BrandColor(
                    id: "\(id)-text",
                    name: "Text",
                    color: ThumbnailDocumentColor(color: .white)
                ),
                BrandColor(
                    id: "\(id)-background",
                    name: "Background",
                    color: ThumbnailDocumentColor(
                        red: 18.0 / 255.0,
                        green: 26.0 / 255.0,
                        blue: 38.0 / 255.0,
                        alpha: 1
                    )
                )
            ],
            primaryFontRawValue: CustomFont.montserrat.rawValue,
            secondaryFontRawValue: CustomFont.openSans.rawValue
        )
    }

    var primaryFont: CustomFont {
        CustomFont(rawValue: primaryFontRawValue) ?? .goNoto
    }

    var secondaryFont: CustomFont? {
        secondaryFontRawValue.flatMap(CustomFont.init(rawValue:))
    }

    func applied(to configuration: SimpleMakerConfigurationModel) -> SimpleMakerConfigurationModel {
        var probe = configuration
        probe.selectedImage = nil // styling never reads pixels; skip the PNG encode
        var configuration = configuration
        configuration.adoptStyling(from: applied(to: probe.document, scope: .projectWide))
        configuration.usesFallbackFont = false
        return configuration
    }

    func applied(to configuration: PremiumMakerConfigurationModel) -> PremiumMakerConfigurationModel {
        var probe = configuration
        probe.selectedImage = nil
        var configuration = configuration
        configuration.adoptStyling(from: applied(to: probe.document, scope: .projectWide))
        configuration.usesFallbackFont = false
        return configuration
    }
}
