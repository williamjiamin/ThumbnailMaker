//
//  ImageImportError.swift
//  ThumbnailMaker
//
//  Describes a single failure point in the image-import pipeline so the
//  editor can publish actionable messages and recover without losing the
//  current document.
//

import Foundation

enum ImageImportError: Equatable {
    case transferFailed(String)
    case unsupportedFormat
    case decodeFailed
    case cancelled
    case unknown(String)

    var message: String {
        switch self {
        case .transferFailed(let detail):
            return "Couldn't import the image (\(detail))."
        case .unsupportedFormat:
            return "This image format is not supported."
        case .decodeFailed:
            return "The image file could not be decoded."
        case .cancelled:
            return "Image import was cancelled."
        case .unknown(let detail):
            return "Image import failed (\(detail))."
        }
    }
}
