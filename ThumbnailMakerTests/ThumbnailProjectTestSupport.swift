//
//  ThumbnailProjectTestSupport.swift
//  ThumbnailMakerTests
//
//  FEATURE-01 shared helpers.
//

import Foundation
import SwiftUI
import UIKit
@testable import ThumbnailMaker

struct StubProjectPreviewRenderer: ThumbnailProjectPreviewRendering {
    var bytes: Data? = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02, 0x03])

    @MainActor
    func previewPNGData(for document: ThumbnailDocument, maxPixelWidth: CGFloat) async -> Data? {
        bytes
    }
}

enum ProjectTestSupport {
    static func makeTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FEATURE01-\(UUID().uuidString)", isDirectory: true)
    }

    static func cleanUp(_ directory: URL) {
        // Restore permissions everywhere under the directory before removing it.
        if let enumerator = FileManager.default.enumerator(atPath: directory.path) {
            for case let relative as String in enumerator {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o700],
                    ofItemAtPath: directory.appendingPathComponent(relative).path
                )
            }
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try? FileManager.default.removeItem(at: directory)
    }

    @MainActor
    static func makeLibrary(
        root: URL,
        renderer: ThumbnailProjectPreviewRendering = StubProjectPreviewRenderer()
    ) -> ThumbnailProjectLibrary {
        ThumbnailProjectLibrary(
            store: ThumbnailProjectStore(rootDirectory: root.appendingPathComponent("Projects", isDirectory: true)),
            previewRenderer: renderer,
            previewDelay: 0
        )
    }

    static func makeImage(
        size: CGSize = CGSize(width: 24, height: 16),
        color: UIColor = .systemTeal
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    static func simpleDocument(
        text: String,
        ratio: AspectRatio = .ratio16_9,
        image: UIImage? = nil
    ) -> ThumbnailDocument {
        var configuration = SimpleMakerConfigurationModel()
        configuration.overlayText = text
        configuration.selectedRatio = ratio
        configuration.selectedImage = image
        return configuration.document
    }

    static func premiumDocument(text: String) -> ThumbnailDocument {
        var configuration = PremiumMakerConfigurationModel()
        configuration.overlayText = text
        return configuration.document
    }
}
