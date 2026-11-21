import Foundation
import SwiftUI
import UIKit

struct YouTubeVideoInfo {
    let thumbnailImage: UIImage
    let title: String

    var thumbnail: Image {
        Image(uiImage: thumbnailImage)
    }
}

enum YouTubeError: LocalizedError {
    case invalidURL
    case invalidVideoID
    case missingAPIKey
    case httpError(Int)
    case networkError(Error)
    case noThumbnailFound
    case noTitleFound

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid YouTube URL."
        case .invalidVideoID:
            return "Could not find a YouTube video ID in that link."
        case .missingAPIKey:
            return "YouTube import is not configured on this build."
        case .httpError(let statusCode):
            return "YouTube returned an unexpected response (\(statusCode))."
        case .networkError(let error):
            return error.localizedDescription
        case .noThumbnailFound:
            return "No thumbnail was found for that video."
        case .noTitleFound:
            return "No title was found for that video."
        }
    }
}

class YouTubeService {
    static func extractVideoID(from url: String) -> String? {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)

        if isValidVideoID(trimmedURL) {
            return trimmedURL
        }

        var components = URLComponents(string: trimmedURL)
        if components?.host == nil {
            components = URLComponents(string: "https://\(trimmedURL)")
        }

        if let components,
           let host = components.host?.lowercased() {
            let pathSegments = components.path
                .split(separator: "/")
                .map(String.init)

            if isShortYouTubeHost(host),
               let candidate = pathSegments.first,
               isValidVideoID(candidate) {
                return candidate
            }

            if isFullYouTubeHost(host) {
                if let queryVideoID = components.queryItems?
                    .first(where: { $0.name == "v" })?
                    .value,
                   isValidVideoID(queryVideoID) {
                    return queryVideoID
                }

                let pathVideoContainers: Set<String> = ["embed", "live", "shorts", "v"]
                for (index, segment) in pathSegments.enumerated()
                    where pathVideoContainers.contains(segment) {
                    let nextIndex = index + 1
                    guard pathSegments.indices.contains(nextIndex) else { continue }
                    let candidate = pathSegments[nextIndex]
                    if isValidVideoID(candidate) {
                        return candidate
                    }
                }
            }
        }

        return nil
    }

    private static func isValidVideoID(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z0-9_-]{11}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isShortYouTubeHost(_ host: String) -> Bool {
        host == "youtu.be" || host.hasSuffix(".youtu.be")
    }

    private static func isFullYouTubeHost(_ host: String) -> Bool {
        host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host == "youtube-nocookie.com"
            || host.hasSuffix(".youtube-nocookie.com")
    }
    
    static func fetchVideoInfo(videoURL: String) async throws -> YouTubeVideoInfo {
        guard let videoID = extractVideoID(from: videoURL) else {
            throw YouTubeError.invalidVideoID
        }

        let apiKey: String
        do {
            apiKey = try APIConfig.getYouTubeAPIKey()
        } catch APIConfigurationError.missingYouTubeAPIKey {
            throw YouTubeError.missingAPIKey
        }
        
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")
        components?.queryItems = [
            URLQueryItem(name: "id", value: videoID),
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "part", value: "snippet")
        ]
        
        guard let url = components?.url else {
            throw YouTubeError.invalidURL
        }
        
        let (data, urlResponse) = try await URLSession.shared.data(from: url)
        if let httpResponse = urlResponse as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw YouTubeError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(YouTubeResponse.self, from: data)
        
        guard let thumbnailURL = response.items.first?.snippet.thumbnails.maxres?.url ??
              response.items.first?.snippet.thumbnails.high.url,
              let url = URL(string: thumbnailURL) else {
            throw YouTubeError.noThumbnailFound
        }
        
        guard let title = response.items.first?.snippet.title else {
            throw YouTubeError.noTitleFound
        }
        
        let (imageData, _) = try await URLSession.shared.data(from: url)
        
        guard let uiImage = UIImage(data: imageData) else {
            throw YouTubeError.noThumbnailFound
        }
        
        return YouTubeVideoInfo(
            thumbnailImage: uiImage,
            title: title
        )
    }
}

// Update Response models
struct YouTubeResponse: Codable {
    let items: [VideoItem]
}

struct VideoItem: Codable {
    let snippet: VideoSnippet
}

struct VideoSnippet: Codable {
    let title: String
    let thumbnails: ThumbnailCollection
}

struct ThumbnailCollection: Codable {
    let maxres: Thumbnail?
    let high: Thumbnail
}

struct Thumbnail: Codable {
    let url: String
} 
