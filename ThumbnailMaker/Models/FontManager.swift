import SwiftUI
import NaturalLanguage

enum CustomFont: String, CaseIterable, Identifiable {
    // Universal font with full language support
    case goNoto = "GoNotoCurrent-Regular"
    
    // Style fonts with specific language support
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
    case montserrat = "Montserrat-Regular"
    case mysteryQuest = "MysteryQuest-Regular"
    case openSans = "OpenSans-Regular"
    case oswald = "Oswald-Regular"
    case pixelifySans = "PixelifySans-VariableFont_wght"
    case poppins = "Poppins-Regular"
    case roboto = "Roboto-Regular"
    case yujiBoku = "YujiBoku-Regular"
    case zhiMangXing = "ZhiMangXing-Regular"
    
    var id: String { rawValue }
    
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
    
    static var styleOnlyFonts: [CustomFont] {
        Array(allCases.dropFirst()) // All fonts except goNoto
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
    
    func registerFonts() {
        CustomFont.allCases.forEach { font in
            guard let fontURL = Bundle.main.url(forResource: font.rawValue, withExtension: "ttf") else {
                print("Failed to find font: \(font.rawValue)")
                return
            }
            
            var error: Unmanaged<CFError>?
            guard CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error) else {
                print("Failed to register font: \(error.debugDescription)")
                return
            }
        }
    }
    
    func getAttributedText(_ text: String, selectedFont: CustomFont, size: CGFloat, color: Color) -> AttributedString {
        var attributedString = AttributedString(text)
        
        // Apply default font and color to entire string
        attributedString.font = .custom(selectedFont.rawValue, size: size)
        attributedString.foregroundColor = color
        
        // If using GoNoto, return early as it supports all scripts
        if selectedFont == .goNoto {
            return attributedString
        }
        
        // Check each character and apply GoNoto font for unsupported scripts
        text.unicodeScalars.enumerated().forEach { index, scalar in
            let script = getScript(for: scalar)
            if !selectedFont.supportedScripts.contains(script) {
                let range = attributedString.range(of: String(scalar))
                if let range = range {
                    attributedString[range].font = .custom(CustomFont.goNoto.rawValue, size: size)
                }
            }
        }
        
        return attributedString
    }
    
    func getFontForText(_ text: String, selectedFont: CustomFont) -> (font: CustomFont, needsFallback: Bool) {
        // If it's GoNoto, use it directly as it supports all languages
        if selectedFont == .goNoto {
            return (selectedFont, false)
        }
        
        // Check if all characters in the text are supported by the selected font
        let hasUnsupportedCharacters = text.unicodeScalars.contains { scalar in
            let script = getScript(for: scalar)
            return !selectedFont.supportedScripts.contains(script)
        }
        
        return hasUnsupportedCharacters ? (.goNoto, true) : (selectedFont, false)
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