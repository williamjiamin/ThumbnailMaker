//
//  ThumbnailPerformanceTestSupport.swift
//  ThumbnailMakerTests
//
//  APP-09: shared fixtures for the image-work budget tests.
//

import Foundation
import UIKit
@testable import ThumbnailMaker

enum ThumbnailPerformanceTestSupport {
    /// A gradient photo whose PNG is comfortably larger than inline `Data`.
    static func makePhoto(
        width: Int = 256,
        height: Int = 192,
        seed: CGFloat = 0,
        opaque: Bool = true,
        scale: CGFloat = 1
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = opaque
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            for column in stride(from: 0, to: width, by: 4) {
                let hue = (CGFloat(column) / CGFloat(width) + seed).truncatingRemainder(dividingBy: 1)
                UIColor(hue: hue, saturation: 0.8, brightness: 0.9, alpha: opaque ? 1 : 0.5).setFill()
                context.fill(CGRect(x: column, y: 0, width: 4, height: height / 2))
                UIColor(hue: 1 - hue, saturation: 0.6, brightness: 0.7, alpha: 1).setFill()
                context.fill(CGRect(x: column, y: height / 2, width: 4, height: height / 2))
            }
        }
    }

    /// A payload with its own heap buffer and distinct bytes.
    static func payload(bytes: Int, fill: UInt8) -> Data {
        Data((0..<bytes).map { UInt8(truncatingIfNeeded: $0) &+ fill })
    }

    static func document(text: String, imageData: Data?) -> ThumbnailDocument {
        var document = ThumbnailDocument(updatedAt: Date(timeIntervalSince1970: 0), imageData: imageData)
        document.text.value = text
        return document
    }

    /// Runs `body` with a private recorder bound to the current task.
    @MainActor
    static func recording(_ body: () throws -> Void) rethrows -> ThumbnailPerformanceRecorder {
        let recorder = ThumbnailPerformanceRecorder()
        try ThumbnailPerformanceRecorder.$scoped.withValue(recorder) {
            try body()
        }
        return recorder
    }
}
