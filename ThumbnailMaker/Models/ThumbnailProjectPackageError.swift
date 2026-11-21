//
//  ThumbnailProjectPackageError.swift
//  ThumbnailMaker
//
//  FEATURE-06: every way a .thumbproj export or import can fail, with copy that
//  says what happened and that nothing was changed.
//

import Foundation

enum ThumbnailProjectPackageError: LocalizedError, Equatable {
    case notAPackage
    case unreadable(String)
    case manifestMissing
    case manifestTooLarge(byteCount: Int, limit: Int)
    case manifestUnreadable(String)
    case unsupportedFormatIdentifier(String)
    case unsupportedFutureVersion(found: Int, supported: Int)
    case unsupportedLegacyVersion(found: Int)
    case documentMissing
    case documentTooLarge(byteCount: Int, limit: Int)
    case documentUnreadable(String)
    case assetCountExceeded(found: Int, limit: Int)
    case assetPathRejected(String)
    case assetMissing(id: String)
    case assetSizeMismatch(id: String)
    case assetTooLarge(id: String, byteCount: Int, limit: Int)
    case packageTooLarge(byteCount: Int, limit: Int)
    case assetChecksumMismatch(id: String)
    case assetUndecodable(id: String)
    case bindingUnresolved(slot: String)
    case variantInvalid(String)
    case projectUnavailable
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAPackage:
            return "That file isn't a Simple Thumbnail project."
        case .unreadable(let reason):
            return "The project file couldn't be read (\(reason))."
        case .manifestMissing:
            return "This project is missing its manifest, so it can't be opened."
        case .manifestTooLarge(let byteCount, let limit):
            return "This project's manifest is too large (\(Self.bytes(byteCount)), limit \(Self.bytes(limit)))."
        case .manifestUnreadable:
            return "This project's manifest is damaged, so it can't be opened."
        case .unsupportedFormatIdentifier(let identifier):
            return "This file uses an unknown project format (\(identifier))."
        case .unsupportedFutureVersion(let found, let supported):
            return "This project was made with a newer version of Simple Thumbnail (format \(found); this app reads up to \(supported))."
        case .unsupportedLegacyVersion(let found):
            return "This project uses an unsupported format version (\(found))."
        case .documentMissing:
            return "This project is missing its design document."
        case .documentTooLarge(let byteCount, let limit):
            return "This project's design document is too large (\(Self.bytes(byteCount)), limit \(Self.bytes(limit)))."
        case .documentUnreadable:
            return "This project's design document is damaged, so it can't be opened."
        case .assetCountExceeded(let found, let limit):
            return "This project has too many images (\(found), limit \(limit))."
        case .assetPathRejected(let path):
            return "This project refers to a file outside its package (\(path)), so it was not opened."
        case .assetMissing:
            return "An image in this project is missing."
        case .assetSizeMismatch:
            return "An image in this project is incomplete."
        case .assetTooLarge(_, let byteCount, let limit):
            return "An image in this project is too large (\(Self.bytes(byteCount)), limit \(Self.bytes(limit)))."
        case .packageTooLarge(let byteCount, let limit):
            return "This project is too large (\(Self.bytes(byteCount)), limit \(Self.bytes(limit)))."
        case .assetChecksumMismatch:
            return "An image in this project is damaged."
        case .assetUndecodable:
            return "An image in this project can't be decoded."
        case .bindingUnresolved(let slot):
            return "This project refers to an image it doesn't contain (\(slot))."
        case .variantInvalid(let reason):
            return "This project's variants are damaged (\(reason))."
        case .projectUnavailable:
            return "That project isn't available to export."
        case .writeFailed(let reason):
            return "The project couldn't be saved (\(reason))."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unsupportedFutureVersion:
            return "Update Simple Thumbnail to open it. The file has not been changed."
        case .writeFailed, .projectUnavailable:
            return "Your current project is unchanged. Try again."
        case .packageTooLarge, .assetTooLarge, .assetCountExceeded:
            return "Remove some images and export the project again."
        default:
            return "Nothing was imported and your current project is unchanged. Export the project again from the original device."
        }
    }

    /// Single line for banners: description plus the recovery hint.
    var userMessage: String {
        [errorDescription, recoverySuggestion].compactMap { $0 }.joined(separator: " ")
    }

    private static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}
