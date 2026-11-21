import SwiftUI
import UIKit
import NaturalLanguage

enum CustomFont: String, CaseIterable, Identifiable {
    // Basic fonts (Available in Simple Maker)
    case goNoto = "GoNotoCurrent-Regular"
    case openSans = "OpenSans-Regular"
    case roboto = "Roboto-Regular"
    case montserrat = "Montserrat-Regular"
    
    // Premium fonts
    case borel = "Borel-Regular"
    case cherryBombOne = "CherryBombOne-Regular"
    case deliciousHandrawn = "DeliciousHandrawn-Regular"
    case eastSeaDokdo = "EastSeaDokdo-Regular"
    case hachiMaruPop = "HachiMaruPop-Regular"
    case hennyPenny = "HennyPenny-Regular"
    case lato = "Lato-Regular"
    case longCang = "LongCang-Regular"
    case lxgwWenKaiMonoTC = "LXGWWenKaiMonoTC-Regular"
    case meowScript = "MeowScript-Regular"
    case mysteryQuest = "MysteryQuest-Regular"
    case oswald = "Oswald-Regular"
    case pixelifySans = "PixelifySans-VariableFont_wght"
    case poppins = "Poppins-Regular"
    case yujiBoku = "YujiBoku-Regular"
    case zhiMangXing = "ZhiMangXing-Regular"
    
    var id: String { rawValue }

    /// The bundled file name (without extension). `rawValue` is also persisted in saved
    /// documents as `selectedFontRawValue`, so these strings must never change.
    var fileName: String { rawValue }

    /// The font's real PostScript name — what `Font.custom(_:size:)` resolves against.
    /// Most match `rawValue`, but a few faces do not, and a mismatch makes SwiftUI fall
    /// back to the system font *silently*. `FontRegistrationTests` guards every case.
    var postScriptName: String {
        switch self {
        case .goNoto: return "GoNotoCurrent-Regular-Regular"
        case .mysteryQuest: return "MysteryQuest"
        case .pixelifySans: return "PixelifySans-Regular"
        default: return rawValue
        }
    }
    
    var displayName: String {
        switch self {
        case .goNoto: return "Go Noto (All Languages)"
        case .borel: return "Borel"
        case .cherryBombOne: return "Cherry Bomb One"
        case .deliciousHandrawn: return "Delicious Handrawn"
        case .eastSeaDokdo: return "East Sea Dokdo"
        case .hachiMaruPop: return "Hachi Maru Pop"
        case .hennyPenny: return "Henny Penny"
        case .lato: return "Lato"
        case .longCang: return "Long Cang"
        case .lxgwWenKaiMonoTC: return "LXGW WenKai Mono TC"
        case .meowScript: return "Meow Script"
        case .montserrat: return "Montserrat"
        case .mysteryQuest: return "Mystery Quest"
        case .openSans: return "Open Sans"
        case .oswald: return "Oswald"
        case .pixelifySans: return "Pixelify Sans"
        case .poppins: return "Poppins"
        case .roboto: return "Roboto"
        case .yujiBoku: return "Yuji Boku"
        case .zhiMangXing: return "Zhi Mang Xing"
        }
    }
    
    var supportDescription: String {
        switch self {
        case .goNoto:
            return "Supports all languages and scripts"
        case .longCang, .lxgwWenKaiMonoTC, .zhiMangXing:
            return "Supports Chinese and Latin characters"
        case .yujiBoku, .hachiMaruPop:
            return "Supports Japanese and Latin characters"
        case .eastSeaDokdo:
            return "Supports Korean and Latin characters"
        default:
            return "Supports English and Latin-based languages"
        }
    }
    
    var supportedScripts: Set<UnicodeScript> {
        switch self {
        case .goNoto:
            return Set(UnicodeScript.allCases)
        case .longCang, .lxgwWenKaiMonoTC, .zhiMangXing:
            return [.latin, .latinExtended, .han]
        case .yujiBoku, .hachiMaruPop:
            return [.latin, .latinExtended, .hiragana, .katakana, .han]
        case .eastSeaDokdo:
            return [.latin, .latinExtended, .hangul]
        default:
            return [.latin, .latinExtended]
        }
    }
    
    var isPremium: Bool {
        switch self {
        case .goNoto, .openSans, .roboto, .montserrat:
            return false
        default:
            return true
        }
    }
    
    static var basicFonts: [CustomFont] {
        allCases.filter { !$0.isPremium }
    }
    
    static var premiumFonts: [CustomFont] {
        allCases.filter { $0.isPremium }
    }
}

enum UnicodeScript: CaseIterable {
    case latin
    case latinExtended
    case han // Chinese characters
    case hiragana
    case katakana
    case hangul
    // Add other scripts as needed
}

class FontManager {
    static let shared = FontManager()
    
    private let languageRecognizer = NLLanguageRecognizer()
    
    /// Fonts that failed to register at launch. Empty in a correctly built bundle;
    /// a non-empty list means the picker would otherwise offer faces that silently
    /// render as the system font.
    private(set) var registrationFailures: [(font: CustomFont, reason: String)] = []

    @discardableResult
    func registerFonts() -> [(font: CustomFont, reason: String)] {
        registrationFailures = []

        for font in CustomFont.allCases {
            guard let fontURL = Bundle.main.url(forResource: font.fileName, withExtension: "ttf") else {
                registrationFailures.append((font, "no bundled file named \(font.fileName).ttf"))
                continue
            }

            // UIAppFonts in Info.plist registers bundled fonts automatically, so this
            // call normally reports "already registered". That is fine — what matters
            // is whether the face resolves by its PostScript name afterwards.
            var error: Unmanaged<CFError>?
            _ = CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error)
            if UIFont(name: font.postScriptName, size: 12) == nil {
                let detail = error?.takeRetainedValue().localizedDescription ?? "no error reported"
                registrationFailures.append((font, "'\(font.postScriptName)' does not resolve (\(detail))"))
            }
        }

        assert(
            registrationFailures.isEmpty,
            "Unregistered fonts: " + registrationFailures.map { "\($0.font.rawValue) (\($0.reason))" }
                .joined(separator: ", ")
        )
        return registrationFailures
    }
    
    func getAttributedText(_ text: String, selectedFont: CustomFont, size: CGFloat, color: Color) -> AttributedString {
        var attributedString = AttributedString(text)

        // Apply default font and color to entire string
        attributedString.font = .custom(selectedFont.postScriptName, size: size)
        attributedString.foregroundColor = color

        // If using GoNoto, return early as it supports all scripts
        if selectedFont == .goNoto {
            return attributedString
        }

        var attributedIndex = attributedString.startIndex
        for character in text {
            guard attributedIndex < attributedString.endIndex else { break }
            let nextIndex = attributedString.characters.index(after: attributedIndex)

            if characterRequiresFallback(character, selectedFont: selectedFont) {
                attributedString[attributedIndex..<nextIndex].font = .custom(CustomFont.goNoto.postScriptName, size: size)
            }

            attributedIndex = nextIndex
        }

        return attributedString
    }

    func getFontForText(_ text: String, selectedFont: CustomFont) -> (font: CustomFont, needsFallback: Bool) {
        guard selectedFont != .goNoto else {
            return (selectedFont, false)
        }

        return needsFallback(for: text, selectedFont: selectedFont)
            ? (.goNoto, true)
            : (selectedFont, false)
    }

    func needsFallback(for text: String, selectedFont: CustomFont) -> Bool {
        guard selectedFont != .goNoto else { return false }

        return text.contains { characterRequiresFallback($0, selectedFont: selectedFont) }
    }

    private func characterRequiresFallback(_ character: Character, selectedFont: CustomFont) -> Bool {
        character.unicodeScalars.contains { scalar in
            let script = getScript(for: scalar)
            return !selectedFont.supportedScripts.contains(script)
        }
    }
    
    func getScript(for scalar: Unicode.Scalar) -> UnicodeScript {
        // This is a simplified version. You'll need to implement proper Unicode range checking
        if scalar.value <= 0x007F { return .latin }
        if scalar.value <= 0x024F { return .latinExtended }
        if (0x3040...0x309F).contains(scalar.value) { return .hiragana }
        if (0x30A0...0x30FF).contains(scalar.value) { return .katakana }
        if (0x4E00...0x9FFF).contains(scalar.value) { return .han }
        if (0xAC00...0xD7AF).contains(scalar.value) { return .hangul }
        return .latin // Default fallback
    }
} 