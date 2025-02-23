struct APIConfig {
    // Store API key in a more secure way
    private static let youtubeAPIKey = "AIzaSyDX2XIX-CZ55WwF3r-0GWOuG2ZTxa3Om8Q"
    
    static func getYouTubeAPIKey() -> String {
        // In a production app, you might want to:
        // 1. Encrypt this key
        // 2. Use environment variables
        // 3. Use a key management service
        return youtubeAPIKey
    }
} 