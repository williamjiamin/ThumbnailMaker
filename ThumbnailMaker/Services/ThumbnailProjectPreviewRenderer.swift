//
//  ThumbnailProjectPreviewRenderer.swift
//  ThumbnailMaker
//
//  FEATURE-01: renders the small library-card preview by reusing the real
//  editor preview views, so a card can never drift from the thumbnail.
//
//  Honest threading note: SwiftUI's ImageRenderer is @MainActor, so the
//  composition step runs on the main actor (at a small size, after the save
//  has already completed). PNG encoding happens off the main actor.
//

import SwiftUI
import UIKit

protocol ThumbnailProjectPreviewRendering {
    @MainActor
    func previewPNGData(for document: ThumbnailDocument, maxPixelWidth: CGFloat) async -> Data?
}

struct ThumbnailProjectPreviewRenderer: ThumbnailProjectPreviewRendering {
    static func previewSize(for document: ThumbnailDocument, maxPixelWidth: CGFloat) -> CGSize {
        let ratio = AspectRatio(rawValue: document.canvas.aspectRatioRawValue) ?? .ratio16_9
        let dimensions = ratio.dimensions
        let scale = maxPixelWidth / max(dimensions.width, dimensions.height)
        return CGSize(
            width: (dimensions.width * scale).rounded(),
            height: (dimensions.height * scale).rounded()
        )
    }

    @MainActor
    func previewPNGData(for document: ThumbnailDocument, maxPixelWidth: CGFloat = 640) async -> Data? {
        let size = Self.previewSize(for: document, maxPixelWidth: maxPixelWidth)
        let content: AnyView
        switch document.editorMode {
        case .simple:
            content = AnyView(
                PreviewComponentView(
                    simpleMakerConfiguration: .constant(document.makeSimpleConfiguration()),
                    width: size.width,
                    height: size.height,
                    isTextInteractive: false
                )
                .frame(width: size.width, height: size.height)
            )
        case .premium:
            content = AnyView(
                PremiumPreviewComponentView(
                    premiumMakerConfiguration: document.makePremiumConfiguration(),
                    width: size.width,
                    height: size.height,
                    isInteractive: false
                )
                .frame(width: size.width, height: size.height)
            )
        }

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else { return nil }

        let image = UIImage(cgImage: cgImage)
        return await Task.detached(priority: .utility) {
            image.pngData()
        }.value
    }
}
