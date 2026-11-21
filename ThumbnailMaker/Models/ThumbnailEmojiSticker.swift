//
//  ThumbnailEmojiSticker.swift
//  ThumbnailMaker
//
//  DONOR (Simple Meme Maker App/EditorBars.swift StickerPicker): reaction
//  emoji as stickers. An emoji becomes an ordinary sticker IMAGE layer — a
//  transparent PNG of the glyph — so it moves, scales, rotates, undoes,
//  groups, cuts out and exports like any other sticker, and no new layer
//  kind or document field is needed. Emoji are drawn by the system emoji
//  font at render time; no artwork is bundled.
//

import Foundation
import UIKit

enum ThumbnailEmojiSticker {
    /// The reaction set, in the donor's order (4 rows of 8).
    static let favourites: [String] = [
        "😂", "💀", "😭", "🔥", "👀", "🤡", "🗿", "😎",
        "🙃", "😬", "🤯", "😤", "🥲", "🫠", "🤔", "😱",
        "👍", "👎", "👏", "🙏", "💯", "✅", "❌", "⚠️",
        "❤️", "💔", "⭐️", "💥", "💩", "🎉", "🍿", "🚨",
    ]

    /// A sticker is one or a few glyphs; a paragraph pasted into the field is
    /// a caption, and text layers are the tool for that.
    static let maximumCharacters = 4
    /// Longest side of the rendered PNG, in pixels. Large enough that a
    /// sticker scaled to the maximum layer size stays crisp at 4K export.
    static let renderedPixelSize: CGFloat = 512

    /// Trims whitespace and caps the length. nil when nothing usable remains.
    static func sanitized(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let capped = String(trimmed.prefix(maximumCharacters))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return capped.isEmpty ? nil : capped
    }

    /// Canvas size for `text` whose longest side is `pixelSize`.
    static func imageSize(for text: String, pixelSize: CGFloat = renderedPixelSize) -> CGSize {
        let measured = attributed(text, fontSize: pixelSize).size()
        guard measured.width > 0, measured.height > 0 else {
            return CGSize(width: pixelSize, height: pixelSize)
        }
        let scale = pixelSize / max(measured.width, measured.height)
        return CGSize(
            width: max(1, (measured.width * scale).rounded(.up)),
            height: max(1, (measured.height * scale).rounded(.up))
        )
    }

    /// A transparent PNG of the glyphs, longest side `pixelSize` pixels.
    static func pngData(for text: String, pixelSize: CGFloat = renderedPixelSize) -> Data? {
        guard let text = sanitized(text), pixelSize > 0, pixelSize.isFinite else { return nil }
        let natural = attributed(text, fontSize: pixelSize).size()
        guard natural.width > 0, natural.height > 0 else { return nil }
        let scale = pixelSize / max(natural.width, natural.height)
        let fontSize = pixelSize * scale
        let size = imageSize(for: text, pixelSize: pixelSize)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            let string = attributed(text, fontSize: fontSize)
            let drawn = string.size()
            let origin = CGPoint(
                x: (size.width - drawn.width) / 2,
                y: (size.height - drawn.height) / 2
            )
            string.draw(at: origin)
        }
        return image.pngData()
    }

    /// The layer name shown in the layer strip.
    static func layerName(for text: String) -> String {
        "Sticker \(text)"
    }

    private static func attributed(_ text: String, fontSize: CGFloat) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: fontSize),
                // Plain text fallbacks (e.g. "OK") draw dark on the sticker.
                .foregroundColor: UIColor.black,
            ]
        )
    }
}
