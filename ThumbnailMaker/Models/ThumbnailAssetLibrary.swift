//
//  ThumbnailAssetLibrary.swift
//  ThumbnailMaker
//
//  EDITOR (1.1.0 parity): the data behind the unified asset "Library" sheet.
//  Pure and view-free so it can be unit tested: built-in emoji stickers,
//  images already used in the open project, and brand-kit logos.
//

import CryptoKit
import Foundation
import UIKit

/// How an asset lands on the canvas.
enum ThumbnailAssetInsertKind: String, Equatable {
    case image
    case sticker
}

enum ThumbnailAssetSource: String, Equatable {
    case sticker
    case recent
    case brand
}

struct ThumbnailAssetLibraryItem: Identifiable, Equatable {
    var id: String
    var title: String
    var source: ThumbnailAssetSource
    var insertKind: ThumbnailAssetInsertKind
    /// Encoded image bytes (PNG/JPEG) ready for `addImageLayer`/`addStickerLayer`.
    var imageData: Data

    var accessibilityIdentifier: String { "assetLibraryItem_\(id)" }
}

enum ThumbnailAssetLibrary {
    /// Built-in reaction stickers that suit thumbnails.
    static let stickerEmoji: [(emoji: String, name: String)] = [
        ("🔥", "Fire"),
        ("😱", "Shocked"),
        ("🤯", "Mind Blown"),
        ("😂", "Laughing"),
        ("👉", "Pointing"),
        ("👀", "Eyes"),
        ("💯", "Hundred"),
        ("⭐️", "Star"),
        ("❤️", "Heart"),
        ("✅", "Check"),
        ("❌", "Cross"),
        ("⚠️", "Warning"),
        ("💰", "Money"),
        ("🏆", "Trophy"),
        ("🎮", "Game"),
        ("🚀", "Rocket")
    ]

    static let stickerRenderSide: CGFloat = 240

    /// Emoji rendered to transparent PNGs, cached for the process.
    @MainActor
    static var builtInStickers: [ThumbnailAssetLibraryItem] {
        if let cachedStickers { return cachedStickers }
        let items = stickerEmoji.enumerated().compactMap { index, entry -> ThumbnailAssetLibraryItem? in
            guard let data = renderEmoji(entry.emoji, side: stickerRenderSide) else { return nil }
            return ThumbnailAssetLibraryItem(
                id: "sticker\(index)",
                title: "\(entry.name) sticker",
                source: .sticker,
                insertKind: .sticker,
                imageData: data
            )
        }
        cachedStickers = items
        return items
    }

    @MainActor private static var cachedStickers: [ThumbnailAssetLibraryItem]?

    static func renderEmoji(_ emoji: String, side: CGFloat) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            let font = UIFont.systemFont(ofSize: side * 0.8)
            let text = emoji as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(x: (side - textSize.width) / 2, y: (side - textSize.height) / 2),
                withAttributes: attributes
            )
        }
        return image.pngData()
    }

    /// Distinct images already placed in this project (image and sticker
    /// layers, newest first), so they can be reused in one tap.
    static func recentAssets(
        in layers: [ThumbnailDocumentLayer],
        limit: Int = 12
    ) -> [ThumbnailAssetLibraryItem] {
        var seen = Set<String>()
        var items: [ThumbnailAssetLibraryItem] = []
        for layer in layers.sorted(by: { $0.zIndex > $1.zIndex }) {
            guard case .image(let content) = layer.content, !content.imageData.isEmpty else { continue }
            let digest = fingerprint(content.imageData)
            guard seen.insert(digest).inserted else { continue }
            items.append(
                ThumbnailAssetLibraryItem(
                    id: "recent_\(digest.prefix(12))",
                    title: layer.name.isEmpty ? (content.isSticker ? "Sticker" : "Image") : layer.name,
                    source: .recent,
                    insertKind: content.isSticker ? .sticker : .image,
                    imageData: content.imageData
                )
            )
            if items.count >= limit { break }
        }
        return items
    }

    /// Logos from every saved brand kit (active kit first), inserted as image
    /// layers.
    static func brandAssets(in library: BrandKitLibrary) -> [ThumbnailAssetLibraryItem] {
        let ordered = library.kits.sorted { lhs, rhs in
            (lhs.id == library.activeKitID ? 0 : 1) < (rhs.id == library.activeKitID ? 0 : 1)
        }
        var seen = Set<String>()
        return ordered.compactMap { kit in
            guard let data = kit.logoImageData, !data.isEmpty else { return nil }
            let digest = fingerprint(data)
            guard seen.insert(digest).inserted else { return nil }
            return ThumbnailAssetLibraryItem(
                id: "brand_\(digest.prefix(12))",
                title: "\(kit.name) logo",
                source: .brand,
                insertKind: .image,
                imageData: data
            )
        }
    }

    static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension ThumbnailQuickActionEditing {
    /// Inserts a library asset as a new layer (one undo step) and returns
    /// the new layer to select.
    @discardableResult
    func insertLibraryAsset(_ item: ThumbnailAssetLibraryItem) -> ThumbnailLayerSelection? {
        guard UIImage(data: item.imageData) != nil else { return nil }
        switch item.insertKind {
        case .image: return addImageLayer(imageData: item.imageData)
        case .sticker: return addStickerLayer(imageData: item.imageData)
        }
    }
}
