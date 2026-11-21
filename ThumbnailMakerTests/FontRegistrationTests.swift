//
//  FontRegistrationTests.swift
//  ThumbnailMakerTests
//
//  Guards the bundle against the defect found on 2026-09-09: `CustomFont` offered 20
//  faces while only 5 .ttf files shipped, including none of the four free-tier fonts.
//  `Font.custom(_:size:)` falls back to the system face silently, so nothing surfaced
//  the gap at runtime. These tests fail loudly instead.
//

import Foundation
import SwiftUI
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct FontRegistrationTests {
    /// Every declared font must actually ship in the bundle.
    @Test(arguments: CustomFont.allCases)
    func everyDeclaredFontHasABundledFile(font: CustomFont) throws {
        let url = Bundle.main.url(forResource: font.fileName, withExtension: "ttf")
        #expect(url != nil, "\(font.rawValue): no bundled \(font.fileName).ttf")
        let size = try #require(try url.map { try Data(contentsOf: $0).count })
        #expect(size > 1024, "\(font.rawValue): bundled file is implausibly small (\(size) bytes)")
    }

    /// `postScriptName` must match the font's real PostScript name, or SwiftUI silently
    /// renders the system font. Montserrat is the cautionary case: its variable build
    /// defaults to `Montserrat-Thin`, so a static Regular is bundled instead.
    @Test(arguments: CustomFont.allCases)
    func postScriptNameResolvesToARealFont(font: CustomFont) throws {
        FontManager.shared.registerFonts()
        let uiFont = UIFont(name: font.postScriptName, size: 17)
        #expect(uiFont != nil, "\(font.rawValue): PostScript name '\(font.postScriptName)' does not resolve")
        if let uiFont {
            #expect(uiFont.fontName.caseInsensitiveCompare(font.postScriptName) == .orderedSame,
                    "\(font.rawValue): resolved to '\(uiFont.fontName)' instead of '\(font.postScriptName)'")
        }
    }

    /// Registration must be clean and idempotent.
    @Test func registrationReportsNoFailures() {
        FontManager.shared.registerFonts()
        let failures = FontManager.shared.registerFonts()
        let summary = failures.map { "\($0.font.rawValue) — \($0.reason)" }.joined(separator: "; ")
        #expect(failures.isEmpty, "unregistered: \(summary)")
    }

    /// The free tier must actually have usable fonts — the original defect made every
    /// free font unbundled, so non-paying users had no working font at all.
    @Test func freeTierFontsAreBundledAndResolvable() throws {
        #expect(!CustomFont.basicFonts.isEmpty)
        FontManager.shared.registerFonts()
        for font in CustomFont.basicFonts {
            #expect(Bundle.main.url(forResource: font.fileName, withExtension: "ttf") != nil,
                    "free font \(font.rawValue) is not bundled")
            #expect(UIFont(name: font.postScriptName, size: 17) != nil,
                    "free font \(font.rawValue) does not resolve")
        }
    }

    /// `.goNoto` is the universal fallback used by `getAttributedText` for any character
    /// the selected face cannot render. If it is missing, all CJK fallback breaks.
    @Test func universalFallbackFontIsAvailable() throws {
        FontManager.shared.registerFonts()
        #expect(Bundle.main.url(forResource: CustomFont.goNoto.fileName, withExtension: "ttf") != nil)
        #expect(UIFont(name: CustomFont.goNoto.postScriptName, size: 17) != nil)
        #expect(CustomFont.goNoto.supportedScripts == Set(UnicodeScript.allCases))
    }

    /// Info.plist's UIAppFonts must list exactly the files the enum expects.
    @Test func infoPlistDeclaresEveryDeclaredFont() throws {
        let declared = Set((Bundle.main.object(forInfoDictionaryKey: "UIAppFonts") as? [String]) ?? [])
        #expect(!declared.isEmpty, "UIAppFonts missing from Info.plist")
        for font in CustomFont.allCases {
            #expect(declared.contains("\(font.fileName).ttf"),
                    "UIAppFonts is missing \(font.fileName).ttf")
        }
    }
}
