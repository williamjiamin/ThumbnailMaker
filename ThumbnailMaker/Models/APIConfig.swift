import Foundation

struct APIConfig {
    private enum Constants {
        static let secretsFileName = "Secrets"
        static let secretsFileExtension = "plist"
        static let youtubeAPIKeyField = "YOUTUBE_API_KEY"
    }

    private static var cachedYouTubeKey: String?

    static func getYouTubeAPIKey() -> String {
        if let cachedYouTubeKey {
            return cachedYouTubeKey
        }

        if let environmentValue = ProcessInfo.processInfo
            .environment[Constants.youtubeAPIKeyField],
           !environmentValue.isEmpty {
            cachedYouTubeKey = environmentValue
            return environmentValue
        }

        guard let secretsKey = loadKeyFromSecretsFile(), !secretsKey.isEmpty else {
            assertionFailure("YouTube API key missing. Provide it via the YOUTUBE_API_KEY environment variable or a Secrets.plist file.")
            return ""
        }

        cachedYouTubeKey = secretsKey
        return secretsKey
    }

    private static func loadKeyFromSecretsFile() -> String? {
        guard let secretsURL = Bundle.main.url(
            forResource: Constants.secretsFileName,
            withExtension: Constants.secretsFileExtension
        ) else {
            return nil
        }

        do {
            let secretsData = try Data(contentsOf: secretsURL)
            let plist = try PropertyListSerialization.propertyList(
                from: secretsData,
                options: [],
                format: nil
            )
            let dictionary = plist as? [String: Any]
            return dictionary?[Constants.youtubeAPIKeyField] as? String
        } catch {
            assertionFailure("Failed to load Secrets.plist: \(error.localizedDescription)")
            return nil
        }
    }
}
