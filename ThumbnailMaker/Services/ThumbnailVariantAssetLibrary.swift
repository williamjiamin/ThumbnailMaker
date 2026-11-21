//
//  ThumbnailVariantAssetLibrary.swift
//  ThumbnailMaker
//
//  FEATURE-02: content-addressed image storage for variant sets.
//
//  Variants A/B/C usually share the same photos. Rather than storing three
//  copies of multi-megabyte PNG payloads, each distinct payload is stored once
//  by SHA-256 digest and variant documents reference it. The originals are
//  never re-encoded, so any number of round trips is lossless.
//

import CryptoKit
import Foundation

struct ThumbnailVariantAssetRefs: Codable, Equatable {
    var backgroundImage: String?
    var profileImage: String?
    /// Content layer ID -> digest of its image payload.
    var contentLayers: [String: String]

    init(backgroundImage: String? = nil, profileImage: String? = nil, contentLayers: [String: String] = [:]) {
        self.backgroundImage = backgroundImage
        self.profileImage = profileImage
        self.contentLayers = contentLayers
    }

    private enum CodingKeys: String, CodingKey {
        case backgroundImage
        case profileImage
        case contentLayers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        backgroundImage = try container.decodeIfPresent(String.self, forKey: .backgroundImage)
        profileImage = try container.decodeIfPresent(String.self, forKey: .profileImage)
        contentLayers = try container.decodeIfPresent([String: String].self, forKey: .contentLayers) ?? [:]
    }

    var allDigests: Set<String> {
        var digests = Set(contentLayers.values)
        if let backgroundImage { digests.insert(backgroundImage) }
        if let profileImage { digests.insert(profileImage) }
        return digests
    }
}

enum ThumbnailVariantAssetLibrary {
    static func digest(_ data: Data) -> String {
        // APP-09: memoized for photo buffers shared with live images.
        ThumbnailEncodedImageCache.shared.digest(for: data)
    }

    /// Moves every image payload out of the document into `assets`.
    static func dehydrate(
        _ document: ThumbnailDocument,
        into assets: inout [String: Data]
    ) -> (document: ThumbnailDocument, refs: ThumbnailVariantAssetRefs) {
        var document = document
        var refs = ThumbnailVariantAssetRefs()

        func store(_ data: Data) -> String {
            let key = digest(data)
            if assets[key] == nil {
                assets[key] = data
            }
            return key
        }

        if let imageData = document.imageData {
            refs.backgroundImage = store(imageData)
            document.imageData = nil
        }

        if let profileData = document.profile?.imageData {
            refs.profileImage = store(profileData)
            document.profile?.imageData = nil
        }

        for index in document.layers.indices {
            guard case .image(var content) = document.layers[index].content, !content.imageData.isEmpty else {
                continue
            }
            refs.contentLayers[document.layers[index].id] = store(content.imageData)
            content.imageData = Data()
            document.layers[index].content = .image(content)
        }

        return (document, refs)
    }

    /// Puts payloads back. Never throws: a missing digest leaves that payload
    /// absent and is reported, so a damaged file still opens.
    static func hydrate(
        _ document: ThumbnailDocument,
        refs: ThumbnailVariantAssetRefs,
        assets: [String: Data]
    ) -> (document: ThumbnailDocument, missingDigests: Set<String>) {
        var document = document
        var missing = Set<String>()

        if let key = refs.backgroundImage {
            if let data = assets[key] {
                document.imageData = data
            } else {
                missing.insert(key)
            }
        }

        if let key = refs.profileImage {
            if let data = assets[key] {
                document.profile?.imageData = data
            } else {
                missing.insert(key)
            }
        }

        for index in document.layers.indices {
            guard case .image(var content) = document.layers[index].content,
                  let key = refs.contentLayers[document.layers[index].id] else {
                continue
            }
            if let data = assets[key] {
                content.imageData = data
                document.layers[index].content = .image(content)
            } else {
                missing.insert(key)
            }
        }

        return (document, missing)
    }
}
