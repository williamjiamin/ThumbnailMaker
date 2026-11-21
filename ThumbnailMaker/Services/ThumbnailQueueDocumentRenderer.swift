//
//  ThumbnailQueueDocumentRenderer.swift
//  ThumbnailMaker
//
//  FEATURE-10: renders any variant's ThumbnailDocument at a full export size
//  through the SAME preview views and the SAME `ThumbnailExporter.render` the
//  editor's single export uses, so a queued file matches a single export.
//  Mirrors ThumbnailProjectPreviewRenderer (left untouched).
//

import SwiftUI
import UIKit

@MainActor
protocol ThumbnailExportJobRendering {
    func render(_ document: ThumbnailDocument, size: ThumbnailExportSize) throws -> UIImage
}

struct ThumbnailQueueDocumentRenderer: ThumbnailExportJobRendering {
    func render(_ document: ThumbnailDocument, size: ThumbnailExportSize) throws -> UIImage {
        var options = ThumbnailExportOptions()
        options.usesCustomSize = true
        options.customSize = size
        let width = CGFloat(size.width)
        let height = CGFloat(size.height)

        switch document.editorMode {
        case .simple:
            return try ThumbnailExporter.render(
                content: PreviewComponentView(
                    simpleMakerConfiguration: .constant(document.makeSimpleConfiguration()),
                    width: width,
                    height: height
                ),
                options: options
            )
        case .premium:
            return try ThumbnailExporter.render(
                content: PremiumPreviewComponentView(
                    premiumMakerConfiguration: document.makePremiumConfiguration(),
                    width: width,
                    height: height
                ),
                options: options
            )
        }
    }
}
