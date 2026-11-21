//
//  ThumbnailExportModel.swift
//  ThumbnailMaker
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ThumbnailExportSize: Equatable, Hashable {
    var width: Int
    var height: Int

    var cgSize: CGSize {
        CGSize(width: width, height: height)
    }

    var displayText: String {
        "\(width) x \(height)"
    }
}

enum ThumbnailExportFormat: String, CaseIterable, Identifiable {
    case png
    case jpeg
    case webP

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .png:
            return "PNG"
        case .jpeg:
            return "JPEG"
        case .webP:
            return "WebP"
        }
    }

    var fileExtension: String {
        switch self {
        case .png:
            return "png"
        case .jpeg:
            return "jpg"
        case .webP:
            return "webp"
        }
    }

    var uniformTypeIdentifier: String {
        switch self {
        case .png:
            return UTType.png.identifier
        case .jpeg:
            return UTType.jpeg.identifier
        case .webP:
            return UTType.webP.identifier
        }
    }

    var contentType: UTType {
        UTType(uniformTypeIdentifier) ?? .data
    }

    var supportsCompressionQuality: Bool {
        self != .png
    }

    var canEncodeOnCurrentPlatform: Bool {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return identifiers.contains(uniformTypeIdentifier)
    }
}

struct ThumbnailExportPreset: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let platform: String
    let aspectRatio: AspectRatio
    let size: ThumbnailExportSize
    let safeZone: ThumbnailSafeZone?

    init(
        id: String,
        name: String,
        platform: String,
        aspectRatio: AspectRatio,
        size: ThumbnailExportSize,
        safeZone: ThumbnailSafeZone? = nil
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.aspectRatio = aspectRatio
        self.size = size
        self.safeZone = safeZone
    }

    var summary: String {
        "\(platform) · \(size.displayText)"
    }
}

struct ThumbnailSafeZone: Equatable, Hashable {
    let id: String
    let name: String
    let guidance: String
    let topInset: CGFloat
    let leadingInset: CGFloat
    let bottomInset: CGFloat
    let trailingInset: CGFloat

    func contentRect(in size: CGSize) -> CGRect {
        let x = size.width * leadingInset
        let y = size.height * topInset
        let width = size.width * max(0, 1 - leadingInset - trailingInset)
        let height = size.height * max(0, 1 - topInset - bottomInset)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    var hasValidNormalizedInsets: Bool {
        topInset >= 0
            && leadingInset >= 0
            && bottomInset >= 0
            && trailingInset >= 0
            && topInset + bottomInset < 1
            && leadingInset + trailingInset < 1
    }
}

struct ThumbnailExportUploadLimit: Equatable, Hashable {
    let label: String
    let byteLimit: Int

    var displayLimit: String {
        ThumbnailExportFileSize(byteCount: byteLimit).formatted
    }
}

extension ThumbnailExportPreset {
    static let youTubeThumbnail = ThumbnailExportPreset(
        id: "youtube-thumbnail",
        name: "YouTube Thumbnail",
        platform: "YouTube",
        aspectRatio: .ratio16_9,
        size: ThumbnailExportSize(width: 3840, height: 2160),
        safeZone: ThumbnailSafeZone(
            id: "youtube-watch-safe-zone",
            name: "YouTube watch safe zone",
            guidance: "Keep key text and faces inside the guide for watch-page crops and duration badges.",
            topInset: 0.06,
            leadingInset: 0.06,
            bottomInset: 0.14,
            trailingInset: 0.14
        )
    )

    static let shortFormCover = ThumbnailExportPreset(
        id: "short-form-cover",
        name: "Shorts / TikTok / Reels",
        platform: "Vertical video",
        aspectRatio: .ratio9_16,
        size: ThumbnailExportSize(width: 1080, height: 1920),
        safeZone: ThumbnailSafeZone(
            id: "short-form-ui-safe-zone",
            name: "Short-form UI safe zone",
            guidance: "Keep title, face, and logo away from captions, progress bars, and right-side action rails.",
            topInset: 0.12,
            leadingInset: 0.08,
            bottomInset: 0.24,
            trailingInset: 0.20
        )
    )

    static let instagramSquare = ThumbnailExportPreset(
        id: "instagram-square",
        name: "Instagram Square",
        platform: "Instagram",
        aspectRatio: .ratio1_1,
        size: ThumbnailExportSize(width: 1080, height: 1080),
        safeZone: ThumbnailSafeZone(
            id: "instagram-square-crop-safe-zone",
            name: "Instagram square crop safe zone",
            guidance: "Keep important details away from feed and profile crop edges.",
            topInset: 0.08,
            leadingInset: 0.08,
            bottomInset: 0.08,
            trailingInset: 0.08
        )
    )

    static let instagramReelsCover = ThumbnailExportPreset(
        id: "instagram-reels-cover",
        name: "Instagram Reels Cover",
        platform: "Instagram",
        aspectRatio: .ratioReelsCover,
        size: ThumbnailExportSize(width: 1080, height: 1682),
        safeZone: ThumbnailSafeZone(
            id: "instagram-reels-cover-safe-zone",
            name: "Instagram Reels cover safe zone",
            guidance: "Matches Instagram's 420 x 654 cover ratio at higher export density. Keep faces, titles, and logos centered for feed and profile crops.",
            topInset: 0.10,
            leadingInset: 0.08,
            bottomInset: 0.14,
            trailingInset: 0.08
        )
    )

    static let podcastCover = ThumbnailExportPreset(
        id: "podcast-cover",
        name: "Podcast / Cover Art",
        platform: "Podcast",
        aspectRatio: .ratio1_1,
        size: ThumbnailExportSize(width: 3000, height: 3000),
        safeZone: ThumbnailSafeZone(
            id: "podcast-art-safe-zone",
            name: "Podcast art safe zone",
            guidance: "Keep title and host marks clear of rounded corners and app-specific crops.",
            topInset: 0.08,
            leadingInset: 0.08,
            bottomInset: 0.08,
            trailingInset: 0.08
        )
    )

    static let videoCover = ThumbnailExportPreset(
        id: "video-cover",
        name: "Video Cover",
        platform: "General video",
        aspectRatio: .ratio4_3,
        size: ThumbnailExportSize(width: 1600, height: 1200),
        safeZone: ThumbnailSafeZone(
            id: "general-video-cover-safe-zone",
            name: "Video cover safe zone",
            guidance: "Keep primary text and subjects inside the guide for previews that crop or round edges.",
            topInset: 0.07,
            leadingInset: 0.07,
            bottomInset: 0.10,
            trailingInset: 0.07
        )
    )

    static let portraitCover = ThumbnailExportPreset(
        id: "portrait-cover",
        name: "Portrait Cover",
        platform: "Social portrait",
        aspectRatio: .ratio3_4,
        size: ThumbnailExportSize(width: 1200, height: 1600),
        safeZone: ThumbnailSafeZone(
            id: "portrait-cover-safe-zone",
            name: "Portrait cover safe zone",
            guidance: "Keep title and faces away from top and bottom UI chrome.",
            topInset: 0.10,
            leadingInset: 0.08,
            bottomInset: 0.16,
            trailingInset: 0.08
        )
    )

    static let all: [ThumbnailExportPreset] = [
        .youTubeThumbnail,
        .shortFormCover,
        .instagramSquare,
        .instagramReelsCover,
        .podcastCover,
        .videoCover,
        .portraitCover
    ]

    var uploadLimits: [ThumbnailExportUploadLimit] {
        if self == .youTubeThumbnail {
            return [
                ThumbnailExportUploadLimit(
                    label: "YouTube mobile video thumbnail limit",
                    byteLimit: 2_000_000
                ),
                ThumbnailExportUploadLimit(
                    label: "YouTube desktop thumbnail limit",
                    byteLimit: 50_000_000
                )
            ]
        } else if self == .podcastCover {
            return [
                ThumbnailExportUploadLimit(
                    label: "YouTube mobile podcast thumbnail limit",
                    byteLimit: 10_000_000
                ),
                ThumbnailExportUploadLimit(
                    label: "YouTube desktop podcast thumbnail limit",
                    byteLimit: 50_000_000
                )
            ]
        } else {
            return []
        }
    }
}

struct ThumbnailExportOptions: Equatable {
    var preset: ThumbnailExportPreset = .youTubeThumbnail
    var format: ThumbnailExportFormat = .png
    var compressionQuality: Double = 0.9
    var usesCustomSize = false
    var customSize = ThumbnailExportSize(width: 1920, height: 1080)

    var outputSize: ThumbnailExportSize {
        usesCustomSize ? customSize : preset.size
    }

    var activeSafeZone: ThumbnailSafeZone? {
        usesCustomSize ? nil : preset.safeZone
    }

    mutating func applyPreset(_ preset: ThumbnailExportPreset) {
        self.preset = preset
        usesCustomSize = false
        customSize = preset.size
    }

    func validationMessages(forByteCount byteCount: Int) -> [ThumbnailExportValidationMessage] {
        var messages: [ThumbnailExportValidationMessage] = []

        if preset == .youTubeThumbnail && format == .webP {
            messages.append(
                ThumbnailExportValidationMessage(
                    severity: .warning,
                    message: "YouTube custom thumbnail upload supports JPG, GIF, and PNG. Use JPEG or PNG for direct YouTube upload."
                )
            )
        }

        let exceededLimits = preset.uploadLimits.filter { byteCount > $0.byteLimit }
        for limit in exceededLimits {
            messages.append(
                ThumbnailExportValidationMessage(
                    severity: .warning,
                    message: "File is over the \(limit.label) of \(limit.displayLimit)."
                )
            )
        }

        if messages.isEmpty && !preset.uploadLimits.isEmpty {
            messages.append(
                ThumbnailExportValidationMessage(
                    severity: .success,
                    message: "File size is within known upload limits for this preset."
                )
            )
        }

        return messages
    }
}

struct ThumbnailExportFileSize: Equatable {
    let byteCount: Int

    var formatted: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(byteCount),
            countStyle: .file
        )
    }
}

enum ThumbnailExportValidationSeverity: String, Equatable {
    case success
    case warning
}

struct ThumbnailExportValidationMessage: Identifiable, Equatable {
    let severity: ThumbnailExportValidationSeverity
    let message: String

    var id: String {
        "\(severity.rawValue)-\(message)"
    }
}

struct ThumbnailPreparedFileExport: Identifiable, Equatable {
    let id = UUID()
    let data: Data
    let fileName: String
    let contentType: UTType
    let options: ThumbnailExportOptions

    var fileSize: ThumbnailExportFileSize {
        ThumbnailExportFileSize(byteCount: data.count)
    }

    var validationMessages: [ThumbnailExportValidationMessage] {
        options.validationMessages(forByteCount: data.count)
    }
}

struct ThumbnailExportReport: Equatable {
    let byteCount: Int
    let options: ThumbnailExportOptions

    var fileSize: ThumbnailExportFileSize {
        ThumbnailExportFileSize(byteCount: byteCount)
    }

    var validationMessages: [ThumbnailExportValidationMessage] {
        options.validationMessages(forByteCount: byteCount)
    }
}

struct ThumbnailSmallPreviewSize: Identifiable, Equatable {
    let id: String
    let name: String
    let width: CGFloat

    func size(for aspectRatio: AspectRatio) -> CGSize {
        CGSize(width: width, height: width / aspectRatio.value)
    }
}

extension ThumbnailSmallPreviewSize {
    static let search = ThumbnailSmallPreviewSize(
        id: "search",
        name: "Search",
        width: 160
    )

    static let mobile = ThumbnailSmallPreviewSize(
        id: "mobile",
        name: "Mobile",
        width: 96
    )

    static let all: [ThumbnailSmallPreviewSize] = [.search, .mobile]
}
