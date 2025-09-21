//
//  ThumbnailMakerTests.swift
//  ThumbnailMakerTests
//
//  Created by william on 2024/11/22.
//

import SwiftUI
import Testing
@testable import ThumbnailMaker

struct ThumbnailMakerTests {

    @Test func appliesFallbackFontToEveryUnsupportedCharacter() async throws {
        // Roboto does not support Han characters, so each one should fall back to Go Noto.
        let text = "測試測試"
        let attributedText = FontManager.shared.getAttributedText(
            text,
            selectedFont: .roboto,
            size: 24,
            color: .white
        )

        let expectedFallbackCount = text.reduce(into: 0) { partialResult, character in
            if FontManager.shared.needsFallback(
                for: String(character),
                selectedFont: .roboto
            ) {
                partialResult += 1
            }
        }

        var appliedFallbackCount = 0
        attributedText.runs.forEach { run in
            guard let font = run.font else { return }
            if String(describing: font).contains(CustomFont.goNoto.rawValue) {
                appliedFallbackCount += attributedText[run.range].characters.count
            }
        }

        #expect(appliedFallbackCount == expectedFallbackCount, "Each unsupported character should use the fallback font.")
    }
}
