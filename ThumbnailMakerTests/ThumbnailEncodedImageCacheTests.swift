//
//  ThumbnailEncodedImageCacheTests.swift
//  ThumbnailMakerTests
//
//  APP-09: a photo is PNG-encoded once and every later document shares the
//  buffer; the bytes are the same lossless encoding documents always used.
//

import Foundation
import Testing
import UIKit
@testable import ThumbnailMaker

@MainActor
struct ThumbnailEncodedImageCacheTests {
    private typealias Support = ThumbnailPerformanceTestSupport

    @Test func sameImageIsEncodedOnceAndSharesItsBuffer() throws {
        let cache = ThumbnailEncodedImageCache()
        let image = Support.makePhoto()
        var first: Data?
        var second: Data?
        let recorder = Support.recording {
            first = cache.encodedPNG(for: image)
            second = cache.encodedPNG(for: image)
        }
        let firstData = try #require(first)
        let secondData = try #require(second)
        #expect(recorder.count(of: .imageEncode) == 1)
        #expect(ThumbnailDocumentPayloads.sharesBuffer(firstData, secondData))
        #expect(ThumbnailEncodedImageCache.isPNG(firstData))
        #expect(firstData == ThumbnailEncodedImageCache.encodeDocumentPNG(image))
    }

    @Test func decodedPNGReencodesToItsOwnBytesWithoutWork() throws {
        let cache = ThumbnailEncodedImageCache()
        let data = try #require(ThumbnailEncodedImageCache.encodeDocumentPNG(Support.makePhoto(seed: 0.3)))
        let decoded = try #require(cache.image(decoding: data))
        var reencoded: Data?
        let recorder = Support.recording {
            reencoded = cache.encodedPNG(for: decoded)
        }
        #expect(recorder.count(of: .imageEncode) == 0)
        #expect(ThumbnailDocumentPayloads.sharesBuffer(try #require(reencoded), data))
        let again = try #require(cache.image(decoding: data))
        #expect(again === decoded, "Decoding the same buffer again reuses the decoded image.")
    }

    @Test func documentRoundTripDoesNotReencodeThePhoto() throws {
        var configuration = SimpleMakerConfigurationModel()
        configuration.selectedImage = Support.makePhoto(seed: 0.6)
        configuration.overlayText = "Round trip"

        var firstDocument: ThumbnailDocument?
        var secondDocument: ThumbnailDocument?
        let recorder = try Support.recording {
            firstDocument = configuration.document
            let restored = try #require(firstDocument).makeSimpleConfiguration()
            secondDocument = restored.document
            _ = restored.document
        }
        let first = try #require(firstDocument)
        let second = try #require(secondDocument)
        #expect(recorder.count(of: .imageEncode) == 1)
        #expect(ThumbnailDocumentPayloads.sharesBuffer(try #require(first.imageData), try #require(second.imageData)))
        #expect(ThumbnailDocumentHistory.snapshot(first) == ThumbnailDocumentHistory.snapshot(second))
    }

    @Test func premiumProfilePhotoIsAlsoEncodedOnce() throws {
        var configuration = PremiumMakerConfigurationModel()
        configuration.selectedImage = Support.makePhoto(seed: 0.1)
        configuration.circularProfile = CircularProfileConfig(image: Support.makePhoto(width: 96, height: 96, seed: 0.5), size: 120)

        let recorder = Support.recording {
            for _ in 0..<5 {
                _ = configuration.document
            }
            let restored = configuration.document.makePremiumConfiguration()
            _ = restored.document
        }
        #expect(recorder.count(of: .imageEncode) == 2, "One encode each for background and profile.")
    }

    @Test func rotatedImageIsStoredUprightAsBefore() throws {
        let cache = ThumbnailEncodedImageCache()
        let source = try #require(Support.makePhoto(width: 80, height: 40).cgImage)
        let rotated = UIImage(cgImage: source, scale: 1, orientation: .right)
        let data = try #require(cache.encodedPNG(for: rotated))
        #expect(data == ThumbnailEncodedImageCache.encodeDocumentPNG(rotated))
        let decoded = try #require(UIImage(data: data))
        #expect(decoded.imageOrientation == .up)
        #expect(decoded.size == CGSize(width: 40, height: 80))
    }

    @Test func transparentCutoutKeepsAlpha() throws {
        let cache = ThumbnailEncodedImageCache()
        let data = try #require(cache.encodedPNG(for: Support.makePhoto(opaque: false)))
        let decoded = try #require(cache.image(decoding: data)?.cgImage)
        #expect(decoded.alphaInfo != .none && decoded.alphaInfo != .noneSkipLast && decoded.alphaInfo != .noneSkipFirst)
    }

    @Test func jpegPayloadIsNotTreatedAsDocumentPNG() throws {
        let cache = ThumbnailEncodedImageCache()
        let jpeg = try #require(Support.makePhoto().jpegData(compressionQuality: 0.9))
        let decoded = try #require(cache.image(decoding: jpeg))
        #expect(!cache.hasEncodedPNG(for: decoded))
        var encoded: Data?
        let recorder = Support.recording {
            encoded = cache.encodedPNG(for: decoded)
        }
        #expect(recorder.count(of: .imageEncode) == 1)
        #expect(ThumbnailEncodedImageCache.isPNG(try #require(encoded)))
    }

    @Test func corruptDataStillFailsToDecode() {
        let cache = ThumbnailEncodedImageCache()
        #expect(cache.image(decoding: Data(repeating: 0x42, count: 512)) == nil)
    }

    @Test func digestIsMemoizedForSharedBuffersAndMatchesSHA256() throws {
        let cache = ThumbnailEncodedImageCache()
        let image = Support.makePhoto(seed: 0.9)
        let data = try #require(cache.encodedPNG(for: image))
        var digests: [String] = []
        let recorder = Support.recording {
            digests.append(cache.digest(for: data))
            digests.append(cache.digest(for: data))
            digests.append(cache.digest(for: Data(Array(data))))
        }
        #expect(recorder.count(of: .assetDigest) == 2, "Shared buffer hashed once; an independent copy is hashed.")
        #expect(Set(digests).count == 1)
        #expect(digests.first?.count == 64)
        #expect(digests.first == ThumbnailVariantAssetLibrary.digest(data))
        withExtendedLifetime(image) {}
    }

    @Test func concurrentEncodesAgreeByteForByte() async throws {
        let cache = ThumbnailEncodedImageCache()
        let image = Support.makePhoto(seed: 0.2)
        let results = await withTaskGroup(of: Data?.self) { group in
            for _ in 0..<8 {
                group.addTask { cache.encodedPNG(for: image) }
            }
            var collected: [Data?] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }
        let payloads = results.compactMap { $0 }
        #expect(payloads.count == 8)
        #expect(Set(payloads).count == 1)
    }
}
