import Foundation
import SwiftUI

enum YouTubeError: Error {
    case invalidURL
    case invalidVideoID
    case networkError(Error)
    case noThumbnailFound
}

class YouTubeService {
    static func extractVideoID(from url: String) -> String? {
        let pattern = "(?<=v=)[a-zA-Z0-9-_]{11}|(?<=be/)[a-zA-Z0-9-_]{11}"
        let regex = try? NSRegularExpression(pattern: pattern)
        if let match = regex?.firstMatch(
            in: url,
            range: NSRange(url.startIndex..., in: url)
        ) {
            return (url as NSString).substring(with: match.range)
        }
        return nil
    }
    
    static func fetchThumbnail(videoURL: String) async throws -> Image {
        guard let videoID = extractVideoID(from: videoURL) else {
            throw YouTubeError.invalidVideoID
        }
        
        let urlString = "https://www.googleapis.com/youtube/v3/videos?id=\(videoID)&key=\(APIConfig.getYouTubeAPIKey())&part=snippet"
        
        guard let url = URL(string: urlString) else {
            throw YouTubeError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoder = JSONDecoder()
        let response = try decoder.decode(YouTubeResponse.self, from: data)
        
        guard let thumbnailURL = response.items.first?.snippet.thumbnails.maxres?.url ??
              response.items.first?.snippet.thumbnails.high.url,
              let url = URL(string: thumbnailURL) else {
            throw YouTubeError.noThumbnailFound
        }
        
        let (imageData, _) = try await URLSession.shared.data(from: url)
        
        guard let uiImage = UIImage(data: imageData) else {
            throw YouTubeError.noThumbnailFound
        }
        
        return Image(uiImage: uiImage)
    }
}

// Response models
struct YouTubeResponse: Codable {
    let items: [VideoItem]
}

struct VideoItem: Codable {
    let snippet: VideoSnippet
}

struct VideoSnippet: Codable {
    let thumbnails: ThumbnailCollection
}

struct ThumbnailCollection: Codable {
    let maxres: Thumbnail?
    let high: Thumbnail
}

struct Thumbnail: Codable {
    let url: String
} 
