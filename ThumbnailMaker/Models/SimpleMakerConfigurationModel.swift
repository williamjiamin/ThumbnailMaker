//
//  ThumbnailModel.swift
//  ThumbnailMaker
//
//  Created by william on 2024/11/28.
//

import Foundation
import SwiftUI

struct SimpleMakerConfigurationModel {
    var selectedImage: UIImage?
    /// FEATURE-03: non-destructive fit/fill/focal/zoom framing of `selectedImage`.
    var imageRecipe: ThumbnailImageFrameRecipe = .identity
    var overlayText: String = ""
    var selectedRatio: AspectRatio = .ratio16_9
    var backgroundColor: Color = Color(uiColor: .secondarySystemBackground)
    /// SHELL: optional gradient background (nil = solid `backgroundColor`).
    var backgroundFill: ThumbnailBackgroundFill? = nil
    var textColor: Color = .white
    var textSize: CGFloat = 0.15
    var verticalAlignment: VerticalAlignment = .center
    var horizontalAlignment: HorizontalAlignment = .center
    var textTransform = ThumbnailOverlayTransform.centered
    var selectedFont: CustomFont = .goNoto
    var usesFallbackFont: Bool = false
    /// FEATURE-04: nil keeps the legacy overlay text look.
    var textStyle: ThumbnailTextStyle? = nil
    /// GAPS: the main title shrinks to fit (text size becomes a maximum).
    var overlayAutoFit: Bool = false
    var layers: [ThumbnailDocumentLayer] = ThumbnailDocumentLayer.defaultLayers(
        hasText: false,
        hasProfile: false
    )
    var exportOptions = ThumbnailExportOptions()
    /// FEATURE-08: brand kit / style provenance (badge only, never rendered).
    var branding = ThumbnailDocumentBranding()
    /// FEATURE-09: alternate sizes, carried verbatim (never resolved here).
    var formatSet: ThumbnailFormatSet? = nil
}

extension SimpleMakerConfigurationModel {
    init(document: ThumbnailDocument) {
        self = document.makeSimpleConfiguration()
    }

    var document: ThumbnailDocument {
        ThumbnailDocument(configuration: self)
    }
}
