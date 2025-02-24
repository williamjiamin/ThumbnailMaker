import SwiftUI
import NaturalLanguage

enum CustomFont: String, CaseIterable, Identifiable {
    // Universal font with full language support
    case goNoto = "GoNotoCurrent-Regular"
    
    // Style fonts (for Latin only)
    case roboto = "Roboto-Regular"
    case openSans = "OpenSans-Regular"
    case poppins = "Poppins-Regular"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .goNoto: return "Go Noto (All Languages)"
        case .roboto: return "Roboto (Latin Only)"
        case .openSans: return "Open Sans (Latin Only)"
        case .poppins: return "Poppins (Latin Only)"
        }
    }
    
    var supportDescription: String {
        switch self {
        case .goNoto:
            return "Supports all languages and scripts"
        case .roboto, .openSans, .poppins:
            return "Supports English and Latin-based languages only"
        }
    }
    
    var supportedLanguages: Set<NLLanguage> {
        switch self {
        case .goNoto:
            return []  // GoNoto supports all languages
        case .roboto, .openSans, .poppins:
            return [.english] // Latin only
        }
    }
    
    static var styleOnlyFonts: [CustomFont] {
        [.roboto, .openSans, .poppins]
    }
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
    
    func getFontForText(_ text: String, selectedFont: CustomFont) -> (font: CustomFont, needsFallback: Bool) {
        // If it's GoNoto, use it directly as it supports all languages
        if selectedFont == .goNoto {
            return (selectedFont, false)
        }
        
        // Check if all characters are within Latin range
        // This includes basic Latin, numbers, punctuation, and common symbols
        let latinPattern = "^[\\p{Latin}\\p{N}\\p{P}\\s]*$"
        if let regex = try? NSRegularExpression(pattern: latinPattern),
           let _ = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            return (selectedFont, false)
        }
        
        // If text contains any non-Latin characters, use language detection as backup
        languageRecognizer.processString(text)
        if let dominantLanguage = languageRecognizer.dominantLanguage,
           dominantLanguage == .english {
            return (selectedFont, false)
        }
        
        // Fallback to GoNoto for any other case
        return (.goNoto, true)
    }
} 